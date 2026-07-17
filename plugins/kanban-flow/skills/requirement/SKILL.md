---
name: requirement
description: Add, amend or supersede a single requirement on a running project. Interviews the driver into a well-formed requirement, persists it to the spec via req-ids, slices it into cards per the intake doctrine, and applies its impact on the board — editing backlog cards directly and queueing amendments for cards already in flight. Intake only — never starts implementation. Run under Opus.
---

# /requirement — add, amend, or supersede a requirement

`/refine` turns a whole spec into a backlog. **You handle one requirement on a project
that is already running** — the mid-flight ask, the changed mind, the thing the spec
never said.

You are an **intake** skill. You never write code, never create branches or worktrees,
and never start a card.

Usage: `/requirement [rough one-liner]`. With no argument, ask what the driver wants to add.

## The ownership boundary — read this first

`/kanban` is the **sole writer** of every `card.md` from the moment a card leaves
`backlog`. That rule is what makes the board safe to drive unattended under `/loop`, and
a card beyond backlog owns a git branch, a worktree, and possibly an open PR — so
retiring one is a **teardown**, not a file edit.

You respect that boundary absolutely. Classify every existing card by `status` alone:

| Card status | What you may do |
|---|---|
| `backlog` | **Edit, re-slice, or delete it directly.** No branch, no worktree, no PR — nothing to tear down. This is the same authority `/refine` has. |
| `slice` … `deliver`, `blocked` | **Never touch the file.** Append an amendment to `{board_dir}/AMENDMENTS.md`; `/kanban` applies it on its next pump. |
| `done` | **Never amend, never supersede** — it shipped. If the new requirement contradicts shipped behaviour, that is a **new card** (usually a `defect`). |
| `split`, `superseded` | Terminal. Ignore. |

## Steps

1. **Load context.** Read `{board_dir}/config.md` first (`spec_path`, `layers`,
   `board_dir`). Then read:
   - the plugin's card doctrine at `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md` — the
     rules for every card you propose. Follow it exactly; it is not duplicated here.
   - the spec at `spec_path`;
   - every `docs/cards/CARD-*/card.md` (you need `status`, `reqs` and `depends_on` on all
     of them for impact analysis);
   - `{board_dir}/MILESTONES.md` and `{board_dir}/KNOWLEDGE.md`;
   - the card template — `config.md`'s `template_overrides["card-template.md"]` if set,
     else `${CLAUDE_PLUGIN_ROOT}/templates/card-template.md`.

2. **Ensure the spec has REQ ids.** Invoke the **`req-ids`** skill's **`backfill`**
   operation. On an un-id'd spec it proposes an id'd version for approval; otherwise it is
   a silent no-op. Everything below addresses requirements by id, so this must happen first.

3. **Elicit.** Interview the driver **one question at a time** — never a wall of questions.
   Prefer multiple choice where the options are genuinely enumerable. Cover:
   - **Intent** — what becomes possible, and for whom. Why now.
   - **Scope** — and explicitly what is *out* of scope.
   - **Edge cases** — what happens at the boundaries, on failure, for the unauthorised user.
   - **Acceptance** — the observable criteria that would prove it done.

   **Stop as soon as the requirement is testable** — not after a fixed number of questions.
   A requirement is testable when you could hand it to someone who has never met the driver
   and they could tell you whether the built thing satisfies it.

4. **Analyse impact.** Decide what this requirement *is*:
   - **new** — it adds a capability nothing in the spec covers;
   - **amends** an existing `REQ-NNN` — same capability, changed detail;
   - **supersedes** one or more existing `REQ-NNN` — the old requirement is now wrong.

   Then find every affected card. Use the `reqs` frontmatter field as the index — it is a
   lookup, not an inference. Two traps:
   - **A card with empty `reqs` means _unknown_, not _unaffected_.** It pre-dates the
     field. Read it and judge; surface it to the driver as *impact undetermined* rather
     than silently assuming it is fine.
   - **Superseding a card orphans its dependents.** Any card whose `depends_on` names a
     card you are superseding can never become ready — `/kanban` will park it forever. For
     **every** dependent you must propose a rewire: drop the dead id, or repoint it at the
     replacement card. A `backlog` dependent you rewire directly; an in-flight dependent
     needs its own `revisit` amendment. **Never leave a dangling `depends_on`.**

   Classify each affected card by the ownership boundary above.

5. **Propose — once.** A single approval surface. Show:
   - the **requirement** exactly as it will appear in the spec (heading, `**Status:**`, prose);
   - any **supersede** links (`REQ-012 supersedes REQ-004`);
   - the **new cards** — id, type, layer, title, `reqs`, `depends_on`, and acceptance
     criteria, per `INTAKE.md`;
   - **edits and deletions to backlog cards**, each with its reason;
   - **`depends_on` rewires**, each with its reason;
   - **milestone placement** for every new card, with both `INTAKE.md` invariants
     re-validated across the whole board;
   - the **amendments to be queued** — one line per in-flight card, naming the action and
     why.

   **Check before you propose.** Unless `config.md`'s `checks.intake` is `off`, dispatch
   **`card-intake-checker`** (opus) with the new cards, the milestone placements, the existing board,
   the requirement, `spec_path`, **`size_limit` and `size_exclude`** (the ceiling and exclusions for
   `INT-SIZED`), and the doctrine paths (`${CLAUDE_PLUGIN_ROOT}/templates/AGENT-PROTOCOL.md`,
   `${CLAUDE_PLUGIN_ROOT}/templates/checks/_method.md`, `${CLAUDE_PLUGIN_ROOT}/templates/checks/intake.md`, `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md`,
   `<board_dir>/PROTOCOL-ADDENDUM.md`). `verdict: fail` → revise against the blocking findings and
   re-check, up to `check_budget.intake` (default 2); exhausted → present anyway with the unresolved
   findings shown as open questions. Show advisory findings alongside the proposal.

   **Keep the checker's `estimated_lines` for every proposed card** — you persist it in step 6. It
   comes from `INT-SIZED`, and for a card you mark `right_sized: true` it is the **only** estimate
   that will ever exist: that card skips the slice phase, so `SLC-SIZE` never runs on it.

   Ask for approval, edits, or removals. Iterate until approved. **Write nothing before
   approval.**

6. **On approval, write — then commit once.**
   1. Persist the requirement via **`req-ids`**: `allocate` for the new one (it returns the
      id), then `supersede` for any it replaces. Never edit the spec by hand.
   2. Create the new cards from the card template, and apply the approved edits, deletions
      and `depends_on` rewires to `backlog` cards. **Set each new card's `estimated_lines` to the
      value `card-intake-checker` produced for it under `INT-SIZED`** — never leave it empty. A card
      marked `right_sized: true` **skips the slice phase**, so no slicer will ever size it and
      `SLC-SIZE` will never run: this is the only moment its estimate can be recorded. Empty, and
      `DLV-SIZE` has no baseline for `actual_lines` and `/retro` cannot see the card's estimate at
      all. (`checks.intake: off` → no estimate exists to persist; tell the driver those cards reach
      the board unsized.)
   2b. **Persist the intake check report** to `{board_dir}/intake-checks/YYYY-MM-DD-<slug>.md`
      (`<slug>` from the requirement), creating the directory if needed. `/retro` aggregates every
      check doc **by criterion id** and reads this directory alongside the cards' check docs — without
      it the `INT-*` verdicts leave no durable record and intake is the one target `/retro` can never
      tune. Persist it for a budget-exhausted failing run too.
   3. Update `{board_dir}/MILESTONES.md` — place each new card, and **remove from its
      milestone's `**Cards:**` line every card you queued for `supersede`**, putting its
      replacement card (if any) in its place. A superseded card can never be `done`, so
      leaving it there would make that milestone's progress permanently unreachable. Both
      `INTAKE.md` invariants must still hold across the whole board afterwards.
   4. Append the approved amendments to `{board_dir}/AMENDMENTS.md` (format below),
      creating the file if it does not exist.
   5. Commit everything as **one** Conventional Commit:
      `chore(kanban): add REQ-NNN — <title>` (or `amend` / `supersede` as fitting), ending
      with the project's `Co-Authored-By` trailer.

   The commit matters: `/kanban` drains the queue on a later pump, possibly in another
   session. An uncommitted amendment is a lost amendment.

7. **Hand off.** Tell the driver to run **`/kanban`** — it will drain the queue and
   schedule the new cards. If you queued no amendments, say so; the next pump just picks up
   the new cards.

## The amendment queue

`{board_dir}/AMENDMENTS.md` is a queue **you write and `/kanban` drains**. A missing file
means an empty queue.

One block per pending amendment:

```markdown
## CARD-007 — supersede
**Raised:** 2026-07-12 by /requirement
**Reason:** REQ-004 superseded by REQ-012 — export moves from CSV to XLSX, so this card builds the wrong thing.
**Action:** supersede
```

**Exactly two actions.** There is no third — do not invent one.

- **`supersede`** — the card is dead. `/kanban` will close any open PR, tear down the
  worktree and branch, and set `status: superseded` (terminal). Use when the card builds
  something the project no longer wants.
- **`revisit`** — the card is still wanted, but its scope moved. `/kanban` will set
  `status: blocked` with a blocker naming the REQ, leaving the branch, worktree and PR
  intact, and its blocked-card conversation asks the driver how to proceed. Use for
  everything that is not a clean kill.

There is deliberately **no "re-slice a card that already has code on its branch"** action.
That is `revisit` plus a human decision. Do not automate it.

`**Reason:**` is written for a human reading it days later in a different session. Name the
REQ ids and say what actually changed.

## Rules

- **Intake only.** No branches, no worktrees, no code, no starting cards.
- **Never write a `card.md` that is not in `backlog`.** In-flight cards are reached only
  through `AMENDMENTS.md`. This is not a style preference — it is the invariant that keeps
  the board's state from being corrupted by two concurrent writers.
- **Never write `BOARD.md` or `KNOWLEDGE.md`.** `/kanban` owns them.
- **Never edit the spec directly.** `req-ids` is the sole authority for requirement
  identity; you supply the prose, it supplies the identity.
- **Never delete a requirement.** Superseding leaves it in place, marked. History is the point.
- Card doctrine lives in `INTAKE.md`. If a rule about slicing, typing, layering, `reqs`,
  `depends_on`, `right_sized`, or milestones seems missing here, it is there.
- Never leave a dangling `depends_on` pointing at a superseded card.
- Elicit one question at a time.
