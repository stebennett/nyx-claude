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
- **Templates:** the plugin-owned doctrine (`AGENT-PROTOCOL.md`, `lenses/` — shared etiquette/method plus one file per review lens — `checks/`, `INTAKE.md` — the card doctrine shared by `refine` and `requirement` — and the card/PR templates) that agents read **live from the plugin** — never copied into your repo, so a plugin update reaches every project. `/kanban-init` copies only `config.md`, an empty `PROTOCOL-ADDENDUM.md` (where `/retro` layers project-specific doctrine), and empty board starters.

## Every agent is checked

Each producing agent has a **checker** that verifies it, and checkers are **terminal** — nothing
checks a checker; the human is their backstop. Checkers write and mutate nothing; they return a
verdict the orchestrator persists and reworks against.

The doctrine — stable criterion ids, one cited verdict per criterion, findings that can't point at a
line dropped, `/retro` pruning/escalating by id — lives at **`templates/checks/`** (rationale in
**`RATIONALE.md`**). Blocking findings rework the producer against a per-producer `check_budget`;
`checks` can turn one off, and `/kanban` then warns every pump about what ships unchecked.

### The size budget

`size_limit` (default **500** changed lines including tests; exclusions via `size_exclude`) is the
hard ceiling, enforced at slice (`SLC-SIZE`, blocking — **forces a split**) and deliver (`DLV-SIZE`,
advisory — **proposes a split**). Details in **`templates/checks/`**; the intake path, where a
`right_sized` card is sized once, is in **`INTAKE.md` `## Check`**. Every card records
`estimated_lines` and `actual_lines` so `/retro` catches a systematic under-estimator.

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
