---
name: pr-reviewer
description: Review open pull requests and merge the ones that are ready. Runs a three-lens agent panel (requirements-conformity, correctness and edge cases, craft) over a PR's diff, posts one GitHub review with inline comments, then either requests changes with concrete recommendations or approves and merges. Bare invocation drains the current repo's open-PR queue; pass a PR number, a PR URL, or a repo URL to target something else. Each invocation is one pass; safe under /loop. Excludes Renovate PRs, which the renovator skill owns. Use when asked to review, triage, approve, or merge pull requests.
---

# pr-reviewer — review open PRs and merge what is ready

You are the coordinator. You classify and route; you never review a diff yourself and you never
merge yourself. The `pr-review-lens` agents review, `pr-review-verdict` adjudicates, and
`pr-merger` merges — each in its own context. Keep your own context lean: hold PR metadata and
structured findings only, never a diff.

Runs fully autonomously, including under `/loop`. The human's window into a pass is the
after-action report (step 11) plus the review each PR carries.

This skill is a sibling to `renovator`, not a replacement: `renovator` owns dependency PRs,
`pr-reviewer` owns everything else, and the two never touch the same PR.

## Invocation

Three forms, resolved to a `target_repo` (`owner/repo`) and an optional `target_pr`. The
classification rules and extraction recipes live in `references/target-resolution.md`
(join this skill's base directory with that relative path to get the absolute path); this
table is the summary, not the authority:

| argument | `target_repo` | `target_pr` | mode |
|---|---|---|---|
| *(none)* | origin of the cwd repo | — | queue pass |
| `42` (all digits) | origin of the cwd repo | `42` | single PR |
| `https://github.com/o/r/pull/42` | `o/r` | `42` | single PR |
| `o/r#42` | `o/r` | `42` | single PR |
| `https://github.com/o/r` | `o/r` | — | queue pass |
| `git@github.com:o/r.git` | `o/r` | — | queue pass |
| `o/r` | `o/r` | — | queue pass |

> **Single-PR mode** — an argument naming one PR bypasses the selection filters of step 3 (draft status, `renovate_authors`, `require_label`, the `reviewer:parked` exclusion) and all three triage skips of step 4 (unchanged SHA, `max_rounds`, CI pending). Naming a PR is an instruction to review it. The `max_review_lines` ceiling and every merge gate still apply in full; when one of them prevents a merge, say which in the report.

## The pass

### 1. Preflight

- `gh auth status` succeeds, else STOP and report exactly what is missing — do nothing else.
- Resolve the target per `references/target-resolution.md` (join this skill's base
  directory — given to you when the skill is invoked — with that relative path to get the
  absolute path). Follow its resolution table and disambiguation rules exactly; this step
  does not restate them. It sets `target_repo` (`owner/repo`) and, when the invocation names
  one, `target_pr`. Resolve `self_login` the same way it describes, once per pass, and reuse
  it for every PR:
  ```bash
  self_login=$(gh api user --jq .login)
  ```
- Merge permission — check once here, and hold the result for step 10 (Task 8):
  ```bash
  gh api "repos/$target_repo" --jq '.permissions'
  ```
  Set `can_merge` true when `push`, `maintain`, or `admin` is `true`. When `can_merge` is
  false the pass runs **review-only**: every PR is still reviewed and commented, and each
  would-be merge is reported `no-permission` rather than attempted. Say so once in the
  report header. A target that 404s here is a hard stop, before any agent is dispatched.
- Ensure the two lifecycle labels exist (idempotent — `--force` updates an existing label):
  ```bash
  gh label create reviewer:working --repo "$target_repo" --color FBCA04 \
    --description "pr-reviewer is processing this PR" --force
  gh label create reviewer:parked --repo "$target_repo" --color D93F0B \
    --description "pr-reviewer parked this PR for a human" --force
  ```

Any preflight failure stops the pass and reports exactly what is missing. Nothing else runs.

### 2. Configuration

Read `.claude/pr-reviewer.json` **from the target repo, never from the working
directory** — a config governing one repository must not silently govern another.

| knob | default | meaning |
|---|---|---|
| `renovate_authors` | `["renovate[bot]"]` | authors excluded so `renovator` keeps its own queue |
| `exclude_authors` | `[]` | additional author logins to skip |
| `require_label` | `null` | when set, only PRs carrying this label are eligible |
| `max_reviews_per_pass` | `3` | PRs reviewed per pass |
| `max_merges_per_pass` | `1` | merges per pass |
| `max_rounds` | `3` | request-changes rounds before parking |
| `merge_method` | `"squash"` | method passed to `gh pr merge` |
| `max_merge_lines` | `800` | above this: review fully, never merge unattended |
| `max_review_lines` | `3000` | above this: park unreviewed with "split this PR" |
| `ignore_paths` | `["*.lock", "package-lock.json", "**/generated/**"]` | excluded from the diff and from both line counts |
| `update_branch_after_merge` | `false` | whether to `gh pr update-branch` remaining approved PRs after a merge |
| `clone_cache_dir` | `null` | persistent clone cache for remote targets; `null` uses the session scratchpad |

Two read recipes, chosen by `references/target-resolution.md`'s locality decision — the
same key and default work for every row above, `max_rounds` shown only as the example:

```bash
# local target
jq -r '.max_rounds // 3' .claude/pr-reviewer.json 2>/dev/null

# remote target — before any clone
gh api "repos/$target_repo/contents/.claude/pr-reviewer.json" --jq .content 2>/dev/null \
  | base64 -d
```

State: a 404 means no config. An absent file or an absent key falls back to the default
above; unknown keys are ignored.

### 3. Select candidates

Queue mode only — single-PR mode goes straight to step 4, with `n` set to `target_pr`.

```bash
gh pr list --repo "$target_repo" --state open --limit 100 \
  --json number,title,author,headRefName,headRefOid,isDraft,mergeStateStatus,labels
```

Drop, in order, recording the reason for each: drafts; authors in `renovate_authors` or
`exclude_authors`; PRs lacking `require_label` when it is set; PRs labelled
`reviewer:parked` (terminal until a human clears it); PRs labelled `reviewer:working`
(another run owns it — outcome `locked`).

Each survivor's `number` becomes `n`, and its `headRefOid` becomes `head_sha`, for the rest
of that PR's processing (steps 4–6 here, and every step Task 8 adds). Single-PR mode
skipped this call, so fetch `head_sha` fresh instead:
```bash
head_sha=$(gh pr view "$n" --repo "$target_repo" --json headRefOid --jq .headRefOid)
```

### 4. Triage before spending an agent

For each surviving candidate `n`, one call yields the round state:
```bash
gh api "repos/$target_repo/pulls/$n/reviews" --paginate \
  --jq "[.[] | select(.user.login == \"$self_login\")]"
```
From that one array: `round` is its length; the last-reviewed SHA is the last entry's
`commit_id`; `prior_recommendations` is the last entry's `body`. Read the prior verdict
from the hidden marker on the body's first line (`<!-- pr-reviewer: verdict=… -->`),
falling back to the review `state` when the marker is absent.

Skip without dispatching anything — **queue mode only; single-PR mode runs none of these
three, since naming a PR is an instruction to review it**:
- head SHA equals the last-reviewed SHA → outcome `skipped`, reason "unchanged since last review";
- `round` ≥ `max_rounds` and the last verdict was `request-changes` → label
  `reviewer:parked`, reason "review rounds exhausted";
- CI still settling → outcome `skipped`, reason "CI in progress".

Then size, in **both** modes. Fetch the changed files and sum `.changes` over files not
matching `ignore_paths`, reusing the exact `jq` filter `pr-merger` uses to recompute size at
merge time — the orchestrator and the merger must never be able to disagree about a PR's
size, so this is not reinvented here:
```bash
gh api "repos/$target_repo/pulls/$n/files" --paginate --jq '.[]' | jq -s \
  --argjson pats "$ignore_paths" '
  # Convert a glob to an anchored regex. "*" and "**" both match across "/",
  # which is what the ignore_paths patterns intend.
  def glob2re: gsub("\\."; "\\.") | gsub("\\*\\*"; "*") | gsub("\\*"; ".*");
  # A path is ignored if a pattern matches the whole path, or (for a pattern
  # naming no directory) matches the basename at any depth.
  def ignored($pats): . as $p
    | any($pats[]; (glob2re) as $re
        | ($p | test("^" + $re + "$"))
          or (($p | test("(^|/)" + $re + "$")) and (. | test("/") | not)));
  map(select((.filename | ignored($pats)) | not) | .changes) | add // 0
'
```
This is the same filter, over the same endpoint, `pr-merger.md` re-runs independently
before it merges. `ignore_paths` is matched entirely inside `jq` — never loop over the
patterns in shell; unquoted multi-line word-splitting is not portable across the shells
this runs under. `--paginate` is what stops a PR with more than one page of files from
silently under-counting. Assign the total to `size` and keep it: step 10 (Task 8) needs it
for the merge ceiling.

Over `max_review_lines`: post a COMMENT review saying the PR is too large to review
meaningfully and should be split, label `reviewer:parked`, outcome `too-large`, move on. An
honest refusal beats a shallow rubber-stamp. This ceiling applies in **both** modes — a PR
too large to review is too large to review however it was named.

Process at most `max_reviews_per_pass` survivors, oldest PR first. Before dispatching
anything for a PR, take the lock: add `reviewer:working` and remove `reviewer:parked`.
Release it when the PR is done, **always, including on failure**.

### 5. Resolve requirements

First, capture the PR body — needed here and by every lens dispatch in Task 8:
```bash
pr_body=$(gh pr view "$n" --repo "$target_repo" --json body --jq .body)
```
Resolve `requirements` in order, stopping at the first substantive result: `pr_body`
itself; then linked issues (`Closes #n` / `Fixes #n` / `Resolves #n` in the body, plus
GitHub's linked-issue field — fetch each issue's title and body); then spec or design
documents the body or branch name references, read from the worktree. Nothing substantive
→ `requirements` is `null`, and the requirements lens turns that into a blocking finding.
The other two lenses review as normal.

### 6. Prepare review context

Bind the two path variables this step and every later one build on:

```bash
workdir=$(mktemp -d)
worktree="$workdir/tree"
```

`workdir` is a fresh per-PR scratch directory: it holds the diff, the worktree, and any
other per-PR working files. `worktree` is `$workdir/tree` **in both modes** — what differs
between a local and a remote target is only which repository the worktree is added from
(the user's own checkout for a local target, the blobless cache clone for a remote one),
never where it lands. Add the worktree at `$worktree`, and clone or fetch into whichever
repository the target is local or remote to, per `references/target-resolution.md` — those
recipes live there and are not restated here.

Then write the canonical diff:
```bash
gh pr diff --repo "$target_repo" "$n" > "$workdir/pr-$n.diff"
```
`diff_path` is that file. **The diff comes from GitHub, never from a local `git diff`** —
inline comments must anchor to lines GitHub recognises as part of the diff, and its own
rendering is what guarantees that. The worktree exists only for surrounding-code context;
it is never the source of a finding's `path:line`. Remove `$workdir` (worktree included)
after the PR is processed, always, including on failure, per
`references/target-resolution.md`'s cleanup recipe.
