---
name: adr
description: Persist Architecture Decision Records (Cognitect lightweight format) into docs/adrs and link them to the kanban card that produced them. Invoked ONLY by the /kanban orchestrator when a phase agent's result carries proposed_adrs. The single authority for ADR format, numbering, supersede handling, the index, and the bidirectional card link. Phase agents never invoke this — they only propose. Run under Opus (as /kanban).
---

# adr — write an Architecture Decision Record

You are invoked by the `/kanban` orchestrator while it processes a phase agent's
`result` that carries one or more `proposed_adrs`. You hold the **sole-writer**
authority for everything under `docs/adrs/`. Phase agents only *propose* ADRs (they
cannot write files); you persist them and link them to the card.

ADRs use the Cognitect lightweight format
(<https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions>):
**Title · Context · Decision · Status · Consequences**.

## When you run

The orchestrator invokes you once it has decided a proposal is safe to write. **Writing
is not free: you reserve a number the moment you write**, so an ADR written for work that
is then reworked burns a number on a decision that gets made again. The routing points
follow from that:

- **design** phase → **when `card-design-checker` returns `verdict: pass`** (or when
  `checks.design` is `off`). That is **before** the design gate and before the design PR
  opens — *not* at the gate, and *not* on a driver `approve`: under the default
  `design: pr` gate policy there is no driver approve at all, because the design PR **is**
  the review. `DSG-ADR-NEEDED` blocks on an ADR that duplicates or contradicts a standing
  one, so the orchestrator holds the designer's proposals unwritten until that check
  clears; a `verdict: fail` routes nothing, and the reworked `design.md` brings its own
  proposals which replace the old ones wholesale.
  The proposals the orchestrator hands you are read from **`design.md`'s `## Proposed ADRs`
  section on disk** (the designer is required to write them there), never from a result
  block held in memory — a pump can end inside the checker's dispatch, and only disk
  survives it. Because that read can therefore happen twice, **routing is idempotent**: the
  orchestrator passes you only the proposals the card's `adrs:` list does not already
  account for, and if it passes you none, there is nothing to write.
- **implement / test / review** phases → when that phase's `result` is processed (the same
  point the phase doc is persisted). There is no checker holding these back.

(There is no `plan` phase. It was folded into `design`.)

You always receive: the `card_id` (e.g. `CARD-015`), the today's date (ISO), and the
list of `proposed_adrs`, each shaped:

```yaml
- title: "Persist Score Differential per round"
  context: "…the forces at play…"
  decision: "…what we decided…"
  consequences: "…what becomes easier/harder…"
  supersedes: []        # optional; ADR ids this one replaces, e.g. [ADR-0003]
```

## What an ADR is for

Only **significant** architecture or technology decisions: a framework or library
choice, a data-model invariant, a cross-cutting pattern, a notable trade-off — anything
that changes the shape of the system or is expensive to reverse. Small conventions go
to `KNOWLEDGE.md ## Conventions`; traps go to `## Gotchas`. If a proposal is really a
minor convention, route it to KNOWLEDGE instead of minting an ADR.

## Storage layout

ADRs are stored in `docs/adrs/` (`adr_dir` in `config.md`, default `docs/adrs/`):

```
docs/adrs/
  README.md            # index table — you maintain it
  template.md          # canonical skeleton (reference; do not edit per-ADR)
  NNNN-<kebab-title>.md # one file per ADR
```

## Procedure — for each proposed ADR (apply serially, in order)

1. **Allocate the number.** `NNNN = max(ADR numbers) + 1`, zero-padded to 4 digits.
   Because ADR files now land via card **branches** (they merge to `main` through the
   card's design or implementation PR), the max is taken across **both** registers:
   the `NNNN-*.md` files under `docs/adrs/` on `main` **and** every id listed in any
   card's `adrs:` frontmatter (card.md updates go straight to `main`, so an id there
   reserves a number whose file is still in flight on a branch). `/kanban` processes
   results serially, so no further locking is needed.
2. **Write `docs/adrs/NNNN-<kebab-title>.md`** — under the **card's worktree** passed
   by the orchestrator (the file rides the card's open PR; design-phase ADRs ride the
   design PR, which is the point) — from `template.md`, filling:
   - frontmatter: `id: ADR-NNNN`, `title`, `status: Accepted`, `date: <today ISO>`,
     `card: <card_id>`, `supersedes: [<ids or empty>]`, `superseded_by: ""`.
   - body: `# ADR-NNNN: <title>`, then `## Context`, `## Decision`,
     `## Status` (`Accepted`), `## Consequences` from the proposal.
   - `<kebab-title>` = the title lower-cased, non-alphanumerics → single hyphens.
3. **Handle supersede.** For each id in `supersedes`: copy that ADR file from `main`
   into the worktree if not present, set its frontmatter `status: Superseded` and
   `superseded_by: ADR-NNNN`, and update its `## Status` body line to
   `Superseded by ADR-NNNN`. Update its index row too.
4. **Update the index** (`docs/adrs/README.md` — in the worktree, based on `main`'s
   current copy): append (or refresh) one table row
   `| [ADR-NNNN](NNNN-<kebab-title>.md) | <title> | <status> | <card_id> | <date> |`,
   keeping rows in ascending ADR order.
5. **Bidirectional link.** Append `ADR-NNNN` to the producing card's `card.md`
   `adrs:` frontmatter list (create the list entry if empty). This is the one
   `card.md` write you (as /kanban, the sole writer) perform here — it goes **direct
   to `main`** with the pump's state commit, reserving the number while the ADR file
   travels via the PR.

Worktree writes ride the card branch's next `docs(card)` commit; the `card.md` link
rides the pump's `chore(kanban): …` commit on `main` — no separate commits.

## Rules

- ADRs are **immutable** once `Accepted`. Never edit an accepted ADR's Context /
  Decision / Consequences. A reversal is a **new** ADR that `supersedes` the old one;
  only the old one's status fields change.
- `status` is exactly one of `Accepted | Superseded | Deprecated`. Use `Deprecated`
  for a decision dropped without a replacement.
- Every ADR MUST carry a `card:` link. ADRs are only minted through the card lifecycle.
- You never invent decisions — you only persist what a phase agent proposed.
