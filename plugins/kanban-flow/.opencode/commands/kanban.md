---
description: Run one kanban-flow pump cycle — the conductor reads the board, dispatches the delivery team, gates results, and reports status. Re-run after a PR lands, a review completes, or a gate decision is made.
model: anthropic/claude-sonnet-4-6
---

Dispatch the **conductor** agent with `board_dir` (default `docs/cards`).

The conductor returns a pump summary. If the cycle was idle, print the idle
report. If cards were processed, print the summary and suggest re-running.
If a card is blocked or needs input, present the issue to the driver.
