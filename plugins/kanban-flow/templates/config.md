---
spec_path: docs/spec.md
gh_command: gh
board_dir: docs/cards
adr_dir: docs/adrs
kanban_flow_version: "0.1.0"
template_overrides: {}
wip_limit: 3
gates:
  slice: auto
  design: pr
  deliver: auto
checks:
  intake: on
  slice: on
  design: on
  split: on
  deliver: on
check_budget:
  intake: 2
  slice: 2
  design: 2
  implement: 2
  split: 1
  deliver: 1
size_limit: 500
size_exclude:
  - "*.lock"
  - "package-lock.json"
  - "yarn.lock"
  - "pnpm-lock.yaml"
  - "Cargo.lock"
  - "poetry.lock"
  - "uv.lock"
  - "go.sum"
  - "Gemfile.lock"
  - "composer.lock"
  - "vendor/**"
  - "node_modules/**"
  - "docs/cards/**"
layers:
  - infra
  - domain
  - db
  - api
  - web
gate_layer: domain
coverage_target: "90% on the core logic layer"
---

# kanban-flow configuration

The single source of project-specific tunables. `/kanban-init` creates this file;
the skills read it; **`/kanban` never rewrites it**, so it is safe to hand-edit.

- **spec_path** — the requirements document `/refine` and `card-slicer` read.
- **gh_command** — the GitHub CLI, or a wrapper script that supplies a bot/service
  identity for automation. Every `gh`/API call in the skills and agents goes
  through this. Default `gh`.
- **board_dir** / **adr_dir** — where the board (cards, templates, this file) and
  ADRs live. These are the **conventional locations the skills assume**
  (`docs/cards`, `docs/adrs`) and match `/kanban-init`'s scaffold. The skills and
  agents currently hardcode these paths in most places, so relocating them today
  also requires editing every path reference in the skills/agents — leave them at
  the defaults unless you're prepared to do that. Full parameterization (so these
  keys alone control the location) is a future enhancement.
- **kanban_flow_version** — the plugin version this board's config and scaffold
  were last synced to. `/kanban-init` stamps it; `/migrate` updates it. `/kanban`
  compares it to the installed plugin version to nudge you to run `/migrate`.
- **template_overrides** — optional map from a template name (`card-template.md` |
  `pr-template.md` | `design-pr-template.md`) to a repo-relative path. When an entry
  is set, the skills read that file instead of the plugin's template; leave empty
  (`{}`) to use the plugin templates. `/migrate` sets an entry automatically if it
  finds a template you had customized.
- **wip_limit** — max cards in flight at once.
- **gates** — per-gate policy. `slice`: `auto` | `manual`. `design`: `pr` (the
  design PR is the review) | `domain` (interactive stop for `gate_layer` cards
  only) | `manual` (stop every card). `deliver`: `auto` | `manual`.
- **checks** — every producer has a checker, and by default every check runs.
  This switch exists as an escape hatch for a checker that turns out noisy, not
  as a routine tunable: while any check is `off`, `/kanban` warns in every pump
  report and on `BOARD.md`'s header, naming what is shipping unchecked. Note the
  reach of `slice: off` in particular — `SLC-SIZE` is the only thing enforcing
  **size_limit** *before code is written*, so disabling the slice check removes
  the hard cap on card size and leaves only `DLV-SIZE`'s after-the-fact warning.
  There is deliberately **no `implement` switch**: the implementer's checkers are
  `card-tester` and the lens panel, so an off switch there would silently skip
  running the test suite. The implement chain is unconditional. `split: off`
  disables the carve entirely — an oversized branch is never split and the human
  gets one oversized PR, with only `DLV-SIZE`'s advisory warning about it.
- **check_budget** — per-producer automatic rework loops before a card parks for
  the driver. Budgets are per-producer so a card that needed two design revisions
  does not arrive at implement with nothing left. `implement: 2` is the historic
  behaviour of the old single `reworks` counter. `deliver: 1` because a delivery
  check failing twice means something another rework pass will not fix — and it is
  allowed **per PR**: a card ships two PRs (design, then implementation) — and a
  **split** card ships N implementation PRs, one per slice — each with its own
  deliver check, and each gets the full allowance, so the shipped `1` is one loop
  per PR, not one for the whole card. `/kanban` makes that real by resetting
  `reworks.deliver` (and `reworks.implement`) to `0` when the design PR merges and
  again on each slice merge with slices still to come. `split: 1` for the same reason as
  `deliver`: a split that fails `card-split-checker` twice is not going to work on
  a third try — `pr-splitter` is a safety net, not a routine path, and a repeated
  failure means the carve itself is unworkable, not that another attempt will find
  one; the card falls back to `SPL-NO-LOSS`'s refusal path and ships as one
  oversized PR.
  An **omitted** producer defaults to `2` — except `deliver` and `split`, which
  default to `1` — so an older config missing this key behaves exactly as the
  shipped values do. Likewise an omitted `checks` producer defaults to `on`, and an
  omitted `size_limit` to `500`: a project that never touches this file gets
  every check, at the shipped budgets, under the shipped ceiling.
- **size_limit** — the hard ceiling on a card's **changed lines, including
  tests** (default 500). Enforced twice: `card-slice-checker` independently
  estimates before any code is written and a projected breach **forces a split**
  (`SLC-SIZE`, blocking); `card-deliver-checker` measures the real diff and, on a
  breach, must propose a concrete split into smaller PRs (`DLV-SIZE`, advisory).
  This is the real ceiling on card size in the system.
- **size_exclude** — glob paths omitted from both counts: files that are not the
  change a human must review. Lock files and vendored dependencies by default —
  machine-authored and never read — **plus the board itself (`docs/cards/**`), so a
  card's own phase docs do not count against its size budget.** That last exclusion
  is what makes the two counts comparable: `estimated_lines` is an estimate of
  **code + tests**, but the implementation branch also carries `implement.md`,
  `test.md`, `review.md` (concatenated across the whole review panel), `pr-body.md`
  and `feedback.md` — hundreds of lines of paperwork *about* the change. Counting
  them inflates `actual_lines` against the estimate it is compared to, and lets a
  card breach `size_limit` on documentation volume alone. The budget measures the
  diff a human reviews, not the prose describing it. Add your project's generated
  code (protobuf stubs, OpenAPI clients) here too. If you move the board with
  `board_dir`, move this glob with it.
- **layers** — the project's architectural layers, **in order**. The scheduler
  uses this order as the tie-break rank when picking the next ready card. Tag each
  card's `layer` with one of these values.
- **gate_layer** — the layer that triggers the `design: domain` interactive stop
  (its rules are the riskiest to get wrong). Usually the pure-logic core.
- **coverage_target** — the test-coverage expectation agents cite.
