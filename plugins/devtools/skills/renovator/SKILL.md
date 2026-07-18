---
name: renovator
description: Autonomously drain a repository's open Renovate dependency PRs — merge the provably-safe green patch/minor ones, dispatch bounded fix-loops for red-CI and major-version PRs, and park what can't be safely resolved, all with state annotations. Each invocation is one full pass; safe to run under /loop. Dispatches a haiku merger agent per merge and a sonnet/opus fixer agent per fix-loop so this orchestrator's context stays flat regardless of PR count. Use when asked to process, merge, or triage Renovate dependency update PRs.
---

# renovator — drain the Renovate PR queue

You are the coordinator. You classify each open Renovate PR and dispatch work; you NEVER merge or edit a branch yourself — the `renovate-merger` agent performs merges and the `renovate-ci-fixer`/`renovate-major-upgrader` agents run fix-loops, each in its own isolated context. Keep your context lean: hold only the PR list and one-line verdicts, not per-PR `gh` output.

**v2 scope:** auto-merge green patch/minor PRs; dispatch a bounded fix-loop for `RED` (patch/minor) and `MAJOR` PRs via the `renovate-ci-fixer`/`renovate-major-upgrader` agents (per `enable_ci_fixer`/`enable_major_upgrader`); park whatever a fix-loop can't safely resolve, or route a green major/test-touching fix to `renovator:review` for a human.

Runs fully autonomously, including under `/loop`. The human's window into a pass is the after-action report (step 8) plus the per-PR state annotations.

## Configuration
Read `.claude/renovator.json` from the repo root if it exists; otherwise use these defaults. Unknown keys are ignored; missing keys fall back to the default.

| knob | default | meaning |
|---|---|---|
| `renovate_authors` | `["renovate[bot]"]` | author logins that count as Renovate (override for self-hosted / on-prem Renovate) |
| `merge_method` | `"squash"` | `gh pr merge` method |
| `require_checks` | `true` | a PR with zero checks is skipped, never merged |
| `max_merges_per_pass` | `1` | merges performed per pass (serialize-and-rebase throttle) |
| `enable_ci_fixer` | `true` | attempt red-CI patch/minor fixes (else park as v1) |
| `enable_major_upgrader` | `true` | attempt major-version upgrades (else park as v1) |
| `fix_attempts` | `3` | max push→remote-CI cycles a fixer runs before parking |

Read it with, e.g.:
`jq -r '.renovate_authors // ["renovate[bot]"]' .claude/renovator.json 2>/dev/null` (fall back to defaults if the file or key is absent).

## Pass procedure

### 1. Preflight
- Confirm `gh auth status` succeeds and you are in a git repo with an `origin` remote (`git remote get-url origin`). If either fails, STOP and report exactly what is missing — do nothing else.
- Ensure the five lifecycle labels exist (idempotent; `--force` updates an existing label):
  - `gh label create renovator:working --color FBCA04 --description "renovator is processing this PR" --force`
  - `gh label create renovator:skipped --color EDEDED --description "renovator skipped this PR; will retry" --force`
  - `gh label create renovator:parked --color D93F0B --description "renovator parked this PR for review / v2" --force`
  - `gh label create renovator:fixing --color 1D76DB --description "renovator is running a fix-loop on this PR" --force`
  - `gh label create renovator:review --color 0E8A16 --description "renovator fixed this PR; awaiting human diff review" --force`

### 2. Fetch candidate PRs
- `gh pr list --state open --limit 100 --json number,title,author,headRefName,mergeStateStatus,statusCheckRollup,labels`
- Keep only PRs whose `author.login` is a member of `renovate_authors`. These are your candidates.

### 3. Skip locked PRs
- Any candidate already carrying the `renovator:working` label is owned by another run/agent — do not touch it this pass; record it with outcome `locked` for the report (step 8) and exclude it from classification.
- A candidate carrying `renovator:fixing` is an in-flight fix-loop. It MUST NOT be treated as a step-5 merge candidate — a green fixing PR must never be merged by step 5, because its test-edit gate has not been checked. Handle it ONLY in step 7 (resume), which re-derives the merge gate before any merge. Exclude `renovator:fixing` PRs from the `GREEN_SAFE` set that step 5 processes.

### 4. Classify
- Assign each remaining candidate a bucket per `references/classification.md` (bump type × CI status): `GREEN_SAFE`, `MAJOR`, `RED`, or `PENDING`. Record, for each candidate, the bump type and the `old_version` → `new_version` transition (the orchestrator reads the old version from the base-branch manifest/lockfile when the title names only the new version, per `references/classification.md`) — you pass these to the merger and use them in the report and annotation.

### 5. Merge green candidates (serialized)
Exclude any PR labeled `renovator:fixing` from this step — those are handled only by step 7. Process `GREEN_SAFE` PRs, performing at most `max_merges_per_pass` merges this pass (default 1), one at a time — never concurrently (siblings share lockfiles):
- Set state → working: add `renovator:working`, remove any other `renovator:*` label, and upsert the sticky comment with state `working` (see State annotation).
- Dispatch a `renovate-merger` subagent, passing `{ pr, bump, old_version, new_version, renovate_authors, merge_method, require_checks }`.
- On return, remove `renovator:working`, then:
  - `outcome: merged` → upsert the sticky comment's final line "merged by renovator"; the PR closes on merge.
  - `outcome: aborted`, `reason: behind` or `not-green` → set `renovator:skipped`, upsert comment with the reason (transient — will retry).
  - `outcome: aborted`, `reason: conflict` → set `renovator:parked`, upsert comment "merge conflict — needs manual resolution".
  - `outcome: aborted`, `reason: blocked` → set `renovator:parked`, upsert comment "blocked by branch protection (e.g. a required review) — needs a human".
  - `outcome: aborted`, `reason: bump-mismatch` or `identity` → set `renovator:parked`, upsert comment with the reason (the merger disagreed with classification — a human should look).

### 6. Drain the rest (active rebase)
- After this pass's merge lands, for every remaining `GREEN_SAFE` candidate NOT merged this pass: run `gh pr update-branch <n>` to update the branch with its base — this MERGES base into the head branch (it is not a rebase) and re-triggers CI. If it errors because the branch is already up to date or has conflicts, that is non-fatal — the PR resurfaces next pass. Set `renovator:skipped` and upsert the comment (state `skipped`, reason "rebasing after sibling merge"). They are re-evaluated next pass.
- If no merge happened this pass (nothing was `GREEN_SAFE`), skip this step.

### 7. Dispatch fix-loops (or park if disabled)
Process at most ONE fix-loop this pass (they push commits — serialize like merges). Prefer resuming a `renovator:fixing` PR over starting a new one.

For a `RED` PR (or a `renovator:fixing` PR whose bump is patch/minor):
- If `enable_ci_fixer` is false → park as v1 (`renovator:parked`, "CI failing — fixer disabled").
- Else run the fix-loop (below) with the `renovate-ci-fixer` agent.

For a `MAJOR` PR (or a `renovator:fixing` PR whose bump is major):
- If `enable_major_upgrader` is false → park as v1 (`renovator:parked`, "major version — upgrader disabled").
- Else run the fix-loop (below) with the `renovate-major-upgrader` agent.

For a `PENDING` PR → set `renovator:skipped`, reason "CI in progress — will retry" (unchanged from v1).

**Running the fix-loop for one PR:**

The normal path is a single dispatch that owns the whole `fix_attempts` budget: dispatch the fixer, it runs its push→remote-CI cycles inline and returns a terminal outcome, then you route that outcome. The `renovator:fixing` label and the persisted `fix_base_sha` exist only to cover the RESUME case — a prior dispatch that was interrupted (crash/timeout) or whose branch got clobbered by a Renovate rebase mid-loop.

Accounting rule: `attempt` is the number of push→remote-CI cycles ALREADY consumed on this PR (0 on a fresh start), matching the fixer's `fix-loop.md` contract. Track it from git, not a guess: each push→CI cycle lands at least one commit, so the commits the fixer has pushed since the loop's base SHA are a conservative count of cycles consumed.

1. `git fetch origin <headRefName>` so the branch's commit objects are local — the orchestrator learned this PR via the API and has not fetched it, so SHA math below would otherwise run against missing objects. If the fetch itself fails, skip this PR this pass (report outcome `skipped`, reason "could not fetch branch"). Then read persisted `fix_base_sha` and `dispatches` (default 0) from the sticky comment, and take the PR's current head SHA from the fetched ref.
2. **Clobber check:** run `git merge-base --is-ancestor <fix_base_sha> <head>` and branch on its EXIT CODE (do not conflate error with "not an ancestor"): exit 0 → still an ancestor, normal resume; exit 1 → the branch no longer contains `fix_base_sha` (Renovate force-rebased away the fixer's commits), so treat this as a clobber — a fresh start AND reset `dispatches` to 0; exit 2 or higher → a git error (e.g. a missing object), NOT a clobber — skip this PR this pass and retry next (do not clear `fix_base_sha`).
3. **Compute consumed cycles (`attempt`):**
   - Fresh start (no `fix_base_sha`): `attempt` is 0; set `fix_base_sha` to the current head SHA (the base before any fixer commit).
   - Resume (`fix_base_sha` set and still an ancestor): `attempt` is `git rev-list --count <fix_base_sha>..<head>` — the commits pushed since the loop began.
4. If `attempt` >= `fix_attempts` (cycles consumed) OR `dispatches` >= `fix_attempts` (dispatches made — this catches a fixer that keeps crashing before it can push a commit) → park `renovator:parked`; reason "attempts exhausted" when `attempt`-based, or "no progress after repeated fix attempts" when `dispatches`-based; keep the last summary. Stop.
5. Increment the persisted `dispatches` count (do this now, before dispatching, so an interrupted dispatch still counts against the bound). Set `renovator:fixing`; upsert the sticky comment with state `fixing`, `fix: <attempt>/<fix_attempts>`, `fix_base_sha`, and `dispatches`.
6. Dispatch the agent (`renovate-ci-fixer` or `renovate-major-upgrader`) with `{ pr, bump, old_version, new_version, fix_attempts, attempt, fix_loop_path }`. `fix_loop_path` is the absolute path to `references/fix-loop.md` inside this skill's own directory (this skill's base directory is provided to you when the skill is invoked; join it with `references/fix-loop.md`) — the fixer reads the shared doctrine from this path, not a bare relative path. Because `attempt` carries the already-consumed count, the fixer's own bounding (it sums `attempt` + its new pushes against `fix_attempts`) keeps the total across dispatches within budget.
7. The dispatch waits inline for the agent to reach a terminal outcome (it does not hand back mid-loop). On return, route by `outcome`:
   - `green` + bump is **major** → set `renovator:review` (a major upgrade NEVER auto-merges); upsert comment "fixed — awaiting human diff review (renovator authored these changes)", include the agent `summary` and its returned `attempts`.
   - `green` + bump is **patch/minor**: independently derive whether a test was touched — run `git diff --name-only <fix_base_sha>..<head>` and match each changed path against the repo's test paths (treat as a test if the path contains a `test/`, `tests/`, `spec/`, or `__tests__/` segment, or the filename matches `*_test.*` / `*.test.*` / `*.spec.*` / `*_spec.*`). Auto-merge ONLY if BOTH the agent returned `touched_tests: false` AND the diff shows no test path changed → dispatch `renovate-merger` exactly as in step 5 (its independent re-verify gates the merge); on `merged`, remove `renovator:*` and record `fixed-merged`.
   - `green` + bump is patch/minor but EITHER the agent returned `touched_tests: true` OR the diff shows a test path changed → set `renovator:review` (do not merge); upsert comment "fixed with test changes — awaiting human diff review", include the agent `summary`.
   - `exhausted` → set `renovator:parked`; upsert comment with `summary` + "attempts exhausted".
   - `needs-human` → set `renovator:parked`; upsert comment: "needs human — reproducible but not safely fixable: " + `summary`.
   - `cannot-reproduce` → set `renovator:parked`; upsert comment: "can't reproduce CI locally — " + `summary`.
   - If the dispatch was interrupted (crashed/timed out) before returning any outcome → leave `renovator:fixing` and `fix_base_sha` in place; the NEXT pass recomputes `attempt` from the commit count (steps 1–3), which accurately reflects cycles actually consumed — do NOT guess an increment. If that recomputed `attempt` has reached `fix_attempts`, step 4 parks it.

### 8. Report
Print a compact table — one row per candidate: `PR # | title | bump | bucket | outcome` (outcome ∈ merged / fixed-merged / review / fixing / parked / skipped / rebasing / locked). This is the human's after-action view of the pass.

## State annotation

Two layers per PR:

- **Labels** — mutually exclusive: exactly one of `renovator:working` / `renovator:skipped` / `renovator:parked` / `renovator:fixing` / `renovator:review` at a time. Before adding one, remove the others:
  `gh pr edit <n> --add-label renovator:parked --remove-label renovator:working --remove-label renovator:skipped --remove-label renovator:fixing --remove-label renovator:review`
- **Sticky comment** — exactly ONE renovator comment per PR, found by the hidden marker `<!-- renovator-state -->` on its first line. Upsert it:
  1. Find it: `gh pr view <n> --json comments --jq '.comments[] | select(.body | startswith("<!-- renovator-state -->")) | .url'` (empty ⇒ none yet).
  2. If none, create: `gh pr comment <n> --body "<body>"`.
  3. If one exists, edit it in place. The REST PATCH needs the **numeric** comment id — this is the trailing number of the comment `url` (`…#issuecomment-123456`), NOT the `.id` field from `--json comments` (that is a GraphQL node id and will not work). Extract it from the url and PATCH:
     ```
     url=$(gh pr view <n> --json comments --jq '.comments[] | select(.body | startswith("<!-- renovator-state -->")) | .url' | head -n1)
     id=${url##*issuecomment-}
     gh api -X PATCH repos/{owner}/{repo}/issues/comments/"$id" -f body="<body>"
     ```
  Never post a second renovator comment.

  Comment `<body>` template (first line is the marker):
  ```
  <!-- renovator-state -->
  **renovator** · state: `<working|skipped|parked|fixing|review>` · <reason>
  - update: `<dep>` <old> → <new> (<bump>)
  - CI: <last conclusion>
  - fix: `<attempt>/<fix_attempts>` · base `<short fix_base_sha>` · dispatches `<dispatches>`
  - summary: <agent summary, when parked/review>
  - updated: <UTC timestamp>
  ```
  Timestamp via `date -u +%Y-%m-%dT%H:%M:%SZ` (portable; avoid the GNU-only `-Iseconds` date flag).

- **Idempotent by construction:** every pass sets labels to the target state and upserts the one comment, so re-running never duplicates.

## Under /loop
Each invocation is one full pass. `PENDING`/rebasing/parked PRs resolve over subsequent passes as Renovate rebases and CI re-runs. No state persists outside the PRs themselves (labels + the one comment).

## Never do
- Never merge more than `max_merges_per_pass` per pass; never run more than one fix-loop per pass.
- Never merge a `MAJOR` upgrade or any fix that edited a test — those go to `renovator:review` for a human.
- Never let a fixer fake green (delete/skip a test, blanket-suppress an error, or loosen an assertion to pass) — that is a park.
- Never exceed `fix_attempts` push→CI cycles on a PR — park instead.
- Never merge a PR whose author is not in `renovate_authors`.
