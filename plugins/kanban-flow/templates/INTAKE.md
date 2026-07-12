# Intake doctrine — turning requirements into cards

Read **live from the plugin** by `/refine` (whole-backlog intake) and `/requirement`
(single-requirement intake). Never copied into a project.

Requirement **identity** — REQ ids, spec headings, supersede markers — is **not** here.
That belongs to the `req-ids` skill. This file is about **cards**.

## Card numbering

`CARD-NNN`, zero-padded to three digits. The next id is `max + 1` across existing
`docs/cards/CARD-*` directories; start at `CARD-001` when there are none. Ids are never
reused and never renumbered. A card lives at `docs/cards/CARD-NNN-<slug>/card.md`, where
`<slug>` is a short kebab-case of the title.

## Slice vertically

Each card must be **independently shippable and testable**. Prefer a thin vertical slice
over a horizontal layer. Apply YAGNI — propose only what the requirement actually demands.

## Classify `type`

- `feature` — a new user-facing capability
- `task` — internal scaffolding or refactor, no direct user value
- `defect` — fixing broken behaviour, **including behaviour a changed requirement has
  made wrong**

## Annotate `layer`

One of `config.layers`. Tag a vertical slice by the **lowest** layer where it does
substantive work — a card adding a domain rule plus the API endpoint that exposes it is
`domain`. `/kanban` orders ready cards by position in that list, so this drives scheduling.

## Link `reqs`

Every card carries `reqs: [REQ-NNN, …]` — the requirement ids it implements. This is the
machine-readable index `/requirement` uses for impact analysis.

**An empty `reqs` means _unknown_, not _unaffected_.** Only cards written before this
field existed should be empty. Never propose a new card without at least one REQ id.

## Write acceptance criteria

Observable, testable bullets. Each cites the requirement it enforces:

```markdown
- [ ] Export produces one CSV row per card, with id, title, status and milestone (REQ-012)
- [ ] A user without read access on the board gets 403 (REQ-012)
```

## Set `depends_on`

The card ids that must be `done` before this card starts — an `api` card depends on its
`domain` and `db` cards. **Keep the graph acyclic.**

## Set `right_sized`

`true` **only** when the card is obviously atomic: a single small change you cannot
imagine splitting. `true` makes `/kanban` skip the slice phase entirely, so use it only
when you are sure. Otherwise leave it `""` and the slice phase decides.

You are the **coarse** slicer. `/kanban`'s `card-slicer` re-checks every non-right-sized
card at pickup and splits anything still too big — so do not agonise over perfect
atomicity here.

## Milestones

A milestone is a **delivery increment** — a coherent set of cards that together ship a
capability. (Distinct from a card's workflow *phase*, slice→deliver.) `MILESTONES.md`
holds one `## M<N> — <title>` heading per milestone **in delivery order**, each with
`**Goal:**` (one line), `**Exit criteria:**` (observable), and `**Cards:**` (member ids).

Two invariants, validated **before** you present a proposal:

1. **Coverage** — every card, new and existing, belongs to **exactly one** milestone.
   None orphaned, none in two.
2. **Dependency consistency** — no card may `depends_on` a card in a **later** milestone.
   Same or earlier is fine.

Report and fix any violation before presenting — rework the grouping or the card's
milestone until both hold.

`/refine` and `/requirement` are the only writers of `MILESTONES.md`. `/kanban` reads it
and never writes it, except for the mechanical parent→children swap on an applied split.

## Never

- Bundle multiple cards into one `card.md`. One card = one file.
- Write `BOARD.md` or `KNOWLEDGE.md` — `/kanban` is their sole writer.
- Touch a card that is **not** in `backlog`. A card beyond backlog owns a branch, a
  worktree and possibly an open PR; only `/kanban` may change it. `/requirement` reaches
  those cards through the amendment queue instead.
- Create branches or worktrees, or write code. Intake is intake.
