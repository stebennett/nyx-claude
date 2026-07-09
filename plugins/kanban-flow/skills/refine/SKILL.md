---
name: refine
description: Use to populate or re-slice a project's backlog. Reads the project spec (`spec_path` from `config.md`) and proposes decomposed, ordered cards (type, acceptance criteria, depends_on) for approval into docs/cards/. Intake only — never starts implementation.
---

# Refine — backlog intake

Turn the spec into a backlog of right-sized cards. You propose; the driver approves; only then do cards land on disk. **Never** start plan/design/implementation work here — that is `/kanban`'s job.

## Steps

1. **Read context.** Read `{board_dir}/config.md` for `spec_path` and `layers` first. Read the spec at `spec_path`, any referenced material it points to, `{board_dir}/KNOWLEDGE.md`, and `{board_dir}/card-template.md`. Read every existing `docs/cards/CARD-*/card.md` so you don't duplicate or renumber over existing cards.

2. **Determine the next card number.** Scan existing `CARD-NNN-*` directory names; the next id is `max + 1`, zero-padded to three digits. If none exist, start at `CARD-001`.

3. **Slice the work vertically**, respecting `config.layers`' order. Each card must be independently shippable and testable. Prefer a thin vertical slice over a horizontal layer. Apply YAGNI — propose only what the spec requires.

4. **Classify each card** as `feature` (new user-facing capability), `task` (internal/scaffolding/refactor with no direct user value), or `defect` (fixing broken behaviour).

5. **Annotate the `layer`** — the card's primary architectural layer, taken from the spec's layering order. Use one of the values in `config.layers`; `/kanban` orders ready cards by their position in that list, instead of inferring the layer from the title. Tag a thin vertical slice by the *lowest* layer where it does substantive work (e.g. a card adding a domain rule plus the API endpoint that exposes it is `domain`).

6. **Set `depends_on`** to the card ids that must be `done` first (e.g. an `api` card depends on its `domain` and `db` cards). Keep the graph acyclic.

7. **Write acceptance criteria** as observable, testable bullets drawn from the spec (cite the specific spec section each criterion enforces).

8. **Group cards into ordered milestones.** A *milestone* (distinct from a card's workflow *phase* slice→deliver) is a delivery increment — a coherent set of cards that together ship a capability. Assign **every** card (proposed plus existing) to **exactly one** milestone, and order the milestones by delivery sequence (`M1` ships before `M2`). Give each a short title, a one-line capability **Goal**, and an observable **Exit criteria**. `/kanban` reads this to prefer the earliest incomplete milestone when choosing the next ready card. **Validate before proposing:** (a) *coverage* — every card belongs to exactly one milestone, none orphaned, none in two; (b) *dependency consistency* — no card may `depends_on` a card in a **later** milestone (same or earlier is fine). Report any violation and rework the grouping (or the card's milestone) until both hold.

9. **Present the proposal** to the driver: the **card table** (id, type, layer, title, depends_on, one-line why, 2–4 acceptance criteria each) **and** the **milestone plan** (ordered `M1…Mn` with title, goal, and member ids). Ask for approval, edits, or removals; iterate the cards and milestones together until approved.

10. **On approval, write the cards and the milestone plan.** For each approved card, create `docs/cards/CARD-NNN-slug/card.md` from the `card-template.md` template — resolved as `config.md`'s `template_overrides["card-template.md"]` if set, else `${CLAUDE_PLUGIN_ROOT}/templates/card-template.md` with `status: backlog`, `phase: backlog`, the chosen `layer`, empty `branch`/`worktree`, `reworks: 0`, and today's date (slug = short kebab-case of the title). Set `right_sized: true` when the card is **obviously atomic** (a single small change you cannot imagine splitting — this lets `/kanban` skip its slice check entirely); otherwise `right_sized: ""` and the slice phase decides. Then create/update `docs/cards/MILESTONES.md` in its documented format — one `## M<N> — <title>` heading per milestone (in order), each with `**Goal:**`, `**Exit criteria:**`, and a `**Cards:**` line listing its member ids. When re-slicing an existing backlog, place new cards into the right milestone and keep the step-8 invariants holding across the whole set.

11. **Tell the driver to run `/kanban`** to render the board and begin scheduling. Do not modify `BOARD.md` yourself — `/kanban` renders it.

## Rules
- Intake only. No branches, no worktrees, no code.
- Aim for right-sized cards, but you are the *coarse* slicer: `/kanban` runs a per-card `slice` check at pickup (the `card-slicer` agent) and splits anything still too big, so don't agonise over perfect atomicity here. Mark only the obviously-atomic cards `right_sized: true` (skips that check); everything else stays `right_sized: ""` and the slice phase decides.
- One card = one `card.md`. Never bundle multiple cards into one file.
- Do not edit `BOARD.md` or `KNOWLEDGE.md`.
- `/refine` is the **sole writer** of `MILESTONES.md`; milestone membership lives there, not on cards. `/kanban` reads it but never edits it.
