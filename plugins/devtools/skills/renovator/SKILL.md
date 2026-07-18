---
name: renovator
description: Autonomously drain a repository's open Renovate dependency PRs — merge the provably-safe green patch/minor ones and park the rest with state annotations. Each invocation is one full pass; safe to run under /loop. Dispatches a haiku merger agent per merge so this orchestrator's context stays flat regardless of PR count. Use when asked to process, merge, or triage Renovate dependency update PRs.
---

# renovator — drain the Renovate PR queue

You are the coordinator. You classify each open Renovate PR and dispatch work; you NEVER merge or edit a branch yourself — the `renovate-merger` agent performs merges in its own isolated context. Keep your context lean: hold only the PR list and one-line verdicts, not per-PR `gh` output.

**v1 scope:** auto-merge green patch/minor PRs; PARK everything else (major versions, red CI). The major-upgrade and red-CI fix-loops are a later phase — do not attempt them.

Runs fully autonomously, including under `/loop`. The human's window into a pass is the after-action report (step 8) plus the per-PR state annotations.

## Configuration
Read `.claude/renovator.json` from the repo root if it exists; otherwise use these defaults. Unknown keys are ignored; missing keys fall back to the default.

| knob | default | meaning |
|---|---|---|
| `renovate_authors` | `["renovate[bot]"]` | author logins that count as Renovate (override for self-hosted / on-prem Renovate) |
| `merge_method` | `"squash"` | `gh pr merge` method |
| `require_checks` | `true` | a PR with zero checks is skipped, never merged |
| `max_merges_per_pass` | `1` | merges performed per pass (serialize-and-rebase throttle) |

Read it with, e.g.:
`jq -r '.renovate_authors // ["renovate[bot]"]' .claude/renovator.json 2>/dev/null` (fall back to defaults if the file or key is absent).

## Pass procedure

### 1. Preflight
- Confirm `gh auth status` succeeds and you are in a git repo with an `origin` remote (`git remote get-url origin`). If either fails, STOP and report exactly what is missing — do nothing else.
- Ensure the three lifecycle labels exist (idempotent; `--force` updates an existing label):
  - `gh label create renovator:working --color FBCA04 --description "renovator is processing this PR" --force`
  - `gh label create renovator:skipped --color EDEDED --description "renovator skipped this PR; will retry" --force`
  - `gh label create renovator:parked --color D93F0B --description "renovator parked this PR for review / v2" --force`

### 2. Fetch candidate PRs
- `gh pr list --state open --limit 100 --json number,title,author,headRefName,mergeStateStatus,statusCheckRollup,labels`
- Keep only PRs whose `author.login` is a member of `renovate_authors`. These are your candidates.

### 3. Skip locked PRs
- Any candidate already carrying the `renovator:working` label is owned by another run/agent — skip it this pass (do not touch it).

### 4. Classify
- Assign each remaining candidate a bucket per `references/classification.md` (bump type × CI status): `GREEN_SAFE`, `MAJOR`, `RED`, or `PENDING`. Record the bump type and version transition for the report and annotation.

### 5. Merge green candidates (serialized)
Process `GREEN_SAFE` PRs, performing at most `max_merges_per_pass` merges this pass (default 1), one at a time — never concurrently (siblings share lockfiles):
- Set state → working: add `renovator:working`, remove any other `renovator:*` label, and upsert the sticky comment with state `working` (see State annotation).
- Dispatch a `renovate-merger` subagent, passing `{ pr, bump, renovate_authors, merge_method, require_checks }`.
- On return, remove `renovator:working`, then:
  - `outcome: merged` → upsert the sticky comment's final line "merged by renovator"; the PR closes on merge.
  - `outcome: aborted`, `reason: behind` or `not-green` → set `renovator:skipped`, upsert comment with the reason (transient — will retry).
  - `outcome: aborted`, `reason: conflict` → set `renovator:parked`, upsert comment "merge conflict — needs manual resolution".
  - `outcome: aborted`, `reason: bump-mismatch` or `identity` → set `renovator:parked`, upsert comment with the reason (the merger disagreed with classification — a human should look).

### 6. Drain the rest (active rebase)
- After this pass's merge lands, for every remaining `GREEN_SAFE` candidate NOT merged this pass: run `gh pr update-branch <n>` so it rebases onto the new base and CI re-runs. Set `renovator:skipped` and upsert the comment (state `skipped`, reason "rebasing after sibling merge"). They are re-evaluated next pass.
- If no merge happened this pass (nothing was `GREEN_SAFE`), skip this step.

### 7. Park the rest
- `MAJOR` → set `renovator:parked`, upsert comment: bucket `major`, the version transition, reason "major version — needs manual upgrade (renovator v2 will automate this)".
- `RED` → set `renovator:parked`, upsert comment: bucket `red`, reason "CI failing — needs manual fix (renovator v2 will automate this)".
- `PENDING` → set `renovator:skipped`, upsert comment: reason "CI in progress — will retry".

### 8. Report
Print a compact table — one row per candidate: `PR # | title | bump | bucket | outcome` (outcome ∈ merged / parked / skipped / rebasing / locked). This is the human's after-action view of the pass.

## State annotation

Two layers per PR:

- **Labels** — mutually exclusive: exactly one of `renovator:working` / `renovator:skipped` / `renovator:parked` at a time. Before adding one, remove the others:
  `gh pr edit <n> --add-label renovator:parked --remove-label renovator:working --remove-label renovator:skipped`
- **Sticky comment** — exactly ONE renovator comment per PR, found by the hidden marker `<!-- renovator-state -->` on its first line. Upsert it:
  1. Find it: `gh pr view <n> --json comments --jq '.comments[] | select(.body | startswith("<!-- renovator-state -->")) | .url'` (empty ⇒ none yet).
  2. If none, create: `gh pr comment <n> --body "<body>"`.
  3. If one exists, edit it in place via the REST API using its id (derive the numeric id from the comment url, then `gh api -X PATCH repos/{owner}/{repo}/issues/comments/{id} -f body="<body>"`).
  Never post a second renovator comment.

  Comment `<body>` template (first line is the marker):
  ```
  <!-- renovator-state -->
  **renovator** · state: `<working|skipped|parked>` · <reason>
  - update: `<dep>` <old> → <new> (<bump>)
  - CI: <last conclusion>
  - updated: <UTC timestamp>
  ```
  Timestamp via `date -u +%Y-%m-%dT%H:%M:%SZ` (portable; avoid the GNU-only `-Iseconds` date flag).

- **Idempotent by construction:** every pass sets labels to the target state and upserts the one comment, so re-running never duplicates.

## Under /loop
Each invocation is one full pass. `PENDING`/rebasing/parked PRs resolve over subsequent passes as Renovate rebases and CI re-runs. No state persists outside the PRs themselves (labels + the one comment).

## Never do (v1)
- Never merge more than `max_merges_per_pass` per pass.
- Never merge a `MAJOR`, `RED`, or `PENDING` PR.
- Never edit a branch, resolve a conflict, or fix CI — that is v2.
- Never merge a PR whose author is not in `renovate_authors`.
