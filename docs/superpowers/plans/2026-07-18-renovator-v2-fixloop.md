# renovator v2 (fix-loops) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add v2 to the `devtools` plugin's `renovator` skill — two specialist agents that work the Renovate PRs v1 parks (major upgrades, red CI) to green via a bounded worktree fix-loop, then merge (the one low-risk case) or park for human review.

**Architecture:** A shared `fix-loop.md` doctrine (worktree → discover the test recipe → iterate locally → confirm on remote CI → bounded by `fix_attempts` → hand outcome back) is read by two agents: `renovate-ci-fixer` (sonnet, red-CI patch/minor) and `renovate-major-upgrader` (opus, major, changelog-first). The `renovator` orchestrator dispatches instead of parking, drives the loop across `/loop` passes via attempt-state persisted on the PR, and reuses v1's `renovate-merger` (haiku) for the actual merge of an adaptation-only red-CI fix.

**Tech Stack:** Claude Code plugin components (Markdown agents/skills). Runtime deps: `gh` (authenticated), `jq`, `git worktree`, and the target repo's own toolchain (for local test runs). No application code, no test runner in THIS repo.

## Testing note (read before Task 1)

This repo has **no build/test runner** — components are Markdown, validated by static checks and by exercising the plugin (CLAUDE.md). The TDD cycle is adapted exactly as in the v1 plan: each task's "test" is a concrete **validation command** (`grep`/`jq`) asserting the deliverable's key property — it fails before the file exists / edit is made, and passes after. The one true end-to-end check (running a fixer against a live broken Renovate PR) is a documented human exercise in Task 5.

## Global Constraints

Copied verbatim from the v2 spec and CLAUDE.md — every task implicitly includes these:

- **Portability:** any shell shown in a component body must run on bash 3.2 (macOS) and Linux. No GNU-isms: no `grep -oP`/`\K`, no `find -printf`, no `date -Iseconds`. Use `date -u +%Y-%m-%dT%H:%M:%SZ`, `sed -nE`, `${var##*x}`.
- **Runtime deps:** `gh` (authenticated), `jq`, `git worktree`. Fixer agents also run the *target repo's* toolchain locally. Do not add new hard deps to this plugin.
- **Never fake green:** a fixer must never delete/skip a test, blanket-suppress an error (`@ts-ignore`, broad `# noqa`, `--no-verify`), or loosen an assertion without a documented dependency-behavior reason to reach green. If green needs a forbidden change → park.
- **Agent-authored code gating:** auto-merge (via `renovate-merger`) fires ONLY for a red-CI patch/minor fix that is `green` AND `touched_tests: false`. Any test edit → park `renovator:review`. Any major upgrade → park `renovator:review` on green, never auto-merge.
- **Bounded:** `fix_attempts` (default 3) caps push→remote-CI cycles; local cycles self-capped. On exhaustion → park with a summary.
- **Configurable identity preserved:** v1's `renovate_authors` still governs which PRs are Renovate's; unchanged.
- **The merge still goes through `renovate-merger`'s independent re-verification** — two independent classifications before any unattended merge, even for a fixed PR.
- **Outcome contract (exact):** a fixer returns `{ "pr": <n>, "outcome": "green" | "exhausted" | "cannot-reproduce", "touched_tests": <bool>, "attempts": <k>, "summary": "<...>" }`.
- **v2 stacks on v1:** the current branch already contains v1 (`renovate-merger`, `classification.md`, the v1 `SKILL.md`). Do not re-create v1 files; Task 4 MODIFIES the existing `SKILL.md`.
- **RTK proxy:** this machine rewrites `cat`/`grep`/`git`; fall back to `rtk proxy <cmd>` if a flag is rejected.

## File structure

| File | Responsibility |
|---|---|
| `plugins/devtools/skills/renovator/references/fix-loop.md` (create) | Shared fix-loop doctrine + outcome contract |
| `plugins/devtools/agents/renovate-ci-fixer.md` (create) | sonnet agent: red-CI patch/minor fix-loop |
| `plugins/devtools/agents/renovate-major-upgrader.md` (create) | opus agent: major upgrade, changelog-first |
| `plugins/devtools/skills/renovator/SKILL.md` (modify) | dispatch instead of park; new labels; attempt state; clobber handling; merge hand-off; config knobs |
| `plugins/devtools/README.md` (modify) | document v2 behavior + new config knobs |

Build order: doctrine first (both agents read it), then the two agents (they define the outcome contract the orchestrator consumes), then the SKILL.md integration, then README + sweep.

---

### Task 1: Shared fix-loop doctrine (`fix-loop.md`)

**Files:**
- Create: `plugins/devtools/skills/renovator/references/fix-loop.md`

**Interfaces:**
- Produces: the 8-step loop, the change-scope guardrails, the discovery priority list, and the outcome contract `{ pr, outcome, touched_tests, attempts, summary }` that Tasks 2–4 depend on.

- [ ] **Step 1: Write the failing validation**

MUST fail now (file absent):

```bash
f=plugins/devtools/skills/renovator/references/fix-loop.md
test -f "$f" && grep -q 'touched_tests' "$f" && grep -qi 'never fake green' "$f" && echo "doctrine OK"
```

Expected: FAIL.

- [ ] **Step 2: Create the doctrine**

Create `plugins/devtools/skills/renovator/references/fix-loop.md`:

```markdown
# renovator fix-loop doctrine

Shared by `renovate-ci-fixer` and `renovate-major-upgrader`. It defines how a fixer agent takes a Renovate PR that v1 parked and works it to green inside a worktree, bounded, then hands the outcome back to the `renovator` orchestrator. Your agent adds only its own front-loaded step (the major upgrader reads the changelog first); everything else is here.

You work ONE PR. You write code and run tests. You NEVER fake green. You never touch any PR but the one you were given, and you never merge, label, or comment — the orchestrator owns all of that.

## Input (from your dispatch)
- `pr` — the PR number.
- `bump` — `patch` | `minor` | `major`.
- `old_version` → `new_version` — the dependency transition.
- `fix_attempts` — max push→remote-CI cycles before you give up (default 3).
- `attempt` — which attempt this is (1-based); the orchestrator increments it across passes.

## Steps

### 1. Set up the worktree
Create a git worktree on the PR's head branch via the `superpowers:using-git-worktrees` skill. Work only inside it. Do not touch the main checkout.

### 2. Discover the test/build recipe
Find how to run the repo's checks locally, in priority order — stop at the first that yields runnable commands, but cross-check against the workflow files (they are what CI enforces):
1. `CLAUDE.md` / `AGENTS.md` — human-curated build/test/lint commands.
2. `README.md` / `CONTRIBUTING.md` — dev-setup and test instructions.
3. Project manifests — `package.json` scripts, `Makefile`/`justfile`, `pyproject.toml`/`tox.ini`, `cargo`, `go test ./...`.
4. `.github/workflows/*.yml` — the jobs triggered on this PR (`on: pull_request` / push to the default branch) and their `run:` steps + toolchain setup. This is what CI **actually enforces**.

Reconcile: use 1–3 for the ergonomic local commands, but make sure you reproduce what the workflow enforces. If they diverge, remote CI (step 5) is the final authority. If NO source yields a runnable recipe, go to step 7 (fallback).

### 3. Reproduce locally and iterate
Run the recipe in the worktree. On failure, make an adaptation change (step 4) and re-run the failing check. This is your cheap inner loop — keep it local, no pushing. Cap yourself: if roughly ~10 local edits pass without the failure set shrinking, stop thrashing and move toward park.

### 4. Change-scope guardrails
- **Allowed:** change call sites, configuration, and application code to adapt to the new dependency version.
- **Tests — conditional:** you MAY edit a test ONLY when the dependency legitimately changed behavior (a renamed API, a changed default, a new required argument). Record a per-test justification in your `summary`. Set `touched_tests: true` if you edit ANY test file.
- **Forbidden — this is faking green, never do it:** deleting or skipping/`xfail`-ing a test to get past it; blanket suppress/ignore directives (`@ts-ignore`, broad `# noqa`, `eslint-disable`, `--no-verify`); loosening or removing an assertion without a documented dependency-behavior reason; commenting out failing code.
- If the only path to green you can find is a forbidden change, STOP and park — that is a human's call.

### 5. Confirm on remote CI
When the recipe passes locally, commit and push ONCE to the PR branch. Wait for remote CI to settle (`gh pr checks <pr>`).
- Remote green → outcome `green`.
- Remote red where local passed → read the failure, do ONE more local iteration (step 3) informed by it, then push again. Each push consumes one `fix_attempts`.

### 6. Bounding
`fix_attempts` (default 3) caps the push→remote-CI cycles. When they are used up and CI is still red, STOP: outcome `exhausted`. Do not keep pushing.

### 7. Fallback — never fake green
If you cannot faithfully reproduce the checks locally (missing toolchain; the workflow needs services/secrets/containers; self-hosted runners; the recipe won't start for environment reasons):
- Fall back to making your best-reasoned change, pushing, and reading remote CI (still bounded by `fix_attempts`).
- If even that is impractical (you cannot tell what to change without running it), STOP: outcome `cannot-reproduce`.
Never claim green you did not observe on remote CI.

### 8. Hand the outcome back
Return exactly this to the orchestrator (one JSON object, no prose):
`{ "pr": <n>, "outcome": "green" | "exhausted" | "cannot-reproduce", "touched_tests": <true|false>, "attempts": <k>, "summary": "<what you changed, and/or why it is stuck>" }`
- `green` — remote CI is green. The orchestrator decides merge vs review.
- `exhausted` — used all `fix_attempts`, still red; `summary` names the last failure.
- `cannot-reproduce` — could not establish a reliable check; `summary` says why.
```

- [ ] **Step 3: Verify it passes**

Re-run the Step 1 command. Expected: `doctrine OK`.

- [ ] **Step 4: Verify guardrails + contract present**

```bash
f=plugins/devtools/skills/renovator/references/fix-loop.md
grep -qi 'CLAUDE.md' "$f" && grep -qi 'workflows' "$f" \
  && grep -qi 'Forbidden' "$f" \
  && grep -q '"green" | "exhausted" | "cannot-reproduce"' "$f" \
  && grep -q 'fix_attempts' "$f" \
  && echo "contract OK"
```

Expected: `contract OK`.

- [ ] **Step 5: Commit**

```bash
git add plugins/devtools/skills/renovator/references/fix-loop.md
git commit -m "docs(devtools): add shared renovator fix-loop doctrine"
```

---

### Task 2: `renovate-ci-fixer` agent (sonnet)

**Files:**
- Create: `plugins/devtools/agents/renovate-ci-fixer.md`

**Interfaces:**
- Consumes: `references/fix-loop.md` (the loop) + the dispatch input `{ pr, bump, old_version, new_version, fix_attempts, attempt }`.
- Produces: the outcome contract back to the orchestrator; the routing (green+no-test-edit → merge; green+test-edit → review; exhausted/cannot-reproduce → park).

- [ ] **Step 1: Write the failing validation**

MUST fail now:

```bash
f=plugins/devtools/agents/renovate-ci-fixer.md
test -f "$f" && grep -qx 'model: sonnet' "$f" \
  && grep -q 'fix-loop.md' "$f" \
  && echo "ci-fixer OK"
```

Expected: FAIL.

- [ ] **Step 2: Create the agent**

Create `plugins/devtools/agents/renovate-ci-fixer.md`:

```markdown
---
name: renovate-ci-fixer
description: Fixes a red-CI patch/minor Renovate PR by adapting code to the new dependency inside a worktree, bounded by fix_attempts, following the shared fix-loop doctrine. Reports green/exhausted/cannot-reproduce back to the renovator orchestrator; never merges. Runs on sonnet.
model: sonnet
tools: Read, Grep, Glob, Edit, Write, Bash, Skill
---

# renovate-ci-fixer — get a red patch/minor Renovate PR green

You take ONE patch/minor Renovate PR whose CI is red and try to make it pass by adapting the code to the new dependency version. The version bump itself already happened — you are fixing the fallout.

Follow the shared fix-loop doctrine in `references/fix-loop.md` EXACTLY — it defines every step (worktree, recipe discovery, local iteration, change-scope guardrails, remote confirmation, bounding, fallback, and the outcome object you return). Read it first.

You have no extra front-loaded step: go straight into the loop at doctrine step 1.

## Outcome routing (informational — the orchestrator acts on your returned object)
- `green` and you did NOT edit any test (`touched_tests: false`) → the orchestrator merges via `renovate-merger`.
- `green` but you edited a test (`touched_tests: true`) → the orchestrator parks the PR for human review.
- `exhausted` / `cannot-reproduce` → the orchestrator parks for a human.

Return the doctrine's outcome object and nothing else. Never merge, label, or comment yourself.
```

- [ ] **Step 3: Verify it passes**

Re-run Step 1. Expected: `ci-fixer OK`.

- [ ] **Step 4: Verify tools + no-merge discipline**

```bash
f=plugins/devtools/agents/renovate-ci-fixer.md
grep -qx 'tools: Read, Grep, Glob, Edit, Write, Bash, Skill' "$f" \
  && grep -qi 'never merge' "$f" \
  && grep -qi 'touched_tests' "$f" \
  && echo "discipline OK"
```

Expected: `discipline OK`.

- [ ] **Step 5: Commit**

```bash
git add plugins/devtools/agents/renovate-ci-fixer.md
git commit -m "feat(devtools): add renovate-ci-fixer sonnet agent"
```

---

### Task 3: `renovate-major-upgrader` agent (opus)

**Files:**
- Create: `plugins/devtools/agents/renovate-major-upgrader.md`

**Interfaces:**
- Consumes: `references/fix-loop.md` + the same dispatch input as Task 2 (with `bump: major`).
- Produces: the outcome contract; routing is `green → always park for review` (never auto-merge), exhausted/cannot-reproduce → park.

- [ ] **Step 1: Write the failing validation**

MUST fail now:

```bash
f=plugins/devtools/agents/renovate-major-upgrader.md
test -f "$f" && grep -qx 'model: opus' "$f" \
  && grep -qi 'changelog' "$f" \
  && grep -q 'fix-loop.md' "$f" \
  && echo "upgrader OK"
```

Expected: FAIL.

- [ ] **Step 2: Create the agent**

Create `plugins/devtools/agents/renovate-major-upgrader.md`:

```markdown
---
name: renovate-major-upgrader
description: Works a major-version Renovate PR to green inside a worktree — reads the changelog/release notes for breaking changes first, then follows the shared fix-loop doctrine, bounded by fix_attempts. Always parks the green result for human review; never auto-merges. Runs on opus.
model: opus
tools: Read, Grep, Glob, Edit, Write, Bash, Skill
---

# renovate-major-upgrader — work a major-version Renovate PR to green

You take ONE major-version Renovate PR and make the codebase work with the new major version. Major versions carry breaking changes, so you do judgment-heavy work up front before touching code.

## Front-loaded step — understand the breaking changes FIRST
Before entering the loop, read the authoritative changelog / release notes:
1. The Renovate PR body — Renovate embeds release notes and changelog links for the update; this is the first-class source. Read it with `gh pr view <pr> --json body`.
2. Fall back to the package's GitHub Releases / CHANGELOG across the `old_version` → `new_version` range if the PR body is thin.
Note the breaking changes that plausibly affect THIS repo (renamed/removed APIs, changed defaults, new required arguments, dropped runtime versions). Use them to drive your adaptation changes — do not react to test failures alone.

Then follow the shared fix-loop doctrine in `references/fix-loop.md` EXACTLY (worktree, recipe discovery, local iteration, change-scope guardrails, remote confirmation, bounding, fallback, outcome). Read it first.

## Outcome routing (informational — the orchestrator acts on your returned object)
- `green` → the orchestrator ALWAYS parks for human diff review. You never auto-merge a major upgrade, regardless of `touched_tests`.
- `exhausted` / `cannot-reproduce` → the orchestrator parks for a human.

Return the doctrine's outcome object and nothing else. Never merge, label, or comment yourself.
```

- [ ] **Step 3: Verify it passes**

Re-run Step 1. Expected: `upgrader OK`.

- [ ] **Step 4: Verify always-park + changelog-first**

```bash
f=plugins/devtools/agents/renovate-major-upgrader.md
grep -qi 'ALWAYS park' "$f" \
  && grep -qi 'before entering the loop' "$f" \
  && grep -qi 'never auto-merge' "$f" \
  && echo "major OK"
```

Expected: `major OK`.

- [ ] **Step 5: Commit**

```bash
git add plugins/devtools/agents/renovate-major-upgrader.md
git commit -m "feat(devtools): add renovate-major-upgrader opus agent"
```

---

### Task 4: Orchestrator changes (`SKILL.md`) — keystone

**Files:**
- Modify: `plugins/devtools/skills/renovator/SKILL.md`

**Interfaces:**
- Consumes: the two agents' outcome contract; v1's `renovate-merger` (for the merge hand-off) and `classification.md`.
- Produces: dispatch-instead-of-park behavior, the three new lifecycle states, attempt-state persistence, clobber handling, and the three new config knobs.

**IMPORTANT:** This MODIFIES the existing v1 `SKILL.md`. **Read the current file first**, then apply the edits below anchored on the named sections. Preserve all v1 behavior not explicitly changed (preflight, fetch, classify, merge, drain, state-annotation upsert mechanics, "Under /loop", portability).

- [ ] **Step 1: Write the failing validation**

MUST fail now (these strings are added by this task):

```bash
f=plugins/devtools/skills/renovator/SKILL.md
grep -q 'renovator:fixing' "$f" && grep -q 'renovator:review' "$f" \
  && grep -q 'fix_attempts' "$f" && grep -q 'renovate-ci-fixer' "$f" \
  && grep -q 'renovate-major-upgrader' "$f" && echo "v2 wired"
```

Expected: FAIL (none present yet).

- [ ] **Step 2: Config — add three knobs.**

In the `## Configuration` table, add three rows after `max_merges_per_pass`:

```
| `enable_ci_fixer` | `true` | attempt red-CI patch/minor fixes (else park as v1) |
| `enable_major_upgrader` | `true` | attempt major-version upgrades (else park as v1) |
| `fix_attempts` | `3` | max push→remote-CI cycles a fixer runs before parking |
```

- [ ] **Step 3: Preflight — create the two new labels.**

In `### 1. Preflight`, after the three existing `gh label create` lines, add:

```
  - `gh label create renovator:fixing --color 1D76DB --description "renovator is running a fix-loop on this PR" --force`
  - `gh label create renovator:review --color 0E8A16 --description "renovator fixed this PR; awaiting human diff review" --force`
```

- [ ] **Step 4: Resume in-flight fix-loops — extend step 3.**

In `### 3. Skip locked PRs`, after the existing `renovator:working` skip bullet, add:

```
- A candidate carrying `renovator:fixing` is an in-flight fix-loop; do NOT skip it — it is resumed in step 7 (read its persisted `attempt` from the sticky comment and continue).
```

- [ ] **Step 5: Replace the Park step with a Dispatch step.**

Replace the entire `### 7. Park the rest` section with:

```
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
1. Read persisted state from the sticky comment: `attempt` (default 1 if none) and `head_sha` (the SHA the last attempt ran against).
2. **Clobber check:** fetch the PR's current head SHA. If a stored `head_sha` exists and the current head no longer contains the previous attempt's commits (Renovate force-rebased), reset `attempt` to 1.
3. If `attempt` > `fix_attempts` → park `renovator:parked`, reason "attempts exhausted", keep the last summary. Stop.
4. Set `renovator:fixing`; upsert the sticky comment with state `fixing`, `attempt: <k>/<fix_attempts>`, and the current head SHA.
5. Dispatch the agent with `{ pr, bump, old_version, new_version, fix_attempts, attempt }`.
6. On return, route by `outcome`:
   - `green` + bucket is red-CI (patch/minor) + `touched_tests: false` → dispatch `renovate-merger` exactly as in step 5 (its independent re-verify gates the merge). On `merged`, remove `renovator:*` and record outcome `fixed-merged`.
   - `green` + (bump is major OR `touched_tests: true`) → set `renovator:review`; upsert comment: "fixed — awaiting human diff review (renovator authored these changes)", include the agent `summary`.
   - `exhausted` → set `renovator:parked`; upsert comment with `summary` + "attempts exhausted".
   - `cannot-reproduce` → set `renovator:parked`; upsert comment: "can't reproduce CI locally — " + `summary`.
   - If the agent could not finish this pass and more attempts remain → keep `renovator:fixing`, increment the persisted `attempt`; the next pass resumes.
```

- [ ] **Step 6: Extend the report outcomes — step 8.**

In `### 8. Report`, extend the outcome set to include the v2 outcomes. Change the outcome enumeration to:

```
(outcome ∈ merged / fixed-merged / review / fixing / parked / skipped / rebasing / locked)
```

- [ ] **Step 7: Persist fix-loop state in the sticky comment.**

In `## State annotation`, extend the comment `<body>` template to carry the fix-loop state. After the `- CI:` line, add these two lines to the template block:

```
  - fix: `<attempt>/<fix_attempts>` · head `<short-sha>`
  - summary: <agent summary, when parked/review>
```

- [ ] **Step 8: Update the "Never do (v1)" guardrails for v2.**

Rename the `## Never do (v1)` heading to `## Never do` and replace its bullets with:

```
- Never merge more than `max_merges_per_pass` per pass; never run more than one fix-loop per pass.
- Never merge a `MAJOR` upgrade or any fix that edited a test — those go to `renovator:review` for a human.
- Never let a fixer fake green (delete/skip a test, blanket-suppress an error, or loosen an assertion to pass) — that is a park.
- Never exceed `fix_attempts` push→CI cycles on a PR — park instead.
- Never merge a PR whose author is not in `renovate_authors`.
```

- [ ] **Step 9: Verify all edits landed + no portability regression.**

```bash
f=plugins/devtools/skills/renovator/SKILL.md
grep -q 'renovator:fixing' "$f" && grep -q 'renovator:review' "$f" \
  && grep -q 'enable_ci_fixer' "$f" && grep -q 'enable_major_upgrader' "$f" \
  && grep -q 'fix_attempts' "$f" \
  && grep -q 'renovate-ci-fixer' "$f" && grep -q 'renovate-major-upgrader' "$f" \
  && grep -q 'Clobber check' "$f" \
  && grep -q 'fixed-merged' "$f" \
  && grep -qi 'fake green' "$f" \
  && echo "v2 wired"
if grep -q 'date -Iseconds' "$f" || grep -q 'grep -oP' "$f"; then echo "PORTABILITY_FAIL"; else echo "portability OK"; fi
# v1 must still be intact:
grep -q 'renovate-merger' "$f" && grep -q 'max_merges_per_pass' "$f" && grep -q 'renovator-state' "$f" && echo "v1 intact"
```

Expected: `v2 wired`, `portability OK`, `v1 intact`.

- [ ] **Step 10: Commit**

```bash
git add plugins/devtools/skills/renovator/SKILL.md
git commit -m "feat(devtools): orchestrator dispatches fix-loops, tracks attempts, gates merges"
```

---

### Task 5: README update + static sweep

**Files:**
- Modify: `plugins/devtools/README.md`

**Interfaces:**
- Consumes: all v2 components.
- Produces: user-facing v2 docs (behavior + the three new config knobs) and a final structural sweep + human live-exercise checklist.

- [ ] **Step 1: Write the failing validation**

MUST fail now:

```bash
grep -q 'renovate-ci-fixer\|fix-loop\|renovator:review' plugins/devtools/README.md && echo "readme v2 OK"
```

Expected: FAIL (v2 not documented yet).

- [ ] **Step 2: Update the README.**

Read `plugins/devtools/README.md`. Under the `## renovator` section, after the existing v1 behavior list, add a v2 subsection:

```markdown
### v2 — automatic fix-loops (major upgrades & red CI)

For the PRs v1 parks, renovator can work them to green inside a git worktree before merging or handing back:

- **Red CI on a patch/minor PR** → `renovate-ci-fixer` (sonnet) discovers the repo's test recipe (from CLAUDE.md / README / manifests / the GitHub workflow), iterates locally, and confirms on remote CI. If it reaches green by **adaptation only** (no test edits), the PR auto-merges via the same `renovate-merger` gate as v1. If the fix had to edit a test, it parks for your review instead.
- **Major-version PR** → `renovate-major-upgrader` (opus) reads the changelog/release notes for breaking changes first, then runs the same loop. A green result **always parks for your diff review** — a major upgrade never auto-merges.
- **Stuck** (attempts exhausted, or CI can't be reproduced locally) → parked with a summary of what was tried.

renovator never "fakes green": it will not delete/skip a test or suppress an error to force a merge — that becomes a park for a human.

New labels: `renovator:fixing` (a fix-loop is in progress), `renovator:review` (fixed, awaiting your diff review).
```

Then add three rows to the config table (after `max_merges_per_pass`):

```markdown
| `enable_ci_fixer` | `true` | attempt automatic red-CI fixes on patch/minor PRs |
| `enable_major_upgrader` | `true` | attempt automatic major-version upgrades |
| `fix_attempts` | `3` | max push→remote-CI cycles a fixer runs before parking |
```

And update the example JSON config to include the three new keys (keep it valid JSON).

- [ ] **Step 3: Verify README + JSON validity.**

```bash
grep -q 'renovate-ci-fixer' plugins/devtools/README.md \
  && grep -q 'renovator:review' plugins/devtools/README.md \
  && grep -q 'fix_attempts' plugins/devtools/README.md \
  && echo "readme v2 OK"
sed -n '/^    {$/,/^    }$/p' plugins/devtools/README.md | sed -E 's/^    //' | jq empty && echo "config example valid JSON"
```

Expected: `readme v2 OK` then `config example valid JSON`.

- [ ] **Step 4: Commit**

```bash
git add plugins/devtools/README.md
git commit -m "docs(devtools): document renovator v2 fix-loops and config"
```

- [ ] **Step 5: Full static sweep.**

```bash
for f in \
  plugins/devtools/skills/renovator/references/fix-loop.md \
  plugins/devtools/agents/renovate-ci-fixer.md \
  plugins/devtools/agents/renovate-major-upgrader.md \
  plugins/devtools/skills/renovator/SKILL.md \
  plugins/devtools/README.md; do
  test -f "$f" && echo "present: $f" || echo "MISSING: $f"
done
# frontmatter models pinned correctly:
grep -qx 'model: sonnet' plugins/devtools/agents/renovate-ci-fixer.md && echo "ci-fixer sonnet"
grep -qx 'model: opus' plugins/devtools/agents/renovate-major-upgrader.md && echo "upgrader opus"
# no GNU-isms across the plugin:
if grep -rq 'date -Iseconds\|grep -oP' plugins/devtools; then echo "PORTABILITY_FAIL"; else echo "portability OK"; fi
```

Expected: `present:` for all five, `ci-fixer sonnet`, `upgrader opus`, `portability OK`.

- [ ] **Step 6: Live exercise (end-to-end, human-run).**

Needs a real repo with `gh` authenticated and a Renovate PR that is red or a major bump. NOT runnable by an automated agent (interactive `/plugin install` + a live broken PR). Reproduce this checklist in the report, marked TO BE RUN BY A HUMAN:

1. Install/refresh the plugin; confirm `renovate-ci-fixer` and `renovate-major-upgrader` are discovered.
2. **Red-CI path:** on a repo with a red patch/minor Renovate PR, invoke `renovator`. Expect: the PR gets `renovator:fixing`, the fixer opens a worktree, iterates, pushes; if it reaches adaptation-only green it merges (`fixed-merged`); if it edited a test it lands in `renovator:review`.
3. **Major path:** on a major Renovate PR, expect the upgrader reads the changelog, works to green, and parks `renovator:review` (never auto-merges).
4. **Bounding:** confirm a genuinely-unfixable PR stops after `fix_attempts` and parks with a summary — no infinite loop.
5. **Idempotence / resume:** re-invoke mid-fix; confirm the `attempt` counter resumes from the sticky comment and no duplicate comments appear.

Record which paths were exercisable. If none, note that the fix-loop paths remain to be exercised against a live broken Renovate PR.

- [ ] **Step 7: Commit any doc fixes from the exercise.**

```bash
git add -A && git commit -m "docs(devtools): note v2 live-exercise findings" || echo "nothing to commit"
```

---

## Self-review (completed during authoring)

**Spec coverage** — every v2 spec section maps to a task:
- Component layout → Tasks 1–4 create/modify the named files.
- Shared fix-loop doctrine (8 steps, discovery priority, change-scope, outcome contract) → Task 1.
- The two fixer agents (models, changelog-first for major, routing) → Tasks 2 & 3.
- Orchestrator changes (dispatch, 3 new states, attempt state, clobber handling, merge hand-off, disabled-knob fallback, report outcomes) → Task 4.
- Config knobs (`enable_ci_fixer`, `enable_major_upgrader`, `fix_attempts`) → Task 4 (skill) + Task 5 (README).
- Model tiering (sonnet/opus, haiku merge reuse) → Tasks 2/3 frontmatter; merge hand-off in Task 4.
- Safety invariants (never fake green, gating, bounding, `renovate-merger` re-verify, fixing lock, clobber-safe) → Task 1 doctrine + Task 4 routing/guardrails.

**Placeholder scan:** no TBD/TODO; every file shown in full (creates) or by anchored edit (modifies); every step has a concrete command with expected output.

**Type/name consistency:** the outcome object `{ pr, outcome: green|exhausted|cannot-reproduce, touched_tests, attempts, summary }` is identical across Task 1 (doctrine), Tasks 2/3 (agents reference it), and Task 4 (orchestrator routes it). Dispatch payload `{ pr, bump, old_version, new_version, fix_attempts, attempt }` matches between doctrine input and Task 4 dispatch. Label names (`renovator:fixing` / `renovator:review` / `renovator:parked`) and config knobs are spelled identically across Tasks 1, 4, and 5.
