# Validation record — `/requirement`, `req-ids`, `INTAKE.md`, `/kanban` amendments

**Date:** 2026-07-12
**Subject:** `plugins/kanban-flow` v0.3.0
**Scratch project:** `…/scratchpad/kanban-scratch` — a "Widget Tracker" spec, **no git**

## How this was run, and what that means

The plugin's skills are loaded into a Claude Code session at startup, so the newly
created `/requirement` and `req-ids` were **not invocable** in the session that wrote
them. The walkthrough therefore **executed each `SKILL.md` literally by hand** — one
person playing both the skill and the driver — rather than dispatching them through the
plugin loader.

That is a weaker test than a real invocation in two specific ways, and a stronger one in
one way:

- **Weaker:** it cannot prove the skills are *discovered* and *routed* correctly by
  Claude Code, and a hand-executor unconsciously resolves ambiguities that a cold model
  would trip over.
- **Weaker:** the scratch project has **no git**, so `supersede`'s teardown —
  `gh pr close`, worktree removal, branch deletion — **was not executed**. Card state was
  set to the post-teardown values directly. **Those three operations remain untested.**
- **Stronger:** reading the doctrine as an executor, line by line, is exactly what surfaces
  self-contradiction and missing steps — which is what it did. Five defects, below.

**Nothing here should be read as "the skills work."** It says the doctrine is followable
and internally consistent *after* the fixes below.

## Cases

| # | Case | Result |
|---|---|---|
| 0 | `/kanban-init` scaffold | **Pass** — `config.md`, `PROTOCOL-ADDENDUM.md`, `BOARD.md`, `KNOWLEDGE.md`, `MILESTONES.md`, `docs/adrs/README.md`. `INTAKE.md` correctly **not** copied (plugin-owned). Version stamped `0.3.0`. |
| 1 | `req-ids backfill` on an un-id'd spec | **Pass, after fixing defect C.** 4 requirements identified from prose; `## Overview` correctly left un-id'd as non-normative. |
| 2 | `backfill` idempotency | **Pass** (by inspection — step 2 short-circuits on `### REQ-NNN` headings and writes nothing). |
| 3 | `/refine` slices with `reqs` populated | **Pass** — 4 cards, each citing its REQ; both milestone invariants held. |
| 4 | `/requirement` supersede hitting a **backlog** card | **Pass** — dependent CARD-005 edited and rewired **directly**, no amendment queued. |
| 5 | `/requirement` supersede hitting an **in-flight** card | **Pass, after fixing defect D.** CARD-003 (`status: implement`, open PR) **not modified**; amendment queued instead. Dangling-dependency guard fired: CARD-005's `depends_on` was rewired from the doomed CARD-003 to its replacement CARD-006. |
| 6 | `/kanban` drains a `supersede` | **Partial** — `status: superseded`, `## Notes` reason appended, block deleted, `## Superseded` column rendered. **PR close, worktree teardown and branch deletion NOT executed (no git).** |
| 7 | `/kanban` drains a `revisit` | **Pass** — `status: blocked` with the REQ named; branch, worktree and PR left intact. `phase` correctly stayed at `implement` as the resume point. |

## Defects found and fixed

**A. `BOARD.md` starter had no `## Superseded` section.** Every other column exists in the
starter; `/kanban` now renders a Superseded column. *Fixed: added to `templates/board/BOARD.md`.*

**B. `/kanban-init`'s "Do not copy" list omitted `INTAKE.md`.** Behaviour was already correct
(step 3 enumerates what *to* copy), but that list reads as the canonical roster of
plugin-owned doctrine, so omitting a member invites the very drift it exists to prevent.
*Fixed: added to the list.*

**C. `req-ids backfill` step 4 contradicted itself.** It required both "split a bundled
paragraph into separate REQs" **and** "preserve the author's wording verbatim". The scratch
spec's `Users can create a board and add cards to it.` bundles two requirements **inside one
sentence** — you cannot both split it and leave it unchanged. A model would silently pick one
and not say which. *Fixed: intra-sentence bundles now permit the smallest edit that makes each
REQ standalone, and every such rewrite must be called out explicitly in the approval diff.*

**D. A superseded card would have stalled its milestone forever.** `/kanban` computes milestone
progress as `done members / total members`. A `superseded` card can never be `done`, so leaving
it on a `**Cards:**` line makes that milestone permanently unreachable — it would sit at `2/3`
for the life of the project with no diagnosis. The existing system already solves this for
splits (`/kanban` swaps parent for children), but nothing in the new doctrine said a superseded
card leaves its milestone — and `INTAKE.md`'s coverage invariant ("every card in exactly one
milestone") actively forbade removing it. *Fixed: the coverage invariant now excludes terminal
cards and states why; `/requirement` step 6.3 now removes a superseded card from its milestone
and puts its replacement in its place.*

**E. Gap: `/kanban`'s supersede step didn't say what happens to `pr_url`.** *Fixed: keep
`pr_url`/`design_pr_url` for traceability, as `done` already does.*

## Still untested — do this against a real git repo

1. `supersede` teardown: `gh pr close` with the REQ-naming comment, `git worktree remove`,
   branch deletion.
2. Skill **discovery and routing** — that Claude Code finds `/requirement` and `req-ids` and
   that `/refine` and `/requirement` actually invoke `req-ids` rather than re-implementing it.
3. `req-ids backfill` executed by a **cold model** on a messy real spec — the judgement call
   about what is and isn't a requirement is the part most likely to disappoint.
