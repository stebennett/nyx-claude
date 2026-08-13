# Kanban Flow Agent Specification

## Agents

8 agents. Each name is a single word. Each name tells the driver exactly what work the agent completes.

| # | Agent | Work | Maps to |
|---|-------|------|----------|
| 1 | **`analyst`** | Product refinement — analyzes requirements, defines acceptance criteria with success metrics, produces cards. Owns the *what* and *why*. | Product Manager |
| 2 | **`designer`** | Product design — owns interaction flows, component states (loading, empty, error, edge), accessibility requirements, visual hierarchy, responsive behavior. Produces `design-spec.md`. Owns the *how it works and feels*. | Product Designer |
| 3 | **`architect`** | Technical design — chooses approach with alternatives, defines interfaces and data flow, writes TDD-ready task list, states test strategy with concrete assertions, runs upfront threat modeling and performance modeling. Self-checks design integrity. Produces `design.md` and `proposed_adrs`. Owns the *how we build it*. | System Architect |
| 4 | **`builder`** | Implementation — writes code TDD from the design task list, handles rework and driver PR comments. Never reviews its own work. Owns the *build it*. | Product Development SE |
| 5 | **`verifier`** | Independent verification — runs full test suite, classifies every failure, validates success-metric instrumentation. Dispatches `security-analyst` concurrently. Fast gate — blocking findings skip Council 2. Never fixes code. Owns the *does it work?* | Test Engineer |
| 6 | **`security-analyst`** | Security specialist — runs inside the verifier loop (Phase 5 only). Audits for vulnerabilities, validates dependency health, checks exposed secrets/config, verifies threat mitigations from design are present in code. Does **not** participate in councils. Classify only, never fixes. Owns the *is it safe?* | Security Engineer |
| 7 | **`pilot`** | Delivery pipeline — pre-flight delivery readiness check ("is this ready to ship?"), rebase and ship PRs, carve oversized branches into safe slices, verify delivery readiness. Sole agent touching GitHub production surfaces. Owns the *ship it*. | SRE |
| 8 | **`conductor`** | Orchestration — sole writer of board state, dispatch decisions, council facilitation, gate logic, rework loops, status reporting. Creates and manages worktrees. Interacts with the driver only by exception. Owns the *coordinate it*. | Delivery Manager / Scrum Master |

---

## Lifecycle

### Phase 0 — Product Refinement (`analyst`)

```
Requirement → analyst → card(s) with acceptance criteria + success metrics
```

The `analyst` takes a product requirement (from `/refine`, `/requirement`, or the spec) and produces one or more cards. Each card carries:

- **Acceptance criteria** — observable, testable statements citing the spec section each enforces
- **Success metrics** — "how will we know this worked in production?" (adoption %, error rate, latency, user satisfaction)
- **Scope** — in/out of scope boundaries
- **Dependencies** — depends_on relationships, milestone assignment

The `analyst` self-checks card quality before returning. Approved cards enter `backlog`. The `conductor` does not gate this phase — the driver is the acceptance gate for new cards.

### Phase 1 — Product Design (`designer`)

```
Backlog card → designer → design-spec.md
```

The `designer` takes a refined card and produces `design-spec.md` covering:

- **Interaction flows** — user journey through the feature
- **Component states** — loading, empty, populated, error, edge cases (one row per state)
- **Accessibility requirements** — ARIA roles, keyboard navigation, screen-reader expectations, contrast ratios
- **Visual hierarchy** — layout, information priority, responsive breakpoints
- **Error handling** — user-facing error states and recovery paths

`design-spec.md` is an input to the architect. The architect translates UX decisions into technical decisions; the designer stays in the problem space. For cards with no user-facing surface, the `conductor` skips this phase.

### Phase 2 — Council 1: Solution Refinement

```
Card + design-spec.md → council (architect, builder, verifier, pilot, designer)
                      → solution-review.md (sized, scoped, multi-perspective assessment)
```

The `conductor` dispatches all 5 domain agents concurrently against the same card. Each returns an independent assessment:

| Council member | Assessment |
|----------------|------------|
| `architect` | Complexity, approach viability, architecture risks, reusable patterns |
| `builder` | Size estimate (per-file working), implementation surfaces, gotcha alerts (invokes `board-knowledge`) |
| `verifier` | Testability assessment — assertion gaps, edge-case exposure, test level requirements, success-metric instrumentation feasibility |
| `pilot` | Delivery risk — PR sizing estimate, dependency conflicts, migration impact, CI/CD path |
| `designer` | Design fidelity check — does the technical assessment respect `design-spec.md`? Are interaction states all accounted for? |

The `conductor` merges assessments into `solution-review.md` and gates: any council member returning `verdict: block` halts the card and routes it back to the `analyst` for refinement with the council's findings. A `pass` produces a sized, scoped card ready for formal design. Where the council's feedback is genuinely unclear and cannot be resolved by refinement, the `conductor` escalates to the driver (`needs-input`).

Card status: `spec` → `refine` (pass) or `spec` → `backlog` (block, analyst refines).

### Phase 3 — Technical Design (`architect`)

```
Solution-reviewed card → architect → design.md + proposed_adrs
```

The `conductor` creates a git worktree for the card and dispatches the `architect`. The `architect` produces `design.md`:

- **Intent** — restated in technical terms
- **Approach** — chosen approach with 2-3 alternatives and rejection rationale
- **Interfaces** — function/class signatures, parameter and return types, module boundaries
- **Data flow** — schema impact, migration path
- **Implementation task list** — numbered, file-level, TDD-ordered (test → red → implement → green → commit)
- **Test strategy** — coverage target, property tests for invariants, concrete assertions computed independently of the implementation, per-acceptance-criterion mutation that would break each test
- **Spec references** — cited sections, downstream agents read only these
- **Proposed ADRs** — significant architecture/technology decisions
- **Security & performance** — threat model for new attack surfaces, performance budget, load characteristics

The `architect` self-applies the `design-check` skill before returning. The `conductor` gates: `verdict: fail` triggers rework (the `architect` re-designs, up to configured rework budget, looping within `design`); `verdict: pass` dispatches the `pilot` to open the design PR. The driver reviews and merges the design PR, which approves the ADRs.

Card status: `design` → `design` (rework) or `design` → `implement` (pass).

### Phase 4 — Implementation (`builder`)

```
Design-approved card → builder → working code + implement.md
```

Three dispatch modes:

- **Fresh** — execute the design task list TDD from the top. Conventional Commits, commit after each green task.
- **Rework** — fix blocking findings from `verifier`, `security-analyst`, or Council 2. All rework means the `builder` fixes it. Test-first where the finding is a behavior bug.
- **PR-comment** — address human review comments on an open PR.

The `builder` works in the card's worktree. It does **not** review its own work — quality verification is the council's responsibility.

Card status: `implement` → `verify`.

### Phase 5 — Verification (`verifier` + `security-analyst`)

```
Implemented card → verifier → test.md
                 → security-analyst → security-audit.md
```

The `conductor` dispatches `verifier`, which dispatches `security-analyst` concurrently. Both run in the card's worktree, read-only.

**`verifier`** runs: full test suite, coverage report, property tests, lint/types gates, and configured test levels. Classifies every blocker:

- **product** — the spec or acceptance criteria are wrong
- **test** — the test expectation is wrong (assertion mismatch)
- **environment** — CI, DB, network, dependency
- **flake** — non-deterministic, passes on re-run

Also validates success-metric instrumentation — are the telemetry hooks for each metric defined by the `analyst` present and correctly wired?

**`security-analyst`** audits: security-critical paths, dependency health, exposed secrets/config, auth/authz on new interfaces, threat mitigations from the design phase present in code.

Both agents **classify only** — they never fix code.

**Phase 5 is a fast gate.** If either returns a blocking finding, the `conductor` dispatches the `builder` for rework immediately and **skips Council 2**. After rework the lifecycle resumes at `verify` (Phase 5 re-runs).

Card status: `verify` → `accept` (on pass) or `verify` → `implement` (on block, builder rework).

### Phase 6 — Council 2: Acceptance Verification

```
Verified card → council (architect, designer, pilot)
              → acceptance-review.md
```

The `conductor` dispatches `architect`, `designer`, and `pilot` concurrently. Each has **read-only access to the card's worktree** and reviews the implementation independently against the spec, design, and acceptance criteria, using `test.md` and `security-audit.md` (already on disk from Phase 5) as evidence. The `verifier` and `security-analyst` do **not** re-run. The `builder` is the subject of review, not a reviewer.

| Council member | Verdict |
|----------------|---------|
| `architect` | Design fidelity — interfaces implemented as specified? ADR decisions honored? Task list complete? Performance budgets met? |
| `designer` | Experience fidelity — interaction flows match `design-spec.md`? All component states present? Accessibility met? |
| `pilot` | Delivery readiness — PR size acceptable? Migration path clear? CI/CD configuration correct? |

The `conductor` merges assessments into `acceptance-review.md`. All council members must return `verdict: pass` for the card to proceed to delivery.

Card status: `accept` → `deliver` (on pass) or `accept` → `implement` (on block, builder rework).

> **Council exit condition:** When Council 2 passes, the card is **ready to play** — the defined spec, design, and requirements have all been met. The `pilot` can ship.

### Phase 7 — Delivery (`pilot`)

```
Accepted card → pilot → open PR(s) + deliver-check.md
```

The `pilot` runs a **pre-flight delivery check**: "is this ready to ship?" — verifies CI is green, branch is rebaseable, diff is within limits, docs ride the PR.

**Normal path:** Rebase on `main`, confirm green locally, `git push`, open PR. Validate: targets `main`, body claims are true, docs ride the PR, CI is green, no code in design PRs.

**Oversized path:** When the branch diff exceeds `size_limit`, the `pilot` carves the branch into ordered whole-file slices, proves each independently green in a bootstrap throwaway worktree, and opens one PR per slice. On refusal (entangled code), ships as one oversized PR with the entanglement documented.

The `pilot` self-applies the `deliver-check` skill before returning. It is the **only agent that mutates GitHub**. The driver merges PRs (or instructs the `pilot` to merge).

Card status: `deliver` → `done`.

---

## Results Contract

Every agent returns a structured result. The `conductor` reads this and acts on it.

### Common fields (all agents)

| Field | Type | Description |
|-------|------|-------------|
| `status` | `"complete"` \| `"blocked"` \| `"needs-input"` | Outcome |
| `phase_doc` | `string` | Full markdown content for the phase document. The `conductor` persists it to the card's worktree or directory. |
| `knowledge` | `[{scope, section, entry}]` | Optional. Entries for `KNOWLEDGE.md` (Conventions, Gotchas, Glossary). Scope: `repo` \| `personal`. |

### Agent-specific fields

**`analyst`**

| Field | Type | Description |
|-------|------|-------------|
| `cards` | `[{title, type, layer, acceptance_criteria, success_metrics, scope, depends_on, milestone}]` | The proposed card set |

**`designer`**

No additional fields beyond common.

**`architect`**

| Field | Type | Description |
|-------|------|-------------|
| `proposed_adrs` | `[{title, context, decision, consequences, supersedes}]` | Proposed architecture decisions. The design PR serves as the approval gate. |

**`builder`**

| Field | Type | Description |
|-------|------|-------------|
| `commits` | `[{hash, subject}]` | Commits made during implementation |
| `blockers` | `[{description, evidence}]` | Only when `status: "blocked"` — what stopped progress and the evidence |

**`verifier`**

| Field | Type | Description |
|-------|------|-------------|
| `verdict` | `"pass"` \| `"fail"` | Did the verification pass? |
| `blockers` | `[{type, description, evidence}]` | Only when `verdict: "fail"` — each classified as `product` \| `test` \| `environment` \| `flake` |

**`security-analyst`**

| Field | Type | Description |
|-------|------|-------------|
| `verdict` | `"pass"` \| `"fail"` | Did the security audit pass? |
| `vulnerabilities` | `[{severity, description, path, evidence}]` | Only when `verdict: "fail"` |

**`pilot`**

| Field | Type | Description |
|-------|------|-------------|
| `verdict` | `"pass"` \| `"fail"` | Is delivery ready? |
| `pr_urls` | `[string]` | URLs of opened PRs |
| `slice_count` | `number` | Number of slices shipped (1 = normal, >1 = split, 0 = refused/oversized single PR) |

**Council members** (returned during Phase 2 and Phase 6)

| Field | Type | Description |
|-------|------|-------------|
| `verdict` | `"pass"` \| `"block"` | Does this council member approve? |
| `assessment` | `string` | The member's assessment (merged into solution-review.md or acceptance-review.md) |
| `findings` | `[{severity, description}]` | Specific findings (blocking if `verdict: "block"`) |

**`conductor`** (returned to the `/kanban` command)

| Field | Type | Description |
|-------|------|-------------|
| `pump_summary` | `{in_flight, backlog, wip_limit, free_slots}` | Board snapshot |
| `cards_processed` | `[{card_id, phase, status, phase_doc, pr_urls}]` | Every card touched this cycle |
| `gates` | `[{card_id, gate, verdict}]` | Gate decisions |
| `commits` | `[{hash, subject}]` | State commits made |

---

## Kanban State Machine

Each card has a `status` field. The `conductor` drives transitions based on file presence and agent results.

```
                   analyst
                      │
                      ▼
                   ┌────────┐
            ┌─────│backlog │◄──────────────┐
            │     └───┬─┬──┘               │
            │         │ │ designer         │ Council 1 block
            │         │ │ (UI cards)       │ → analyst refines
            │         │ ▼                  │
            │       ┌────────┐             │
            │       │  spec  │             │
            │       └───┬────┘             │
            │           │ Council 1        │
            │           ▼                  │
            │       ┌────────┐             │
            │ (non- │ refine │             │
            │  UI)  └───┬────┘             │
            │           │ architect        │
            │       ┌───┘ (worktree        │
            │       │     created)         │
            │       ▼                      │
            │  ┌──────────────┐            │
            │  │    design    │◄── arch     │
            │  └──────┬───────┘   rework   │
            │         │ builder            │
            │         ▼                    │
            │  ┌──────────────┐            │
      ┌─────┼─►│  implement   │◄─────┐     │
      │     │  └──────┬───────┘      │     │
      │     │         │ verifier     │     │
      │     │         ▼ + security   │     │
      │     │  ┌──────────────┐      │     │
      │     │  │    verify    │──block──►──┤
      │     │  └──────┬───────┘      │     │
      │     │         │ Council 2    │     │
      │     │         ▼              │     │
      │     │  ┌──────────────┐      │     │
      │     │  │    accept    │──block──►──┘
      │     │  └──────┬───────┘
      │     │         │ pilot
      │     │         ▼
      │     │  ┌──────────────┐
      │     │  │   deliver    │  PR(s) open
      │     │  └──────┬───────┘
      │     │         │ PR merged
      │     │         ▼
      │     │  ┌──────────────┐
      │     │  │     done     │
      │     │  └──────────────┘
      │     │
      │     └── "needs-input" ── any state → driver
      │     └── "blocked"      ── any state → driver
```

### Transitions

| From | To | Trigger |
|------|----|---------|
| *(new)* | `backlog` | `analyst` produces cards, driver approves |
| `backlog` | `spec` | `designer` dispatched, `design-spec.md` present. Skipped for non-UI cards (→ `refine` directly). |
| `backlog` | `refine` | Non-UI card — `designer` skipped, card proceeds directly to Council 1 |
| `spec` | `refine` | Council 1 passes, `solution-review.md` present |
| `spec` | `backlog` | Council 1 blocks — findings routed to `analyst` for refinement |
| `refine` | `design` | `architect` dispatched, conductor creates worktree |
| `design` | `design` | Architect self-check fails — re-designs (up to rework budget) |
| `design` | `implement` | `architect` returns `status: complete`, `design.md` present, design PR merged |
| `implement` | `verify` | `builder` returns `status: complete`, `implement.md` present |
| `verify` | `accept` | Phase 5 passes (both `verifier` and `security-analyst` verdict: pass) |
| `verify` | `implement` | Phase 5 blocks — builder rework |
| `accept` | `deliver` | Council 2 passes, `acceptance-review.md` present |
| `accept` | `implement` | Council 2 blocks — builder rework |
| `deliver` | `done` | `pilot` returns `status: complete`, PR(s) merged |
| *any* | `needs-input` | Agent returns `status: "needs-input"` — clarification required (driver escalation) |
| *any* | `blocked` | Agent returns `status: "blocked"` — driver escalation needed |

### Rework budget

Each phase that can re-trigger work has a configured rework budget (default: 3 cycles):
- `design → design` — architect self-check rework
- `verify → implement` — Phase 5 blocks, builder reworks
- `accept → implement` — Council 2 blocks, builder reworks

When any budget is exhausted, the card transitions to `blocked` with the rework history.

---

## Worktree Management

The `conductor` owns worktree lifecycle. Each card gets one worktree, created when the card enters `design` and cleaned up when the card reaches `done`.

- **Create:** `git worktree add --detach /tmp/kanban-<card_id> origin/main` when card enters `design`
- **Share:** Worktree path passed to `architect`, `builder`, `verifier`, `security-analyst`, and `pilot` via dispatch
- **Bootstrap:** `architect` bootstraps the worktree (install deps, setup) as part of design
- **Cleanup:** `git worktree remove --force /tmp/kanban-<card_id> && git worktree prune` when card reaches `done`
- **Branch:** The `architect` creates the card's branch in the worktree; the `builder` commits to it; the `pilot` pushes it

Phases that do **not** need a worktree: `analyst`, `designer`, Council 1. These write/persist docs to the card directory (`docs/cards/CARD-NNN/`).

Council 2 members receive **read-only** worktree access — they read `design.md`, `implement.md`, and the implementation code but write nothing.

---

## ADR Lifecycle

1. **Propose:** `architect` includes `proposed_adrs` in its return. Proposals also appear in `design.md`'s `## Proposed ADRs` section.
2. **Approve:** The design PR is the approval gate. The driver reviews the design PR (which includes ADR proposals) and merges.
3. **Verify:** Council 2 (`architect` panelist) checks: "Are ADR decisions honored in the implementation?"
4. **Persist:** The `conductor` routes approved ADRs to `docs/adrs/` using the `adr` skill, committed to `main`.

---

## Driver Interaction

The `conductor` is the sole agent that interacts with the driver. Interaction is **by exception only** — the system runs autonomously.

| Event | Conductor action |
|-------|-----------------|
| New cards proposed | Present card set to driver for approval (Phase 0 exit) |
| Agent returns `needs-input` | Present the agent's question to the driver. Park card in `needs-input`. |
| Agent returns `blocked` | Present the blocker to the driver. Park card in `blocked`. |
| Rework budget exhausted | Report the card and its rework history. Park in `blocked`. |
| Pump cycle complete | Report summary: cards processed, gates, PRs, commits. |
| Pump idle | Report idle status with in-flight and backlog counts. |

The driver does **not** approve individual phase transitions, design decisions, or PR merges (exception: design PRs require driver review before merging, and the driver may instruct the `pilot` to merge implementation PRs).

---

## Testability Across the Lifecycle

Testability is not a single phase. It is a thread running through every agent:

| Phase | Agent | Testability responsibility |
|-------|-------|---------------------------|
| Refinement | `analyst` | Every acceptance criterion must be observable — "what would I run to see this?" Success metrics must be measurable. |
| Design | `designer` | Every component state is enumerated and testable. Interaction flows have concrete expected outcomes. |
| Council 1 | `verifier` | Assesses testability before design begins. Flags assertion gaps, edge-case exposure, untestable states. |
| Architecture | `architect` | Test strategy with concrete assertions computed independently of the implementation. For each AC, names the mutation that would break its test. Design for testability: pure domain logic, I/O at edges. |
| Implementation | `builder` | Implements TDD: test first, see red, then code. Never weakens a test to make it pass. Test each task before committing. |
| Verification | `verifier` | Independent gate. Runs full suite. Classifies failures — never fixes. Validates success-metric instrumentation. Fast gate — blocking findings skip Council 2, go straight to builder rework. |
| Verification | `security-analyst` | Threat-model validation, dependency health, secrets/config audit. Classify only — never fixes. Fast gate. |

### Test-level framework (when project configures levels)

When the project configures test levels (integration, contract, journey, experience, unit), the `architect`'s design MUST include a `### Levels` block defining which levels are selected (with what they cover) or declined (with rationale). The `verifier` validates that selected levels are delivered and their test data/seeding needs are met.

---

## Dispatch Patterns

### Standard dispatch

```
conductor → dispatch(agent, {card, worktree?, inputs}) → agent returns structured result
```

The `conductor` reads the board, decides which card is ready for which phase, and dispatches the appropriate agent. Agents return the result contract (see above); the `conductor` persists `phase_doc`, routes `knowledge` entries, updates card status, and commits state to `main`.

### Council 1 dispatch (Phase 2)

```
conductor → dispatch([architect, builder, verifier, pilot, designer]) concurrently
         → merge assessments → solution-review.md
```

Five agents receive the same card and `design-spec.md`. Each returns `{verdict, assessment, findings}`. The `conductor` merges into `solution-review.md` and gates. All five must return `verdict: pass` for the card to proceed to design.

### Council 2 dispatch (Phase 6)

```
conductor → dispatch([architect, designer, pilot]) concurrently
         → merge assessments → acceptance-review.md
```

Three agents review the implementation with **read-only worktree access**. They receive the card's worktree path plus `design-spec.md`, `design.md`, `implement.md`, and Phase 5 evidence (`test.md`, `security-audit.md`) on disk. The `builder` is the subject of review. All three must return `verdict: pass` for the card to proceed to delivery.

Council 2 only fires when Phase 5 passes. If Phase 5 blocks, the conductor dispatches the builder for rework and skips the council.

### Verification dispatch (Phase 5)

```
conductor → dispatch(verifier, {card, worktree, ...})
          → verifier dispatches(security-analyst, {card, worktree, threat-model}) concurrently
          → verifier returns both results
```

The `verifier` dispatches `security-analyst` as a sub-agent. Both run concurrently in the card's worktree. The `verifier` returns its result plus the `security-analyst`'s result, so the conductor receives both verdicts.

---

## Agent Interactions

```
┌──────────────┐
│   analyst    │ ← Phase 0 — Product refinement
└──────┬───────┘
       │ card(s)
┌──────▼───────┐
│   designer   │ ← Phase 1 — Product design (skipped for non-UI cards)
└──────┬───────┘
       │ design-spec.md
       ▼
┌────────────────────────────────────────────┐
│           Council 1 (Phase 2)               │
│  architect  builder  verifier  pilot        │
│  designer                                  │
└──────────────────┬─────────────────────────┘
                   │ solution-review.md
┌──────────────────▼─────────────────────────┐
│   architect   │ ← Phase 3 — Technical design│
│               │   worktree created          │
├───────────────┤                            │
│    builder    │ ← Phase 4 — Implementation  │
├───────────────┤                            │
│   verifier    │──► security-analyst         │
│               │ ← Phase 5 — Verification    │
│               │   (fast gate)               │
├───────────────┤                            │
┌────────────────────────────────────────────┐
│           Council 2 (Phase 6)               │
│  architect  designer  pilot                │
│   (read-only worktree, builder reviewed)   │
└──────────────────┬─────────────────────────┘
                   │ acceptance-review.md
                   │ "ready to play"
┌──────────────────▼─────────────────────────┐
│     pilot     │ ← Phase 7 — Delivery        │
└───────────────┘                            │
                                             │
┌────────────────────────────────────────────┘
│
┌────▼─────────┐
│  conductor   │ ← Throughout
│  - board     │
│  - dispatch  │
│  - worktrees │
│  - gates     │
│  - commits   │
└──────────────┘
```

---

## Boundaries

### Sole-writer invariant

The `conductor` is the sole writer of:
- `docs/cards/BOARD.md`
- `docs/cards/KNOWLEDGE.md`
- `docs/cards/CARD-*/card.md` (once a card leaves `backlog`)
- `docs/adrs/` (ADR files, via the `adr` skill)
- `docs/cards/CARD-*/design-spec.md` (persisted from `designer`'s `phase_doc`)
- `docs/cards/CARD-*/solution-review.md` (merged from Council 1 assessments)
- `docs/cards/CARD-*/acceptance-review.md` (merged from Council 2 assessments)

Phase documents that ride the PR (`design.md`, `implement.md`, `test.md`, `security-audit.md`, `deliver-check.md`) are written by their respective agents to the worktree and committed to the card's branch.

### Sole mutator invariant

The `pilot` is the sole agent permitted to mutate GitHub — pushes, opens PRs, merges (when instructed by driver).

### Never-fix invariant

The `verifier` and `security-analyst` classify findings. They never fix code, never change behavior, never modify the worktree beyond read-only operations.

---

## Agent File Structure

Each agent file (`agents/<name>.md`) follows this structure:

```markdown
---
name: <name>
description: <one-line summary of work>
mode: subagent
model: <model>
permission:
  edit: <allow|deny>
  bash: <allow|deny|ask>
---

# <name> — <persona>

<persona preamble: what you are, what you own, what you produce>

## Inputs

<what the dispatch provides — files, paths, parameters>

## Procedure

<how you do your work>

## Return

<structured result format — per the results contract>
```

Agents discover and invoke skills autonomously. Skills are not hard-coded in agent files or dispatch instructions — an agent may invoke any skill available to it to complete its work.
