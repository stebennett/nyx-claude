# Kanban Flow Agent Migration — Verification Checklist

Each check is a testable yes/no assertion. Every item references the spec section it verifies. A passing implementation must satisfy all checks.

---

## 1. Agent Inventory

### 1.1 File existence

| # | Check | Spec ref |
|---|-------|----------|
| 1.1.1 | `agents/conductor.md` exists | §Agents #8 |
| 1.1.2 | `agents/analyst.md` exists | §Agents #1 |
| 1.1.3 | `agents/designer.md` exists | §Agents #2 |
| 1.1.4 | `agents/architect.md` exists | §Agents #3 |
| 1.1.5 | `agents/builder.md` exists | §Agents #4 |
| 1.1.6 | `agents/verifier.md` exists | §Agents #5 |
| 1.1.7 | `agents/security-analyst.md` exists | §Agents #6 |
| 1.1.8 | `agents/pilot.md` exists | §Agents #7 |

### 1.2 Old agent deletion

| # | Check | Spec ref |
|---|-------|----------|
| 1.2.1 | `agents/pump-gate.md` does not exist | §Agents (replaced by conductor) |
| 1.2.2 | `agents/card-slicer.md` does not exist | §Agents (replaced by analyst) |
| 1.2.3 | `agents/card-slice-checker.md` does not exist | §Agents (replaced by analyst) |
| 1.2.4 | `agents/card-intake-checker.md` does not exist | §Agents (replaced by analyst) |
| 1.2.5 | `agents/card-designer.md` does not exist | §Agents (replaced by architect) |
| 1.2.6 | `agents/card-design-checker.md` does not exist | §Agents (replaced by architect) |
| 1.2.7 | `agents/card-implementer.md` does not exist | §Agents (replaced by builder) |
| 1.2.8 | `agents/card-tester.md` does not exist | §Agents (replaced by verifier) |
| 1.2.9 | `agents/card-lens-reviewer.md` does not exist | §Agents (absorbed into councils) |
| 1.2.10 | `agents/pr-splitter.md` does not exist | §Agents (replaced by pilot) |
| 1.2.11 | `agents/card-split-checker.md` does not exist | §Agents (replaced by pilot) |
| 1.2.12 | `agents/card-deliverer.md` does not exist | §Agents (replaced by pilot) |
| 1.2.13 | `agents/card-deliver-checker.md` does not exist | §Agents (replaced by pilot) |

### 1.3 Exact count

| # | Check | Spec ref |
|---|-------|----------|
| 1.3.1 | Exactly 8 agent files exist in `agents/` (plus `.gitkeep`) | §Agents header |

---

## 2. Agent Frontmatter

Each agent file must have valid YAML frontmatter with these fields.

### 2.1 conductor

| # | Check | Spec ref |
|---|-------|----------|
| 2.1.1 | `name: conductor` | §Agents #8 |
| 2.1.2 | `description` contains "Orchestration", "board state", "dispatch", "council" | §Agents #8 |
| 2.1.3 | `mode: subagent` | §Agent File Structure |
| 2.1.4 | `model: anthropic/claude-sonnet-4-6` | Implementation plan §1 |
| 2.1.5 | `permission.edit: allow` | Implementation plan §1 |
| 2.1.6 | `permission.bash: allow` | Implementation plan §1 |

### 2.2 analyst

| # | Check | Spec ref |
|---|-------|----------|
| 2.2.1 | `name: analyst` | §Agents #1 |
| 2.2.2 | `description` contains "Product refinement", "acceptance criteria", "success metrics" | §Agents #1 |
| 2.2.3 | `mode: subagent` | §Agent File Structure |
| 2.2.4 | `model: anthropic/claude-sonnet-4-6` | Implementation plan §2 |
| 2.2.5 | `permission.edit: deny` | Implementation plan §2 |
| 2.2.6 | `permission.bash: ask` | Implementation plan §2 |

### 2.3 designer

| # | Check | Spec ref |
|---|-------|----------|
| 2.3.1 | `name: designer` | §Agents #2 |
| 2.3.2 | `description` contains "Product design", "interaction flows", "component states", "accessibility" | §Agents #2 |
| 2.3.3 | `mode: subagent` | §Agent File Structure |
| 2.3.4 | `model: anthropic/claude-sonnet-4-6` | Implementation plan §3 |
| 2.3.5 | `permission.edit: deny` | Implementation plan §3 |
| 2.3.6 | `permission.bash: ask` | Implementation plan §3 |

### 2.4 architect

| # | Check | Spec ref |
|---|-------|----------|
| 2.4.1 | `name: architect` | §Agents #3 |
| 2.4.2 | `description` contains "Technical design", "approach", "interfaces", "TDD-ready task list", "test strategy" | §Agents #3 |
| 2.4.3 | `mode: subagent` | §Agent File Structure |
| 2.4.4 | `model: anthropic/claude-sonnet-4-6` | Implementation plan §4 |
| 2.4.5 | `permission.edit: allow` | Implementation plan §4 |
| 2.4.6 | `permission.bash: allow` | Implementation plan §4 |

### 2.5 builder

| # | Check | Spec ref |
|---|-------|----------|
| 2.5.1 | `name: builder` | §Agents #4 |
| 2.5.2 | `description` contains "Implementation", "TDD", "rework" | §Agents #4 |
| 2.5.3 | `description` does NOT contain "review" (builder does not self-review) | §Agents #4, §Phase 4 |
| 2.5.4 | `mode: subagent` | §Agent File Structure |
| 2.5.5 | `model: anthropic/claude-sonnet-4-6` | Implementation plan §5 |
| 2.5.6 | `permission.edit: allow` | Implementation plan §5 |
| 2.5.7 | `permission.bash: allow` | Implementation plan §5 |

### 2.6 verifier

| # | Check | Spec ref |
|---|-------|----------|
| 2.6.1 | `name: verifier` | §Agents #5 |
| 2.6.2 | `description` contains "Independent verification", "classifies", "fast gate", "never fixes" | §Agents #5 |
| 2.6.3 | `description` mentions dispatching `security-analyst` | §Agents #5 |
| 2.6.4 | `mode: subagent` | §Agent File Structure |
| 2.6.5 | `model: anthropic/claude-sonnet-4-6` | Implementation plan §6 |
| 2.6.6 | `permission.edit: deny` | Implementation plan §6 |
| 2.6.7 | `permission.bash: allow` | Implementation plan §6 |

### 2.7 security-analyst

| # | Check | Spec ref |
|---|-------|----------|
| 2.7.1 | `name: security-analyst` | §Agents #6 |
| 2.7.2 | `description` contains "Security", "vulnerabilities", "dependency health", "classify only" | §Agents #6 |
| 2.7.3 | `description` does NOT contain "council" | §Agents #6 |
| 2.7.4 | `mode: subagent` | §Agent File Structure |
| 2.7.5 | `model: anthropic/claude-sonnet-4-6` | Implementation plan §7 |
| 2.7.6 | `permission.edit: deny` | Implementation plan §7 |
| 2.7.7 | `permission.bash: allow` | Implementation plan §7 |

### 2.8 pilot

| # | Check | Spec ref |
|---|-------|----------|
| 2.8.1 | `name: pilot` | §Agents #7 |
| 2.8.2 | `description` contains "Delivery", "pre-flight", "rebase", "PR", "oversized", "sole agent touching GitHub" | §Agents #7 |
| 2.8.3 | `mode: subagent` | §Agent File Structure |
| 2.8.4 | `model: anthropic/claude-haiku-4-5` | Implementation plan §8 |
| 2.8.5 | `permission.edit: allow` | Implementation plan §8 |
| 2.8.6 | `permission.bash: allow` | Implementation plan §8 |

---

## 3. Agent Persona and Ownership

Each agent file must open with a persona preamble that establishes its identity.

### 3.1 conductor

| # | Check | Spec ref |
|---|-------|----------|
| 3.1.1 | Body claims ownership of board state (sole writer) | §Boundaries |
| 3.1.2 | Body claims ownership of dispatch decisions and council facilitation | §Dispatch Patterns |
| 3.1.3 | Body claims ownership of gate logic and rework loops | §Lifecycle Phases 3-7 |
| 3.1.4 | Body claims ownership of worktree lifecycle | §Worktree Management |
| 3.1.5 | Body states it interacts with the driver by exception only | §Driver Interaction |
| 3.1.6 | Body states it NEVER produces a phase document or writes code | §Agents #8 |

### 3.2 analyst

| # | Check | Spec ref |
|---|-------|----------|
| 3.2.1 | Body states it owns product refinement | §Phase 0 |
| 3.2.2 | Body states it produces cards with acceptance criteria and success metrics | §Agents #1 |
| 3.2.3 | Body states it self-checks card quality | §Phase 0 |
| 3.2.4 | Body states it handles Council 1 rework (refining card definitions from council findings) | §Phase 2 |

### 3.3 designer

| # | Check | Spec ref |
|---|-------|----------|
| 3.3.1 | Body states it owns the user experience | §Phase 1 |
| 3.3.2 | Body states it produces `design-spec.md` covering interaction flows, component states, accessibility, visual hierarchy, error handling | §Phase 1 |
| 3.3.3 | Body states it does NOT design the technical solution (architect does that) | §Phase 1 |
| 3.3.4 | Body states it participates in both councils | §Phase 2, §Phase 6 |

### 3.4 architect

| # | Check | Spec ref |
|---|-------|----------|
| 3.4.1 | Body states it owns technical design | §Phase 3 |
| 3.4.2 | Body states it produces `design.md` and `proposed_adrs` | §Agents #3 |
| 3.4.3 | Body states it self-checks design integrity before returning | §Phase 3 |
| 3.4.4 | Body states it bootstraps the worktree | §Worktree Management |
| 3.4.5 | Body states it participates in both councils | §Phase 2, §Phase 6 |
| 3.4.6 | Body lists all 10 design.md sections | §Phase 3 |

### 3.5 builder

| # | Check | Spec ref |
|---|-------|----------|
| 3.5.1 | Body states it implements code TDD from the design task list | §Phase 4 |
| 3.5.2 | Body states it handles rework (fixing findings from verifier, security-analyst, Council 2) | §Phase 4 |
| 3.5.3 | Body states it handles PR comments | §Phase 4 |
| 3.5.4 | Body explicitly states it does NOT review its own work | §Phase 4 |
| 3.5.5 | Body states quality is the council's responsibility | §Phase 4 |

### 3.6 verifier

| # | Check | Spec ref |
|---|-------|----------|
| 3.6.1 | Body states it independently verifies the card's work | §Phase 5 |
| 3.6.2 | Body states it classifies every failure (product/test/environment/flake) | §Phase 5 |
| 3.6.3 | Body states it dispatches `security-analyst` concurrently | §Phase 5 |
| 3.6.4 | Body states it is a fast gate (blocking findings skip Council 2) | §Phase 5 |
| 3.6.5 | Body explicitly states it NEVER fixes code | §Phase 5 |
| 3.6.6 | Body states it validates success-metric instrumentation | §Phase 5 |

### 3.7 security-analyst

| # | Check | Spec ref |
|---|-------|----------|
| 3.7.1 | Body states it runs inside the verifier loop (Phase 5 only) | §Agents #6 |
| 3.7.2 | Body states it audits security-critical paths, dependency health, secrets/config, auth/authz | §Phase 5 |
| 3.7.3 | Body states it verifies threat mitigations from design are present in code | §Phase 5 |
| 3.7.4 | Body explicitly states it NEVER fixes code | §Phase 5 |
| 3.7.5 | Body does NOT mention council participation | §Agents #6 |

### 3.8 pilot

| # | Check | Spec ref |
|---|-------|----------|
| 3.8.1 | Body states it owns the delivery pipeline | §Phase 7 |
| 3.8.2 | Body states it is the sole agent that mutates GitHub | §Boundaries |
| 3.8.3 | Body states it runs a pre-flight delivery readiness check | §Phase 7 |
| 3.8.4 | Body describes normal path (rebase, push, open PR) and oversized path (carve slices) | §Phase 7 |
| 3.8.5 | Body states it self-checks delivery readiness before returning | §Phase 7 |
| 3.8.6 | Body states it participates in both councils | §Phase 2, §Phase 6 |

---

## 4. Agent Procedure Verification

### 4.1 conductor

| # | Check | Spec ref |
|---|-------|----------|
| 4.1.1 | Describes pre-flight check (fetch main, scan merges, count in-flight/backlog, probe open PRs) | §Phase 7 (pre-flight), Implementation plan §1 |
| 4.1.2 | Describes board loading (BOARD.md, KNOWLEDGE.md, MILESTONES.md, card.md) | Implementation plan §1 |
| 4.1.3 | Describes merged PR reconciliation | Implementation plan §1 |
| 4.1.4 | Describes dispatch for every card status (backlog → spec, spec → Council 1, refine → architect, etc.) | §State Machine Transitions |
| 4.1.5 | Describes Council 1 dispatch (5 agents concurrently, merge to solution-review.md, gate all-or-nothing) | §Phase 2 |
| 4.1.6 | Describes Council 2 dispatch (3 agents concurrently with read-only worktree, merge to acceptance-review.md, gate all-or-nothing) | §Phase 6 |
| 4.1.7 | Describes gate handling for each rework path: design→design (architect rework), verify→implement (builder rework), accept→implement (builder rework) | §Rework Budget |
| 4.1.8 | Describes Council 1 block handler (findings → analyst → backlog) | §Phase 2 |
| 4.1.9 | Describes needs-input handler (agent question → driver) | §Driver Interaction |
| 4.1.10 | Describes blocked handler (blocker → driver) | §Driver Interaction |
| 4.1.11 | Describes rework budget exhaustion handler (rework history → driver, card → blocked) | §Rework Budget |
| 4.1.12 | Describes WIP limit scheduling (count in-flight, find ready backlog cards, stop at wip_limit) | Implementation plan §1 |

### 4.2 analyst

| # | Check | Spec ref |
|---|-------|----------|
| 4.2.1 | Describes fresh-refine mode (read spec, propose cards per INTAKE.md, estimate size, build DAG) | §Phase 0 |
| 4.2.2 | Describes self-check against INT-* criteria before returning | §Phase 0 |
| 4.2.3 | Describes council-rework mode (read original cards + Council 1 findings, refine, re-scope, re-size) | §Phase 2 |
| 4.2.4 | Does NOT describe creating a worktree or writing code | §Agents #1 |

### 4.3 designer

| # | Check | Spec ref |
|---|-------|----------|
| 4.3.1 | Describes producing design-spec.md with all 5 sections: interaction flows, component states, accessibility, visual hierarchy, error handling | §Phase 1 |
| 4.3.2 | Describes self-check (every AC has corresponding flow, every state enumerated, every element has accessibility requirement) | §Phase 1 |
| 4.3.3 | Does NOT describe technical architecture or implementation details | §Phase 1 |

### 4.4 architect

| # | Check | Spec ref |
|---|-------|----------|
| 4.4.1 | Describes reading card.md, design-spec.md, solution-review.md, spec sections, ADR index, prior designs, existing code | §Phase 3 |
| 4.4.2 | Describes producing all 10 design.md sections | §Phase 3 |
| 4.4.3 | Describes bootstrapping the worktree (install deps, verify environment builds) | §Worktree Management |
| 4.4.4 | Describes self-check against DSG-* criteria before returning | §Phase 3 |
| 4.4.5 | Describes Council 1 participation (assessment: complexity, viability, risks, patterns) | §Phase 2 |
| 4.4.6 | Describes Council 2 participation (verdict: design fidelity, ADR decisions honored, task list complete, performance budgets met) | §Phase 6 |

### 4.5 builder

| # | Check | Spec ref |
|---|-------|----------|
| 4.5.1 | Describes fresh mode (execute design task list TDD, Conventional Commits, commit after each green task) | §Phase 4 |
| 4.5.2 | Describes rework mode (fix blocking findings from verifier, security-analyst, or Council 2, test-first for behavior bugs) | §Phase 4 |
| 4.5.3 | Describes PR-comment mode (address human review comments on open PR) | §Phase 4 |
| 4.5.4 | Describes running project fast test/lint gates before returning | §Phase 4 |
| 4.5.5 | Does NOT describe self-reviewing code or running a lens panel | §Phase 4 |

### 4.6 verifier

| # | Check | Spec ref |
|---|-------|----------|
| 4.6.1 | Describes running full test suite, coverage report, property tests, lint/types gates | §Phase 5 |
| 4.6.2 | Describes classifier taxonomy (product/test/environment/flake) | §Phase 5 |
| 4.6.3 | Describes validating success-metric instrumentation | §Phase 5 |
| 4.6.4 | Describes dispatching security-analyst concurrently with worktree + threat model | §Phase 5 |
| 4.6.5 | Describes waiting for security-analyst result and forwarding both verdicts | §Phase 5 |
| 4.6.6 | Describes Council 1 participation (assessment: testability, assertion gaps, edge-case exposure, test levels, instrumentation feasibility) | §Phase 2 |
| 4.6.7 | Does NOT describe fixing code or changing behavior | §Phase 5 |

### 4.7 security-analyst

| # | Check | Spec ref |
|---|-------|----------|
| 4.7.1 | Describes reading design.md for threat model | §Phase 5 |
| 4.7.2 | Describes auditing new/modified files for secrets, injection, missing auth/authz, unsafe operations | §Phase 5 |
| 4.7.3 | Describes running dependency audit | §Phase 5 |
| 4.7.4 | Describes confirming threat mitigations from design are present in code | §Phase 5 |
| 4.7.5 | Does NOT describe participating in councils | §Agents #6 |
| 4.7.6 | Does NOT describe fixing code or changing behavior | §Phase 5 |

### 4.8 pilot

| # | Check | Spec ref |
|---|-------|----------|
| 4.8.1 | Describes pre-flight delivery check (CI green, branch rebaseable, diff within limits, docs ride PR) | §Phase 7 |
| 4.8.2 | Describes normal path (rebase on main, confirm green locally, push, open PR) | §Phase 7 |
| 4.8.3 | Describes oversized path (carve into ordered whole-file slices, bootstrap throwaway worktree, prove each green, open one PR per slice) | §Phase 7 |
| 4.8.4 | Describes refusal outcome (entangled code → one oversized PR with entanglement documented) | §Phase 7 |
| 4.8.5 | Describes design PR mode (verify docs-only branch, rebase, push, open design PR) | §Phase 3, Implementation plan §8 |
| 4.8.6 | Describes self-check (targets main, body claims true, docs ride PR, CI green) | §Phase 7 |
| 4.8.7 | Describes Council 1 participation (assessment: delivery risk, PR sizing, dependency conflicts, migration impact, CI/CD path) | §Phase 2 |
| 4.8.8 | Describes Council 2 participation (verdict: delivery readiness, PR size, migration path, CI/CD config) | §Phase 6 |

---

## 5. Agent Return Contract

### 5.1 Common fields (all agents)

| # | Check | Spec ref |
|---|-------|----------|
| 5.1.1 | `status` field defined with values `"complete"`, `"blocked"`, `"needs-input"` | §Results Contract |
| 5.1.2 | `phase_doc` field defined as string markdown content | §Results Contract |
| 5.1.3 | `knowledge` field defined as optional `[{scope, section, entry}]` | §Results Contract |

### 5.2 analyst

| # | Check | Spec ref |
|---|-------|----------|
| 5.2.1 | `cards` field defined with card array structure | §Results Contract |
| 5.2.2 | `cards` array includes these required fields: title, type, layer, acceptance_criteria, success_metrics, scope, depends_on, milestone | §Results Contract |

### 5.3 designer

| # | Check | Spec ref |
|---|-------|----------|
| 5.3.1 | No additional fields beyond common | §Results Contract |

### 5.4 architect

| # | Check | Spec ref |
|---|-------|----------|
| 5.4.1 | `proposed_adrs` field defined with ADR array structure (title, context, decision, consequences, supersedes) | §Results Contract |

### 5.5 builder

| # | Check | Spec ref |
|---|-------|----------|
| 5.5.1 | `commits` field defined as `[{hash, subject}]` | §Results Contract |
| 5.5.2 | `blockers` field defined as `[{description, evidence}]`, only when `status: "blocked"` | §Results Contract |

### 5.6 verifier

| # | Check | Spec ref |
|---|-------|----------|
| 5.6.1 | `verdict` field defined with values `"pass"`, `"fail"` | §Results Contract |
| 5.6.2 | `blockers` field defined as `[{type, description, evidence}]`, only when `verdict: "fail"` | §Results Contract |
| 5.6.3 | `blockers[].type` enumeration includes: `"product"`, `"test"`, `"environment"`, `"flake"` | §Results Contract |

### 5.7 security-analyst

| # | Check | Spec ref |
|---|-------|----------|
| 5.7.1 | `verdict` field defined with values `"pass"`, `"fail"` | §Results Contract |
| 5.7.2 | `vulnerabilities` field defined as `[{severity, description, path, evidence}]`, only when `verdict: "fail"` | §Results Contract |

### 5.8 pilot

| # | Check | Spec ref |
|---|-------|----------|
| 5.8.1 | `verdict` field defined with values `"pass"`, `"fail"` | §Results Contract |
| 5.8.2 | `pr_urls` field defined as string array | §Results Contract |
| 5.8.3 | `slice_count` field defined as number (1=normal, >1=split, 0=oversized) | §Results Contract |

### 5.9 Council member return

| # | Check | Spec ref |
|---|-------|----------|
| 5.9.1 | Every agent that participates in councils describes the council return format: `verdict: "pass"|"block"`, `assessment`, `findings` | §Results Contract |
| 5.9.2 | Applied to: architect, builder (Council 1 only), verifier, pilot, designer | §Phase 2, §Phase 6 |

### 5.10 conductor

| # | Check | Spec ref |
|---|-------|----------|
| 5.10.1 | `pump_summary` field defined with `{in_flight, backlog, wip_limit, free_slots}` | §Results Contract |
| 5.10.2 | `cards_processed` field defined as array of `{card_id, phase, status, phase_doc, pr_urls}` | §Results Contract |
| 5.10.3 | `gates` field defined as array of `{card_id, gate, verdict}` | §Results Contract |
| 5.10.4 | `commits` field defined as array of `{hash, subject}` | §Results Contract |

---

## 6. Agent Permissions Audit

| # | Check | Spec ref |
|---|-------|----------|
| 6.1 | Only these agents have `edit: allow`: conductor, architect, builder, pilot | §Boundaries, Implementation plan |
| 6.2 | These agents have `edit: deny`: analyst, designer, verifier, security-analyst | §Boundaries |
| 6.3 | `verifier` has `bash: allow` but `edit: deny` (read-only worktree access) | §Boundaries |
| 6.4 | `security-analyst` has `bash: allow` but `edit: deny` (read-only worktree access) | §Boundaries |
| 6.5 | `pilot` is the only agent whose description states it is the sole agent mutating GitHub | §Boundaries |

---

## 7. Lifecycle and State Machine

### 7.1 State coverage

| # | Check | Spec ref |
|---|-------|----------|
| 7.1.1 | Every state in the state machine appears in the conductor's dispatch table: backlog, spec, refine, design, implement, verify, accept, deliver, done | §State Machine |
| 7.1.2 | `needs-input` is reachable from any state when an agent returns `status: "needs-input"` | §State Machine |
| 7.1.3 | `blocked` is reachable from any state when an agent returns `status: "blocked"` or rework budget is exhausted | §State Machine |

### 7.2 Transition coverage

| # | Check | Spec ref |
|---|-------|----------|
| 7.2.1 | `(new) → backlog` trigger is documented (analyst produces cards, driver approves) | §Transitions |
| 7.2.2 | `backlog → spec` trigger is documented (designer dispatched, design-spec.md present) | §Transitions |
| 7.2.3 | `backlog → refine` trigger is documented (non-UI card, designer skipped) | §Transitions |
| 7.2.4 | `spec → refine` trigger is documented (Council 1 passes, solution-review.md present) | §Transitions |
| 7.2.5 | `spec → backlog` trigger is documented (Council 1 blocks, findings to analyst) | §Transitions |
| 7.2.6 | `refine → design` trigger is documented (architect dispatched, worktree created) | §Transitions |
| 7.2.7 | `design → design` trigger is documented (architect self-check fails, re-design) | §Transitions |
| 7.2.8 | `design → implement` trigger is documented (architect complete, design.md present, design PR merged) | §Transitions |
| 7.2.9 | `implement → verify` trigger is documented (builder complete, implement.md present) | §Transitions |
| 7.2.10 | `verify → accept` trigger is documented (Phase 5 passes, both verdicts pass) | §Transitions |
| 7.2.11 | `verify → implement` trigger is documented (Phase 5 blocks, builder rework) | §Transitions |
| 7.2.12 | `accept → deliver` trigger is documented (Council 2 passes, acceptance-review.md present) | §Transitions |
| 7.2.13 | `accept → implement` trigger is documented (Council 2 blocks, builder rework) | §Transitions |
| 7.2.14 | `deliver → done` trigger is documented (pilot complete, PR(s) merged) | §Transitions |

### 7.3 Rework budget

| # | Check | Spec ref |
|---|-------|----------|
| 7.3.1 | Three rework paths are documented: design→design, verify→implement, accept→implement | §Rework Budget |
| 7.3.2 | Default budget of 3 cycles per path is stated | §Rework Budget |
| 7.3.3 | Budget exhaustion outcome is documented (card → blocked with rework history) | §Rework Budget |

### 7.4 Fast gate

| # | Check | Spec ref |
|---|-------|----------|
| 7.4.1 | Phase 5 is documented as a fast gate (blocking findings skip Council 2) | §Phase 5 |
| 7.4.2 | After Phase 5 rework, lifecycle resumes at verify (not accept) | §Phase 5 |
| 7.4.3 | Council 2 procedure states it only fires when Phase 5 passes | §Phase 6 |

---

## 8. Council Dispatch Verification

### 8.1 Council 1

| # | Check | Spec ref |
|---|-------|----------|
| 8.1.1 | 5 members: architect, builder, verifier, pilot, designer | §Phase 2 |
| 8.1.2 | `security-analyst` is NOT a Council 1 member | §Agents #6 |
| 8.1.3 | `analyst` is NOT a Council 1 member | §Phase 2 |
| 8.1.4 | Members are dispatched concurrently | §Phase 2 |
| 8.1.5 | Each member's assessment topic matches the spec table | §Phase 2 assessment table |
| 8.1.6 | Conductor merges into solution-review.md | §Phase 2 |
| 8.1.7 | All-or-nothing gate: all 5 must pass for card to proceed | §Phase 2 |
| 8.1.8 | Block outcome: findings to analyst, card → backlog | §Phase 2 |
| 8.1.9 | Unclear feedback escalates to driver via needs-input | §Phase 2 |

### 8.2 Council 2

| # | Check | Spec ref |
|---|-------|----------|
| 8.2.1 | 3 members: architect, designer, pilot | §Phase 6 |
| 8.2.2 | `verifier` is NOT a Council 2 member | §Phase 6 |
| 8.2.3 | `security-analyst` is NOT a Council 2 member | §Agents #6 |
| 8.2.4 | `builder` is NOT a Council 2 member (subject of review) | §Phase 6 |
| 8.2.5 | Members are dispatched concurrently | §Phase 6 |
| 8.2.6 | Each member's verdict topic matches the spec table | §Phase 6 verdict table |
| 8.2.7 | Members receive read-only worktree access | §Phase 6 |
| 8.2.8 | Members receive test.md and security-audit.md as evidence inputs | §Phase 6 |
| 8.2.9 | Conductor merges into acceptance-review.md | §Phase 6 |
| 8.2.10 | All-or-nothing gate: all 3 must pass for card to proceed | §Phase 6 |
| 8.2.11 | Block outcome: builder rework, card → implement | §Phase 6 |
| 8.2.12 | Exit condition documented: "ready to play" | §Phase 6 |

---

## 9. Worktree Management

| # | Check | Spec ref |
|---|-------|----------|
| 9.1 | Conductor owns worktree creation (at refine → design transition) | §Worktree Management |
| 9.2 | Create command: `git worktree add --detach /tmp/kanban-<card_id> origin/main` | §Worktree Management |
| 9.3 | Worktree path passed to: architect, builder, verifier, security-analyst, pilot | §Worktree Management |
| 9.4 | Conductor owns worktree cleanup (at done transition) | §Worktree Management |
| 9.5 | Cleanup command: `git worktree remove --force /tmp/kanban-<card_id> && git worktree prune` | §Worktree Management |
| 9.6 | Architect bootstraps the worktree (install deps, setup) | §Worktree Management |
| 9.7 | Architect creates the card's branch in the worktree | §Worktree Management |
| 9.8 | Builder commits to it | §Worktree Management |
| 9.9 | Pilot pushes it | §Worktree Management |
| 9.10 | Phases without worktree: analyst, designer, Council 1 (docs to card directory) | §Worktree Management |
| 9.11 | Council 2 receives read-only worktree access (read implementation files, write nothing) | §Worktree Management |

---

## 10. Boundaries

### 10.1 Sole-writer invariant

| # | Check | Spec ref |
|---|-------|----------|
| 10.1.1 | Conductor is documented as sole writer of BOARD.md | §Boundaries |
| 10.1.2 | Conductor is documented as sole writer of KNOWLEDGE.md | §Boundaries |
| 10.1.3 | Conductor is documented as sole writer of card.md (once card leaves backlog) | §Boundaries |
| 10.1.4 | Conductor is documented as sole writer of ADR files (via adr skill) | §Boundaries |
| 10.1.5 | Conductor is documented as sole writer of design-spec.md, solution-review.md, acceptance-review.md | §Boundaries |
| 10.1.6 | Phase docs on the PR (design.md, implement.md, test.md, security-audit.md, deliver-check.md) are documented as agent-written to worktree | §Boundaries |
| 10.1.7 | No agent file claims to write files the conductor owns | §Boundaries |

### 10.2 Sole mutator invariant

| # | Check | Spec ref |
|---|-------|----------|
| 10.2.1 | Only pilot claims GitHub mutation (push, open PR, merge) | §Boundaries |
| 10.2.2 | No other agent describes pushing to GitHub, opening PRs, or merging | §Boundaries |

### 10.3 Never-fix invariant

| # | Check | Spec ref |
|---|-------|----------|
| 10.3.1 | Verifier states it never fixes code | §Boundaries |
| 10.3.2 | Security-analyst states it never fixes code | §Boundaries |
| 10.3.3 | Verifier and security-analyst have `edit: deny` permissions | §Agent permissions |

---

## 11. Driver Interaction

| # | Check | Spec ref |
|---|-------|----------|
| 11.1 | Only conductor describes driver interaction | §Driver Interaction |
| 11.2 | Conductor presents new cards for driver approval | §Driver Interaction |
| 11.3 | Conductor presents needs-input to driver | §Driver Interaction |
| 11.4 | Conductor presents blocked cards to driver | §Driver Interaction |
| 11.5 | Conductor reports rework budget exhaustion | §Driver Interaction |
| 11.6 | Conductor reports pump cycle summary | §Driver Interaction |
| 11.7 | Conductor reports idle status | §Driver Interaction |
| 11.8 | Driver interaction is documented as "by exception only" | §Driver Interaction |
| 11.9 | Phase transitions do not require driver approval | §Driver Interaction |
| 11.10 | Design PRs require driver review before merging | §Driver Interaction |

---

## 12. ADR Lifecycle

| # | Check | Spec ref |
|---|-------|----------|
| 12.1 | Architect returns `proposed_adrs` in its result | §ADR Lifecycle |
| 12.2 | ADR proposals appear in design.md's `## Proposed ADRs` section | §ADR Lifecycle |
| 12.3 | Design PR is documented as the ADR approval gate | §ADR Lifecycle |
| 12.4 | Council 2 architect panelist checks ADR decisions honored in implementation | §ADR Lifecycle |
| 12.5 | Conductor persists approved ADRs to docs/adrs/ via adr skill | §ADR Lifecycle |

---

## 13. Skills

| # | Check | Spec ref |
|---|-------|----------|
| 13.1 | No agent file hard-codes a specific skill name in its instructions | §Agent File Structure |
| 13.2 | `skills/board-knowledge/SKILL.md` exists and is unchanged | Implementation plan §13 |
| 13.3 | `skills/adr/SKILL.md` exists and is unchanged | Implementation plan §13 |
| 13.4 | `skills/req-ids/SKILL.md` exists and is unchanged | Implementation plan §13 |
| 13.5 | All other skill files have updated agent name references (no old names) | Implementation plan §13 |

---

## 14. Command Verification

### 14.1 /kanban command

| # | Check | Spec ref |
|---|-------|----------|
| 14.1.1 | Dispatches `conductor` agent (not pump-gate + orchestrator skill) | §Dispatch Patterns |
| 14.1.2 | Passes `board_dir` to conductor | Implementation plan §10 |
| 14.1.3 | Reports pump summary from conductor's return | Implementation plan §10 |
| 14.1.4 | Reports idle status when conductor returns idle | Implementation plan §10 |
| 14.1.5 | Does NOT reference `pump-gate` or `kanban-orchestrator` skill | Implementation plan §10 |

### 14.2 Other commands

| # | Check | Spec ref |
|---|-------|----------|
| 14.2.1 | `/refine` references `analyst` (not `card-intake-checker`) | Implementation plan §11 |
| 14.2.2 | `/requirement` references `analyst` (not `card-intake-checker`) | Implementation plan §11 |
| 14.2.3 | `/kanban-init` description reflects new phase structure | Implementation plan §11 |
| 14.2.4 | `/retro` phase name references are updated (slice→spec/refine, review→accept) | Implementation plan §11 |
| 14.2.5 | `/migrate` agent name references are updated (if any) | Implementation plan §11 |

---

## 15. Doctrine Files

| # | Check | Spec ref |
|---|-------|----------|
| 15.1 | `AGENT-PROTOCOL.md` uses new agent names throughout | Implementation plan §12 |
| 15.2 | `AGENT-PROTOCOL.md` does NOT contain "Read KNOWLEDGE.md in full" as a pre-read instruction | §Agent File Structure |
| 15.3 | `AGENT-PROTOCOL.md` sole-writer boundaries list the expanded file set | §Boundaries |
| 15.4 | `INTAKE.md` references `analyst` (not `card-intake-checker` or `card-slicer`) | Implementation plan §12 |
| 15.5 | `checks/design.md` references `architect` (not `card-designer`) | Implementation plan §12 |
| 15.6 | `checks/intake.md` references `analyst` (not `card-intake-checker`) | Implementation plan §12 |
| 15.7 | `checks/slice.md` references `analyst` (not `card-slicer` or `card-slice-checker`) | Implementation plan §12 |
| 15.8 | `checks/deliver.md` references `pilot` (not `card-deliverer` or `card-deliver-checker`) | Implementation plan §12 |
| 15.9 | `checks/split.md` references `pilot` (not `pr-splitter` or `card-split-checker`) | Implementation plan §12 |

---

## 16. Marketplace and Plugin Metadata

| # | Check | Spec ref |
|---|-------|----------|
| 16.1 | `plugins/kanban-flow/.claude-plugin/plugin.json` version is `0.11.0` | Implementation plan §14 |
| 16.2 | `plugins/kanban-flow/.claude-plugin/plugin.json` description references 8 agents or the new team structure | Implementation plan §14 |
| 16.3 | `.claude-plugin/marketplace.json` kanban-flow entry description is updated | Implementation plan §14 |

---

## 17. Global Consistency Checks

| # | Check | Method |
|---|-------|--------|
| 17.1 | Zero matches for old agent names across the entire `.opencode/` tree | `rg "card-slicer\|card-implementer\|pump-gate\|card-designer\|card-tester\|card-lens-reviewer\|pr-splitter\|card-deliverer\|card-deliver-checker\|card-split-checker\|card-slice-checker\|card-design-checker\|card-intake-checker" plugins/kanban-flow/.opencode/` — expect zero results |
| 17.2 | Every new agent name appears exactly once as an agent file | Count files matching `agents/{analyst,designer,architect,builder,verifier,security-analyst,pilot,conductor}.md` — expect 8 |
| 17.3 | No agent name collision with command names | Check commands/ for files matching agent names — expect zero |
| 17.4 | No agent name collision with skill directory names | Check skills/ for directories matching agent names — expect zero |
| 17.5 | All 8 agent files follow the file structure template (frontmatter → # heading → persona → ## Inputs → ## Procedure → ## Return) | Manual review |

---

## Verification Summary

| Section | Checks | Pass threshold |
|---------|--------|----------------|
| 1. Agent Inventory | 22 | 22/22 |
| 2. Agent Frontmatter | 40 | 40/40 |
| 3. Agent Persona and Ownership | 42 | 42/42 |
| 4. Agent Procedure Verification | 44 | 44/44 |
| 5. Agent Return Contract | 19 | 19/19 |
| 6. Agent Permissions Audit | 5 | 5/5 |
| 7. Lifecycle and State Machine | 23 | 23/23 |
| 8. Council Dispatch | 21 | 21/21 |
| 9. Worktree Management | 11 | 11/11 |
| 10. Boundaries | 9 | 9/9 |
| 11. Driver Interaction | 10 | 10/10 |
| 12. ADR Lifecycle | 5 | 5/5 |
| 13. Skills | 5 | 5/5 |
| 14. Command Verification | 10 | 10/10 |
| 15. Doctrine Files | 9 | 9/9 |
| 16. Marketplace Metadata | 3 | 3/3 |
| 17. Global Consistency | 5 | 5/5 |
| **Total** | **283** | **283/283** |
