# pr-reviewer — design

**Date:** 2026-07-26
**Plugin:** `devtools`
**Status:** approved design, not yet implemented

## Purpose

Review open pull requests and merge the ones that are ready. One invocation reviews a
PR — or drains a repository's whole open-PR queue — through a three-lens panel, posts a
single GitHub review carrying inline comments and a verdict, and then either requests
changes with concrete recommendations or approves and merges.

The skill exists because Claude Code's built-in `/review` handles one PR interactively and
never merges. `pr-reviewer` is the autonomous, multi-PR, merge-capable variant, built on the
same house pattern as `renovator`: a thin orchestrating skill that dispatches specialist
subagents and never holds a diff itself.

It is a sibling to `renovator`, not a replacement: `renovator` owns dependency PRs,
`pr-reviewer` owns everything else, and the two never touch the same PR.

## Scope

**In scope**

- Reviewing non-draft open PRs through three lenses: requirements-conformity, correctness
  and edge cases, and craft (simplicity, style, consistency).
- Posting one GitHub review per round: verdict, numbered recommendations, inline comments.
- Merging a PR when the review approves it and every mechanical gate passes.
- Operating on the current repository, on a named PR, or on a remote repository given
  by URL.
- Bounded re-review rounds as the author pushes fixes.

**Out of scope (explicit non-goals)**

- Running tests. CI green is a gate; the skill never executes the suite.
- Fixing code. It reviews; the author reworks. This is the opposite of `renovator`'s
  fix-loops, and deliberately so — someone owns this PR.
- Rebasing or otherwise mutating another person's branch, except the optional
  `update_branch_after_merge` knob.
- PRs by any author in `ignore_authors` (default `["renovate[bot]"]`). The default keeps
  `renovator`'s queue and this one from colliding; the operator can add any author.
- Draft PRs.

## Invocation

Three forms, resolved to a `target_repo` (`owner/repo`) and an optional `target_pr`.

| argument | `target_repo` | `target_pr` | mode |
|---|---|---|---|
| *(none)* | origin of the cwd repo | — | queue pass |
| `42` (all digits) | origin of the cwd repo | `42` | single PR |
| `https://github.com/o/r/pull/42` | `o/r` | `42` | single PR |
| `o/r#42` | `o/r` | `42` | single PR |
| `https://github.com/o/r` | `o/r` | — | queue pass |
| `git@github.com:o/r.git` | `o/r` | — | queue pass |
| `o/r` | `o/r` | — | queue pass |

Disambiguation is total: an all-digits argument is a PR number; an argument containing `/`
is a repo reference. No argument and no git repo in the working directory is a hard stop
with a clear message.

Once resolved, `target_repo` is threaded through every `gh` call as `--repo <target_repo>`.
The pass logic does not branch on local-versus-remote anywhere else.

**Single-PR mode** bypasses the selection filters — `require_label`, the
`reviewer:parked` exclusion, and the unchanged-SHA skip. Draft status and `ignore_authors`
are **absolute and never bypassed in either mode**; naming such a PR is a hard stop. Naming a PR is
an instruction to review it, so it also skips the `max_rounds` park and the CI-pending defer
(a review does not depend on CI; the *merge* gate still does). It honours every merge gate
and both size ceilings; when one of those prevents a merge, the report says which.

## Architecture

Claude Code subagents cannot spawn subagents, so the orchestrator dispatches every agent
directly. It holds PR metadata and structured findings only — never a diff.

```
pr-reviewer (skill, main loop, opus)
  ├─ pr-review-lens     ×3 in parallel per PR   sonnet   requirements / correctness / craft
  ├─ pr-review-verdict  ×1 per PR               opus     dedup, adjudicate, author the review
  └─ pr-merger          ×1 per merge            haiku    re-verify gates, merge
```

Sequential across PRs, parallel within a PR.

## The pass

### 1. Preflight

- `gh auth status` succeeds. Resolve our own login: `gh api user --jq .login` → `self_login`.
- Resolve `target_repo` / `target_pr` per the table above.
- `gh api repos/{owner}/{repo} --jq .permissions` — record whether we hold
  `push`/`maintain`/`admin`. Without them the pass runs **review-only**: every PR is still
  reviewed and commented, and each would-be merge is reported as `no-permission` rather
  than attempted. A target we cannot read at all fails here, before any agent is dispatched.
- Ensure the two labels exist (idempotent):
  - `gh label create reviewer:working --color FBCA04 --description "pr-reviewer is processing this PR" --force`
  - `gh label create reviewer:parked --color D93F0B --description "pr-reviewer parked this PR for a human" --force`

Any preflight failure stops the pass and reports exactly what is missing. Nothing else runs.

### 2. Configuration

Read `.claude/pr-reviewer.json` **from the target repo, never from the working directory** —
a config governing one repository must not silently govern another.

- Local target (cwd repo's origin matches `target_repo`): read the file from disk.
- Remote target: fetch it over the API before any clone —
  `gh api repos/{o}/{r}/contents/.claude/pr-reviewer.json --jq .content | base64 -d`.
  A 404 means no config.

Absent file or absent key falls back to the default. Unknown keys are ignored.

| knob | default | meaning |
|---|---|---|
| `ignore_authors` | `["renovate[bot]"]` | author logins never reviewed or touched, in either mode; exact login match, case-insensitive |
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

### 3. Select candidates

Queue mode only; single-PR mode skips straight to step 4.

`gh pr list --repo <target_repo> --state open --limit 100 --json number,title,author,headRefName,headRefOid,isDraft,mergeStateStatus,labels`

Drop, in order: drafts; authors in `ignore_authors`; PRs lacking
`require_label` when it is set; PRs labelled `reviewer:parked` (terminal until a human clears
it); PRs labelled `reviewer:working` (another run owns it — record outcome `locked`).

### 4. Triage before spending an agent

For each candidate, one call yields all the state we need:

```
gh api repos/{o}/{r}/pulls/{n}/reviews --paginate \
  --jq '[.[] | select(.user.login == "<self_login>")]'
```

From that array: **round count** is its length, **last-reviewed SHA** is the last entry's
`commit_id`, and the **prior review body** is the last entry's `body` (which carries the
previous round's numbered recommendations, and the hidden verdict marker).

Skip without dispatching anything when (queue mode only — single-PR mode runs none of these
three skips, since naming a PR is an instruction to review it):

- the PR head SHA equals the last-reviewed SHA — nothing has changed, there is nothing new
  to say (outcome `skipped`, reason "unchanged since last review");
- round count ≥ `max_rounds` and the last verdict was `request-changes` — label
  `reviewer:parked`, reason "review rounds exhausted";
- CI is still settling (outcome `skipped`, reason "CI in progress").

Then compute the reviewable size:

```
gh api repos/{o}/{r}/pulls/{n}/files --paginate --jq '.[] | [.filename, .changes] | @tsv'
```

Sum `.changes` over files not matching `ignore_paths`. Above `max_review_lines`, post a
COMMENT review saying the PR is too large to review meaningfully and should be split, label
`reviewer:parked`, and move on — an honest refusal beats a shallow rubber-stamp. This ceiling
applies in both modes: a PR too large to review is too large to review however it was named.
Record the size; step 10 needs it for the merge ceiling.

Process at most `max_reviews_per_pass` surviving candidates, oldest PR first.

### 5. Resolve requirements

Cheap, orchestrator-level, producing one text blob passed to the lenses. Resolve in order
and stop at the first substantive result:

1. The PR body.
2. Linked issues — `Closes #n` / `Fixes #n` / `Resolves #n` in the body, and GitHub's own
   linked-issue field. Fetch each issue's title and body.
3. Spec or design documents the body or branch name references, read from the worktree.

If nothing substantive is found, pass `requirements: null`. The requirements lens turns that
into a blocking finding: a PR whose intent is not written down anywhere does not merge
unattended. The other two lenses review and comment as normal.

### 6. Prepare review context

**The diff is canonical from GitHub, not computed locally.** Write
`gh pr diff --repo <target_repo> <n>` to `<workdir>/pr-<n>.diff` and give lens agents the
path. This matters for more than convenience: inline comments must anchor to lines GitHub
recognises as part of the diff, and using GitHub's own rendering of it guarantees the line
numbers line up. It also keeps the diff out of the orchestrator's context.

**The worktree exists purely for surrounding-code context** — checking callers, conventions,
and invariants a hunk does not show.

- Local target (cwd repo's origin matches `target_repo`):
  ```
  git -C <repo> fetch origin pull/<n>/head:refs/pr-reviewer/<n> --force
  git -C <repo> worktree add --detach <workdir>/tree refs/pr-reviewer/<n>
  ```
  This never touches the user's checkout, branches, or index.
- Remote target: blobless partial clone into the scratchpad (or `clone_cache_dir`),
  cached per repo and reused across PRs in the pass and across passes under `/loop`:
  ```
  git clone --filter=blob:none --no-checkout <url> <cache>/<owner>-<repo>
  ```
  Blobs arrive on demand, so this stays fast on a large repository. Reuse fetches rather
  than re-clones.

After the PR is processed: `git worktree remove --force <workdir>/tree` and
`git update-ref -d refs/pr-reviewer/<n>`. A local target must be left exactly as found.

### 7. Review — the three-lens panel

Dispatch three `pr-review-lens` agents in parallel, each with
`{ lens, pr, target_repo, diff_path, worktree, requirements, pr_body, prior_recommendations,
shared_brief_path, lens_brief_path }`.

The brief paths are absolute, joined from the skill's own base directory — the same
convention `renovator` uses for `fix_loop_path`.

| lens | owns | blocking bar |
|---|---|---|
| **requirements** | does the diff do what the resolved requirements say — all of it, and nothing undisclosed | a requirement unimplemented, behaviour contradicting stated intent, silent scope creep, or no stated requirements at all |
| **correctness** | edge cases, error paths, boundaries, concurrency, resource lifecycle | a concrete failure scenario: inputs or state → wrong output or crash |
| **craft** | simplicity, style, consistency with surrounding code | needless complexity a reader must hold in their head, duplication of something that already exists, or a convention break that misleads the next reader. Most craft findings are advisory by design |

`references/lenses/_shared.md` binds all three. It is what keeps the review from becoming
noise:

- Anchor every finding to `path:line` within the diff. Observation → consequence →
  concrete fix.
- Review the diff as written, not the code you would have written. Taste is not a finding.
- Do not flag what a linter, formatter, or CI already enforces.
- Do not flag pre-existing code the diff does not touch.
- Blocking requires a stated consequence a reasonable author would accept.
- When a prior round's recommendation was addressed, say so; do not re-raise it.

**Lens return — exactly one JSON object:**

```json
{
  "lens": "correctness",
  "status": "complete",
  "findings": [
    {
      "path": "src/foo.ts",
      "line": 42,
      "side": "RIGHT",
      "severity": "blocking",
      "claim": "…",
      "consequence": "…",
      "failure_scenario": "…",
      "fix": "…"
    }
  ],
  "notes": "one-line summary"
}
```

`failure_scenario` is required on a blocking correctness finding. `side` is `RIGHT` for
added or context lines and `LEFT` for deleted ones. `status: needs-input` means the lens
could not review at all (unreadable worktree, empty diff) — distinct from finding nothing.

### 8. Adjudicate

Dispatch `pr-review-verdict` with PR metadata, resolved requirements, the prior round's
recommendations, and all findings from the three lenses — **never the diff**. Withholding
the diff is deliberate: the adjudicator weighs claims, and giving it the code invites a
fourth, unaccountable review.

It:

1. Dedups overlapping findings — craft and correctness routinely hit the same hunk.
2. Downgrades nitpicks, matters of taste, speculation without a concrete scenario, and
   anything a linter owns.
3. Compares against the prior round: a blocker the author addressed must not be re-raised;
   one they ignored is re-raised and escalates.
4. Issues one verdict and authors the review body and inline comments.

**`request-changes` requires at least one surviving blocking finding with a stated
consequence.** If nothing blocking survives, the verdict is `approve` and the advisory
findings still go out as inline comments *on the approving review*. Comment, and merge.

`park` is a third verdict, distinct from `request-changes`: the PR needs a human decision —
an architectural fork, a product call, a security-sensitive surface — not a rework loop.

**Verdict return:**

```json
{
  "verdict": "approve",
  "reason": "one line for the report",
  "body": "markdown review body: verdict, summary, numbered recommendations",
  "comments": [ { "path": "…", "line": 42, "side": "RIGHT", "body": "…" } ],
  "blocker_count": 0
}
```

### 9. Deliver the review

Submit exactly one review per round:

```
gh api -X POST repos/{o}/{r}/pulls/{n}/reviews \
  -f commit_id=<head_sha> -f body=<body> -f event=<event> \
  --input <comments.json>
```

`commit_id` pins the review to the SHA actually reviewed — this is what makes step 4's
triage reliable.

**Event mapping and the self-review downgrade.** GitHub returns 422 for `APPROVE` or
`REQUEST_CHANGES` when the reviewer is the PR author. Detect it up front by comparing
`author.login` to `self_login` rather than catching the error:

| verdict | event (normal) | event (self-authored) |
|---|---|---|
| `approve` | `APPROVE` | `COMMENT` |
| `request-changes` | `REQUEST_CHANGES` | `COMMENT` |
| `park` | `COMMENT` | `COMMENT` |

A downgraded review loses the verdict from GitHub's review *state*, so **every review body
opens with a hidden marker** — invisible on GitHub, authoritative for the next pass:

```
<!-- pr-reviewer: verdict=request-changes round=2 sha=abc1234 -->
```

Step 4 reads the verdict from this marker, falling back to the review state when absent.

Installing this repo's **github-app-identity** plugin gives `gh` a distinct App identity, so
real `APPROVE` and `REQUEST_CHANGES` records work on your own PRs. The README should say so.

**Inline-comment robustness.** A single comment anchored outside the diff 422s the *entire*
review POST. On a 422 whose message implicates the comments array, retry once with
`comments` dropped and the findings appended to the body as a `path:line — finding` list.
An unattended pass must not lose a review to one bad anchor.

A newer review from the same user supersedes the older one for merge purposes, so an
`APPROVE` after a prior `REQUEST_CHANGES` clears our own block without an explicit dismissal.

### 10. Route to an outcome

| verdict | gates | action | outcome |
|---|---|---|---|
| `approve` | all pass | dispatch `pr-merger` | `merged` |
| `approve` | CI pending | review posted, no merge; retry next pass | `approved-pending-ci` |
| `approve` | unresolved human threads | review posted, `reviewer:parked` | `approved-blocked-by-human` |
| `approve` | size > `max_merge_lines` | review posted, `reviewer:parked`, "approved; the merge is yours" | `approved-too-large` |
| `approve` | no merge permission | review posted | `no-permission` |
| `request-changes` | — | review posted with numbered recommendations | `changes-requested` |
| `park` | — | COMMENT review explaining why, `reviewer:parked` | `parked` |

**Mechanical gates, all of which must hold before a merge:**

- **CI green and cleanly mergeable.** Every status check succeeded; none pending or failing;
  `mergeStateStatus` is `CLEAN`. Same bar `renovate-merger` enforces.
- **No unresolved human review threads.** Two checks:
  - a GraphQL query for open threads —
    `reviewThreads(first:100){nodes{isResolved isOutdated comments(first:1){nodes{author{login}}}}}`
    — any thread that is unresolved, not outdated, and not authored by `self_login` blocks;
  - any other user whose latest review state is `CHANGES_REQUESTED` blocks.
- **Size ceiling.** Reviewable size ≤ `max_merge_lines`.
- **Merge permission.** Held, per preflight.

At most `max_merges_per_pass` merges per pass (default 1), serialized — a merge invalidates
other PRs' mergeability and re-triggers their CI. Remaining approved PRs are left untouched
and resurface next pass, unless `update_branch_after_merge` is true, in which case each gets
`gh pr update-branch`. It defaults to false because pushing a merge commit onto someone
else's branch is not the skill's business by default.

`pr-merger` re-verifies every gate live before merging, exactly as `renovate-merger` does —
two independent agreements gate an unattended merge. It never edits files, never comments,
never labels, and never touches a PR other than the one it was given. It is a new agent
rather than a reuse of `renovate-merger`, whose gates hard-code semver-bump re-verification
and Renovate identity checks.

**`pr-merger` return:**

```json
{ "pr": 42, "outcome": "merged", "reason": "merged" }
```

with `reason` ∈ `merged` | `behind` | `conflict` | `blocked` | `not-green` | `threads-open`.

### 11. Report

One table, the human's after-action view of the pass:

`PR # | title | lines | round | verdict | outcome`

## State model

Deliberately thinner than `renovator`'s, because GitHub's reviews API already *is* the state
store. One call per PR yields round count, last-reviewed SHA, prior recommendations, and —
via the hidden marker — the prior verdict. There is no sticky comment.

Two labels persist only what GitHub cannot tell us:

- **`reviewer:working`** — a momentary lock held while a PR is processed, so an overlapping
  run or a `/loop` re-entry cannot double-process it. Added before the panel is dispatched,
  removed when the PR is done, always, including on failure.
- **`reviewer:parked`** — terminal. Excluded from selection until a human removes it.

They are mutually exclusive; adding one removes the other.

Idempotent by construction: every pass sets labels to the target state and posts at most one
review per PR per head SHA, so re-running never duplicates.

## Under /loop

Each invocation is one full pass. A PR whose CI was pending, whose author has since pushed,
or that was skipped for throughput resurfaces next pass. Parked PRs stay parked until a human
clears the label. The unchanged-SHA skip in step 4 means an idle queue costs one `gh pr list`
plus one reviews call per candidate and dispatches nothing.

## Never do

- Never merge a PR the verdict did not approve.
- Never merge over an unresolved human objection.
- Never merge a PR above `max_merge_lines`, or review one above `max_review_lines`.
- Never request changes without at least one blocking finding carrying a stated consequence.
- Never touch a PR authored by someone in `ignore_authors`, or a draft — in either mode.
- Never modify the user's working tree, branches, or index; worktrees are detached and
  removed.
- Never post more than one review per PR per round.

## Files

```
plugins/devtools/
  .claude-plugin/plugin.json                     # version bump, description, keywords
  README.md                                      # pr-reviewer section
  agents/
    pr-review-lens.md                            # sonnet — dispatched 3× with a lens param
    pr-review-verdict.md                         # opus   — adjudicator
    pr-merger.md                                 # haiku  — gate re-verify + merge
  skills/pr-reviewer/
    SKILL.md                                     # orchestrator: resolution, pass, routing
    references/
      target-resolution.md                       # arg → target_repo/target_pr; clone & worktree
      lenses/_shared.md                          # etiquette + method, binds all lenses
      lenses/requirements.md
      lenses/correctness.md
      lenses/craft.md
      verdict.md                                 # adjudication doctrine + review body format
  templates/pr-reviewer.json                     # config scaffold
```

One `pr-review-lens` agent definition serves all three lenses, parameterised by its brief
path — the same reuse `kanban-flow`'s `card-lens-reviewer` makes, and one file to maintain
instead of three near-duplicates.

`devtools` is already registered in `.claude-plugin/marketplace.json`; only its description
needs updating.

## Portability

Same constraints as the rest of this repo: bash 3.2 (no `mapfile`, `readarray`, or
`declare -A`), no GNU-only flags (`grep -oP`, `find -printf`, `date -Iseconds`). `jq` and
`gh` are required; `git` is required for the worktree and clone paths.

## Validation

No test runner exists in this repo; plugin components are validated by installing the plugin
and exercising it. The acceptance scenarios that must pass:

1. **Local queue pass** — run bare in a repo with several open PRs. Renovate PRs and drafts
   are untouched; at most `max_reviews_per_pass` are reviewed; the report matches what
   landed on GitHub.
2. **Single PR by number** — `42` in a repo reviews only PR 42, including one already
   labelled `reviewer:parked`.
3. **Remote by PR URL** — from an unrelated working directory, a
   `https://github.com/o/r/pull/n` argument reviews that PR, cloning into the scratchpad and
   leaving the working directory's repo untouched.
4. **Remote by repo URL** — a full queue pass on a repo not checked out locally.
5. **Self-review downgrade** — on a PR authored by the `gh` user, the review posts as
   `COMMENT`, the hidden marker carries the verdict, and the next pass reads it back.
6. **Approve-and-merge** — a small, green, well-described PR merges, with the approving
   review recorded first.
7. **Request-changes and re-review** — a PR with a real defect gets numbered
   recommendations; after the author pushes a fix, the next pass re-reviews, confirms the
   blocker is resolved, does not re-raise it, and merges.
8. **Rounds exhausted** — a PR that fails `max_rounds` times is parked, not looped.
9. **Both size ceilings** — a PR over `max_merge_lines` is reviewed and approved but not
   merged; one over `max_review_lines` is parked unreviewed.
10. **No merge permission** — a remote target without push rights reviews cleanly and
    reports `no-permission` rather than erroring.
11. **Unresolved human thread** — an approving verdict does not merge while a colleague's
    unresolved thread is open.
12. **Bad inline anchor** — a review whose comments 422 falls back to a body-only review
    with the findings inlined as text.
13. **Idempotence** — running twice with no intervening push posts no second review and
    changes no labels.
