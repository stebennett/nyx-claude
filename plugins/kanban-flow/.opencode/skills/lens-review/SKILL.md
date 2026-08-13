---
name: lens-review
description: "One pass of a code review through a single lens (from .opencode/doctrine/lenses/). Whole-diff mode: map pass then line pass per the lens's Walk. Slice mode: scope diff to slice paths, answer two questions (trace to criteria, stand alone). Returns findings with path:line evidence."
---

# lens-review

Review a branch diff through one lens only. You run **before any PR exists** — you do not touch
GitHub and return findings; the orchestrator persists them and runs the rework loop.

Read only: the plugin's `.opencode/doctrine/lenses/_shared.md` (**Etiquette**
and **Method** — they bind every finding) and your lens's file
`.opencode/doctrine/lenses/<lens>.md`, both at the absolute paths your dispatch provides; and
the card's `design.md` (acceptance criteria, scope, spec references), `implement.md` and
`test.md`. Read the spec sections `design.md` cites if your lens needs them. Do not read other
lenses' files.

Your lens file's **Walk** is your procedure — execute its steps in order and hold its **Ask of
every hunk** questions through the line pass; its **Example finding** is your calibration bar
for depth and finding shape.

## Slice mode — when your dispatch carries a slice number

If — and only if — your dispatch carries a `slice` number `k`, a `slices: N` total, that slice's
path list (each with change type), and `split.md`, you are in slice mode. It fires once per
slice after `pilot`'s carve has passed `pilot`, always with `lens: acceptance`:

1. Scope the diff to that slice's paths:
   ```bash
   git -C <worktree> fetch origin main
   git -C <worktree> diff origin/main...<original-branch> -- <slice k's paths>
   ```
2. Read `split.md` for slice `k`'s name, why its paths belong together, and which acceptance
   criteria it claims; read `card.md` and `design.md` for what those criteria actually say.
3. Answer two questions only:
   - **Does this slice trace to the criteria it claims?** For each criterion slice `k` claims
     in `split.md`, find the code in this slice's paths that serves it. A claimed criterion its
     own paths do not serve is blocking.
   - **Does this slice stand alone?** Handed only this diff, against a `main` that contains
     slices `1..k-1` and nothing later, could a human review it to a decision — and would it
     build? A reference to something only a later slice introduces, or a deletion a later slice
     still needs, is blocking.
   - A slice claiming only some of the card's criteria is correct, not partial — never flag a
     slice for not implementing the whole card.
4. Your `phase_doc` heading is `## [acceptance] — slice k`. `### Blocking` / `### Advisory`
   beneath it.
5. A blocking finding here reworks `pilot` (the carve), not `builder` (the code).

## Whole-diff mode — the normal panel

1. Get the diff: `git -C <worktree> fetch origin main`, then
   `git -C <worktree> diff origin/main...<branch>` — **naming the branch your dispatch gave
   you, never `HEAD`**. Map pass first (whole diff + `design.md`, write nothing), then the line
   pass through your lens's Walk. Use the worktree (Read/Grep) for surrounding context the diff
   hides.

## Return

- `status: blocked` with `blockers` = blocking findings, if any. Each blocker must be
  actionable: `path:line`, what is wrong, what right looks like.
- `status: needs-input` if you cannot review at all — no `design.md`, unreadable worktree,
  empty diff. NOT the same as `blocked`.
- Otherwise `status: complete`, `gate: none`, `phase: review`.
- `phase_doc` is your lens's slice of `review.md`: `## [<lens>]` then `### Blocking` and
  `### Advisory` bullets (`path:line — observation → consequence → fix`).
- Add `knowledge` entries for recurring patterns worth teaching earlier phases (scope: repo).
  Route every finding you defer rather than block on into one (`Gotchas` for a trap,
  `Conventions` for a rule).
- Return a `proposed_adrs` entry if your lens surfaces a significant architecture or technology
  decision the branch made silently.

## Role assignment

Lenses are used by Council 2 members (**architect**, **designer**, **pilot**) for full panel
review. The **verifier** also applies lenses in a testability-assessment capacity during the test
phase.
