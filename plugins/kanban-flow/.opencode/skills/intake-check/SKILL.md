---
name: intake-check
description: "Check a proposed card set against INT-* criteria before the driver sees it. Vets observable ACs, resolved reqs, vertical slices, coverage, no overlap, acyclic DAG, consistent milestones, no card exceeds size_limit. Returns estimated_lines per card."
---

# intake-check

Check a proposed card set before any card exists on disk and before the driver is asked to
approve it. Read `checks/_method.md` (the discipline, the return format, and the size-estimate
appendix) and obey it exactly.

Read: `checks/_method.md` and `checks/intake.md` (absolute paths in your dispatch; layer any
`## Check criteria — intake` addendum on top), `PROTOCOL-ADDENDUM.md` and the plugin
`INTAKE.md` (the slicing and milestone doctrine) if present.

Your dispatch gives you: the proposed cards (title, type, layer, reqs, why, acceptance criteria,
depends_on), the milestone plan, the existing board (card ids and their milestones), the
requirement(s) in scope, `spec_path`, and `size_limit` / `size_exclude`.

## Work the intake criteria

Work the `## intake` criteria by the Walk in `checks/intake.md`: list the requirement's
observable behaviours in your own words *before* reading the cards, map behaviours ↔ cards
(unclaimed → `INT-COVERAGE`, doubly-claimed → `INT-NO-OVERLAP`), test each acceptance criterion
with *what would I run to see this?* (`INT-AC-OBSERVABLE`), resolve every `reqs` id, build the
`depends_on` graph by hand (`INT-DAG` / `INT-MILESTONE`), confirm each card is a vertical slice
(`INT-VERTICAL`), and **size every proposed card** (`INT-SIZED`, by `_method.md`'s appendix) —
returning `estimated_lines` for every card, breach or not.

Verdict every criterion with evidence citing the proposed card or the spec line.

## Return

- `verdict: pass` (`status: complete`, `gate: none`, `phase: check`, `checks: intake`) when no
  finding is blocking.
- `verdict: fail` when any finding is blocking.
- `phase_doc` is the intake check report: `## Verdict`, `## Criteria` (the full table),
  `## Requirement coverage` (behaviour → card map), `## Size` (`estimated_lines` per proposed
  card, with per-file working and excluded paths), `## Blocking findings`, `## Advisory
  findings`. Persisted to `<board_dir>/intake-checks/YYYY-MM-DD-<slug>.md`.
- `status: needs-input` only if you cannot check at all (spec unreadable, no proposal supplied).
- A card set you would have sliced differently is a `pass` — granularity that meets
  `INT-VERTICAL` is the intake skill's call. Taste is not a defect.
- Add `knowledge` entries for recurring intake traps (scope: repo, section: Conventions).
