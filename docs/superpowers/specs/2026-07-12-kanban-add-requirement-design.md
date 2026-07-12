# `/requirement` — add, amend, and supersede requirements in kanban-flow

**Date:** 2026-07-12
**Plugin:** `plugins/kanban-flow`
**Status:** approved design

## Problem

`kanban-flow` reads a project spec (`spec_path`, conventionally `docs/spec.md`) and
`/refine` slices it into backlog cards. The spec itself is entirely hand-authored —
no skill writes to it. There is therefore no supported way to add a new requirement
to a running project: the user hand-edits the spec, then re-runs `/refine` and hopes
the delta comes out right. Nothing detects that a new requirement contradicts an
existing one, or invalidates a card already in flight.

## Goal

A single skill, `/requirement`, that takes a rough one-liner, interviews the user
into a well-formed requirement, writes it into the spec, slices it into cards, and
reports and applies its impact on work already on the board — in one pass.

## Non-goals

- Re-implementing `/refine`. `/refine` remains the whole-backlog intake skill.
- Editing cards that are in flight or done. See "Ownership boundary" below.
- A re-slice path for a card that already has code on its branch. That case is a
  human decision (`revisit`), not an automated transform.

## Constraint that shapes everything: the sole-writer invariant

`/kanban` declares itself the **sole writer** of `BOARD.md`, `KNOWLEDGE.md`, and
every `card.md` after intake. That rule is what makes the board safe to drive
unattended (`/kanban` is explicitly designed to run under `/loop`). A card in flight
also owns a git branch, a worktree, and possibly an open PR, so "cancel this card"
is a teardown operation, not a file edit.

`/requirement` therefore does **not** become a second writer of `card.md`. It takes
the intake authority `/refine` already has, and hands everything else to `/kanban`
through an explicit queue.

## Ownership boundary

Each existing card is classified by `status` alone:

| Card status | What `/requirement` does |
| --- | --- |
| `backlog` | Edits, re-slices, or deletes it **directly**. No branch, worktree, or PR exists — nothing to tear down. This is the authority `/refine` already exercises when re-slicing a backlog. |
| `slice`…`deliver`, `blocked` | **Never touches the file.** Appends an amendment record to `docs/cards/AMENDMENTS.md`, which `/kanban` drains on its next pump. |
| `done` | Never amended, never superseded — it shipped. A new requirement that contradicts shipped behaviour produces a **new card** (usually `defect` or `feature`), which falls out of normal slicing. |
| `split` | Terminal; ignored. |

## Command surface

```
/requirement [rough one-liner]
```

The argument is optional; with none, the skill asks what the user wants to add.
The skill's description carries the **"Run under Opus"** note that `/kanban` and
`/adr` already use — elicitation and impact analysis are the judgement-heavy work
in this plugin. (Skills take no `model` frontmatter field; the description is where
this convention lives.)

### Flow

1. **Load context** — `{board_dir}/config.md` (for `spec_path`, `layers`,
   `board_dir`), the spec, `MILESTONES.md`, every `docs/cards/CARD-*/card.md`,
   `KNOWLEDGE.md`, and the plugin's `INTAKE.md` doctrine.
2. **Ensure the spec is id'd** — invoke `req-ids` (below). If the spec has no
   `REQ-NNN` headings it backfills them; otherwise it is a no-op.
3. **Elicit** — interview the user **one question at a time**: the intent and who
   it serves, what is explicitly out of scope, edge cases, and the observable
   criteria that would prove it done. Stop as soon as the requirement is testable —
   not after a fixed number of questions.
4. **Analyse impact** — determine whether the requirement is new, amends an existing
   `REQ`, or supersedes one. Find every card affected, via the `reqs` frontmatter
   field, and classify each by the ownership boundary above.
5. **Propose once** — a single approval surface covering: the new or changed `REQ`
   text exactly as it will appear in the spec; any supersede links; new cards (id,
   type, layer, title, `depends_on`, `reqs`, acceptance criteria); edits and
   deletions to backlog cards; milestone placement; and the amendment records to be
   queued, with the action chosen for each.
6. **On approval, write and commit** — persist the requirement into the spec via
   `req-ids` (which allocates the id and writes any supersede markers), then write
   the cards, `MILESTONES.md`, and `AMENDMENTS.md`, as one Conventional Commit
   (`chore(kanban): add REQ-NNN — …`). Then tell the driver to run `/kanban` to
   drain the queue and schedule.

## The `req-ids` skill — sole authority for REQ identity

Both intake skills need requirement ids, so id-ing is **externalised into its own
skill** rather than duplicated. `req-ids` is the single authority for the `REQ`
format, numbering, and supersede handling — exactly as the existing `adr` skill is
the single authority for ADR format, numbering, supersede handling, and its index.
The parallel is deliberate: callers compose requirement *prose*; `req-ids` persists
it with correct identity.

It is invoked by `/refine` and `/requirement`, and may also be run directly. It
carries the same **"Run under Opus"** note — deciding what constitutes a discrete
requirement in existing prose is judgement, not string manipulation.

Three operations:

- **backfill** — scan `spec_path`. If requirements are unnumbered, propose an id'd
  version as a diff for approval and write it on approval. **Idempotent**: a no-op
  on an already-id'd spec. This is what `/refine` calls on its first pass, and what
  `/requirement` calls before it does anything else.
- **allocate** — given requirement prose and its placement, insert it under the next
  free id with `**Status:** active`, and return the id to the caller.
- **supersede** — mark `REQ-A` as `**Status:** superseded by REQ-B`. Never deletes.

Consequence worth stating plainly: **`/refine` gains the ability to write to
`spec_path`**, which it could not do before. That write is confined to backfilling
ids onto existing prose — `/refine` never authors or changes requirement content.

## Spec format

Owned by `req-ids`. Requirements become addressable headings in `spec_path`:

```markdown
## Boards

### REQ-012 — Export a board to CSV
**Status:** active

Users with read access can export a board to CSV...
```

- Ids are `REQ-NNN`, zero-padded to three digits, numbered `max + 1` across the spec.
- A superseded requirement is **never deleted**. It stays in place with
  `**Status:** superseded by REQ-019`, so history survives and cards that cited it
  still resolve.
- `**Status:**` is `active` or `superseded by REQ-NNN`.

## Card ↔ requirement link

Cards gain a frontmatter field:

```yaml
reqs: []              # REQ ids this card implements, e.g. [REQ-012]
```

This makes impact analysis a lookup rather than an inference over prose. Acceptance
criteria continue to cite the requirement in their text as they do today; `reqs` is
the machine-readable index over the same fact.

A card written before this field simply has no `reqs`, which reads as **unknown** —
so no migration is forced, and `/requirement` surfaces such cards to the driver as
"impact undetermined" rather than silently assuming they are unaffected.

## The amendment queue

`docs/cards/AMENDMENTS.md` is a queue written by `/requirement` and drained by
`/kanban`. A **missing file means an empty queue**, so no existing board needs a
migration.

One block per pending amendment:

```markdown
## CARD-007 — supersede
**Raised:** 2026-07-12 by /requirement
**Reason:** REQ-004 superseded by REQ-012 — export moves from CSV to XLSX.
**Action:** supersede
```

Exactly two actions:

- **`supersede`** — the card is dead. `/kanban` tears down its worktree and branch,
  closes any open PR (design or implementation) with a comment pointing at the new
  `REQ`, and sets `status: superseded` / `phase: superseded`. Terminal.
- **`revisit`** — the card is still wanted, but its scope moved. `/kanban` sets
  `status: blocked` with a blocker naming the `REQ`. This reuses machinery that
  already exists: `/kanban`'s blocked-card conversation already offers the driver
  re-dispatch-with-guidance, edit, or park.

`/kanban` removes each block once applied.

## Changes to `/kanban`

Small and contained:

1. **Reconcile (Section 0)** — a new step that drains `AMENDMENTS.md`: for each
   block, apply the action above, then delete the block. Report what was applied in
   the pump digest.
2. **Render (Section 2)** — a new terminal `## Superseded` column, mirroring the
   existing `## Split` column. `superseded` cards are not in-flight and hold no WIP
   slot.
3. **Rules** — the sole-writer sentence becomes: *"`/refine` and `/requirement`
   create and edit backlog cards; thereafter `/kanban` is the sole writer of
   `BOARD.md`, `KNOWLEDGE.md`, and every `card.md`."*

## Shared intake doctrine (`templates/INTAKE.md`)

`/refine` and `/requirement` both turn requirements into cards. Two copies of those
rules would drift, so they move into a new **plugin-owned doctrine file read live**,
in the same pattern as `AGENT-PROTOCOL.md` and `REVIEW-LENSES.md` (never copied into
the consuming repo).

`INTAKE.md` holds the **card** doctrine only — REQ identity belongs to `req-ids`:

- vertical slicing — each card independently shippable and testable, YAGNI applied;
- `type` classification (`feature` | `task` | `defect`);
- `layer` annotation from `config.layers`, tagging a vertical slice by the *lowest*
  layer where it does substantive work;
- `depends_on`, kept acyclic;
- acceptance criteria as observable, testable bullets citing the `REQ` they enforce;
- `reqs` population;
- `right_sized` — `true` only when obviously atomic;
- milestone invariants — every card in exactly one milestone; no card `depends_on`
  a card in a **later** milestone.

`/refine` keeps what is genuinely its own: backfilling ids via `req-ids` on its first
pass, reading the whole spec, proposing the *entire* backlog, and owning its approval
loop. It delegates the card rules above to `INTAKE.md`. `/requirement` applies the
same rules **scoped to one requirement**.

`MILESTONES.md` ownership becomes **shared between the two intake skills** —
previously `/refine` alone. `/kanban` still never writes it, except for the existing
mechanical parent→children swap on an applied split.

## Files

**New**

- `plugins/kanban-flow/skills/requirement/SKILL.md`
- `plugins/kanban-flow/skills/req-ids/SKILL.md`
- `plugins/kanban-flow/templates/INTAKE.md`

**Edited**

- `plugins/kanban-flow/skills/refine/SKILL.md` — invoke `req-ids` on the first pass;
  delegate slicing rules to `INTAKE.md`; populate `reqs`.
- `plugins/kanban-flow/skills/kanban/SKILL.md` — drain `AMENDMENTS.md`; render the
  `Superseded` column; update the sole-writer rule.
- `plugins/kanban-flow/templates/card-template.md` — add `reqs: []`; add
  `superseded` to the `status` enum.
- `plugins/kanban-flow/README.md` — document `/requirement`.
- `plugins/kanban-flow/.claude-plugin/plugin.json` — version → `0.3.0`.

**Deliberately untouched**

- `skills/migrate/SKILL.md` — nothing needs a cutover. A missing `AMENDMENTS.md`
  reads as an empty queue; a missing `reqs` reads as unknown.
- `skills/kanban-init/SKILL.md` — `AMENDMENTS.md` is created lazily on first use,
  so the scaffold does not change.

## Validation

This repo has no test runner, and plugin components are Markdown. Validation is by
installing the plugin and exercising it against a scratch repo, recording the actual
results rather than asserting success:

1. **New requirement** — `/requirement` on a fresh REQ produces the spec entry and
   correctly sliced cards, and `/kanban` schedules them.
2. **Supersede affecting a backlog card** — the backlog card is edited or deleted
   in place; no amendment is queued.
3. **Supersede affecting an in-flight card** — the card file is untouched, an
   amendment is queued, and the next `/kanban` pump tears down the worktree and
   branch, closes the PR, and lands the card in `Superseded`.
4. **`revisit`** — the card reaches `blocked` with the `REQ` named in the blocker,
   and `/kanban`'s blocked-card conversation offers the usual choices.
5. **Un-id'd spec, via `/requirement`** — `req-ids` backfill is offered, applied on
   approval, and is a no-op on the second run.
6. **Un-id'd spec, via `/refine`** — the first `/refine` pass backfills ids through
   the same `req-ids` skill, and the cards it proposes cite those ids in `reqs`.
   Running `/refine` again re-ids nothing.
