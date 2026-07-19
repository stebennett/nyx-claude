# renovator — design

**Status:** approved (design) · **Date:** 2026-07-18 · **Plugin:** `devtools` (new)

## Purpose

`renovator` autonomously drains a repository's queue of open [Renovate](https://docs.renovatebot.com/)
dependency PRs. It merges the PRs that are provably safe and green, and — in a later phase — works
the harder upgrades (major versions, red CI) to green inside isolated worktrees before merging.

It is built as a **thin orchestrator skill + specialist subagents**, so that the expensive,
judgment-heavy work runs in isolated contexts on the cheapest capable model, while the coordinator's
context stays flat regardless of how many PRs are in flight. This is the same pattern as this repo's
`kanban-flow` plugin.

## Autonomy posture

**Fully autonomous.** Designed to run unattended, including under `/loop`. Patch/minor green PRs merge
with no human confirmation. The human's window into what happened is the after-action report each pass
plus the per-PR state annotations. The posture is made defensible by the safety invariants below, not
by a human at the merge point.

## Scope

Phased, merge-first.

- **v1 (this build):** orchestrator + patch/minor/green **auto-merge**. Everything else
  (major versions, red CI) is **parked** with a state annotation for a human or for v2.
- **v2 (later):** worktree-based fix-loops for major upgrades and red CI. The design leaves clean
  seams (Section: v2 extension points) so v2 slots in without reshaping v1.

## Environment assumptions

- `gh` CLI installed and authenticated.
- Operates on the **current working directory's repo** (its `origin` remote).
- CI status is read via `gh pr checks` / the checks API — i.e. GitHub-hosted CI (Actions or any
  status-check-reporting CI).
- Renovate PRs are identified by author login, configurable via `renovate_authors`
  (default `["renovate[bot]"]`) to support self-hosted / on-prem Renovate whose bot identity differs.

## Plugin & component layout

```
plugins/devtools/
  .claude-plugin/plugin.json          # name: devtools, version 0.1.0
  skills/renovator/SKILL.md           # the orchestrator (thin coordinator)
  agents/renovate-merger.md           # haiku — mechanical verify+merge of one PR
  README.md
```

Registered in `.claude-plugin/marketplace.json`. `${CLAUDE_PLUGIN_ROOT}` is not required (no
hooks/MCP). v2 adds `agents/renovate-major-upgrader.md`, `agents/renovate-ci-fixer.md`, and a
worktree-isolation reference doc.

## Configuration

The skill reads an optional repo-level `.claude/renovator.json`; absent that, documented defaults
apply, so a stock GitHub + hosted-Renovate repo needs zero setup.

| knob | default | purpose |
|---|---|---|
| `renovate_authors` | `["renovate[bot]"]` | who counts as Renovate (self-hosted override) |
| `merge_method` | `squash` | `gh pr merge` method |
| `require_checks` | `true` | if a PR has zero checks, skip rather than merge |
| `max_merges_per_pass` | `1` | serialize-and-rebase throttle (see Concurrency) |

## Orchestrator control flow (`renovator` skill)

The skill classifies and dispatches; it never merges or edits a branch itself. Its context holds only
the PR list plus one-line verdicts.

1. **Preflight** (inline): confirm `gh` is authenticated and we are in a git repo with an `origin`.
   Abort with a clear message otherwise.
2. **Fetch Renovate PRs** — one `gh pr list` filtered to authors in `renovate_authors`, open PRs,
   pulling number, title, `headRefName`, and check-status rollup. This is the only bulk data held.
3. **Skip locked PRs** — any PR already labeled `renovator:working` is owned by another run; skip it.
4. **Classify** each PR into a bucket (below).
5. **Dispatch** — serialized (see Concurrency). For each `GREEN_SAFE` PR up to `max_merges_per_pass`:
   set `renovator:working`, launch a `renovate-merger` subagent, clear `renovator:working` on return,
   annotate the outcome.
6. **Rebase the rest** — after a merge lands, trigger `gh pr update-branch` on the remaining
   `GREEN_SAFE` candidates so they rebase and CI re-runs (they become `PENDING`); label them
   `renovator:skipped` (rebasing). They are picked up on the next pass.
7. **Park** — `MAJOR` / `RED` PRs get `renovator:parked` + a state comment (v1). In v2 these dispatch
   the corresponding fix-loop agent instead.
8. **Report** — a compact end-of-run table: each PR, its bucket, and outcome
   (merged / parked / skipped-pending / rebasing).

Runs cleanly under `/loop`: each invocation is a full pass; `PENDING`/rebasing/parked PRs are
re-evaluated next pass. No persistent state beyond what lives on the PRs (labels/comments).

**Model:** orchestrator is lightweight classify+dispatch; it recommends a model in its guidance but
inherits the session model. The expensive work is pushed into pinned agents.

## Classification (bump-type + CI)

**Bump type (patch / minor / major):**

- **Primary:** parse the version transition from the Renovate PR title (highly structured, e.g.
  `Update dependency foo to v2.3.1`, `... from 1.2.3 to 1.2.4`). Compare old→new semver.
- **Fallback / ambiguity rule:** if both versions cannot be extracted and compared with confidence
  (digests, pinned SHAs, ranges, non-semver, grouped multi-package PRs with differing bumps) →
  classify as `MAJOR` (the conservative park bucket). Never guess "safe".
- **Grouped PRs:** if any member is major or unparseable → the whole PR is `MAJOR`.

**CI status:** from the check rollup — `SUCCESS` → green; `FAILURE`/`ERROR`/`CANCELLED` → `RED`;
`PENDING`/`IN_PROGRESS` or no checks yet → `PENDING`. A PR with **zero** checks is treated as
`PENDING`/skip when `require_checks` is true (never auto-merge with no CI signal).

**Bucket = f(bump, CI):**

| | CI green | CI red | CI pending |
|---|---|---|---|
| **patch/minor** | `GREEN_SAFE` → merge | `RED` → park (v2 fix) | `PENDING` → skip |
| **major / ambiguous** | `MAJOR` → park (v2 upgrade) | `MAJOR` → park (v2) | `MAJOR` → park |

Conservative bias throughout: anything not provably a safe, green patch/minor is parked, never merged.

## Concurrency & staleness

Renovate PRs almost all touch the same manifest + lockfile, so concurrent or batch-trusted merges are
unsafe: two green PRs conflict, and once PR #1 lands, PR #2's green CI was run against a stale base.

**Rules:**

1. **Serialize merges.** Mergers are dispatched one at a time (`max_merges_per_pass`, default 1), not
   fanned out — eliminating lockfile write-races.
2. **Re-verify live before merging.** The batch classification is a *candidate* list only. Inside its
   isolated context the merger checks the PR's live `mergeStateStatus` + check rollup:
   - `CLEAN` + green → merge.
   - `BEHIND` (base moved because a sibling merged) → stale green; do **not** merge.
   - `DIRTY` (real conflict) / `BLOCKED` → park.
3. **Drain via active rebase.** After the pass's merge, trigger `gh pr update-branch` on the remaining
   candidates so they rebase and CI re-runs (→ `PENDING`, labeled `renovator:skipped`). The next pass
   merges the next now-green PR. One merge per pass; the pipeline keeps moving without waiting on
   Renovate's own rebase schedule.

## `renovate-merger` agent (haiku)

One PR in, a merge outcome out. Isolated context; pinned to **haiku** — the job is a short mechanical
`gh` sequence with no open-ended reasoning.

- **Frontmatter:** `model: haiku`, `tools: Bash, Read`. Never touches files (no Edit/Write).
- **Input:** PR number + expected bump type (`patch`/`minor`) from the orchestrator.
- **Procedure:**
  1. Re-fetch the PR live (`mergeStateStatus`, check rollup, author, title, base).
  2. **Independent re-verification** (never trust the caller blindly):
     - author ∈ `renovate_authors`,
     - re-parse title, bump type still patch/minor,
     - check rollup still `SUCCESS`,
     - `mergeStateStatus` is `CLEAN`.
     Any failure → abort without merging; return structured reason
     (`behind` / `conflict` / `not-green` / `bump-mismatch` / `identity`).
  3. Merge — `gh pr merge <n> --<merge_method> --delete-branch` (`squash` default).
  4. Return a compact result `{pr, outcome: merged|aborted, reason}`. No prose into the orchestrator's
     context.
- **Why the split earns its keep:** transient `gh` JSON stays in the throwaway agent context; only the
  one-line result reaches the orchestrator. Cheapest model because every branch is a deterministic
  check. The independent re-verification is the safety backstop that makes unattended merge
  defensible — two independent classifications must agree.

## PR state annotation

Two layers per PR: **labels** (at-a-glance, filterable, mutually exclusive) + **one sticky comment**
(human-readable detail, updated in place — never spammed).

**Lifecycle labels** (exactly one `renovator:*` at a time; transitioning removes the prior):

| Label | Meaning | Set when |
|---|---|---|
| `renovator:working` | an agent is processing it now | on dispatch; **cleared** on completion |
| `renovator:skipped` | transient — resolves itself | CI `PENDING`, or `BEHIND`/rebasing |
| `renovator:parked` | needs intervention (v2/human) | `MAJOR`, `RED`, conflict, attempts exhausted |

Merged PRs close, so no terminal label — the sticky comment's final line records the renovator merge.

**`renovator:working` as a lock:** a PR already carrying it is owned by another run and is skipped.
Set-before-dispatch, clear-after. Stale-lock recovery (an agent that dies mid-merge) is a v2 hardening
item; v1 keeps the simple set/clear.

**Sticky comment:** anchored with a hidden marker (`<!-- renovator-state -->`) so the skill edits the
same comment each pass. Carries: state + reason, bump type + version transition, last CI conclusion,
attempt count (v2), and a UTC timestamp.

**Idempotent by construction** — labels set to the target state, the one comment upserted; re-running
is always safe and never duplicates.

## v2 extension points (not built in v1)

- **`renovate-major-upgrader` agent (opus).** For a `MAJOR` PR: create a worktree (via the
  `using-git-worktrees` skill), pull the **authoritative changelog / release notes** — Renovate
  embeds release notes + changelog links in the PR body (first-class source); fall back to the
  package's repo releases — derive a plan, implement the required code changes, push, wait for CI, and
  loop **up to the bounded attempt cap**, then merge on green or park with a written summary of what
  was tried and why it is stuck.
- **`renovate-ci-fixer` agent (sonnet).** Same bounded worktree loop for a patch/minor PR whose CI is
  `RED`: diagnose, fix, push, re-check, merge-or-park.
- **Orchestrator change:** `MAJOR`/`RED` branches move from "park" to "dispatch agent". The
  bounded-attempts + park-on-exhaustion behavior is enforced by the orchestrator.
- v1's `renovator:parked` labels become v2's work queue; annotation mechanics are unchanged.

**Failure boundary (v2):** bounded attempts (N push/CI cycles or a token/cost ceiling), then park with
a summary. Never an unbounded loop.

## Model tiering & token economics

| Component | Model | Why |
|---|---|---|
| `renovator` orchestrator | inherits session (recommend sonnet) | list + classify + dispatch; holds only verdicts |
| `renovate-merger` | **haiku** | deterministic `gh` checks + merge, zero judgment |
| `renovate-major-upgrader` (v2) | **opus** | reads changelogs, plans + writes code changes |
| `renovate-ci-fixer` (v2) | **sonnet** | diagnose + fix a known-scoped failure |

A repo with N Renovate PRs runs N haiku merger contexts whose transient `gh` JSON never touches the
orchestrator — the orchestrator's context stays flat regardless of PR count. Expensive opus reasoning
(v2) fires only for the handful of major upgrades, one isolated context each.

## Safety invariants

The fully-autonomous posture rests on:

- **Two independent classifications must agree** (orchestrator + merger re-verify) before any merge.
- **Conservative bias** — ambiguous bump, no checks, or any doubt ⇒ park, never merge.
- **Serialized merges + live `mergeStateStatus` re-check** ⇒ no stale/racy merge can land.
- **Configurable identity backstop** (`renovate_authors`) ⇒ only bot dependency PRs auto-merge.
- **`renovator:working` lock** ⇒ concurrent/`/loop` passes never double-process a PR.
- **Bounded fix-loops + park-with-summary** (v2) ⇒ no infinite token burn; a clear trail for humans.
- **Full after-action report** every pass ⇒ the human's view into unattended runs.

## Out of scope

- Non-GitHub hosts / non-`gh` tooling.
- Non-Renovate dependency bots (Dependabot, etc.) — not targeted, though `renovate_authors` could in
  principle be pointed at another bot.
- Configuring Renovate itself.
- v2 fix-loop implementation (major upgrades, red-CI recovery) — designed here, built later.
