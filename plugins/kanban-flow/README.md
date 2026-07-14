# kanban-flow

A Claude Code plugin: an autonomous, card-driven kanban development system.

## Install

Add this repo as a plugin marketplace, then install `kanban-flow`.

## Use

1. In your project, run `/kanban-init` to scaffold `docs/cards/` (board, templates, config).
2. Edit `docs/cards/config.md` — set `spec_path`, adjust `layers`, set `gh_command` if you use a bot identity.
3. Run `/refine` to populate the backlog from your spec.
4. Run `/kanban` to drive cards through the board (safe under `/loop`).
5. When a new requirement lands mid-project, run `/requirement` — it interviews you, writes the requirement to your spec with a stable `REQ-NNN` id, slices it into cards, and reports what it invalidates on the board. Then run `/kanban` to apply it.

## Contents

- **Skills:** `kanban` (orchestrator), `refine` (whole-backlog intake), `requirement` (add/amend/supersede a single requirement on a running project), `req-ids` (sole authority for REQ ids in the spec), `retro` (process improvement), `adr` (ADR persistence), `kanban-init` (project scaffolder), `migrate` (one-time upgrade of an existing repo to plugin-owned doctrine).
- **Agents — producers:** `card-slicer`, `card-designer`, `card-implementer`, `card-deliverer`.
- **Agents — checkers:** `card-intake-checker`, `card-slice-checker`, `card-design-checker`, `card-deliver-checker`, plus `card-tester` and the `card-lens-reviewer` panel (together, the implementer's checkers). **Checkers are terminal — nothing checks a checker.** That is what stops the regress; the human is their backstop, at the intake and slice gates and at the two PR merges.
- **Templates:** the plugin-owned doctrine (`AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `CHECK-CRITERIA.md`, `INTAKE.md` — the card doctrine shared by `refine` and `requirement` — and the card/PR templates) that agents read **live from the plugin** — never copied into your repo, so a plugin update reaches every project. `/kanban-init` copies only `config.md`, an empty `PROTOCOL-ADDENDUM.md` (where `/retro` layers project-specific doctrine), and empty board starters.

## Every agent is checked

Each agent that **produces** something has a **checker** that verifies it, and checkers are
**terminal** — nothing checks a checker. Checkers write nothing and mutate nothing; they return a
verdict, and the orchestrator persists it and runs the rework loop.

What makes a check more than a rubber stamp: criteria live in the plugin's `CHECK-CRITERIA.md` with
**stable ids**, a checker must return a verdict for **every** criterion with an evidence citation,
and **a finding that cannot point at a line is invalid and gets dropped**. `/retro` aggregates
verdicts by id — a criterion that never fires gets pruned, and one that fires constantly means the
**producer** is wrong and *its* prompt gets fixed, not the check.

Blocking findings automatically rework the producer, against a per-producer budget
(`check_budget` in `config.md`). Checks are on by default; `checks` can turn one off if it proves
noisy, and `/kanban` then warns loudly, every pump, about what is shipping unchecked.

### The size budget

`size_limit` (default **500** changed lines, **including tests**; only lock files and vendored deps
are excluded via `size_exclude`) is the hard ceiling on a card, enforced twice:

- **`SLC-SIZE`, at slice — blocking.** `card-slice-checker` independently estimates the card's size
  from the codebase before any code is written. Over the limit **forces a split**, however atomic the
  card felt. This makes `size_limit` the real ceiling on card size, tighter than any "is this a
  vertical slice?" judgement call.
- **`DLV-SIZE`, at deliver — advisory, escalated.** `card-deliver-checker` measures the real diff. A
  breach cannot block (the code is written), but it **must propose a concrete split into smaller
  PRs**, which `/kanban` surfaces for you to act on.

A `DLV-SIZE` breach is, by definition, an `SLC-SIZE` estimate that was wrong — so every card records
`estimated_lines` and `actual_lines`, and `/retro` reads the delta to catch a slicer that
systematically under-estimates.

### Review happens before the PR

The lens panel (`card-lens-reviewer`, one agent per lens, in parallel) reviews the branch diff at the
**review** phase, in the worktree, **before any PR opens** — and blocking findings automatically
rework the implementer. The PR you open has already survived every lens.

No agent comments on a PR. `card-deliverer` is the only one that touches GitHub at all, and only to
push the branch and open the PR. On the PR you review normally: signal review-complete (submit a
review, or comment `REVIEWED`), and every comment you wrote gets addressed and answered with a commit
link. A healthy card needs exactly three actions from you: merge the design PR, complete a review,
merge the implementation PR.

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
