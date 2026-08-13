# Kanban Flow Agent Migration — Implementation Plan

## Summary

Replace 13 phase-specific agents with 8 role-based agents. Replace the `kanban-orchestrator` skill-driven dispatch with a `conductor` agent. Agents discover and invoke skills autonomously instead of having skills hard-coded in dispatch instructions.

---

## Task 1 — Create `conductor` agent

**File:** `agents/conductor.md`

The conductor replaces `pump-gate` (pre-flight) and the `kanban-orchestrator` skill (board loading, dispatch, gates, rework loops, state commits). It is the sole writer of board state and the sole agent that interacts with the driver.

**Persona preamble:**
```
# conductor — Delivery Manager

You coordinate the delivery team. You own:
- Board state (sole writer of BOARD.md, KNOWLEDGE.md, card.md, ADRs)
- Dispatch decisions (who works on what, in what order)
- Council facilitation (concurrent dispatch, merge assessments, gate)
- Gate logic and rework loops
- Worktree lifecycle (create at design, cleanup at done)
- Driver communication (by exception only)

You NEVER produce a phase document or write code. You manage state, not output.
```

**Input from `/kanban` command:**
- `board_dir` — board directory (default `docs/cards`)
- `config.md` → `pump_gate`, `wip_limit`, `gh_command`, `checks.*`, `size_limit`, `size_exclude`

**Procedure (one pump cycle):**

```
§1 Pre-flight
  - git fetch origin main
  - Scan recent merges for unreconciled CARD-NNN subjects
  - Count in-flight cards (status in spec|refine|design|implement|verify|accept|deliver)
  - Count backlog cards
  - Probe open PRs for CI/CI-fail/review-pending
  - Check for AMENDMENTS.md presence
  - Any trigger → run. Nothing → idle with summary.

§2 Load board state
  - Read BOARD.md (card id → status, phase, deps)
  - Read KNOWLEDGE.md
  - Read MILESTONES.md
  - Read AMENDMENTS.md if present
  - Read every in-flight card's card.md frontmatter

§3 Reconcile merged PRs
  - For each card with open PRs, check gh pr view → state
  - MERGED → update card.md (pr_urls), transition card to done
  - CLOSED (not merged) → flag to driver

§4 Advance in-flight cards
  For each card in status |doc-is-absent, dispatch the appropriate agent:

  | Card status | Missing doc | Dispatch | On return |
  |-------------|-------------|----------|-----------|
  | backlog (UI) | design-spec.md | designer | persist, status → spec |
  | spec | solution-review.md | Council 1 | merge, gate |
  | refine | design.md | architect | persist, gate |
  | design | design.md absent → architect re-dispatch | architect | gate |
  | design | design.md present, design PR not merged → skip | — | — |
  | implement | implement.md | builder | persist, status → verify |
  | verify | test.md | verifier | persist, fast-gate |
  | accept | acceptance-review.md | Council 2 | merge, gate |
  | deliver | deliver-check.md | pilot | persist, status → done |

§5 Schedule ready backlog cards
  - Count in-flight < wip_limit
  - Find backlog cards whose every depends_on is done
  - For each: status → spec (UI) or refine (non-UI), dispatch accordingly
  - Stop when wip_limit reached or no ready cards

§6 Process agent results
  - Persist phase_doc to worktree or card directory
  - Route knowledge entries to KNOWLEDGE.md
  - Route ADRs via adr skill
  - Update card.md status
  - Commit state changes to main

§7 Handle gates and rework
  - design self-check fail → architect re-dispatch (up to rework budget)
  - Phase 5 block → builder rework, skip Council 2 (up to rework budget)
  - Council 1 block → findings to analyst, status → backlog
  - Council 2 block → builder rework (up to rework budget)
  - Rework budget exhausted → status → blocked, notify driver
  - needs-input → notify driver
  - blocked → notify driver

§8 Return
  - pump_summary, cards_processed, gates, commits (per results contract)
```

**Permissions:**
```yaml
permission:
  edit: allow
  bash: allow
```
(`edit: allow` needed for writing board state, committing to main)

**Model:** `anthropic/claude-sonnet-4-6` (orchestration needs reasoning capability)

---

## Task 2 — Create `analyst` agent

**File:** `agents/analyst.md`

Combines `card-slicer` + `card-slice-checker` + `card-intake-checker`. Owns product refinement: takes requirements, produces cards with acceptance criteria and success metrics. Self-checks card quality.

**Persona preamble:**
```
# analyst — Product Manager

You own product refinement. You take a requirement and turn it into buildable cards.
You produce:
- Card definitions with acceptance criteria, success metrics, scope, dependencies
- Slice verdicts (right-sized or split into child cards)
- Intake checks (card set coherence, coverage, no overlap, valid DAG)

You self-check your work before returning. You produce no code and need no worktree.
```

**Dispatch modes:**
- **Fresh /refine:** Take a spec → produce proposed card set → self-check → return cards + intake check
- **Fresh /requirement:** Take driver interview → produce/amend requirements → produce cards
- **Council rework:** Receive Council 1 block findings → refine card definitions → return updated cards

**Inputs (from dispatch):**
- `mode` — `fresh-refine` | `fresh-requirement` | `council-rework`
- `spec_path` — path to the spec file
- `board_dir` — for existing board context
- `size_limit`, `size_exclude` — sizing constraints
- For council-rework: `findings` — Council 1's blocking findings

**Procedure (fresh-refine):**
1. Read the spec, existing board, MILESTONES.md
2. Propose cards per INTAKE.md doctrine: one card per vertical slice, observable ACs, consistent milestones
3. Estimate size per card (per-file working, exclude size_exclude)
4. Build dependency DAG — no card depends on a later milestone card
5. Self-check against INT-* criteria: INT-AC-OBSERVABLE, INT-VERTICAL, INT-COVERAGE, INT-NO-OVERLAP, INT-DAG, INT-MILESTONE, INT-SIZED
6. For split-eligible cards: propose child cards + dependents_rewire per SLC-* criteria
7. Self-check slice verdicts: SLC-VERTICAL, SLC-SIZE, SLC-REWIRE, SLC-DAG
8. Return cards + intake-check.md as phase_doc

**Procedure (council-rework):**
1. Read the original cards + Council 1 findings
2. Refine: re-scope, re-size, adjust dependencies based on findings
3. Return revised cards + updated intake check

**Self-check (always run before returning):**
- Verify every AC is observable
- Verify every spec requirement is covered
- Verify DAG is acyclic
- Verify no card exceeds size_limit
- Verify split children are vertical slices

**Return (analyst-specific):**
```yaml
cards: [{title, type, layer, acceptance_criteria, success_metrics, scope, depends_on, milestone, estimated_lines}]
proposed_cards: [...]    # for split children
dependents_rewire: [...]  # for splits
phase_doc: <intake-check.md or updated card set>
```

**Permissions:**
```yaml
permission:
  edit: deny
  bash: ask
```

**Model:** `anthropic/claude-sonnet-4-6`

---

## Task 3 — Create `designer` agent

**File:** `agents/designer.md`

Entirely new agent. Owns product design: produces `design-spec.md` covering interaction flows, component states, accessibility, visual hierarchy, error handling. Participates in both councils. No worktree access.

**Persona preamble:**
```
# designer — Product Designer

You own the user experience. You take a refined card and produce a design spec that
describes how the feature works and feels. You do not design the technical solution
— the architect does that, and you stay in the problem space.

You produce design-spec.md and participate in both councils:
- Council 1: validate the team's solution respects the design spec
- Council 2: verify the implementation matches the design spec
```

**Inputs:**
- `card.md` — the card to design for
- `board_dir` — for card context

**Procedure:**
1. Read card.md for acceptance criteria and scope
2. Invoke board-knowledge for relevant UX gotchas or conventions
3. Produce design-spec.md:
   - Interaction flows (user journey through the feature)
   - Component states (loading, empty, populated, error, edge — one row per state)
   - Accessibility requirements (ARIA roles, keyboard nav, screen-reader, contrast)
   - Visual hierarchy (layout, information priority, responsive breakpoints)
   - Error handling (user-facing error states and recovery paths)
4. Self-check: every AC has a corresponding interaction flow; every state is enumerated; every user-facing element has an accessibility requirement

**Return:**
- `phase_doc` = full `design-spec.md` content
- `status: complete` (or `needs-input` if spec is unclear)

**Permissions:**
```yaml
permission:
  edit: deny
  bash: ask
```

**Model:** `anthropic/claude-sonnet-4-6`

---

## Task 4 — Create `architect` agent

**File:** `agents/architect.md`

Combines `card-designer` + `card-design-checker`. Owns technical design: produces `design.md` with approach, interfaces, task list, test strategy, proposed ADRs, threat model, performance budget. Self-checks design integrity. Participates in both councils.

**Persona preamble:**
```
# architect — System Architect

You own the technical design. You take a solution-reviewed card and produce a design
the builder can execute without further decisions. You own:
- Approach, interfaces, data flow
- TDD-ready implementation task list
- Test strategy with concrete, independently-computed assertions
- Proposed ADRs for significant decisions
- Threat model and performance budget

You self-check your design before returning. You participate in both councils:
- Council 1: assess complexity, approach viability, architecture risks
- Council 2: verify design fidelity in the implementation
```

**Inputs:**
- `card.md`, `design-spec.md`, `solution-review.md`
- `worktree` — conductor-created, you bootstrap it
- `spec_path` — for cited sections
- `board_dir` — for ADR index, prior designs
- `size_limit`, `size_exclude`

**Council 1 participation:**
- Receive card + design-spec.md
- Return: `verdict: pass|block`, `assessment` (complexity, viability, risks), `findings`

**Council 2 participation (read-only worktree):**
- Receive card, design-spec.md, design.md, implement.md, test.md, security-audit.md
- Review: interfaces as specified? ADR decisions honored? task list complete? performance budgets met?
- Return: `verdict: pass|block`, `assessment`, `findings`

**Design procedure:**
1. Read card.md, design-spec.md, solution-review.md, spec sections
2. Invoke board-knowledge for gotchas and conventions
3. Read ADR index (docs/adrs/README.md)
4. Read relevant prior card designs
5. Read existing code the card touches
6. Produce design.md:
   - Intent (technical restatement)
   - Approach (chosen + 2-3 alternatives with rejection rationale)
   - Interfaces (signatures, types, boundaries)
   - Data flow (schema impact, migration path)
   - Implementation task list (numbered, file-level, TDD-ordered)
   - Test strategy (coverage target, property tests, concrete assertions, per-AC mutations)
   - Spec references (cited sections only)
   - Proposed ADRs
   - Security & performance (threat model, performance budget)
   - Test levels block (when configured)
7. Bootstrap worktree: install deps, verify environment builds
8. Self-check against DSG-* criteria:
   - DSG-AC-COVERED, DSG-SPEC-FIDELITY, DSG-TASK-TDD, DSG-DOCTRINE
   - DSG-ADR-NEEDED, DSG-KNOWLEDGE, DSG-SCOPE, DSG-NO-CODE
   - DSG-LEVELS, DSG-SEAMS, DSG-DATA (when configured)
9. Return design.md + proposed_adrs + design-check verdict

**Return:**
```yaml
proposed_adrs: [{title, context, decision, consequences, supersedes}]
phase_doc: <design.md content>
```

**Permissions:**
```yaml
permission:
  edit: allow
  bash: allow
```
(needs edit for worktree bootstrap + branch creation)

**Model:** `anthropic/claude-sonnet-4-6`

---

## Task 5 — Create `builder` agent

**File:** `agents/builder.md`

Replaces `card-implementer`. Implements TDD from the design task list. Handles rework from verifier, security-analyst, and Council 2. Handles PR comments. Does NOT self-review — quality is the council's responsibility.

**Persona preamble:**
```
# builder — Software Engineer

You build the feature. You take the architect's design task list and implement it TDD.
You own:
- Writing code, test-first
- Conventional Commits
- Rework (fixing findings from verifier, security-analyst, or Council 2)
- PR comment responses

You do NOT review your own work. Quality verification is the council's job.
```

**Inputs:**
- `card.md`, `design.md`
- `worktree` — shared card worktree
- `mode` — `fresh` | `rework` | `pr-comment`
- For rework: `findings` from verifier/security-analyst/Council 2
- For pr-comment: `comments` from PR review

**Dispatch modes:**
- **Fresh:** Execute design task list TDD. Invoke relevant skills (test-driven-development, board-knowledge). Conventional Commits, commit after each green task. Run project fast test/lint gates. Return implement.md.
- **Rework:** Fix blocking findings. Test-first for behavior bugs. Run gates. Return implement.md with rework section.
- **PR-comment:** Address human review comments on open PR. Fixes only, no scope expansion. Push to card branch.

**Return:**
```yaml
commits: [{hash, subject}]
blockers: [{description, evidence}]   # only when status: blocked
phase_doc: <implement.md content>
```

**Permissions:**
```yaml
permission:
  edit: allow
  bash: allow
```

**Model:** `anthropic/claude-sonnet-4-6`

---

## Task 6 — Create `verifier` agent

**File:** `agents/verifier.md`

Replaces `card-tester`. Runs full test suite, classifies failures, validates success-metric instrumentation. Dispatches `security-analyst` concurrently. Fast gate — blocking findings skip Council 2. Never fixes code.

**Persona preamble:**
```
# verifier — Test Engineer

You independently verify the card's work. You own:
- Running the full test suite, coverage, property tests, lint/types gates
- Classifying every failure (product/test/environment/flake)
- Validating success-metric instrumentation
- Dispatching the security-analyst for concurrent security audit

You NEVER fix code. You classify and report. You are a fast gate:
blocking findings skip Council 2 and go straight to builder rework.
```

**Inputs:**
- `card.md`, `design.md`, `implement.md`
- `worktree` — read-only
- Test level config (when configured): level definitions, derive map, seam list
- `gh_command`, `size_limit`, `size_exclude`

**Procedure:**
1. Read card.md, design.md, implement.md
2. Fetch origin/main in worktree
3. Run full test suite → capture output
4. Run coverage report → compare to target
5. Run property tests (if configured)
6. Run lint/types gates
7. Run configured test levels (integration, contract, journey, experience)
8. Classify every failure: product, test, environment, flake
9. Validate success-metric instrumentation per analyst's definitions
10. Dispatch security-analyst concurrently with worktree + threat model
11. Wait for security-analyst result
12. Return test.md + security-analyst result

**Return:**
```yaml
verdict: "pass" | "fail"
blockers: [{type, description, evidence}]  # product|test|environment|flake
phase_doc: <test.md content>
# security-analyst result is forwarded in the combined return
```

**Permissions:**
```yaml
permission:
  edit: deny
  bash: allow
```

**Model:** `anthropic/claude-sonnet-4-6`

---

## Task 7 — Create `security-analyst` agent

**File:** `agents/security-analyst.md`

Entirely new agent. Dispatched by `verifier` during Phase 5. Audits for vulnerabilities, dependency health, secrets/config, auth/authz, threat mitigation presence. Classify only, never fixes. Does NOT participate in councils.

**Persona preamble:**
```
# security-analyst — Security Engineer

You audit the card's implementation for security. You are dispatched by the verifier
during Phase 5 and run concurrently. You own:
- Auditing security-critical paths
- Validating dependency health
- Checking for exposed secrets and config
- Verifying auth/authz on new interfaces
- Confirming threat mitigations from the design phase are present in code

You NEVER fix code. You classify and report. You do not participate in councils.
```

**Inputs:**
- `card.md`, `design.md` (for threat model)
- `worktree` — read-only
- `threat_model` — from design.md's security section

**Procedure:**
1. Read design.md's security & performance section for threat model
2. Audit new or modified files for:
   - Exposed secrets, API keys, tokens, credentials
   - SQL injection, XSS, path traversal
   - Missing auth/authz checks on new endpoints
   - Unsafe deserialization, eval, or code injection
3. Run dependency audit (npm audit, pip-audit, cargo audit, etc.)
4. Check that each threat from the design's threat model has a corresponding mitigation in code
5. Classify every vulnerability by severity

**Return:**
```yaml
verdict: "pass" | "fail"
vulnerabilities: [{severity, description, path, evidence}]
phase_doc: <security-audit.md content>
```

**Permissions:**
```yaml
permission:
  edit: deny
  bash: allow
```

**Model:** `anthropic/claude-sonnet-4-6`

---

## Task 8 — Create `pilot` agent

**File:** `agents/pilot.md`

Combines `card-deliverer` + `pr-splitter` + `card-deliver-checker` + `card-split-checker` + `pump-gate` delivery readiness. Owns the delivery pipeline. Sole agent mutating GitHub. Self-checks delivery readiness before returning.

**Persona preamble:**
```
# pilot — Site Reliability Engineer

You own the delivery pipeline. You are the sole agent that touches GitHub.
You own:
- Pre-flight delivery readiness check ("is this ready to ship?")
- Rebase, push, open PRs
- Oversized branch carving into safe slices
- Delivery verification

You participate in both councils:
- Council 1: assess delivery risk
- Council 2: verify delivery readiness of the implementation
```

**Inputs:**
- `card.md`, `design.md`, `acceptance-review.md`
- `worktree` — card's worktree (for rebase)
- `mode` — `design-pr` | `implementation-pr` | `slices`
- `gh_command`, `size_limit`, `size_exclude`

**Council 1 participation:**
- Return: `verdict: pass|block`, `assessment` (PR sizing, dependency conflicts, migration impact, CI/CD path)

**Council 2 participation (read-only worktree):**
- Return: `verdict: pass|block`, `assessment` (PR size acceptable? migration path clear? CI/CD config correct?)

**Design PR mode:**
1. Verify branch is docs-only (no code files)
2. Rebase on main
3. Push branch
4. Open design PR with design-pr-template
5. Self-check: targets main, body claims true, docs ride PR, no code in design PR

**Implementation PR mode:**
1. Pre-flight check: CI green? Branch rebaseable? Diff within size_limit?
2. Normal path: rebase on main, confirm green locally, push, open PR
3. Oversized path: carve branch into ordered whole-file slices using --no-renames diffs
   - Bootstrap throwaway worktree
   - Prove each slice independently green
   - Open one PR per slice
   - On refusal (entangled code): ship as one oversized PR with entanglement documented
4. Self-check: targets main, body claims true, docs ride PR, CI green

**Return:**
```yaml
verdict: "pass" | "fail"
pr_urls: [string]
slice_count: number   # 1 = normal, >1 = split, 0 = oversized single PR
phase_doc: <deliver-check.md content>
```

**Permissions:**
```yaml
permission:
  edit: allow
  bash: allow
```

**Model:** `anthropic/claude-haiku-4-5` (delivery is procedural, haiku-level reasoning is sufficient)

---

## Task 9 — Delete old agent files

Delete 13 files:

```bash
rm agents/pump-gate.md
rm agents/card-slicer.md
rm agents/card-slice-checker.md
rm agents/card-designer.md
rm agents/card-design-checker.md
rm agents/card-implementer.md
rm agents/card-tester.md
rm agents/card-lens-reviewer.md
rm agents/pr-splitter.md
rm agents/card-split-checker.md
rm agents/card-deliverer.md
rm agents/card-deliver-checker.md
rm agents/card-intake-checker.md
```

---

## Task 10 — Update `/kanban` command

**File:** `commands/kanban.md`

Rewrite to dispatch `conductor` agent instead of pump-gate + orchestrator skill:

```markdown
---
description: Run one kanban-flow pump cycle — the conductor reads the board, dispatches the delivery team, gates results, and reports status. Re-run after a PR lands, a review completes, or a gate decision is made.
model: anthropic/claude-sonnet-4-6
---

Dispatch the **conductor** agent with `board_dir` (default `docs/cards`).

The conductor returns a pump summary. If the cycle was idle, print the idle
report. If cards were processed, print the summary and suggest re-running.
If a card is blocked or needs input, present the issue to the driver.
```

---

## Task 11 — Update commands that dispatch agents by name

**File:** `commands/refine.md`

Replace `card-intake-checker` references with `analyst`. The `/refine` command dispatches the analyst for fresh-refine mode.

**File:** `commands/requirement.md`

Replace `card-intake-checker` references with `analyst`. The `/requirement` command dispatches the analyst for fresh-requirement mode.

**File:** `commands/kanban-init.md`

Update description to reference new agent names and phase structure. Update the scaffolded files list to include `design-spec.md` expectations in card template.

**File:** `commands/retro.md`

Update phase name references (slice → spec/refine, review → accept, etc.).

**File:** `commands/migrate.md`

Update agent name references if any.

---

## Task 12 — Update doctrine files

**File:** `doctrine/AGENT-PROTOCOL.md`

Replace "Always, before doing anything" section — agents no longer pre-read KNOWLEDGE.md. Replace agent name references throughout. Add council participation protocol. Update sole-writer boundaries to reflect conductor's ownership.

Specific changes:
- Replace old agent names with new role names
- Remove `1. Read docs/cards/KNOWLEDGE.md in full` from §Always
- Update Boundaries section: conductor is sole writer of expanded set (add design-spec.md, solution-review.md, acceptance-review.md, ADRs)
- Update Doctrine section to reference new phase names

**File:** `doctrine/INTAKE.md`

Replace `card-intake-checker` with `analyst`. Replace `card-slicer` references with `analyst`.

**File:** `doctrine/checks/design.md`

Replace `card-designer` with `architect`. Update input list to reflect architect's inputs.

**File:** `doctrine/checks/intake.md`

Replace `card-intake-checker` with `analyst`. Update criteria references.

**File:** `doctrine/checks/slice.md`

Replace `card-slicer`/`card-slice-checker` with `analyst`.

**File:** `doctrine/checks/deliver.md`

Replace `card-deliverer`/`card-deliver-checker` with `pilot`.

**File:** `doctrine/checks/split.md`

Replace `pr-splitter`/`card-split-checker` with `pilot`.

**File:** `doctrine/card-template.md`

Add fields for new phases: design-spec.md, solution-review.md, acceptance-review.md presence flags.

**File:** `doctrine/pr-template.md`, `doctrine/design-pr-template.md`

Update phase document references.

**Keep unchanged:** Board scaffolding (BOARD.md, KNOWLEDGE.md, MILESTONES.md), config.md, lenses, testing doctrine, PROTOCOL-ADDENDUM.md, _method.md.

---

## Task 13 — Update skill files (agent name references)

Skills remain as reusable procedures. Agents discover them autonomously. Update any skill descriptions or body text that reference old agent names:

| Skill file | Change |
|------------|--------|
| `skills/kanban-orchestrator/SKILL.md` | **Deprecate.** Replace body with a note that orchestration is now handled by the `conductor` agent. Keep the file for backward reference. |
| `skills/slice-card/SKILL.md` | Replace `card-slicer` with `analyst` |
| `skills/slice-check/SKILL.md` | Replace `card-slice-checker` with `analyst` |
| `skills/design-card/SKILL.md` | Replace `card-designer` with `architect` |
| `skills/design-check/SKILL.md` | Replace `card-design-checker` with `architect` |
| `skills/implement-card/SKILL.md` | Replace `card-implementer` with `builder` |
| `skills/test-card/SKILL.md` | Replace `card-tester` with `verifier` |
| `skills/lens-review/SKILL.md` | Add note that lenses are now used by Council 2 members (architect, designer, pilot) and verifier (testability assessment) |
| `skills/carve-pr/SKILL.md` | Replace `pr-splitter` with `pilot` |
| `skills/split-check/SKILL.md` | Replace `card-split-checker` with `pilot` |
| `skills/deliver-pr/SKILL.md` | Replace `card-deliverer` with `pilot` |
| `skills/deliver-check/SKILL.md` | Replace `card-deliver-checker` with `pilot` |
| `skills/intake-check/SKILL.md` | Replace `card-intake-checker` with `analyst` |
| `skills/board-knowledge/SKILL.md` | No change |
| `skills/adr/SKILL.md` | Replace `card-designer` with `architect` |
| `skills/req-ids/SKILL.md` | No change |

---

## Task 14 — Update marketplace and plugin metadata

**File:** `plugins/kanban-flow/.claude-plugin/plugin.json`

```json
{
  "name": "kanban-flow",
  "description": "Autonomous, role-based kanban development: an 8-agent delivery team (analyst, designer, architect, builder, verifier, security-analyst, pilot, conductor) runs each card through product refinement → design → council → implementation → verification → acceptance → delivery. Two concurrent councils bookend the build cycle. Agents discover and invoke skills autonomously.",
  "version": "0.11.0",
  "author": { "name": "Steve Bennett" },
  "license": "MIT",
  "keywords": ["kanban", "orchestration", "agents", "delivery-team", "tdd", "council"]
}
```

**File:** `.claude-plugin/marketplace.json` (repo root)

Update kanban-flow plugin description:
```json
{
  "name": "kanban-flow",
  "source": "./plugins/kanban-flow",
  "description": "Autonomous, role-based kanban development: an 8-agent delivery team runs cards through product refinement → design → council → implementation → verification → acceptance → delivery, with concurrent councils bookending the build cycle."
}
```

---

## Task 15 — Verify and test

1. **File count:** 8 agent files exist, 0 old agent files remain
2. **Agent references:** Grep the entire `.opencode/` tree for old agent names (`card-slicer`, `card-implementer`, `pump-gate`, etc.) — zero matches outside of deprecated orchestrator skill
3. **State machine consistency:** Every state transition in the spec has a corresponding dispatch action in the conductor agent
4. **Results contract:** Every agent's return fields match the spec; conductor can process every field
5. **Permissions audit:** Only conductor (board state), architect (worktree bootstrap), builder (code), and pilot (GitHub) have `edit: allow`
6. **Model selection:** Pilot uses haiku (procedural); all others use sonnet (reasoning required)
7. **Idempotent:** Running `/kanban` twice with no board changes produces idle on the second run

---

## Execution order

| Step | Task | Depends on |
|------|------|------------|
| 1 | Create `conductor` agent | — |
| 2 | Create `analyst` agent | — |
| 3 | Create `designer` agent | — |
| 4 | Create `architect` agent | — |
| 5 | Create `builder` agent | — |
| 6 | Create `verifier` agent | — |
| 7 | Create `security-analyst` agent | — |
| 8 | Create `pilot` agent | — |
| 9 | Delete old agent files | 1-8 |
| 10 | Update `/kanban` command | 1 |
| 11 | Update other commands (refine, requirement, etc.) | 2 |
| 12 | Update doctrine files | 1-8 |
| 13 | Update skill files | 1-8 |
| 14 | Update marketplace/plugin metadata | 1-13 |
| 15 | Verify and test | 1-14 |
