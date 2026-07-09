# kanban-flow — plugin-owned doctrine + one-time repo migration

**Date:** 2026-07-08
**Plugin:** `plugins/kanban-flow`
**Status:** Approved design, ready for implementation planning

## Problem

`/kanban-init` scaffolds a repo by **copying** the plugin's doctrine and templates
into the repo's `board_dir` (`docs/cards/`): `AGENT-PROTOCOL.md`,
`REVIEW-LENSES.md`, `card-template.md`, `pr-template.md`, `design-pr-template.md`,
and `config.md`. The phase agents read the **repo's copies** at runtime (every
agent begins `First read docs/cards/AGENT-PROTOCOL.md`). The plugin's own
skills/agents auto-update when the user updates the plugin — but these copied
files never do. So a doctrine change like PR #3's `AGENT-PROTOCOL.md` rewrite
reaches **zero** existing repos.

`AGENT-PROTOCOL.md` calls itself "the shared contract between the `/kanban`
orchestrator and the phase agents." A shared contract that silently forks per
repo is a defect. The copy-per-repo model exists mainly because `kanban-init`
copies the whole `templates/` folder in one gesture and the agents were written
to read `docs/cards/…` — not because the protocol is project-specific.

We fix the **root cause**: pure doctrine and templates become **plugin-owned**
(read live, so they track the installed version automatically); only genuinely
per-project files stay in the repo; project-specific doctrine tuning moves to a
new layered **addendum**; and a one-time `/migrate` skill brings existing repos
onto the new model without losing their local customizations.

## Approach

**Direction B — stop copying pure doctrine; fix the root cause** (chosen over
Direction A, "build a per-release reconciler for the copies," which treats the
symptom and lets drift return every release).

Feasibility: `${CLAUDE_PLUGIN_ROOT}` resolves in the skill/orchestrator context
(`kanban-init` already uses it in Bash), and a dispatched agent can `Read` an
absolute path into the plugin cache. So the orchestrator injects the live
doctrine path into each dispatch; agents read it there. No dependency on
subagents inheriting environment variables.

## Design

### 1. Ownership split

**Plugin-owned** — read live from `${CLAUDE_PLUGIN_ROOT}/templates/`, tracks the
installed plugin version, never copied into a repo:
- `AGENT-PROTOCOL.md`
- `REVIEW-LENSES.md`
- `card-template.md`, `pr-template.md`, `design-pr-template.md`

**Repo-owned** — in `board_dir`:
- `config.md` — project tunables (unchanged role; gains a `kanban_flow_version`
  key).
- Board state — `BOARD.md`, `KNOWLEDGE.md`, `MILESTONES.md`, cards, ADRs
  (untouched by this change).
- **`PROTOCOL-ADDENDUM.md`** (new) — the layered home for project-specific
  doctrine. Empty stub at init.

### 2. Doctrine delivery (path injection)

The `/kanban` orchestrator resolves the live doctrine directory once per pump
(same mechanism `kanban-init` uses for `${CLAUDE_PLUGIN_ROOT}`) and includes, in
every phase-agent dispatch:
- the absolute path to the plugin's `AGENT-PROTOCOL.md`;
- the absolute path to the repo's `PROTOCOL-ADDENDUM.md`;
- for `pr-expert-reviewer` dispatches, additionally the absolute path to the
  plugin's `REVIEW-LENSES.md`.

**Read composition:** every agent reads the **plugin doctrine first, then the
`PROTOCOL-ADDENDUM.md`** — the addendum layers project-specific rules on top of
the shared contract. Lens reviewers read their plugin lens section plus the
addendum. Where a template is needed, the consumer reads the plugin template
unless the `template_overrides` config key (§5) points at a repo-local file.

### 3. Changes to existing components

- **`kanban-init`** — stop copying the five plugin-owned files. Scaffold only:
  `config.md`, board state (`board/*`), an empty `PROTOCOL-ADDENDUM.md` stub, and
  the ADR dir stub. Write `kanban_flow_version` (current plugin version) into
  `config.md`. Idempotency guard unchanged.
- **The 7 `card-*` / `pr-expert-reviewer` agents** — replace the hardcoded
  `First read docs/cards/AGENT-PROTOCOL.md` with: read the plugin
  `AGENT-PROTOCOL.md` at the absolute path in your dispatch, then the repo's
  `PROTOCOL-ADDENDUM.md` (if present). `pr-expert-reviewer` reads its lens brief
  from the injected plugin `REVIEW-LENSES.md` path.
- **`kanban` orchestrator** — resolve and inject the doctrine paths into every
  dispatch; repoint the `REVIEW-LENSES.md` reference (currently
  `docs/cards/REVIEW-LENSES.md`) to the plugin path; add the migration detection
  nudge (§5).
- **`retro`** — its process-lesson targets change. Project-specific lessons →
  append to `PROTOCOL-ADDENDUM.md`. Universal lessons → a **flagged plugin PR**
  (retro no longer edits repo doctrine/template/lens files inline). Its
  KNOWLEDGE.md / ADR routing is unchanged.

### 4. `/migrate` — one-time cutover skill

Idempotent, per-repo, read-only toward the plugin. Steps:

1. **Detect.** Read `config.md`'s `kanban_flow_version` vs the plugin's current
   version, and scan `board_dir` for leftover plugin-owned copies. If already
   current **and** no leftover copies → report "up to date," stop.
2. **Doctrine files** (`AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`) present in
   `board_dir`: diff the repo copy against the plugin's current version.
   - Identical → delete the copy (now redundant; agents read live).
   - Differs → the delta is local customization: fold it into
     `PROTOCOL-ADDENDUM.md` (semantic extraction of what the repo copy adds over
     the plugin version), present to the driver for approval, then delete the
     copy.
3. **Templates** (`card-template.md`, `pr-template.md`, `design-pr-template.md`)
   present in `board_dir`:
   - Identical → delete.
   - Differs → the repo shaped this template: **preserve it** by setting the
     `template_overrides` config key (§5) to point at the kept file. Do not fold
     into the addendum — a template is a fill-in artifact, not prose doctrine.
4. **`config.md`** — add any keys present in the current config template but
   missing in the repo (additive; never change existing values), and set
   `kanban_flow_version` to the current plugin version.
5. **Ship as a branch + PR** (mirrors `retro` — process changes get the same
   human review as code). The PR body lists every deletion, every folded
   customization (with the addendum text added), every preserved/overridden
   template, and the config keys added.

### 5. Version stamp, escape hatch, detection nudge

- **Version stamp:** a `kanban_flow_version` key in `config.md` (visible,
  hand-editable, no new file). Written by `kanban-init` and updated by
  `/migrate`. Sourced from the plugin's `plugin.json` `version`.
- **Template override (`template_overrides`):** a **built** config key mapping a
  template name to a repo-local override path; when set, the consumer reads the
  override instead of the plugin template. It is not hypothetical — `/migrate`
  uses it to preserve any template a repo already customized.
- **Detection nudge:** each pump, the orchestrator checks `board_dir` for
  leftover plugin-owned copies (or a `kanban_flow_version` behind the plugin). If
  found, it warns prominently: "un-migrated doctrine copies detected — run
  `/migrate`." This closes the one backward-compat gap: a repo that had
  *customized* its doctrine silently loses those edits' effect after a plugin
  update (the orchestrator now reads plugin doctrine, ignoring the leftover copy)
  until `/migrate` folds them into the addendum.

## Backward compatibility

The re-architecture is backward-compatible for correctness: because the new
orchestrator injects the plugin doctrine path, an un-migrated repo runs correctly
— its leftover copies simply become dead files, and the nudge prompts cleanup.
The only behavioural gap is a repo with **customized** doctrine, addressed by the
nudge + `/migrate`.

## Files changed

**P1 — re-architecture (must land first):**
- `skills/kanban-init/SKILL.md` — stop copying the five files; scaffold addendum
  stub + `kanban_flow_version`.
- `agents/card-slicer.md`, `card-designer.md`, `card-implementer.md`,
  `card-tester.md`, `card-reviewer.md`, `card-deliverer.md`,
  `pr-expert-reviewer.md` — doctrine read-path → injected plugin path + addendum.
- `skills/kanban/SKILL.md` — resolve/inject doctrine paths; repoint
  `REVIEW-LENSES.md`; detection nudge; `template_overrides` resolution.
- `skills/retro/SKILL.md` — reroute process-lesson targets (addendum + plugin PR).
- `templates/config.md` — document `kanban_flow_version` and `template_overrides`.
- `templates/PROTOCOL-ADDENDUM.md` (new) — the addendum stub kanban-init copies.

**P2 — `/migrate`:**
- `skills/migrate/SKILL.md` (new) — the one-time cutover. Skills are
  auto-discovered from `skills/`, so no `marketplace.json`/manifest edit is
  needed; verify discovery only.
- `README.md` — document `/migrate` and the plugin-owned-doctrine model.

## Out of scope

- No change to board state, cards, ADRs, or the card lifecycle.
- No per-release reconciler (that was Direction A, rejected).
- No automatic upstreaming of universal retro lessons — retro only *flags* a
  plugin PR for the human.
- Relocating `board_dir`/`adr_dir` remains the existing hardcoded-path caveat;
  not touched here.

## Success criteria

- A fresh `/kanban-init` creates no `AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, or
  template copies in the repo; agents read them live from the plugin.
- Updating the plugin changes every repo's effective doctrine on the next pump,
  with no per-repo action for uncustomized repos.
- `/migrate` on an old repo deletes redundant copies, folds any local doctrine
  edits into `PROTOCOL-ADDENDUM.md`, preserves any customized template via
  `template_overrides`, adds missing config keys, stamps the version, and ships a
  reviewable PR — and is a no-op on a second run.
- A repo with a `PROTOCOL-ADDENDUM.md` has its project-specific rules applied on
  top of plugin doctrine by every phase agent.
- The orchestrator nudges any un-migrated repo each pump until it is migrated.
