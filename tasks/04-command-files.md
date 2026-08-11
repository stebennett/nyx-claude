# Task 04: Command Files — 6 Slash Commands

## Why

Six Claude Code skills (`/kanban`, `/kanban-init`, `/refine`, `/retro`, `/requirement`, `/migrate`) are **user-invoked workflows**. In OpenCode, user-invoked workflows become **commands** (`.opencode/commands/<name>.md`). Each command file has a YAML frontmatter with `description` and optionally `model`, plus a markdown body that serves as the template prompt.

While commands can optionally set `model` in frontmatter, the plan specifies that the orchestrator command may use the user's default model since heavy reasoning is delegated to pinned agents. For consistency with the plan, the `/kanban` and `/refine` commands specify `model` explicitly as `anthropic/claude-sonnet-4-6` (the plan says the orchestrator session is Opus-collapsed-to-Sonnet). Others use the user's default model.

Key adaptation: The Claude Code plugin uses `/loop /kanban` — the loop repeatedly invokes the skill at an interval. OpenCode has no loop primitive. Each `/kanban` invocation runs exactly one pump and stops. The command's closing message tells the user when to re-run.

## What

Create these 6 files under `plugins/kanban-flow/.opencode/commands/`:

1. `kanban.md` — Orchestrator, single pump cycle
2. `kanban-init.md` — Scaffold board + config
3. `refine.md` — Whole-backlog intake from spec
4. `requirement.md` — Single-requirement intake, mid-project
5. `retro.md` — Continuous process improvement
6. `migrate.md` — One-time board upgrade

## How

### 1. `/kanban` → `.opencode/commands/kanban.md`

**Source:** Derived from `skills/kanban/SKILL.md` (lean front-door) + the migration plan's adapted template.

The command body is the **lean front-door** from the Claude Code skill, adapted:

```markdown
---
description: Run one kanban-flow pump cycle — reconcile merged PRs, schedule ready cards, advance in-flight cards through slice→design→implement→test→review→deliver. Re-run after a PR lands, a review completes, or a gate decision is made.
model: anthropic/claude-sonnet-4-6
---

You are the kanban-flow orchestrator. Run **one pump cycle** via the `kanban-orchestrator` skill.

## §0.0 Pre-flight gate

Read `docs/cards/config.md` for `pump_gate` and `board_dir`.

If `pump_gate` is `on` (default):
1. Dispatch `pump-gate` (haiku), passing `board_dir`.
2. `decision: idle` → print `idle — <summary>` and **STOP**.
3. `decision: run` → proceed to load the orchestrator skill.

If `pump_gate` is `off`, proceed directly (debugging escape hatch).

## On `run`

Load the `kanban-orchestrator` skill and execute the full §0–§7 pump cycle. The skill
body lives in `.opencode/skills/kanban-orchestrator/SKILL.md`.

After the pump completes:
- If the pump stopped at a gate (design, slice, deliver → `manual`), tell the user
  which card and what decision is needed, then: *"Run `/kanban` again after you decide."*
- If the pump completed a card or advanced one, report the new board state and
  suggest: *"Run `/kanban` again to continue."*
- If the pump was idle, the pre-flight gate already printed the summary.
```

### 2. `/kanban-init` → `.opencode/commands/kanban-init.md`

**Source:** `skills/kanban-init/SKILL.md` body, with path rewrites.

Read the source file, then:

1. Replace all `${CLAUDE_PLUGIN_ROOT}/templates/` with `.opencode/doctrine/`
2. Replace all `${CLAUDE_PLUGIN_ROOT}` path references with `.opencode/`
3. Wrap in frontmatter:

```yaml
---
description: Scaffold a repo for kanban-flow. Copies config.md, PROTOCOL-ADDENDUM.md, BOARD.md, KNOWLEDGE.md, and MILESTONES.md into the board dir (default docs/cards/). Creates docs/adrs/ with stub README. Idempotent — never clobbers a live board. Run once, before /refine.
---
```

The body pattern adaptation:
- Doctrine source path: `${CLAUDE_PLUGIN_ROOT}/templates/` → `.opencode/doctrine/`
- Stamp `kanban_flow_version` from `.opencode/doctrine/config.md` frontmatter
- Idempotency guard: if `docs/cards/config.md` exists, stop
- Report next steps: edit config, run `/refine`, run `/kanban`

### 3. `/refine` → `.opencode/commands/refine.md`

**Source:** `skills/refine/SKILL.md` body, with path rewrites.

Read the source file, then apply path rewrites (same as above) and wrap in frontmatter:

```yaml
---
description: Populate or re-slice a project's backlog from the spec. Runs req-ids backfill, proposes ordered cards + milestones per INTAKE.md doctrine, dispatches card-intake-checker, presents proposal for driver approval. Intake only — never implements.
model: anthropic/claude-sonnet-4-6
---
```

Key path rewrites in the body:
- `${CLAUDE_PLUGIN_ROOT}/templates/` → `.opencode/doctrine/`
- Agent dispatch names unchanged (`card-intake-checker` matches `.opencode/agents/card-intake-checker.md`)

### 4. `/requirement` → `.opencode/commands/requirement.md`

**Source:** `skills/requirement/SKILL.md` body, with path rewrites.

Same process: read source, rewrite paths, wrap in frontmatter:

```yaml
---
description: Add, amend, or supersede one requirement on a running project. Interviews the driver, persists via req-ids skill, slices into cards, analyzes board impact, queues amendments for in-flight cards. Intake only — never implements.
model: anthropic/claude-sonnet-4-6
---
```

### 5. `/retro` → `.opencode/commands/retro.md`

**Source:** `skills/retro/SKILL.md` body, with path rewrites.

Frontmatter:

```yaml
---
description: Continuous process improvement for a kanban-flow project. Mines done cards' phase docs, check docs, and flow metrics for systemic patterns, then ships approved process changes (KNOWLEDGE entries, addendum rules, LOCAL- criteria, defect cards) as a PR.
model: anthropic/claude-sonnet-4-6
---
```

### 6. `/migrate` → `.opencode/commands/migrate.md`

**Source:** `skills/migrate/SKILL.md` body, adapted for OpenCode.

Frontmatter:

```yaml
---
description: One-time, idempotent cutover upgrading an older kanban-flow repo to plugin-owned doctrine. Deletes stale copies, folds customizations into PROTOCOL-ADDENDUM.md, preserves templates via template_overrides, adds config keys, stamps version, opens a PR.
---
```

Key adaptations in the body (beyond standard path rewrites):
- Detect stale copies by comparing against `.opencode/doctrine/` instead of `${CLAUDE_PLUGIN_ROOT}/templates/`
- Version key deltas updated as needed for any new config keys

## Verification

1. **All 6 files exist:**

```bash
ls plugins/kanban-flow/.opencode/commands/kanban.md
ls plugins/kanban-flow/.opencode/commands/kanban-init.md
ls plugins/kanban-flow/.opencode/commands/refine.md
ls plugins/kanban-flow/.opencode/commands/requirement.md
ls plugins/kanban-flow/.opencode/commands/retro.md
ls plugins/kanban-flow/.opencode/commands/migrate.md
```

2. **No `${CLAUDE_PLUGIN_ROOT}` references remain:**

```bash
grep -l '\${CLAUDE_PLUGIN_ROOT}' plugins/kanban-flow/.opencode/commands/*.md
# Must produce NO output
```

3. **Each file has valid YAML frontmatter** — starts with `---`, has a `description` key, and optionally a `model` key (kanban, refine, requirement, retro have model; kanban-init and migrate do not).

4. **Body content check** — spot-check that the kanban.md command contains the pre-flight gate preamble, the pump-gate dispatch instructions, and the re-run instructions.

## Dependencies

Task 01 (directories created), Task 02 (doctrine files exist for path references).
