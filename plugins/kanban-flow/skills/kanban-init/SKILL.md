---
name: kanban-init
description: Scaffold a repository for the kanban-flow system. Copies the doctrine, templates, config, and empty board starters into the target repo's board directory (default docs/cards/). Idempotent — never clobbers an existing board. Run once per project, before /refine.
---

# /kanban-init — scaffold a project for kanban-flow

Set up the current repository to use the kanban-flow system. You copy bundled
templates into the repo; you never modify the plugin.

## Steps

1. **Resolve the target.** `board_dir` defaults to `docs/cards`. If the user passed
   an argument, use it as `board_dir`. The plugin's templates live at
   `${CLAUDE_PLUGIN_ROOT}/templates/`.

2. **Idempotency guard.** If `<board_dir>/config.md` already exists, STOP: report
   that a board is already initialized here, show the existing `config.md` path, and
   do nothing destructive. Never overwrite an existing board, config, or cards.

3. **Scaffold.** Create `<board_dir>/` and copy from `${CLAUDE_PLUGIN_ROOT}/templates/`:
   - `config.md`, `AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `card-template.md`,
     `pr-template.md`, `design-pr-template.md` → `<board_dir>/`
   - `board/BOARD.md`, `board/KNOWLEDGE.md`, `board/MILESTONES.md` → `<board_dir>/`
   - Create the ADR directory (`adr_dir`, default `docs/adrs/`). Only if
     `<adr_dir>/README.md` does not already exist, create it as a stub containing
     an empty ADR index heading — a repo with pre-existing ADRs must not have its
     index clobbered.

4. **Report next steps.** Tell the user to:
   - Edit `<board_dir>/config.md` — set `spec_path` to their spec, adjust `layers`
     to their architecture, set `gate_layer`, set `gh_command` if they use a bot
     identity wrapper, and review `wip_limit`, `gates`, and `coverage_target` for
     their project.
   - Run `/refine` to populate the backlog, then `/kanban` to start driving cards.

## Rules

- Read-only toward the plugin; write only inside the target repo.
- Idempotent: safe to run again — it no-ops if `config.md` exists.
- Do not run `/refine` or `/kanban` yourself; just scaffold and hand off.
