---
name: refine
description: Use to populate or re-slice a project's backlog. Backfills REQ ids into the spec via req-ids, then proposes decomposed, ordered cards (type, layer, reqs, acceptance criteria, depends_on) and a milestone plan for approval into docs/cards/. Intake only — never starts implementation. Run under Opus.
---

# Refine — backlog intake

Turn the whole spec into a backlog of right-sized cards. You propose; the driver
approves; only then do cards land on disk. **Never** start slice/design/implementation
work here — that is `/kanban`'s job.

You are one of the two **intake** skills. `/requirement` is the other: it handles a
*single* new or changed requirement. You both follow the same card doctrine and share
ownership of `MILESTONES.md`.

## Steps

1. **Read context.** Read `{board_dir}/config.md` first (`spec_path`, `layers`,
   `board_dir`). Then read:
   - the plugin's card doctrine at `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md` — **the
     rules for everything below**: card numbering, vertical slicing, `type`, `layer`,
     `reqs`, acceptance criteria, `depends_on`, `right_sized`, and the milestone
     invariants. Follow it exactly; it is not duplicated here.
   - the spec at `spec_path`, plus any material it references;
   - `{board_dir}/KNOWLEDGE.md`;
   - every existing `docs/cards/CARD-*/card.md`, so you neither duplicate nor renumber
     over an existing card;
   - `{board_dir}/MILESTONES.md`;
   - the card template — `config.md`'s `template_overrides["card-template.md"]` if set,
     else `${CLAUDE_PLUGIN_ROOT}/templates/card-template.md`.

2. **Ensure the spec has REQ ids.** Invoke the **`req-ids`** skill's **`backfill`**
   operation on `spec_path`. On an un-id'd spec it proposes an id'd version for the
   driver's approval; on an already-id'd spec it is a silent no-op. Do this **before
   slicing** — every card you propose must cite REQ ids, so the ids have to exist first.
   Never assign REQ ids yourself; `req-ids` is their sole authority.

3. **Slice the spec into cards**, following `INTAKE.md`. Respect `config.layers`' order.

4. **Group the cards into ordered milestones**, following `INTAKE.md`'s milestone rules.
   Assign **every** card — proposed and existing — to exactly one milestone, and validate
   both invariants (coverage; no card depends on a card in a later milestone) before you
   present anything.

5. **Check the proposal before showing it to anyone.** Unless `config.md`'s `checks.intake` is `off`,
   dispatch **`card-intake-checker`** (opus) with: the proposed cards, the milestone plan, the
   existing board's cards and their milestones, the requirement(s) in scope, `spec_path`, and the
   doctrine paths (`${CLAUDE_PLUGIN_ROOT}/templates/AGENT-PROTOCOL.md`,
   `${CLAUDE_PLUGIN_ROOT}/templates/CHECK-CRITERIA.md`, `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md`,
   and `<board_dir>/PROTOCOL-ADDENDUM.md`).

   `verdict: fail` → **revise the proposal against the blocking findings and re-check**, up to
   `check_budget.intake` (default 2). Budget exhausted → present anyway, with the unresolved findings
   shown to the driver as open questions — never silently.

   `verdict: pass` → proceed. Show the driver the checker's advisory findings alongside the proposal.

   The driver's attention is the scarcest thing in this system: it should go on judgement, not on
   catching an unobservable acceptance criterion or a dependency cycle. That is what this step buys.

6. **Present the proposal** to the driver:
   - the **card table** — id, type, layer, title, `reqs`, `depends_on`, a one-line why,
     and 2–4 acceptance criteria each;
   - the **milestone plan** — ordered `M1…Mn` with title, goal, and member ids.

   Ask for approval, edits, or removals. Iterate the cards and milestones together until
   approved.

7. **On approval, write.** For each approved card, create
   `docs/cards/CARD-NNN-<slug>/card.md` from the card template with `status: backlog`,
   `phase: backlog`, the chosen `type`/`layer`/`reqs`/`depends_on`, empty
   `branch`/`worktree`, the template's all-zero **`reworks` map** (`{slice, design,
   implement, deliver}` — never the retired scalar `reworks: 0`), empty
   `estimated_lines`/`actual_lines`, `right_sized` per `INTAKE.md`, and today's date.
   Then create or update `{board_dir}/MILESTONES.md` in its documented format. When
   re-slicing an existing backlog, place new cards into the right milestone and keep both
   invariants holding across the whole set.

8. **Hand off.** Tell the driver to run `/kanban` to render the board and begin
   scheduling. Do not render `BOARD.md` yourself.

## Rules

- **Intake only.** No branches, no worktrees, no code.
- **Your only spec write is `req-ids`' backfill.** You never author, reword, or delete
  requirement content — that is `/requirement`'s job. You add ids to prose that already
  exists, nothing more.
- Card doctrine lives in `INTAKE.md`, not here. If a rule about slicing, typing, layering,
  `reqs`, `depends_on`, `right_sized`, or milestones seems to be missing, it is in
  `INTAKE.md` — read it, don't invent it.
- You may only create and edit cards in `status: backlog`. A card beyond backlog belongs
  to `/kanban`. If the backlog you are re-slicing collides with an in-flight card, say so
  and stop — `/requirement` is the skill that can act on it, via the amendment queue.
- Do not edit `BOARD.md` or `KNOWLEDGE.md`.
- You share `MILESTONES.md` with `/requirement`. `/kanban` reads it but never writes it.
