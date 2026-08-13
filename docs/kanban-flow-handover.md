# Kanban Flow Agent Migration — Handover

## Context

This conversation transformed the kanban-flow plugin's agent architecture from 13 phase-specific agents into 8 role-based agents aligned to a high-performing product delivery team.

**Starting point:** The plugin had 13 agents (5 producers + 5 checkers + pump-gate + intake-checker + lens-reviewer) with phase-specific names like `card-slicer`, `card-implementer`, `card-deliverer`. Agents self-read `KNOWLEDGE.md` before every dispatch. Skills were hard-coded into agent instructions.

**Ending point:** 8 role-based agents (analyst, designer, architect, builder, verifier, security-analyst, pilot, conductor). Agents invoke a `board-knowledge` skill on-demand rather than pre-reading. Skills are discovered autonomously. Two concurrent councils bookend the build cycle. A state machine governs card transitions.

## Reference Files

Three documents in `docs/` define the complete target state:

| File | Purpose |
|------|---------|
| `docs/kanban-flow-agent-spec.md` | The specification — 8 agents, 8 lifecycle phases, state machine, results contract, boundaries, councils, worktree management |
| `docs/kanban-flow-implementation-plan.md` | The implementation plan — 15 tasks ordered with dependencies, each task specifying what to create/delete/update and how |
| `docs/kanban-flow-verification-checklist.md` | The verification checklist — 283 yes/no checks across 17 sections, each referencing the spec |

## Current Working State

### Committed changes (on branch `task/01-directory-scaffolding`)

**Commit `5b6ceb9`:** Removed `KNOWLEDGE.md` self-read references from all agent and skill files. Created `skills/board-knowledge/SKILL.md` as the single point of `KNOWLEDGE.md` access. Updated `AGENT-PROTOCOL.md`, `checks/design.md`, `lenses/acceptance.md`, and the orchestrator dispatch contract.

Files changed: 14 (13 modified + 1 new)
- 5 agent files: `pump-gate.md`, `card-intake-checker.md`, `card-slice-checker.md`, `card-split-checker.md`, `card-deliver-checker.md` — removed KNOWLEDGE.md references
- 5 skill files: `design-check`, `intake-check`, `kanban-orchestrator`, `slice-check`, `split-check` — removed KNOWLEDGE.md references
- 3 doctrine files: `AGENT-PROTOCOL.md`, `checks/design.md`, `lenses/acceptance.md` — updated to reference `board-knowledge` skill
- 1 new file: `skills/board-knowledge/SKILL.md`

### Uncommitted changes

None — all temporary files are in `docs/` (untracked). The `docs/decouple-agents-from-skills.md` file and untracked skill directories (`carve-pr/`, `deliver-check/`, etc.) are artifacts from a prior session's migration work and are not part of this task.

### What still has KNOWLEDGE.md references (intentionally kept)

- `kanban-orchestrator/SKILL.md` (6 refs) — orchestrator reads/writes board state
- `board-knowledge/SKILL.md` (3 refs) — the skill itself owns access
- `adr/SKILL.md` (1 ref) — routing rule: what goes to ADR vs knowledge
- `req-ids/SKILL.md` (1 ref) — boundary rule: never touches board state
- `doctrine/AGENT-PROTOCOL.md` (3 refs) — now points to skill; boundary rules; routing
- `doctrine/INTAKE.md` (1 ref) — boundary rule
- `doctrine/pr-template.md` (1 ref) — PR template section
- Commands (`refine.md`, `requirement.md`, `retro.md`, `kanban-init.md`, `migrate.md`) — board management concerns

## Key Decisions

### 1. Knowledge access model (pull, not push)
Agents no longer pre-load `KNOWLEDGE.md`. Instead they invoke the `board-knowledge` skill on-demand when uncertain about a convention, gotcha, or glossary term. The skill reads `KNOWLEDGE.md`, searches for relevant entries, and returns only matches. This decouples agents from the storage format — swap `KNOWLEDGE.md` for a different backend and only `board-knowledge/SKILL.md` changes.

### 2. Role-based agents, not phase-based
Agents are named for the role they embody, not the phase they execute. `card-slicer` → `analyst`. `card-designer` → `architect`. `card-implementer` → `builder`. Names are single words that tell the driver what work the agent completes.

### 3. Checkers are self-checks, not separate agents
The 5 checker agents (`card-slice-checker`, `card-design-checker`, etc.) are collapsed into their producer agents as self-check procedures. In a high-performing team, quality is part of the job, not someone else's job.

### 4. Two councils bookend the build cycle
**Council 1** (Phase 2, before design): 5 agents (architect, builder, verifier, pilot, designer) assess the card concurrently. "Should we build this?" Output: `solution-review.md`. Block → back to analyst for refinement.

**Council 2** (Phase 6, after build): 3 agents (architect, designer, pilot) review the implementation concurrently with read-only worktree access. The builder is the subject of review. "Did we build what we agreed?" Output: `acceptance-review.md`. Block → builder rework. Exit condition: "ready to play."

### 5. Phase 5 is a fast gate
The verifier and security-analyst run before Council 2. If either finds a blocking issue, the card goes straight to builder rework and Council 2 is skipped. No point in the council reviewing design fidelity when the tests are failing.

### 6. Security-analyst runs only in Phase 5
Dispatched by the verifier concurrently. Does NOT participate in councils — security is about fast feedback, not council deliberation. Audits for vulnerabilities, dependency health, secrets/config, auth/authz, threat mitigation presence. Classify only, never fixes.

### 7. Product designer is a first-class agent
The `designer` produces `design-spec.md` covering interaction flows, component states, accessibility, visual hierarchy, error handling. Sits between analyst and Council 1. Participates in both councils. Skipped for cards with no user-facing surface.

### 8. Conductor is a peer agent, not an invisible skill
The orchestration logic moves from `skills/kanban-orchestrator/SKILL.md` into `agents/conductor.md`. Conductor is a peer of the other 7 agents with a coordination responsibility. The `/kanban` command dispatches conductor, which dispatches everyone else.

### 9. Driver interaction is by exception only
The system runs autonomously. The conductor contacts the driver only for: new card approval, `needs-input`, `blocked`, rework budget exhaustion, pump cycle summary, idle report. No per-phase approvals.

### 10. Skills are autonomous
Agents discover and invoke skills on their own. No skill names are hard-coded in agent files or dispatch instructions. Skills remain as reusable procedure documents that agents can load when needed.

### 11. State machine governs all transitions
Card states: `backlog → spec → refine → design → implement → verify → accept → deliver → done`. With rework loops (design→design, verify→implement, accept→implement), escape hatches (needs-input, blocked), and rework budgets (default 3 cycles per path). Non-UI cards skip `spec` directly to `refine`.

### 12. Single worktree per card
Conductor creates the worktree at `refine → design` (when architect is dispatched) and cleans up at `done`. All code-phase agents (architect, builder, verifier, security-analyst, pilot) share the same worktree. Council 2 gets read-only access. Designer, analyst, and Council 1 write to the card directory instead.

## Implementation Summary

### Files to create (8)
`agents/conductor.md`, `agents/analyst.md`, `agents/designer.md`, `agents/architect.md`, `agents/builder.md`, `agents/verifier.md`, `agents/security-analyst.md`, `agents/pilot.md`

### Files to delete (13)
All 13 old agent files: `pump-gate.md`, `card-slicer.md`, `card-slice-checker.md`, `card-designer.md`, `card-design-checker.md`, `card-implementer.md`, `card-tester.md`, `card-lens-reviewer.md`, `pr-splitter.md`, `card-split-checker.md`, `card-deliverer.md`, `card-deliver-checker.md`, `card-intake-checker.md`

### Files to update
- 6 commands (kanban, refine, requirement, kanban-init, retro, migrate)
- ~10 doctrine files (AGENT-PROTOCOL.md, INTAKE.md, checks/*, card-template.md, PR templates)
- 13 skill files (agent name references in descriptions + deprecate kanban-orchestrator)
- 2 metadata files (plugin.json, marketplace.json)

### Model assignments
- `conductor`, `analyst`, `designer`, `architect`, `builder`, `verifier`, `security-analyst`: `anthropic/claude-sonnet-4-6`
- `pilot`: `anthropic/claude-haiku-4-5` (delivery is procedural)

### Permissions
- `edit: allow`: conductor (board state), architect (worktree bootstrap), builder (code), pilot (GitHub)
- `edit: deny`: analyst, designer, verifier, security-analyst

### Agent mapping (old → new)
```
pump-gate           → conductor (pre-flight)
card-slicer         → analyst
card-slice-checker  → analyst (self-check)
card-intake-checker → analyst (self-check)
card-designer       → architect
card-design-checker → architect (self-check)
card-implementer    → builder
card-tester         → verifier
card-lens-reviewer  → Council 2 members (architect, designer, pilot)
pr-splitter         → pilot (oversized path)
card-split-checker  → pilot (self-check)
card-deliverer      → pilot
card-deliver-checker → pilot (self-check)
                    + designer (new)
                    + security-analyst (new)
                    + conductor (new)
```

## Execution Order

1. Create 8 agent files (can run in parallel)
2. Delete 13 old agent files
3. Rewrite `/kanban` command
4. Update other commands
5. Update doctrine files
6. Update skill files
7. Update marketplace/plugin metadata
8. Run verification checklist (283 checks)

## Verification

Run `docs/kanban-flow-verification-checklist.md` against the implementation. All 283 checks must pass.

Global grep check:
```bash
rg "card-slicer|card-implementer|pump-gate|card-designer|card-tester|card-lens-reviewer|pr-splitter|card-deliverer|card-deliver-checker|card-split-checker|card-slice-checker|card-design-checker|card-intake-checker" plugins/kanban-flow/.opencode/
```
Must return zero results outside of deprecated orchestrator skill.
