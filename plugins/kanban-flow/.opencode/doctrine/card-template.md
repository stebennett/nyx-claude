<!-- The HTML/inline comments below document the schema and are STRIPPED at instantiation: an instantiated card.md carries bare frontmatter. Do not treat a comment as a field. -->
---
id: CARD-000
type: task            # feature | task | defect
layer: <one of config.layers>    # primary architectural layer; read from config.md
reqs: []              # REQ ids this card implements, e.g. [REQ-012]. Empty = unknown (a card written before this field), NOT "unaffected".
title: Short imperative title
status: backlog       # backlog | spec | refine | design | implement | verify | accept | deliver | done | blocked | split | superseded
phase: backlog        # mirrors status; the phase the card is currently in
right_sized: ""       # `true` once confirmed an indivisible vertical slice (by /refine at intake, the slice phase, a split carve-out, or a keep-as-one override); guards re-slicing. `true` at intake skips the spec phase entirely.
depends_on: []        # list of card ids that must be `done` before this starts, e.g. [CARD-001]
branch: ""            # current branch: `<type>/NNN-slug-design` from the spec→design transition, then `<type>/NNN-slug` once the design PR merges
worktree: ""          # absolute path of the current branch's worktree
design_pr_url: ""     # design PR (spec.md + design.md + ADRs); set when it opens, kept after merge for traceability
pr_urls: []           # implementation PRs, in shipping order. The card is `done` when ALL have merged. A card that ships as one PR has exactly one entry — that is the N=1 case, not a special case.
split_slices: 0       # how many slices this card ships as. 0 = pilot did not run (one PR). N = split into N slices by pilot.
adrs: []              # ADR ids this card produced, e.g. [ADR-0007]; appended by /kanban via the adr skill (the append reserves the number; the file merges via the card's PR)
reworks:              # automatic rework loops consumed, per producer (budgets: config.md `check_budget`); flow-metric input for /retro
  spec: 0            # analyst → analyst
  design: 0           # architect → architect
  implement: 0        # verifier / the lens panel → builder
  split: 0            # pilot / the per-slice acceptance lens → pilot
  deliver: 0          # pilot → pilot (per PR: reset when the design PR merges, and between slice PRs)
review_lenses_failed: []   # lenses whose blocking findings sent the card back; only these re-run on the next panel pass (empty = run the full panel). Written by /kanban in the same state commit that increments reworks.implement; cleared when the panel passes clean.
estimated_lines: ""   # projected changed lines, from whichever estimator sized this card: analyst (verified by analyst under SLC-SIZE), or — for a card that arrives `right_sized: true` — /refine or /requirement at intake (verified by analyst under INT-SIZED). A split child's is copied from the slicer's proposed_cards entry at the carve-out. The ceiling for both is config.md `size_limit`.
actual_lines: ""      # changed lines pilot measured on the implementation PR; vs estimated_lines it is /retro's signal that an estimator under-estimates — /retro tallies both populations (slicer-sized and intake-sized) separately
started: ""           # ISO date the card left backlog (set by /kanban)
delivered: ""         # ISO date the card's PR merged (set by /kanban reconcile)
created: 2026-06-29   # ISO date
---

## Why
One paragraph: the user-facing intent and why this card exists.

## Acceptance criteria
- [ ] Observable, testable criterion one
- [ ] Observable, testable criterion two

## Notes
Free-form context. Phase docs (spec.md, design.md, design-spec.md, solution-review.md, acceptance-review.md, verify.md, accept.md, …) live beside this file and hold the detail. Split lineage is recorded here as prose (e.g. "Split out of CARD-NNN" on a child, "Split into CARD-XXX, CARD-YYY" on a `split` parent).

A `superseded` card is terminal: `/requirement` retired it because the requirement it implemented was superseded. The reason is recorded here.
