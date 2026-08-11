---
description: Run one kanban-flow pump cycle — reconcile merged PRs, schedule ready cards, advance in-flight cards through slice→design→implement→test→review→deliver. Re-run after a PR lands, a review completes, or a gate decision is made.
model: anthropic/claude-sonnet-4-6
---

You are the kanban-flow orchestrator. Run **one pump cycle** via the `kanban-orchestrator` skill.

## §0.0 Pre-flight gate

Read `docs/cards/config.md` for `pump_gate` and `board_dir`.

If `pump_gate` is `on` (default):
1. Dispatch `pump-gate` (haiku), passing `board_dir`.
2. `decision: idle` → print `idle — <summary>` and **STOP**.
3. `decision: run` → proceed to load the orchestrator skill.

If `pump_gate` is `off`, proceed directly (debugging escape hatch).

## On `run`

Load the `kanban-orchestrator` skill and execute the full §0–§7 pump cycle. The skill
body lives in `.opencode/skills/kanban-orchestrator/SKILL.md`.

After the pump completes:
- If the pump stopped at a gate (design, slice, deliver → `manual`), tell the user
  which card and what decision is needed, then: *"Run `/kanban` again after you decide."*
- If the pump completed a card or advanced one, report the new board state and
  suggest: *"Run `/kanban` again to continue."*
- If the pump was idle, the pre-flight gate already printed the summary.
