# renovator v2 — autonomous fix-loops for major upgrades & red CI

**Status:** approved (design) · **Date:** 2026-07-18 · **Plugin:** `devtools` · **Builds on:** [renovator v1](2026-07-18-renovator-design.md)

## Purpose

v1 auto-merges the provably-safe green patch/minor Renovate PRs and **parks** everything harder —
major-version upgrades and PRs with red CI. v2 takes on those parked PRs: an agent works each one to
green inside a git worktree via a **bounded fix-loop**, then merges it (only the low-risk case) or
parks it for human review.

The leap in risk from v1 is deliberate and bounded: v1 merged *Renovate's own mechanical* changes; v2
has an agent **writing its own code** to make a broken upgrade pass. So v2 keeps agent-authored code
from landing unattended except in the one low-risk case, and never lets the loop run unbounded.

Built on v1's structure — thin orchestrator skill + specialist agents + shared reference docs — so v2
slots into the existing `devtools` plugin without reshaping v1.

## Scope

Both fixer agents ship in this build:

- **`renovate-ci-fixer` (sonnet)** — red-CI patch/minor PRs.
- **`renovate-major-upgrader` (opus)** — major-version PRs.

Plus the shared `fix-loop.md` doctrine and the orchestrator changes to dispatch (instead of park) and
drive the loop across passes. v1's `renovate-merger` is reused for the actual merge.

## Autonomy posture

Fully autonomous, but agent-authored code is gated by risk:

- **Red-CI patch/minor, fixed with adaptation only (no test edits)** → auto-merge on green.
- **Red-CI patch/minor, fix edited any test** → park for human diff review.
- **Any major-version upgrade** → park for human diff review on green (never auto-merge).
- **Exhausted / can't reproduce CI** → park stuck, with a summary.

## Environment assumptions

Inherits v1's (GitHub-hosted CI, `gh` authenticated, `jq`, configurable `renovate_authors`), plus:

- The repo uses **GitHub Actions** (`.github/workflows/*.yml`) or documents its build/test commands
  (CLAUDE.md / README) so the loop can derive a local test recipe.
- The local environment can run the repo's toolchain (else the loop falls back or parks — see
  fix-loop step 7).
- `git worktree` is available (v1 already targets local git).

## Component layout

New files under the existing `devtools` plugin; one modified:

```
plugins/devtools/
  agents/
    renovate-ci-fixer.md            # sonnet — red-CI patch/minor fix-loop
    renovate-major-upgrader.md      # opus  — major-version upgrade fix-loop
  skills/renovator/references/
    fix-loop.md                     # shared doctrine both fixer agents read (DRY)
  skills/renovator/SKILL.md         # MODIFIED — dispatch instead of park; drive loop across passes
```

`renovate-merger` (v1, haiku) is reused unchanged for the actual merge of a fixed red-CI PR, so the
"two independent classifications before an unattended merge" invariant holds even for fixed PRs.

## The shared fix-loop doctrine (`fix-loop.md`)

The reusable heart. Both fixer agents follow it; each adds only its own front-matter (changelog
reading for the major upgrader; nothing extra for the ci-fixer).

1. **Set up** — create a git worktree on the PR branch (via the `using-git-worktrees` skill).
2. **Discover the test/build recipe**, in priority order:
   1. `CLAUDE.md` / `AGENTS.md` — human-curated exact build/test/lint commands (most authoritative for
      *how to run locally*).
   2. `README.md` / `CONTRIBUTING.md` — dev-setup and test instructions.
   3. Project manifests — `package.json` scripts, `Makefile`/`justfile`, `pyproject.toml`/`tox.ini`,
      `cargo`, `go test ./...`.
   4. `.github/workflows/*.yml` — the jobs triggered on this PR and their `run:` steps + toolchain
      setup; what CI **actually enforces**.

   **Reconciliation:** use sources 1–3 for the ergonomic local commands, but cross-check against the
   workflow files so you reproduce what CI will enforce. If they diverge, remote CI (step 5) is the
   final authority. If no source yields a runnable recipe → step 7 fallback.
3. **Reproduce locally & iterate (cheap inner loop)** — run the recipe in the worktree; on failure,
   make adaptation changes and re-run. Fast, no network round-trip. Local iterations are self-capped
   to avoid runaway.
4. **Change-scope guardrails** — may change call sites / config / app code to adapt to the new
   dependency. **May edit tests only when the dependency legitimately changed behavior, recording a
   per-test justification** in the summary. **Forbidden:** deleting or skipping tests to force green;
   blanket suppress/ignore directives (`@ts-ignore`, broad `# noqa`, `--no-verify`); loosening an
   assertion without a documented dependency-behavior reason. Never fake green.
5. **Confirm remotely** — once locally green, push **once**; remote CI is authoritative. If remote
   fails where local passed (env drift), feed that failure back for one more local iteration.
6. **Bounding** — the `fix_attempts` cap (default 3) bounds the expensive push→remote-CI cycles. On
   exhaustion → park with a summary of what was tried and the last failure.
7. **Fallback (never fake green)** — if the workflow can't be faithfully reproduced locally (missing
   toolchain, needs services/secrets/containers, self-hosted runners), fall back to
   push-and-read-remote-CI; if that is impractical too, park "can't reproduce CI locally" for a human.
8. **Outcome hand-off** — report to the orchestrator:
   `{ outcome: green | exhausted | cannot-reproduce, touched_tests: <bool>, summary, attempts }`.
   The orchestrator decides merge vs park-for-review vs park-stuck.

## The two fixer agents

Thin wrappers over `fix-loop.md`; they differ only in model and one front-loaded step. Both get
tools `Read, Grep, Glob, Edit, Write, Bash` (they write code and run tests) plus `Skill`.

- **`renovate-ci-fixer` (sonnet).** Input: a `RED` patch/minor PR. Runs the shared loop directly (the
  bump already happened; it's fixing fallout). Outcomes:
  - `green` + `touched_tests: false` → orchestrator dispatches `renovate-merger` to merge.
  - `green` + `touched_tests: true` → orchestrator parks for review (`renovator:review`).
  - `exhausted` / `cannot-reproduce` → orchestrator parks stuck (`renovator:parked`).
- **`renovate-major-upgrader` (opus).** Input: a `MAJOR` PR. **Extra first step:** read the
  changelog / release notes Renovate embeds in the PR body (first-class source; fall back to the
  package's GitHub releases) and note the breaking changes *before* touching code — the judgment that
  justifies opus. Then the shared loop. Outcome:
  - `green` → **always park for review** (`renovator:review`); never auto-merge.
  - `exhausted` / `cannot-reproduce` → park stuck (`renovator:parked`).

## Orchestrator changes & fix-loop state

New lifecycle states (labels), added to v1's `working` / `skipped` / `parked`:

- **`renovator:fixing`** — a fix-loop is in progress on this PR (spans `/loop` passes; a pass resumes
  it, does not restart it). Acts as the fix-loop lock — one fix-loop at a time (they push commits).
- **`renovator:review`** — green, agent-authored diff awaiting human review (all major upgrades on
  green; red-CI fixes that touched tests). Terminal for the bot — ball in the human's court.
- **`renovator:parked`** (existing) — stuck: attempts exhausted or can't reproduce; needs human help.

Changes to the pass procedure:

- **Step 7 dispatches instead of parking:** `MAJOR` → `renovate-major-upgrader` (when
  `enable_major_upgrader`); `RED` → `renovate-ci-fixer` (when `enable_ci_fixer`). Subject to the same
  one-at-a-time serialization as merges (these push commits). If a knob is disabled, fall back to v1
  park behavior for that bucket.
- **Attempt state persisted on the PR** in the sticky comment: `attempt: k/fix_attempts` and the head
  SHA the last attempt ran against. Survives passes and agent restarts.
- **Renovate-clobber handling:** if a pass finds the PR head SHA changed unexpectedly (Renovate
  rebased/force-pushed and the agent's commits are gone), reset the attempt counter and restart the
  loop — bounded by `fix_attempts`, so it cannot runaway.
- **Merge hand-off:** on `green` + adaptation-only red-CI, dispatch `renovate-merger` for the merge
  (its independent re-verify still gates the merge). On any park outcome, set the matching label and
  upsert the sticky comment with the agent's summary.
- **Report:** step 8's outcome set gains `fixing` / `review` / `fixed-merged` alongside v1's outcomes.

## Configuration

New knobs (all optional; sane defaults). Read from `.claude/renovator.json` as in v1.

| knob | default | purpose |
|---|---|---|
| `enable_ci_fixer` | `true` | attempt red-CI patch/minor fixes (else park as v1) |
| `enable_major_upgrader` | `true` | attempt major-version upgrades (else park as v1) |
| `fix_attempts` | `3` | max push→remote-CI cycles before park |

## Model tiering & token economics

| Component | Model | Why |
|---|---|---|
| `renovator` orchestrator | inherits session | dispatch + cross-pass loop control; holds only verdicts |
| `renovate-ci-fixer` | **sonnet** | diagnose + adapt a known-scoped red-CI failure |
| `renovate-major-upgrader` | **opus** | read changelogs, reason about breaking changes, plan + write code |
| `renovate-merger` (reused) | **haiku** | deterministic re-verify + merge |

The expensive opus reasoning fires only for major upgrades, one isolated worktree context each; the
orchestrator context stays flat.

## Safety invariants (v2 additions to v1's)

- **Never fake green** — local fallback → remote → park; never delete/skip a test or blanket-suppress
  an error to force green.
- **Agent-authored code never merges unattended** except adaptation-only red-CI patch/minor fixes; any
  test edit or any major upgrade → `renovator:review` for a human.
- **Bounded attempts + park-with-summary** — `fix_attempts` caps remote cycles; local cycles
  self-capped. No infinite or costly loop.
- **The actual merge still goes through `renovate-merger`'s independent re-verification** — two
  independent classifications before any unattended merge, even for a fixed PR.
- **`renovator:fixing` is the fix-loop lock** — one fix-loop at a time; they push commits and would
  otherwise race.
- **Clobber-safe** — a Renovate rebase that wipes the agent's commits is detected and restarts within
  the attempt budget, never a runaway.

## Out of scope

- Non-GitHub-Actions CI discovery beyond documented commands (self-hosted/other CI → local fallback or
  park).
- Auto-merging major upgrades or any test-touching fix (always human review).
- Coordinating interacting upgrades (e.g. two majors that must land together) — each PR is worked
  independently; cross-PR orchestration is future work.
- Modifying Renovate's own configuration.
