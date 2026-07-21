---
spec_path: docs/spec.md
gh_command: gh
board_dir: docs/cards
adr_dir: docs/adrs
kanban_flow_version: "0.1.0"
template_overrides: {}
wip_limit: 3
pump_gate: on
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
review_panel: full
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

The single source of project-specific tunables. `/kanban-init` creates it;
**`/kanban` never rewrites it**, so it is safe to hand-edit. **Agents never read
this file** — every value an agent needs arrives in its dispatch; only `/kanban`
and the intake skills (`/refine`, `/requirement`, `/kanban-init`, `/migrate`) read it.

- **spec_path** — the requirements doc `/refine` and `card-slicer` read.
- **gh_command** — the GitHub CLI, or a bot-identity wrapper; every `gh`/API call
  goes through it. Default `gh`.
- **board_dir** / **adr_dir** — where the board (cards, templates, this file) and
  ADRs live. Conventional locations (`docs/cards`, `docs/adrs`), hardcoded in most
  places — leave the defaults.
- **kanban_flow_version** — the plugin version this board was last synced to.
  `/kanban-init` stamps it, `/migrate` updates it; `/kanban` compares it to nudge you
  to `/migrate`.
- **template_overrides** — optional map from a template name (`card-template.md` |
  `pr-template.md` | `design-pr-template.md`) to a repo-relative path read instead of
  the plugin's. Empty (`{}`) → plugin templates; `/migrate` sets one for a customized
  template.
- **wip_limit** — max cards in flight at once.
- **pump_gate** — `on` (default; a missing key reads as `on`) runs the cheap
  `pump-gate` haiku agent first each pump (SKILL.md §0.0), so a quiet board under
  `/loop` decides idle-vs-run in a minimal context instead of loading the board.
  `off` bypasses it and runs reconcile directly — a debugging escape hatch, not the
  normal path.
- **gates** — per-gate policy. `slice`: `auto` | `manual`. `design`: `pr` (design PR
  is the review) | `domain` (stop for `gate_layer` cards only) | `manual` (stop every
  card). `deliver`: `auto` | `manual`.
- **checks** — every producer has a checker; every check runs by default. Turning
  one `off` (escape hatch for a noisy checker) makes `/kanban` warn every pump and on
  `BOARD.md` what ships unchecked — `slice: off` in particular removes the pre-code
  **size_limit** cap (`SLC-SIZE`), and `split: off` disables the carve entirely (an
  oversized branch ships as one oversized PR). No `implement` switch exists (tester +
  lens panel are unconditional). Omitted → `on`. (RATIONALE.)
- **check_budget** — per-producer automatic rework loops before a card parks;
  `deliver`/`split` are spent **per PR** (`/kanban` resets the counters at each
  PR/slice boundary). Omitted producer → `2`, except `deliver`/`split` → `1`.
  (RATIONALE.)
- **review_panel** — how many lenses the review panel dispatches (the pump body, §5).
  `full` (default; a missing key reads as `full`) — the whole table: acceptance,
  design, functionality, security, simplicity, tests, readability + the language
  lenses (`python`/`typescript`, when the diff matches). `standard` — acceptance,
  functionality, tests, security + the language lenses. `light` — acceptance,
  functionality + the language lenses. Each reduced tier drops the lenses above it.
  Use `standard`/`light` on low-risk layers watching token spend; keep `full` for
  `gate_layer` cards and anything security-sensitive — such a card under a reduced
  panel is warned in the report. The panel is the costliest phase and lens count is
  its multiplier — the largest token dial. (RATIONALE.)
- **size_limit** — the hard ceiling on a card's **changed lines, including tests**
  (default 500). Enforced at slice (`SLC-SIZE`, blocking — forces a split) and deliver
  (`DLV-SIZE`, advisory — proposes one).
- **size_exclude** — glob paths omitted from both counts: lock files, vendored deps,
  **plus the board (`docs/cards/**`)** so a card's phase docs don't count against it.
  Add generated code (protobuf, OpenAPI); move it with `board_dir`. (RATIONALE.)
- **layers** — the architectural layers, **in order** — the scheduler's tie-break
  rank for the next ready card. Tag each card's `layer` with one.
- **gate_layer** — the layer that triggers the `design: domain` stop (riskiest
  rules); usually the pure-logic core.
- **coverage_target** — the test-coverage expectation agents cite.
