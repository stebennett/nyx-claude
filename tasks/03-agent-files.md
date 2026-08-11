# Task 03: Agent Files — 13 Subagents with Frontmatter + Path Rewrites

## Why

The kanban-flow plugin defines 13 agents in `agents/*.md`. Each agent must be converted to OpenCode's agent format: a YAML frontmatter block followed by the prompt body. The primary changes are:

1. **Add YAML frontmatter** with `name`, `description`, `mode: subagent`, `model`, and `permission` fields
2. **Rewrite all `${CLAUDE_PLUGIN_ROOT}/templates/`** path references to `.opencode/doctrine/`
3. **Preserve the prompt body** unchanged (modulo path rewrites)

The model assignments all use `anthropic/claude-sonnet-4-6` except `pump-gate` and `card-deliverer` which use `anthropic/claude-haiku-4-5`.

## What

Create these 13 files under `plugins/kanban-flow/.opencode/agents/`:

| # | File | Source File | Model | Permissions |
|---|---|---|---|---|
| 1 | `pump-gate.md` | `agents/pump-gate.md` | `anthropic/claude-haiku-4-5` | edit: deny, bash: allow |
| 2 | `card-slicer.md` | `agents/card-slicer.md` | `anthropic/claude-sonnet-4-6` | edit: deny, bash: ask |
| 3 | `card-designer.md` | `agents/card-designer.md` | `anthropic/claude-sonnet-4-6` | edit: deny, bash: ask |
| 4 | `card-implementer.md` | `agents/card-implementer.md` | `anthropic/claude-sonnet-4-6` | edit: allow, bash: allow |
| 5 | `card-tester.md` | `agents/card-tester.md` | `anthropic/claude-sonnet-4-6` | edit: deny, bash: allow |
| 6 | `card-lens-reviewer.md` | `agents/card-lens-reviewer.md` | `anthropic/claude-sonnet-4-6` | edit: deny, bash: allow |
| 7 | `card-deliverer.md` | `agents/card-deliverer.md` | `anthropic/claude-haiku-4-5` | edit: allow, bash: allow |
| 8 | `card-intake-checker.md` | `agents/card-intake-checker.md` | `anthropic/claude-sonnet-4-6` | edit: deny, bash: ask |
| 9 | `card-slice-checker.md` | `agents/card-slice-checker.md` | `anthropic/claude-sonnet-4-6` | edit: deny, bash: ask |
| 10 | `card-design-checker.md` | `agents/card-design-checker.md` | `anthropic/claude-sonnet-4-6` | edit: deny, bash: ask |
| 11 | `card-split-checker.md` | `agents/card-split-checker.md` | `anthropic/claude-sonnet-4-6` | edit: deny, bash: allow |
| 12 | `card-deliver-checker.md` | `agents/card-deliver-checker.md` | `anthropic/claude-sonnet-4-6` | edit: deny, bash: allow |
| 13 | `pr-splitter.md` | `agents/pr-splitter.md` | `anthropic/claude-sonnet-4-6` | edit: allow, bash: allow |

### Frontmatter Template (example for card-slicer)

```yaml
---
name: card-slicer
description: Right-size a backlog card before design. Determines whether a card is atomic (keep as one) or must be split into child cards, applying size_limit as a hard ceiling. Produces no code, needs no worktree. Returns slice.md or proposed_cards + dependents_rewire.
mode: subagent
model: anthropic/claude-sonnet-4-6
permission:
  edit: deny
  bash: ask
---
```

## How

For **each** of the 13 agents:

### Step 1: Read the source file

Read from `plugins/kanban-flow/agents/<name>.md`.

### Step 2: Extract the body and apply path rewrites

Replace ALL occurrences of `${CLAUDE_PLUGIN_ROOT}/templates/` with `.opencode/doctrine/` in the body text.

Example rewrites:
- `${CLAUDE_PLUGIN_ROOT}/templates/AGENT-PROTOCOL.md` → `.opencode/doctrine/AGENT-PROTOCOL.md`
- `${CLAUDE_PLUGIN_ROOT}/templates/checks/_method.md` → `.opencode/doctrine/checks/_method.md`
- `${CLAUDE_PLUGIN_ROOT}/templates/checks/design.md` → `.opencode/doctrine/checks/design.md`
- `${CLAUDE_PLUGIN_ROOT}/templates/lenses/_shared.md` → `.opencode/doctrine/lenses/_shared.md`
- `${CLAUDE_PLUGIN_ROOT}/templates/testing/DIAGNOSIS.md` → `.opencode/doctrine/testing/DIAGNOSIS.md`

**Important:** The body text may contain these references in various forms:
- Full path: `${CLAUDE_PLUGIN_ROOT}/templates/checks/_method.md`
- Embedded in prose: "read `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md` for..."
- In code blocks or YAML examples: `doctrine: ${CLAUDE_PLUGIN_ROOT}/templates/checks/_method.md`

Replace every occurrence.

### Step 3: Write the OpenCode agent file

Write to `plugins/kanban-flow/.opencode/agents/<name>.md` with:
1. The YAML frontmatter (matching the agent's name, description, model, and permissions from the table above)
2. A blank line after the closing `---`
3. The rewritten body text

### Agent Descriptions and Permissions Table

| Agent | Description | Edit | Bash |
|---|---|---|---|
| `pump-gate` | Pre-flight gate: cheap run-vs-idle decision from mechanical file-header probes. Returns decision: run|idle with structured summary. Errs toward run on any ambiguity. Writes no state. | deny | allow |
| `card-slicer` | Right-size a backlog card before design. Determines whether a card is atomic (keep as one) or must be split into child cards, applying size_limit as a hard ceiling. Produces no code, needs no worktree. Returns slice.md or proposed_cards + dependents_rewire. | deny | ask |
| `card-designer` | Scope and design one card. Restates intent, sharpens acceptance criteria, chooses approach with alternatives, writes TDD-ready file-level task list, states test strategy. Produces design.md. Can rework from design PR comments. | deny | ask |
| `card-implementer` | Implement one card TDD. Three modes: Fresh (execute design task list), Rework (fix blocking tester/reviewer/CI findings), PR-comment (address human review comments). Uses Conventional Commits, stays in scope. | allow | allow |
| `card-tester` | Run full test suite, coverage, property tests, lint/types gates, and optional test levels in a worktree. Classifies every blocker as product/test/environment/flake. Environment lifecycle with trap-guarded teardown. Never fixes code. | deny | allow |
| `card-lens-reviewer` | One expert on the review panel. Reviews a worktree diff through exactly one lens (from .opencode/doctrine/lenses/). Slice mode: reviews only a slice's paths for criteria trace + standalone check. Reports phase_doc with findings, blocking findings rework the implementer. | deny | allow |
| `card-deliverer` | Ship one PR. Design mode: rebase docs-only branch, verify docs-only diff, push, open design PR. Implementation/slice mode: rebase on main, confirm green, push, open PR. Only agent permitted to mutate GitHub. Never deletes original branch. | allow | allow |
| `card-intake-checker` | Check a set of proposed kanban cards BEFORE the driver sees them. Vets against INT-* criteria: observable ACs, resolved reqs, vertical slices, coverage, no overlap, acyclic DAG, consistent milestones, no card exceeds size_limit. Returns estimated_lines per card. Terminal checker. | deny | ask |
| `card-slice-checker` | Check one slice verdict against SLC-* criteria: verdict correctness, independent size estimate, child vertical slices, child ACs, no-loss, dependents rewire, acyclic DAG. Derives own view from spec before reading slice.md. Terminal checker. | deny | ask |
| `card-design-checker` | Check one design before the design gate. Vets against DSG-* criteria: AC coverage, spec fidelity, TDD tasks, doctrine conformance, ADR ledger, knowledge, scope, no-code, and conditional levels/seams/data. Derives own task list before reading design.md. Terminal checker. | deny | ask |
| `card-split-checker` | Check pr-splitter's carve against SPL-* criteria. Re-derives change set from NAMED ORIGINAL BRANCH with --no-renames on every --name-status. Verifies SPL-NO-LOSS (set-equality both directions), SPL-GREEN, SPL-SIZE, SPL-ORDER, SPL-FILES, SPL-COHERENT. Terminal checker. | deny | allow |
| `card-deliver-checker` | Check ONE open PR (design, implementation, or slice k of N). DLV-* criteria: targets main, body claims true, size advisory, docs ride PR, no code in design PRs, CI green/running. Read-only. Returns phase_doc named by mode. | deny | allow |
| `pr-splitter` | Carve an oversized reviewed branch into ordered whole-file slices. Proves each independently green in a bootstrap throwaway worktree. Three rules: ground truth from named branch, --no-renames on every --name-status, never touches card's own worktree. Refusal is a first-class outcome. | allow | allow |

## Verification

For **each** of the 13 agent files, verify:

1. **File exists** at `plugins/kanban-flow/.opencode/agents/<name>.md`
2. **YAML frontmatter is valid** — starts with `---`, has `name`, `description`, `mode: subagent`, `model`, and `permission:` with `edit` and `bash` keys
3. **Model assignment is correct** per the table above
4. **No `${CLAUDE_PLUGIN_ROOT}`** references remain in the file:

```bash
# Run this for all agent files
grep -l '\${CLAUDE_PLUGIN_ROOT}' plugins/kanban-flow/.opencode/agents/*.md
# Must produce NO output (no files found)
```

5. **Match count**: Exactly 13 files exist in `plugins/kanban-flow/.opencode/agents/`

```bash
ls plugins/kanban-flow/.opencode/agents/*.md | wc -l
# Must be 13
```

6. **Every agent from the source directory has a corresponding OpenCode agent**:

```bash
cd plugins/kanban-flow
for f in agents/*.md; do
  target=".opencode/agents/$(basename "$f")"
  [ -f "$target" ] || echo "MISSING: $target"
done
# Must produce no output
```

## Dependencies

Task 01 (directories created), Task 02 (doctrine files exist for path verification).
