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

- **Skills:** `kanban` (orchestrator), `refine` (backlog intake), `retro` (process improvement), `adr` (ADR persistence), `kanban-init` (project scaffolder), `migrate` (one-time upgrade of an existing repo to plugin-owned doctrine).
- **Agents:** `card-slicer`, `card-designer`, `card-implementer`, `card-tester`, `card-reviewer`, `card-deliverer`, `pr-expert-reviewer`.
- **Templates:** the plugin-owned doctrine (`AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, and the card/PR templates) that agents read **live from the plugin** — never copied into your repo, so a plugin update reaches every project. `/kanban-init` copies only `config.md`, an empty `PROTOCOL-ADDENDUM.md` (where `/retro` layers project-specific doctrine), and empty board starters.

## Upgrading an existing repo

Doctrine and templates are **plugin-owned** and read live, so updating the plugin
updates every project automatically — no per-repo action for an uncustomized board.

A repo initialized by an **older** kanban-flow still has copies of the doctrine and
templates in its board dir; those copies are now ignored, and any local customization
in them stops taking effect. `/kanban` detects this and nudges you to run **`/migrate`**
— a one-time, idempotent cutover that deletes the redundant copies, folds any local
doctrine edits into `PROTOCOL-ADDENDUM.md`, preserves a customized template via
`template_overrides`, adds any new `config.md` keys, stamps `kanban_flow_version`, and
opens a PR for you to review and merge.
