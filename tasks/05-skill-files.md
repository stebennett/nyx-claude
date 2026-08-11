# Task 05: Skill Files — 3 Domain Knowledge Skills

## Why

Three Claude Code skills provide **domain knowledge** (format specifications, conventions) that load into the session context when their description matches the conversation. These become OpenCode skills (`.opencode/skills/<name>/SKILL.md`).

The most significant change is the **kanban-orchestrator**: the Claude Code plugin split the pump body across a lean front-door SKILL.md + three reference files (`pump.md`, `reconcile-edge-cases.md`, `split-shipping.md`). In OpenCode, all four are folded into a single SKILL.md — the pump-gate pre-flight logic moves to the `/kanban` command (Task 04), and the full state machine becomes one skill body.

## What

Create these 3 skills:

1. `.opencode/skills/kanban-orchestrator/SKILL.md` — Full §0–§7 pump state machine (~800 lines from pump.md + edge cases + split shipping, minus the pump-gate preamble which lives in the command)
2. `.opencode/skills/adr/SKILL.md` — ADR format, numbering, supersede conventions (source: `skills/adr/SKILL.md`)
3. `.opencode/skills/req-ids/SKILL.md` — REQ id format, allocation, backfill (source: `skills/req-ids/SKILL.md`)

## How

### 5.1 kanban-orchestrator SKILL.md

**Frontmatter:**

```yaml
name: kanban-orchestrator
description: Use ONLY when executing a kanban-flow pump cycle triggered by /kanban. Contains the full §0–§7 state machine: §0 Reconcile (merged PRs, amendment queue, legacy normalization), §1 Load state (config, cards, criterion id sets, dispatch/model table), §2 Render board (sole writer of BOARD.md), §3 Resolve gates & blockers, §4 Schedule (WIP limits, ready cards ranked by layer), §5 Advance in-flight cards through slice→design→implement→test→review→deliver (dispatch contracts, check-doc discipline, review panel, persist results), §6 PR open (CI gate, review-complete addressing), §7 Report. Loads reference procedures for reconcile edge cases and split shipping. Do NOT use for general kanban questions or unrelated orchestration tasks.
```

**Body assembly:**

Combine content from THREE source files in this order:

1. **`skills/kanban/references/pump.md`** (~749 lines) — the main state machine body. This is the bulk of the skill. Read it completely.

2. **`skills/kanban/references/reconcile-edge-cases.md`** (~119 lines) — off-happy-path procedures for §0 reconcile. Insert these after the reconcile section. The procedures cover:
   - Closed-PR recovery (including recovering a closed slice PR)
   - Amendment drain (supersede teardown with split-merged-slices exception)
   - Legacy normalization (scalar pr_url → pr_urls, scalar reworks → per-producer map)
   - Orphan-PR adoption
   - Completeness backstop (two-direction procedure)

3. **`skills/kanban/references/split-shipping.md`** (~193 lines) — the split sub-step and sequential PR shipping. Insert these near the relevant phase step in the pump body. Covers:
   - Branch measurement (`--no-renames` on every `--name-status`)
   - Dispatching `pr-splitter` + `card-split-checker` + slice-mode `[acceptance]` re-run
   - Refusal vs blocked outcomes
   - Shipping N slices sequentially
   - The "never split a split" rule

**Path rewrites** to apply across ALL assembled content:
- `${CLAUDE_PLUGIN_ROOT}/templates/` → `.opencode/doctrine/`
- `${CLAUDE_PLUGIN_ROOT}` → `.opencode/` (if any bare references remain)
- `skills/kanban/references/pump.md` → remove (body is now inline)
- `skills/kanban/references/reconcile-edge-cases.md` → remove
- `skills/kanban/references/split-shipping.md` → remove

**Model table preservation:** The dispatch/model table (pinning each agent's model) in the pump body is preserved verbatim. The original table defines which agent to dispatch, which model tier, and for which card phase/action.

**Pump-gate removal:** The §0.0 pump-gate preamble that previously lived in the SKILL.md lean front-door is NOT included in the skill body — it lives in the `/kanban` command (Task 04). The skill body should start directly with the pump state machine.

### 5.2 adr SKILL.md

**Source:** `skills/adr/SKILL.md`

**Frontmatter:**

```yaml
name: adr
description: Use when creating or managing Architecture Decision Records (ADRs) in a kanban-flow project. Sole authority for Cognitect ADR format (Title, Context, Decision, Status, Consequences), numbering (max+1 across main and card adrs: reservations), supersede handling (set superseded ADR status, update index), bidirectional card linking (append to card's adrs: list), and docs/adrs/ layout. Invoked only by the /kanban orchestrator when a phase agent proposes ADRs — never use standalone.
```

**Body:** The original `skills/adr/SKILL.md` body, with path references adapted.

Apply path rewrites:
- `${CLAUDE_PLUGIN_ROOT}/templates/` → `.opencode/doctrine/`

Key invariants preserved:
- Sole-writer authority for `docs/adrs/`
- ADR format: Cognitect lightweight
- Storage: `docs/adrs/README.md` (index), `NNNN-<kebab-title>.md` files
- Numbering spans both committed files and card `adrs:` frontmatter reservations
- ADRs immutable once `Accepted`; statuses: `Accepted | Superseded | Deprecated`

### 5.3 req-ids SKILL.md

**Source:** `skills/req-ids/SKILL.md`

**Frontmatter:**

```yaml
name: req-ids
description: Use when assigning or managing REQ-NNN ids in a project spec. Sole authority for REQ format (### REQ-NNN — title under ## <Area> headings, **Status:** active | superseded by REQ-NNN), id allocation (max+1), and three operations: backfill (id an un-id'd spec — idempotent), allocate (add a new requirement in a named area), supersede (retire requirements by setting status — never delete, never edit prose). Invoked by /refine and /requirement only.
```

**Body:** The original `skills/req-ids/SKILL.md` body, with path references adapted.

Apply path rewrites:
- `${CLAUDE_PLUGIN_ROOT}/templates/` → `.opencode/doctrine/`

Key invariants preserved:
- Writes `spec_path` file (from `config.md`) but never commits
- Requirements never deleted, renumbered, or reused
- `backfill` is idempotent

## Verification

1. **All 3 SKILL.md files exist:**

```bash
ls plugins/kanban-flow/.opencode/skills/kanban-orchestrator/SKILL.md
ls plugins/kanban-flow/.opencode/skills/adr/SKILL.md
ls plugins/kanban-flow/.opencode/skills/req-ids/SKILL.md
```

2. **No `${CLAUDE_PLUGIN_ROOT}` references remain:**

```bash
grep -rl '\${CLAUDE_PLUGIN_ROOT}' plugins/kanban-flow/.opencode/skills/
# Must produce NO output
```

3. **kanban-orchestrator body length check:**

The combined body should be substantial (the pump.md alone is ~749 lines, plus edge cases ~119 lines, plus split shipping ~193 lines = ~1061 lines total, minus pump-gate preamble). Verify the file is longer than 800 lines:

```bash
wc -l plugins/kanban-flow/.opencode/skills/kanban-orchestrator/SKILL.md
# Should be > 800
```

4. **No reference to the old reference file paths:**

```bash
grep -l 'pump\.md\|reconcile-edge-cases\.md\|split-shipping\.md' plugins/kanban-flow/.opencode/skills/kanban-orchestrator/SKILL.md
# Must produce NO output (these are now inline)
```

5. **Each file has valid YAML frontmatter** with `name` and `description` keys.

6. **adr and req-ids body content matches their sources** (modulo path rewrites):

```bash
# Check that key phrases from the original exist in the new file
grep -c "Cognitect" plugins/kanban-flow/.opencode/skills/adr/SKILL.md
grep -c "backfill" plugins/kanban-flow/.opencode/skills/req-ids/SKILL.md
```

## Dependencies

Task 01 (directories created), Task 02 (doctrine files exist for path references). The source files from `skills/kanban/references/` must still exist (they are not modified or moved).
