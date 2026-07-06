# kanban-flow

A Claude Code plugin: an autonomous, card-driven kanban development system.

## Install

Add this repo as a plugin marketplace, then install `kanban-flow`.

## Use

1. In your project, run `/kanban-init` to scaffold `docs/cards/` (board, templates, config).
2. Edit `docs/cards/config.md` — set `spec_path`, adjust `layers`, set `gh_command` if you use a bot identity.
3. Run `/refine` to populate the backlog from your spec.
4. Run `/kanban` to drive cards through the board (safe under `/loop`).

## Contents

- **Skills:** `kanban` (orchestrator), `refine` (backlog intake), `retro` (process improvement), `adr` (ADR persistence), `kanban-init` (project scaffolder).
- **Agents:** `card-slicer`, `card-designer`, `card-implementer`, `card-tester`, `card-reviewer`, `card-deliverer`, `pr-expert-reviewer`.
- **Templates:** the doctrine (`AGENT-PROTOCOL.md`), review lenses, card/PR templates, `config.md`, and empty board starters that `/kanban-init` copies into your repo.
