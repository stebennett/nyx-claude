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

### 7. Review — the three-lens panel

Dispatch three `pr-review-lens` agents **in parallel, in a single message** — one per lens
(`requirements`, `correctness`, `craft`) — never sequentially; sequential dispatch would
triple the wall-clock for no benefit. Each dispatch carries the same ten parameters:

```
{ lens, pr, target_repo, diff_path, worktree, requirements, pr_body, prior_recommendations, shared_brief_path, lens_brief_path }
```

`shared_brief_path` and `lens_brief_path` are **absolute paths** — the same convention
`renovator` uses for `fix_loop_path`. Form them by joining this skill's own base directory
(given to you when the skill is invoked) with `references/lenses/_shared.md` for every
dispatch, and with `references/lenses/requirements.md`, `references/lenses/correctness.md`,
or `references/lenses/craft.md` for `lens_brief_path`, matching the `lens` in that
dispatch. A relative path will not resolve inside an agent's own context — it has no
notion of this skill's directory, only what its dispatch tells it. Getting this join
wrong is the single most likely way this step breaks at runtime, and nothing here surfaces
it as an error; the agent just fails to find the file.

Each lens returns the envelope defined in `_shared.md` — `lens`, `status`, `findings`,
`notes` — collect all three unmodified; step 8 needs the envelopes, not just their
`findings` arrays.

A lens returning `status: needs-input` is not a finding — it means that lens could not
review at all. Note it for the eventual report and continue with whichever lenses
succeeded; `verdict.md`'s adjudicator discloses the degraded coverage in the review body,
but deciding to continue or to skip the PR is this orchestrator's call, not the
adjudicator's. If all three lenses come back `needs-input`, there is nothing left to
adjudicate: release the lock, outcome `skipped`, reason "could not review", and move to the
next candidate without dispatching `pr-review-verdict`.

### 8. Adjudicate

Dispatch one `pr-review-verdict` with:

```
{ pr, target_repo, pr_title, pr_body, requirements, prior_recommendations, round, head_sha, findings, verdict_doctrine_path }
```

`findings` is the array of the three lens envelopes collected in step 7 — each one exactly
as that lens returned it, `status` and `notes` included, not flattened down to a bare list
of finding objects. The adjudicator's coverage disclosure (`verdict.md`'s Coverage section)
reads each envelope's `status` before it touches dedup or downgrade; losing that field here
would silently break that disclosure. `verdict_doctrine_path` is the absolute path formed
by joining this skill's base directory with `references/verdict.md` — the same joining
rule as step 7, and the same failure mode if it is left relative.

State plainly: **pass it the findings, never the diff.** Withholding the diff from the
adjudicator is deliberate — giving it the code invites a fourth, unaccountable review with
none of the three lenses' scope discipline. `references/verdict.md` owns the entire
adjudication procedure (dedup, downgrade, the prior-round comparison, the decision rule,
the three `park` categories, the review body template, and the return schema); this step
does not restate any of it.

### 9. Deliver the review

Submit exactly one review per round:

```bash
jq -n --arg c "$head_sha" --arg b "$body" --arg e "$event" \
      --argjson cm "$comments" \
      '{commit_id:$c, body:$b, event:$e, comments:$cm}' > "$workdir/review.json"
gh api -X POST "repos/$target_repo/pulls/$n/reviews" --input "$workdir/review.json"
```

`commit_id` pins the review to the SHA actually reviewed — the same SHA step 4's
unchanged-SHA triage will compare against on the next pass.

**The self-review downgrade.** GitHub returns 422 for `APPROVE` or `REQUEST_CHANGES` when
the reviewer is the PR's own author. Detect this **up front**, by comparing the PR's
`author.login` to `self_login` (resolved once, in preflight) — never by dispatching the
review and catching the error:

| verdict | `event` (normal) | `event` (self-authored) |
|---|---|---|
| `approve` | `APPROVE` | `COMMENT` |
| `request-changes` | `REQUEST_CHANGES` | `COMMENT` |
| `park` | `COMMENT` | `COMMENT` |

A downgraded review loses the verdict from GitHub's review *state* — this is exactly why
the hidden marker, `<!-- pr-reviewer: verdict=<approve|request-changes|park> round=<n>
sha=<short_sha> -->`, is the first line of the body and the authoritative record step 4
reads back, never the GitHub review `state` field. Installing this repo's
**github-app-identity** plugin gives `gh` a distinct App identity, so real `APPROVE` and
`REQUEST_CHANGES` records post even on your own PRs — worth doing wherever this skill might
review its own author's work.

**Inline-comment robustness.** A single comment anchored outside the diff 422s the *entire*
review POST — an unattended pass must not lose a whole review to one bad line number. On a
422 whose response implicates the `comments` array, retry **once**, with `comments`
removed and the findings folded into the body instead, one `path:line — finding` line per
comment, built with `jq` rather than a shell loop:

```bash
findings_list=$(printf '%s' "$comments" | jq -r '.[] | "- `\(.path):\(.line)` — \(.body)"')
```

Append `findings_list` to `body` before the retry POST (still one `commit_id`, still one
`event`, `comments` simply omitted this time). A 422 for any other reason — or a second 422
on the retry — is a failure, not something to retry again: release the `reviewer:working`
lock, report the failure for this PR, and move on to the next candidate.

A newer review from the same user supersedes the older one in GitHub's own UI, so posting
an `APPROVE` after a prior `REQUEST_CHANGES` clears our own block without an explicit
dismissal call.

### 10. Route to an outcome

| verdict | condition | action | outcome |
|---|---|---|---|
| `approve` | all four merge gates pass, budget available | dispatch `pr-merger` | `merged` (or reroute per its `reason`, below) |
| `approve` | CI not green / still settling | none — leave for next pass | `approved-pending-ci` |
| `approve` | an unresolved human review thread | none — leave for next pass | `approved-blocked-by-human` |
| `approve` | `size` > `max_merge_lines` | none — reviewed in full, never merged unattended | `approved-too-large` |
| `approve` | `can_merge` is false | none — review-only pass | `no-permission` |
| `request-changes` | — | none beyond the posted review | `changes-requested` |
| `park` | — | add `reviewer:parked` | `parked` |

Before trusting an `approve` verdict enough to dispatch `pr-merger`, check the same four
gates `pr-merger` itself re-verifies live: CI green and `mergeStateStatus` `CLEAN`; no
unresolved human review thread (both the GraphQL `reviewThreads` query and the
latest-review-per-other-user check, exactly as `pr-merger.md` runs them — this orchestrator
does not maintain a second copy of that query, it runs the identical one); `size` (already
held from step 4) ≤ `max_merge_lines`; and `can_merge` (held from preflight) true. A gate
failing here routes to the matching row above without dispatching the merger at all — the
merger is reserved for candidates the orchestrator itself already believes are ready.

When every gate passes, dispatch `pr-merger` with:

```
{ pr, target_repo, merge_method, self_login, max_merge_lines, ignore_paths }
```

and route its return by `reason` — all seven values, exhaustively:

| `reason` | route |
|---|---|
| `merged` | outcome `merged` |
| `behind` | outcome `skipped` (transient — retries next pass) |
| `not-green` | outcome `skipped` (transient — retries next pass) |
| `conflict` | label `reviewer:parked`, outcome `parked` |
| `blocked` | label `reviewer:parked`, outcome `parked` |
| `threads-open` | label `reviewer:parked`, outcome `parked` |
| `too-large` | label `reviewer:parked`, outcome `parked` |

`pr-merger` re-verifies every gate live because two independent agreements — the
orchestrator's and the merger's — must hold before an unattended merge happens; when the
merger disagrees with the orchestrator, **the merger wins** and the PR parks. That is not a
bug to reconcile; it is the entire reason the merger exists as a second, independent check.

At most `max_merges_per_pass` merges per pass (default 1), dispatched **serialized, never
concurrent** — a merge invalidates every other open PR's mergeability and re-triggers its
CI, so a second merger running against stale state is a race, not a speedup. Approved
candidates beyond the per-pass budget are left untouched: outcome `skipped`, reason "merge
cap reached this pass" — they resurface next pass with nothing lost. When
`update_branch_after_merge` is `true`, after this pass's merge lands, run
`gh pr update-branch --repo "$target_repo" <n>` for each remaining approved PR; a failure
there (already up to date, conflicts) is non-fatal, the PR simply resurfaces next pass. It
defaults to `false` because pushing a merge commit onto a contributor's branch is not this
skill's business unless a human has opted in.

Release the `reviewer:working` lock for **every** PR before moving to the next — on a
merge, a park, a skip, or a failure partway through this step. There is no path through
step 10 that leaves a PR still locked.

### 11. Report

One table, one row per candidate:

`PR # | title | lines | round | verdict | outcome`

with `outcome` ∈ `merged` / `approved-pending-ci` / `approved-blocked-by-human` /
`approved-too-large` / `changes-requested` / `parked` / `skipped` / `locked` / `too-large` /
`no-permission`. Carry the specific reason (a conflict, exhausted rounds, an oversized
diff, a stale merge) in prose beside a `parked` or `skipped` row, rather than inventing a
new outcome value per reason. When `can_merge` is false, say so once in the report's
header, not once per row — every `no-permission` row already implies it.

## State model

Deliberately thinner than `renovator`'s, because GitHub's own reviews API already *is* the
state store here: one call (step 4's `pulls/$n/reviews`) yields the round count, the
last-reviewed SHA, the prior round's recommendations, and — via the hidden marker on the
review body's first line — the prior verdict. There is no sticky comment to upsert.

Two labels persist only what GitHub's own API cannot tell us:

- `reviewer:working` — a momentary lock held while one PR is processed, so an overlapping
  run or a `/loop` re-entry cannot double-process it. Added before the panel is dispatched
  (step 4); removed when the PR is done, **always, including on failure** — a PR must never
  be left locked because some later step in the pipeline errored.
- `reviewer:parked` — terminal. Excluded from selection (step 3) until a human removes it.

They are mutually exclusive; adding one removes the other:

```bash
gh pr edit "$n" --repo "$target_repo" \
  --add-label reviewer:parked --remove-label reviewer:working
```

Idempotent by construction: every pass sets labels to the target state and posts at most
one review per PR per head SHA, so re-running never duplicates a review or a label.

## Under /loop

Each invocation is one full pass. A PR whose CI was pending, whose author has since
pushed, or that was skipped for throughput (the per-pass merge or review caps) resurfaces
next pass with nothing lost. Parked PRs stay parked until a human clears the label. The
unchanged-SHA skip in step 4 means an idle queue — nothing new since the last pass — costs
one `gh pr list` plus one reviews call per candidate, and dispatches nothing: no agent, no
review post, no label change.

## Never do

- Never merge a PR the verdict did not approve.
- Never merge over an unresolved human objection.
- Never merge a PR above `max_merge_lines`, or review one above `max_review_lines`.
- Never request changes without at least one blocking finding carrying a stated
  consequence.
- Never touch a PR authored by `renovate_authors`, or a draft.
- Never modify the user's working tree, branches, or index; worktrees are detached and
  removed.
- Never post more than one review per PR per round.

Plus two the orchestrator specifically owns:

- Never run tests, fix code, or push to a contributor's branch. Someone owns this PR; you
  review it.
- Never review a diff yourself or merge yourself — those belong to the agents.
