# kanban-flow → OpenCode Native Migration Plan

## Overview

The kanban-flow plugin (v0.10.0) is a **hooks-free** Claude Code plugin — it consists
entirely of Markdown-defined skills, agents, and shared doctrine/template files. No event
hooks, no TypeScript, no runtime code. This makes migration to OpenCode straightforward:
everything maps to OpenCode's native `commands/`, `skills/`, and `agents/` file-based
conventions.

**No TypeScript plugin code is required.**

---

## 1. Architecture Mapping

| Claude Code | OpenCode | Rationale |
|---|---|---|
| Skill (slash-command-triggered workflow: `/kanban`, `/refine`) | **Command** (`.opencode/commands/<name>.md`) | User-invoked action with `template` prompt |
| Skill (domain knowledge: `adr`, `req-ids`) | **Skill** (`.opencode/skills/<name>/SKILL.md`) | Context-loaded via description matching |
| Agent (dispatched subagent) | **Agent** (`.opencode/agents/<name>.md`) | Subagent with `model`, `permission`, prompt body |
| `${CLAUDE_PLUGIN_ROOT}/templates/` | `.opencode/doctrine/` | Referenced by agents as file paths |
| `/loop /kanban` (continuous pump) | `/kanban` single-pump + user re-runs | OpenCode has no `/loop`; session-based |
| `pump-gate` idle-fast-path | Embedded in `/kanban` command preamble | No loop means no idle-detection for cost savings — still useful to avoid loading the ~800-line orchestrator body on a quiet board |
| Plugin marketplace install | Manual copy or symlink to `.opencode/` | No npm-package plugin needed |
| `skills/kanban/references/pump.md` | `.opencode/skills/kanban-orchestrator/SKILL.md` | References folded in |
| `skills/kanban/references/split-shipping.md` | Inline in orchestrator SKILL | |
| `skills/kanban/references/reconcile-edge-cases.md` | Inline in orchestrator SKILL | |

---

## 2. File Layout

All files live under `.opencode/` in the target project, or in this repo for distribution:

```
.opencode/
├── commands/
│   ├── kanban.md              # Orchestrator — single pump cycle (Opus → Sonnet)
│   ├── kanban-init.md         # Scaffold board + config (user default model)
│   ├── refine.md              # Whole-backlog intake from spec (Opus → Sonnet)
│   ├── requirement.md         # Single-requirement intake, mid-project (Opus → Sonnet)
│   ├── retro.md               # Continuous process improvement (Opus → Sonnet)
│   └── migrate.md             # One-time board upgrade (user default model)
│
├── skills/
│   ├── kanban-orchestrator/
│   │   └── SKILL.md           # Full §0–§7 state machine (~800 lines from pump.md + edge-cases + split-shipping)
│   ├── adr/
│   │   └── SKILL.md           # ADR format, numbering, supersede conventions
│   └── req-ids/
│       └── SKILL.md           # REQ id format, allocation, backfill
│
├── agents/
│   │                           ## PRODUCER AGENTS ##
│   ├── card-slicer.md         # Right-size a card before design (Sonnet)
│   ├── card-designer.md       # Technical design + file-level TDD task list (Sonnet)
│   ├── card-implementer.md    # TDD implementation in worktree (Sonnet)
│   ├── card-deliverer.md      # Push branch + open PR (only agent touching GitHub) (Sonnet)
│   ├── pr-splitter.md         # Carve oversized branch into whole-file slices (Sonnet)
│   │                           ## CHECKER AGENTS (terminal — nothing checks a checker) ##
│   ├── card-tester.md         # Run suites, property/lint/coverage gates, classify failures (Sonnet)
│   ├── card-lens-reviewer.md  # One-lens code review of worktree diff, before any PR (Sonnet)
│   ├── card-intake-checker.md  # Verify proposed card set against INT-* criteria (Sonnet)
│   ├── card-slice-checker.md   # Verify slicer output against SLC-* criteria (Sonnet)
│   ├── card-design-checker.md  # Verify design against DSG-* criteria (Sonnet)
│   ├── card-split-checker.md   # Verify PR split against SPL-* criteria (Sonnet)
│   ├── card-deliver-checker.md # Verify open PR against DLV-* criteria (Sonnet)
│   │                           ## PRE-FLIGHT ##
│   └── pump-gate.md           # Run-vs-idle decision from cheap probes (Haiku)
│
└── doctrine/                  # Shared templates — read live by agents, never copied into project
    ├── AGENT-PROTOCOL.md      # Phase agent contract: dispatch params, sole-writer invariant, structured return
    ├── PROTOCOL-ADDENDUM.md   # Project-specific layered doctrine + LOCAL- check criteria
    ├── INTAKE.md              # Card creation doctrine: numbering, vertical slices, milestones, check protocol
    ├── config.md              # Project config scaffold (WIP limits, gate policy, size_limit, layers, testing)
    ├── card-template.md       # Card.md frontmatter schema (13 fields + reworks counters)
    ├── pr-template.md         # Implementation PR body template
    ├── design-pr-template.md  # Design PR body template
    ├── checks/                # 7 files — one per checker target + shared method + id index
    │   ├── _method.md         # Shared checker discipline (derive independently, verdict every criterion, evidence over adjectives, blocking bar, rebuttal test) + return format + size-estimate appendix
    │   ├── design.md          # DSG-AC-COVERED, DSG-SPEC-FIDELITY, DSG-TASK-TDD, DSG-DOCTRINE, DSG-ADR-NEEDED, DSG-KNOWLEDGE, DSG-SCOPE, DSG-NO-CODE + conditional DSG-LEVELS/DSG-SEAMS/DSG-DATA
    │   ├── intake.md          # INT-AC-OBSERVABLE, INT-REQ-RESOLVES, INT-VERTICAL, INT-COVERAGE, INT-NO-OVERLAP, INT-DAG, INT-MILESTONE, INT-SIZED
    │   ├── slice.md           # SLC-VERDICT, SLC-SIZE, SLC-CHILD-VERTICAL, SLC-CHILD-AC, SLC-NO-LOSS, SLC-REWIRE, SLC-DAG
    │   ├── split.md           # SPL-NO-LOSS, SPL-GREEN, SPL-SIZE, SPL-ORDER, SPL-FILES, SPL-COHERENT
    │   ├── deliver.md         # DLV-BASE, DLV-BODY-TRUE, DLV-SIZE, DLV-DOCS, DLV-PURITY, DLV-CI
    │   └── ids.md             # Per-target criterion id index (completeness valve reads this)
    ├── lenses/                # 11 files — one per review lens + shared etiquette
    │   ├── _shared.md         # Binding etiquette (lens tag, severity, anchoring, ≤10 findings, one good thing) + method (map pass then line pass, verify before filing, rebuttal test)
    │   ├── acceptance.md      # Traceability from acceptance criteria to tests, scope enforcement
    │   ├── design.md          # Architecture, layer purity, dependency direction, extensibility
    │   ├── security.md        # Trust boundaries: API input, DB queries, outbound HTTP, secrets, deps
    │   ├── functionality.md   # Correctness: trace code paths with real values, edge-case sweep
    │   ├── simplicity.md      # YAGNI: unnecessary indirection, drive-by refactors, redundant abstraction
    │   ├── readability.md      # Naming, comments, consistency, doc freshness
    │   ├── tests.md           # Test provenance, outcome coverage, branch coverage, level delivery, seam audit
    │   ├── experience.md      # Static UX review: state coverage, selector discipline, keyboard/focus, a11y structure
    │   ├── python.md          # Python/FastAPI/SQLAlchemy: Decimal/money, typing, idioms
    │   └── typescript.md      # React/Vite: type safety, hooks correctness, data flow, design tokens
    ├── testing/               # 4 files
    │   ├── LEVELS.md          # Test level definitions: scope (card|pr), derive map, seams, env lifecycle
    │   ├── DIAGNOSIS.md       # Failure classification: product/test/environment/flake with proof requirements
    │   ├── JOURNEYS.md        # E2E journey doctrine: 5-10 product-owned journeys, Playwright authoring rules, CI workflow shape
    │   └── EXPERIENCE.md      # Experience testing: static lens review vs. runtime CI gates vs. human-judged artefacts
    └── board/                 # 3 files (scaffold starters, copied by /kanban-init)
        ├── BOARD.md           # Empty kanban board with 10 status columns
        ├── KNOWLEDGE.md       # Cross-card knowledge: Conventions, Gotchas, Glossary
        └── MILESTONES.md      # Ordered delivery milestones template
```

---

## 3. Model Assignments

The original plugin uses three Anthropic model tiers (Opus, Sonnet, Haiku) with careful
assignment based on each agent's judgment surface. OpenCode currently supports
`anthropic/claude-sonnet-4-6` and `anthropic/claude-haiku-4-5`. The migration collapses
Opus and Sonnet into `sonnet-4-6` (the strongest available model) while preserving the
Haiku distinction:

| Agent | OpenCode Model | Why |
|---|---|---|
| **kanban orchestrator** (command + skill) | `anthropic/claude-sonnet-4-6` | Completeness valve (comparing checker id sets), stamping verdicts, adjudicating dropped findings — rubber-stamping here manufactures false confidence. The original ran on Opus for exactly this reason. |
| `card-intake-checker` | `anthropic/claude-sonnet-4-6` | Independent size estimation across multiple proposed cards + coverage analysis against spec. Original: Opus. |
| `card-slice-checker` | `anthropic/claude-sonnet-4-6` | Independent sizing, vertical-slice judgment, DAG walk. Original: Opus. |
| `card-design-checker` | `anthropic/claude-sonnet-4-6` | Independent task derivation before reading the design, spec-fidelity verification. Original: Opus. |
| `card-split-checker` | `anthropic/claude-sonnet-4-6` | Independent ground-truth derivation from named branch with `--no-renames`, `SPL-NO-LOSS` set-equality proof both directions. Original: Opus. |
| `card-slicer` | `anthropic/claude-sonnet-4-6` | Architectural decomposition requiring domain understanding + size estimation. Original: Opus. |
| `pr-splitter` | `anthropic/claude-sonnet-4-6` | Complex carve with bootstrapped throwaway worktrees and per-slice green proof. Original: Opus. |
| `card-designer` | `anthropic/claude-sonnet-4-6` | Structured design work with file-level task decomposition. Original: Sonnet. |
| `card-implementer` | `anthropic/claude-sonnet-4-6` | Code generation with TDD, Conventional Commits. Original: Sonnet. |
| `card-tester` | `anthropic/claude-sonnet-4-6` | Runs test suites + card-scope levels, classifies failures into product/test/environment/flake. Needs judgment; original uses Sonnet when levels configured, Haiku otherwise. |
| `card-lens-reviewer` | `anthropic/claude-sonnet-4-6` | Deep code review through a single lens. Full panel: original Opus. Slice-mode acceptance re-run: original Sonnet. |
| `card-deliverer` | `anthropic/claude-sonnet-4-6` | Mechanical: rebase, push, open PR. Original: Sonnet. |
| `card-deliver-checker` | `anthropic/claude-sonnet-4-6` | gh/git read-only verification of an open PR. Original: Sonnet. |
| `pump-gate` | `anthropic/claude-haiku-4-5` | Mechanical file-header scanning via `ls`/`grep`/`git` — no state mutation, no judgment, errs toward `run`. Original: Haiku. |
| `/refine`, `/requirement` commands | `anthropic/claude-sonnet-4-6` | Intake analysis and proposal generation. Original: Opus. |
| `/retro` command | `anthropic/claude-sonnet-4-6` | Systemic pattern mining from done cards. Original: Opus. |

**Future upgrade path:** When OpenCode adds support for stronger Anthropic models (e.g.
`claude-opus-4-6`), the orchestrator, the four key checkers (intake, slice, design, split),
`card-slicer`, and `pr-splitter` should move to that tier. The original RATIONALE for
Opus assignment applies undiminished.

**Why no agent runs on the user's default model:** Every dispatched agent's model is
pinned in its configuration. The orchestrator command can use the user's default model
since the heavy reasoning work is delegated to pinned agents — this is consistent with
the original plugin design where only the orchestrator's session model matters and
dispatched agents are pinned per dispatch.

---

## 4. Conversion Details — Commands

Each Claude Code skill that is a **user-invoked workflow** becomes an OpenCode command
(file: `.opencode/commands/<name>.md`). OpenCode commands have a `template` (the prompt
body) and optional frontmatter (`description`, `model`, `agent`).

### 4.1 `/kanban`

**File:** `.opencode/commands/kanban.md`

**Frontmatter:**
```yaml
description: Run one kanban-flow pump cycle — reconcile merged PRs, schedule ready cards, advance in-flight cards through slice→design→implement→test→review→deliver. Re-run after a PR lands, a review completes, or a gate decision is made.
model: anthropic/claude-sonnet-4-6
```

**Template body (lean front-door):**
```markdown
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

**Key adaptation from the original:** The Claude Code plugin uses `/loop /kanban` — the
loop repeatedly invokes the skill at an interval. OpenCode has no loop primitive. Each
`/kanban` invocation runs exactly one pump and stops. The user re-runs it manually.
The pump-gate still fires as a cheap pre-flight (avoids loading the ~800-line
orchestrator body when the board is truly quiet), but its token-saving motivation is
weaker since every pump is a deliberate user action rather than a background cycle.

### 4.2 `/kanban-init`

**File:** `.opencode/commands/kanban-init.md`

**Frontmatter:**
```yaml
description: Scaffold a repo for kanban-flow. Copies config.md, PROTOCOL-ADDENDUM.md, BOARD.md, KNOWLEDGE.md, and MILESTONES.md into the board dir (default docs/cards/). Creates docs/adrs/ with stub README. Idempotent — never clobbers a live board. Run once, before /refine.
```

**Template body:** The original `skills/kanban-init/SKILL.md` body, adapted:
- Doctrine path: `${CLAUDE_PLUGIN_ROOT}/templates/` → `.opencode/doctrine/`
- Stamp `kanban_flow_version` from `.opencode/doctrine/config.md` frontmatter
- Idempotency guard: if `docs/cards/config.md` exists, stop
- Report next steps: edit config, run `/refine`, run `/kanban`

### 4.3 `/refine`

**File:** `.opencode/commands/refine.md`

**Frontmatter:**
```yaml
description: Populate or re-slice a project's backlog from the spec. Runs req-ids backfill, proposes ordered cards + milestones per INTAKE.md doctrine, dispatches card-intake-checker, presents proposal for driver approval. Intake only — never implements.
model: anthropic/claude-sonnet-4-6
```

**Template body:** The original `skills/refine/SKILL.md` body, adapted:
- All `${CLAUDE_PLUGIN_ROOT}/templates/` → `.opencode/doctrine/`
- Agent dispatch: `card-intake-checker` name unchanged (matches `.opencode/agents/card-intake-checker.md`)

### 4.4 `/requirement`

**File:** `.opencode/commands/requirement.md`

**Frontmatter:**
```yaml
description: Add, amend, or supersede one requirement on a running project. Interviews the driver, persists via req-ids skill, slices into cards, analyzes board impact, queues amendments for in-flight cards. Intake only — never implements.
model: anthropic/claude-sonnet-4-6
```

**Template body:** The original `skills/requirement/SKILL.md` body, adapted identically.

### 4.5 `/retro`

**File:** `.opencode/commands/retro.md`

**Frontmatter:**
```yaml
description: Continuous process improvement for a kanban-flow project. Mines done cards' phase docs, check docs, and flow metrics for systemic patterns, then ships approved process changes (KNOWLEDGE entries, addendum rules, LOCAL- criteria, defect cards) as a PR.
model: anthropic/claude-sonnet-4-6
```

**Template body:** The original `skills/retro/SKILL.md` body.

### 4.6 `/migrate`

**File:** `.opencode/commands/migrate.md`

**Frontmatter:**
```yaml
description: One-time, idempotent cutover upgrading an older kanban-flow repo to plugin-owned doctrine. Deletes stale copies, folds customizations into PROTOCOL-ADDENDUM.md, preserves templates via template_overrides, adds config keys, stamps version, opens a PR.
```

**Template body:** The original `skills/migrate/SKILL.md` body, adapted:
- Detect stale copies by comparing against `.opencode/doctrine/` instead of `${CLAUDE_PLUGIN_ROOT}/templates/`
- Version key deltas updated as needed for any new config keys

---

## 5. Conversion Details — Skills

Each Claude Code skill that provides **domain knowledge** (format specifications,
conventions) becomes an OpenCode skill. These load into the session context when their
description matches the conversation.

### 5.1 kanban-orchestrator

**File:** `.opencode/skills/kanban-orchestrator/SKILL.md`

**Frontmatter:**
```yaml
name: kanban-orchestrator
description: Use ONLY when executing a kanban-flow pump cycle triggered by /kanban. Contains the full §0–§7 state machine: §0 Reconcile (merged PRs, amendment queue, legacy normalization), §1 Load state (config, cards, criterion id sets, dispatch/model table), §2 Render board (sole writer of BOARD.md), §3 Resolve gates & blockers, §4 Schedule (WIP limits, ready cards ranked by layer), §5 Advance in-flight cards through slice→design→implement→test→review→deliver (dispatch contracts, check-doc discipline, review panel, persist results), §6 PR open (CI gate, review-complete addressing), §7 Report. Loads reference procedures for reconcile edge cases and split shipping. Do NOT use for general kanban questions or unrelated orchestration tasks.
```

**Body:** The complete state machine, incorporating all three reference files:
- The main pump body (from `skills/kanban/references/pump.md`, ~800 lines)
- Reconcile edge cases (from `skills/kanban/references/reconcile-edge-cases.md`): closed PR recovery, amendment drain, legacy normalization, orphan-PR adoption, completeness backstop
- Split shipping (from `skills/kanban/references/split-shipping.md`): measuring the branch diff, dispatching `pr-splitter` + `card-split-checker` + acceptance re-run, shipping N slices sequentially, the "never split a split" rule

All `${CLAUDE_PLUGIN_ROOT}` paths replaced: `.opencode/doctrine/`.

The dispatch/model table (pinning each agent's model) is preserved verbatim — it
defines which agent to dispatch, which model tier, and for which card phase/action.

### 5.2 adr

**File:** `.opencode/skills/adr/SKILL.md`

**Frontmatter:**
```yaml
name: adr
description: Use when creating or managing Architecture Decision Records (ADRs) in a kanban-flow project. Sole authority for Cognitect ADR format (Title, Context, Decision, Status, Consequences), numbering (max+1 across main and card adrs: reservations), supersede handling (set superseded ADR status, update index), bidirectional card linking (append to card's adrs: list), and docs/adrs/ layout. Invoked only by the /kanban orchestrator when a phase agent proposes ADRs — never use standalone.
```

**Body:** The original `skills/adr/SKILL.md` body, with paths adapted. Key invariants
preserved:
- Sole-writer authority for `docs/adrs/`
- ADR format: Cognitect lightweight
- Storage: `docs/adrs/README.md` (index), `NNNN-<kebab-title>.md` files
- Numbering spans both committed files and card `adrs:` frontmatter reservations
- ADRs immutable once `Accepted`; statuses: `Accepted | Superseded | Deprecated`

### 5.3 req-ids

**File:** `.opencode/skills/req-ids/SKILL.md`

**Frontmatter:**
```yaml
name: req-ids
description: Use when assigning or managing REQ-NNN ids in a project spec. Sole authority for REQ format (`### REQ-NNN — title` under `## <Area>` headings, `**Status:** active | superseded by REQ-NNN`), id allocation (max+1), and three operations: backfill (id an un-id'd spec — idempotent), allocate (add a new requirement in a named area), supersede (retire requirements by setting status — never delete, never edit prose). Invoked by /refine and /requirement only.
```

**Body:** The original `skills/req-ids/SKILL.md` body, with paths adapted:
- Writes `spec_path` file (from `config.md`) but never commits
- Requirements never deleted, renumbered, or reused
- `backfill` is idempotent

---

## 6. Conversion Details — Agents

All 13 agents from `agents/` become `.opencode/agents/<name>.md` files. Each file
contains OpenCode frontmatter followed by the agent's prompt body. The prompt body is
the original agent file content with path references updated
(`${CLAUDE_PLUGIN_ROOT}/templates/` → `.opencode/doctrine/`).

### 6.1 Standard Agent Frontmatter Pattern

All agents use the `subagent` mode. Permissions are assigned per agent:

| Agent | Permission Profile |
|---|---|
| `card-slicer` | `{ edit: deny, bash: ask }` — no code, no worktree; structured return only |
| `card-designer` | `{ edit: deny, bash: ask }` — docs-only (no code); design branch is docs-only |
| `card-implementer` | `{ edit: allow, bash: allow }` — primary code producer in worktree |
| `card-tester` | `{ edit: deny, bash: allow }` — runs test commands, never fixes code |
| `card-lens-reviewer` | `{ edit: deny, bash: allow }` — reviews diff, never writes |
| `card-deliverer` | `{ edit: allow, bash: allow }` — pushes branch, opens PR (only agent touching GitHub) |
| `card-intake-checker` | `{ edit: deny, bash: ask }` — verdict only; no mutation |
| `card-slice-checker` | `{ edit: deny, bash: ask }` — verdict only |
| `card-design-checker` | `{ edit: deny, bash: ask }` — verdict only |
| `card-split-checker` | `{ edit: deny, bash: allow }` — derives git ground truth via `--no-renames` diff, verdict only |
| `card-deliver-checker` | `{ edit: deny, bash: allow }` — reads `gh pr view`/`gh pr checks`, verdict only |
| `pr-splitter` | `{ edit: allow, bash: allow }` — creates branches, bootstraps throwaway worktrees |
| `pump-gate` | `{ edit: deny, bash: allow }` — read-only `ls`/`grep`/`git fetch` probes |

### 6.2 Example: card-slicer

**File:** `.opencode/agents/card-slicer.md`

```markdown
---
name: card-slicer
description: Right-size a backlog card before design. Determines whether a card is atomic (keep as one) or must be split into child cards, applying size_limit as a hard ceiling. Produces no code, needs no worktree. Returns slice.md or proposed_cards + dependents_rewire.
mode: subagent
model: anthropic/claude-sonnet-4-6
permission:
  edit: deny
  bash: ask
---

[original agents/card-slicer.md body with .opencode/doctrine/ paths]
```

### 6.3 Example: card-intake-checker

**File:** `.opencode/agents/card-intake-checker.md`

```markdown
---
name: card-intake-checker
description: Check a set of proposed kanban cards before the driver sees them. Verifies against INT-* criteria: acceptance criteria are observable, requirements are resolved, cards are vertical slices, coverage is complete, no overlap, DAG is acyclic, milestones are consistent, no card exceeds size_limit. Terminal checker — nothing checks this checker.
mode: subagent
model: anthropic/claude-sonnet-4-6
permission:
  edit: deny
  bash: ask
---

[original agents/card-intake-checker.md body with .opencode/doctrine/ paths]
```

### 6.4 Agent Dispatch Protocol (unchanged)

The orchestrator dispatches agents via OpenCode's Task tool (`subagent_type: "card-slicer"`,
etc.). The dispatch contract from `AGENT-PROTOCOL.md` is preserved verbatim:

- Each agent receives its inputs in the dispatch prompt (card ID, worktree, phase docs,
  doctrine paths)
- Each agent returns a YAML `result` block with `status`, `phase`, `phase_doc`, and any
  `gate`/`blockers`/`open_questions`/`proposed_adrs`/`proposed_cards`
- Checkers return `verdict: pass|fail` with `findings` and `phase_doc` (frontmatter with
  `criteria:` map)
- The orchestrator parses the structured return exactly as in the original

### 6.5 Checker Terminal Contract

The original plugin's rule — *"checkers are terminal: nothing checks a checker; the human
is the backstop at the intake and slice gates and the two PR merges"* — holds. The
completeness valve (§5) and the discipline (`checks/_method.md`) are the safeguards, not
a meta-checker. This is preserved by construction.

---

## 7. Shared Doctrine

The `doctrine/` directory preserves all template files **unchanged in content** from the
original plugin's `templates/` directory. Only path references inside agent/command/skill
bodies change.

### 7.1 Path Rewriting Rule

| Original | Replacement |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}/templates/AGENT-PROTOCOL.md` | `.opencode/doctrine/AGENT-PROTOCOL.md` |
| `${CLAUDE_PLUGIN_ROOT}/templates/checks/_method.md` | `.opencode/doctrine/checks/_method.md` |
| `${CLAUDE_PLUGIN_ROOT}/templates/checks/<target>.md` | `.opencode/doctrine/checks/<target>.md` |
| `${CLAUDE_PLUGIN_ROOT}/templates/lenses/_shared.md` | `.opencode/doctrine/lenses/_shared.md` |
| `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md` | `.opencode/doctrine/INTAKE.md` |
| `${CLAUDE_PLUGIN_ROOT}/templates/testing/` | `.opencode/doctrine/testing/` |
| `<board_dir>/PROTOCOL-ADDENDUM.md` | `docs/cards/PROTOCOL-ADDENDUM.md` (unchanged — project-owned) |
| `<board_dir>/config.md` | `docs/cards/config.md` (unchanged — project-owned) |

### 7.2 Which Files Are Project-Owned vs. Plugin-Owned

**Plugin-owned** (in `.opencode/doctrine/`, read live, never copied):
- `AGENT-PROTOCOL.md`, `INTAKE.md`, `card-template.md`, `pr-template.md`, `design-pr-template.md`
- `checks/` (all 7 files), `lenses/` (all 11 files), `testing/` (all 4 files)

**Project-owned** (in `docs/cards/`, scaffolded by `/kanban-init`, editable):
- `config.md`, `PROTOCOL-ADDENDUM.md`, `BOARD.md`, `KNOWLEDGE.md`, `MILESTONES.md`

This matches the original plugin's ownership model exactly.

---

## 8. Key Semantic Adaptations

### 8.1 No `/loop` — Single-Pump Model

**Original:** Claude Code's `/loop` runs `/kanban` at an interval (e.g. 60s).
**OpenCode:** Session-based, no loop primitive.

**Adaptation:** `/kanban` runs exactly one pump and stops. The command's closing message
tells the user when to re-run:

- *"Run `/kanban` again when a PR merges, a review is complete, or you've made a gate decision."*

The pump-gate pre-flight still fires: on a quiet board it prints a one-line summary and
stops without loading the orchestrator body. This keeps the cheap-first-pass benefit even
without a loop.

### 8.2 No `${CLAUDE_PLUGIN_ROOT}`

**Original:** Claude Code injects the plugin install path as `CLAUDE_PLUGIN_ROOT`.
**OpenCode:** No equivalent; doctrine and agents live inside the project or a referenced path.

**Adaptation:** All references use relative paths from the project root (`.opencode/doctrine/`).
The `board_dir` config key (`config.md`) defaults to `docs/cards` — if a project moves
the board, only that key changes.

### 8.3 Agent Dispatch Mechanism

**Original:** The orchestrator dispatches agents by name via Claude Code's Task tool.
**OpenCode:** The Task tool accepts `subagent_type: "<name>"` where `<name>` matches
`.opencode/agents/<name>.md` exactly.

**Adaptation:** Agent names remain unchanged. The orchestrator's dispatch table stays
verbatim. OpenCode's Task tool handles the dispatch identically.

### 8.4 Structured Return Parsing

**Original:** The orchestrator parses YAML `result` blocks from agent responses.
**OpenCode:** Agent responses are returned to the orchestrator command's context, where
the same YAML parsing logic applies.

**Adaptation:** No change needed. The command body contains the same parsing
instructions from the original `AGENT-PROTOCOL.md`.

### 8.5 Pump-Gate in a Single-Pump Model

**Original:** The pump-gate's primary value is avoiding Opus context burn on idle
loop cycles.
**OpenCode:** Every pump is a deliberate user action, so the token-saving argument is
weaker. However, the pump-gate still provides value by:
- Telling the user immediately that the board has no work (avoids loading the
  ~800-line orchestrator body)
- Scanning for merges/CI/reviews without reading any card files
- Serving as the same `run`/`idle` predicate for consistency

The `pump_gate: off` config key remains as a debugging escape hatch.

### 8.6 Filtered Tool Commands (RTK)

The original CLAUDE.md notes an RTK proxy that rewrites common shell commands. OpenCode
has no RTK concept — all `Bash` commands run directly. Agents that previously assumed RTK
proxying (`ls`, `grep`, `git`) work unchanged.

---

## 9. Installation

### Option A: Copy from the marketplace repo

```bash
# From this repository, copy the migration artifacts into your project
cp -r /path/to/nyx-claude/plugins/kanban-flow/.opencode .opencode
```

OpenCode auto-discovers `.opencode/commands/`, `.opencode/skills/`, and
`.opencode/agents/` on startup.

### Option B: Symlink (live updates)

```bash
ln -s /path/to/nyx-claude/plugins/kanban-flow/.opencode .opencode
```

Plugin doctrine updates propagate automatically without re-copying.

### Option C: Reference via skills.paths

If the artifacts stay in this repo, reference them in `opencode.json`:

```json
{
  "skills": {
    "paths": ["/path/to/nyx-claude/plugins/kanban-flow/.opencode/skills"]
  }
}
```

Commands and agents must each be in the local project's `.opencode/` or in global config
(`~/.config/opencode/agents/`). Skills can live externally via `skills.paths`.

### Post-Install Steps

1. **Restart OpenCode** (config is loaded on startup)
2. Run `/kanban-init` to scaffold `docs/cards/` (board, config, addendum)
3. Edit `docs/cards/config.md` — set `spec_path`, adjust `layers`, set `gh_command` if using a bot identity
4. Run `/refine` to populate the backlog from your spec
5. Run `/kanban` to drive cards through the board. Re-run when:
   - A PR merges
   - A design review is complete
   - A gate awaits a driver decision
   - You've answered a `needs-input` question

---

## 10. `opencode.json` Registration

OpenCode auto-discovers agents in `.opencode/agents/*.md` and commands in
`.opencode/commands/*.md`. Model assignment is done in frontmatter — no additional
`agent` key needed in `opencode.json` unless you need to override permissions or
disable an agent.

Minimal `opencode.json` additions (only if needed):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "agent": {
    "card-implementer": {
      "permission": {
        "edit": "allow",
        "bash": "allow"
      }
    },
    "card-deliverer": {
      "permission": {
        "edit": "allow",
        "bash": "allow"
      }
    },
    "pr-splitter": {
      "permission": {
        "edit": "allow",
        "bash": "allow"
      }
    }
  }
}
```

All other agents are auto-discovered with their frontmatter-configured models and
default permissions (`edit: deny`, `bash: ask`).

To increase subagent depth (the orchestrator dispatches agents that may themselves
dispatch the Task tool for file reading):

```json
{
  "subagent_depth": 2
}
```

---

## 11. Migration Checklist

### Files to Create

- [ ] `.opencode/commands/kanban.md`
- [ ] `.opencode/commands/kanban-init.md`
- [ ] `.opencode/commands/refine.md`
- [ ] `.opencode/commands/requirement.md`
- [ ] `.opencode/commands/retro.md`
- [ ] `.opencode/commands/migrate.md`
- [ ] `.opencode/skills/kanban-orchestrator/SKILL.md`
- [ ] `.opencode/skills/adr/SKILL.md`
- [ ] `.opencode/skills/req-ids/SKILL.md`
- [ ] `.opencode/agents/card-slicer.md`
- [ ] `.opencode/agents/card-designer.md`
- [ ] `.opencode/agents/card-implementer.md`
- [ ] `.opencode/agents/card-tester.md`
- [ ] `.opencode/agents/card-lens-reviewer.md`
- [ ] `.opencode/agents/card-deliverer.md`
- [ ] `.opencode/agents/card-intake-checker.md`
- [ ] `.opencode/agents/card-slice-checker.md`
- [ ] `.opencode/agents/card-design-checker.md`
- [ ] `.opencode/agents/card-split-checker.md`
- [ ] `.opencode/agents/card-deliver-checker.md`
- [ ] `.opencode/agents/pr-splitter.md`
- [ ] `.opencode/agents/pump-gate.md`
- [ ] `.opencode/doctrine/` (all 30 files from `templates/`, copied verbatim)

### Path Rewrites in Agent/Command/Skill Bodies

- [ ] `${CLAUDE_PLUGIN_ROOT}/templates/` → `.opencode/doctrine/` in all 13 agents
- [ ] `${CLAUDE_PLUGIN_ROOT}/templates/` → `.opencode/doctrine/` in 6 command bodies
- [ ] `${CLAUDE_PLUGIN_ROOT}/templates/` → `.opencode/doctrine/` in 3 skill bodies
- [ ] `skills/kanban/references/*` content folded into `kanban-orchestrator/SKILL.md`

### Config Updates

- [ ] Add `subagent_depth: 2` to `opencode.json` if needed for nested agent dispatches
- [ ] Verify agent permissions in `opencode.json` (only producers write files)

### Validation

- [ ] Run `/kanban-init` on a clean project — verify scaffold includes all 5 files
- [ ] Run `/refine` on a project with a spec — verify card proposals + intake checker dispatch
- [ ] Run `/kanban` — verify pump-gate dispatches, orchestrator loads, one pump completes
- [ ] Verify agent dispatch works (Task tool finds agents by name in `.opencode/agents/`)
- [ ] Verify checker return protocol (completeness valve parses `criteria:` maps correctly)
- [ ] Verify `actual_lines` / `estimated_lines` cycle works end-to-end

---

## 12. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| **Orchestrator body too large for context.** The full state machine is ~800 lines + two reference files (~300 lines) ≈ 1,100 lines. This is large but intentionally complete. Mitigation: The pump-gate front-door avoids loading it on idle pumps. The original plugin loaded the same content. |
| **No `/loop` means cards advance slower.** True: unattended progress requires a loop. Mitigation: The command tells the user when to re-run. For unattended operation, the user could script external loop invocations. |
| **Sonnet-4-6 may not match Opus judgment.** The original used Opus for the orchestrator and key checkers with explicit rationale. Mitigation: Sonnet-4-6 is the strongest available model. When a stronger model becomes available in OpenCode, the affected agents should be upgraded per the future-upgrade path in §3. |
| **Agent dispatch via Task tool may have different context limits.** OpenCode subagents run in isolated contexts. Mitigation: The structured return protocol is explicit and self-contained — agents don't rely on shared session state. Each agent returns what it produces; the orchestrator is the sole writer of board state. |
| **Haiku model quality varies by provider.** If the user's Anthropic provider includes Haiku-4-5, it's sufficient for mechanical probes. If not, fall back to Sonnet for the pump-gate. Mitigation: The pump-gate errs toward `run` — a false-`run` costs one pump, a false-`idle` would starve the board. The asymmetry is safe. |
| **`config.md` path resolution.** The orchestrator reads `board_dir` from `config.md` and resolves doctrine paths relative to the project root. If a project has an unusual layout, paths may break. Mitigation: `config.md` is scaffolded by `/kanban-init` with conventional defaults. |