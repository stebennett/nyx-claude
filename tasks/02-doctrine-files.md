# Task 02: Doctrine Files — Copy Templates Verbatim

## Why

The kanban-flow plugin stores shared doctrine files (agent contracts, check criteria, review lenses, testing doctrine, board templates, PR templates, intake rules, card templates) in `templates/`. In the OpenCode migration, these become the `doctrine/` directory under `.opencode/`. The files are **copied verbatim** — no path rewrites are needed inside these files because they are the authoritative source consumed by agents/commands/skills at runtime.

The distinction between plugin-owned and project-owned files is preserved:
- **Plugin-owned** (in `.opencode/doctrine/`, read live, never copied): everything except `board/` and `config.md`
- **Project-owned** (scaffolded by `/kanban-init` into `docs/cards/`): `BOARD.md`, `KNOWLEDGE.md`, `MILESTONES.md` from `board/`, plus `config.md`, `PROTOCOL-ADDENDUM.md`

## What

Copy all 30 files from `plugins/kanban-flow/templates/` to `plugins/kanban-flow/.opencode/doctrine/`, preserving the directory structure:

| Source | Destination |
|---|---|
| `templates/AGENT-PROTOCOL.md` | `.opencode/doctrine/AGENT-PROTOCOL.md` |
| `templates/PROTOCOL-ADDENDUM.md` | `.opencode/doctrine/PROTOCOL-ADDENDUM.md` |
| `templates/INTAKE.md` | `.opencode/doctrine/INTAKE.md` |
| `templates/card-template.md` | `.opencode/doctrine/card-template.md` |
| `templates/config.md` | `.opencode/doctrine/config.md` |
| `templates/pr-template.md` | `.opencode/doctrine/pr-template.md` |
| `templates/design-pr-template.md` | `.opencode/doctrine/design-pr-template.md` |
| `templates/board/BOARD.md` | `.opencode/doctrine/board/BOARD.md` |
| `templates/board/KNOWLEDGE.md` | `.opencode/doctrine/board/KNOWLEDGE.md` |
| `templates/board/MILESTONES.md` | `.opencode/doctrine/board/MILESTONES.md` |
| `templates/checks/_method.md` | `.opencode/doctrine/checks/_method.md` |
| `templates/checks/deliver.md` | `.opencode/doctrine/checks/deliver.md` |
| `templates/checks/design.md` | `.opencode/doctrine/checks/design.md` |
| `templates/checks/ids.md` | `.opencode/doctrine/checks/ids.md` |
| `templates/checks/intake.md` | `.opencode/doctrine/checks/intake.md` |
| `templates/checks/slice.md` | `.opencode/doctrine/checks/slice.md` |
| `templates/checks/split.md` | `.opencode/doctrine/checks/split.md` |
| `templates/lenses/_shared.md` | `.opencode/doctrine/lenses/_shared.md` |
| `templates/lenses/acceptance.md` | `.opencode/doctrine/lenses/acceptance.md` |
| `templates/lenses/design.md` | `.opencode/doctrine/lenses/design.md` |
| `templates/lenses/experience.md` | `.opencode/doctrine/lenses/experience.md` |
| `templates/lenses/functionality.md` | `.opencode/doctrine/lenses/functionality.md` |
| `templates/lenses/python.md` | `.opencode/doctrine/lenses/python.md` |
| `templates/lenses/readability.md` | `.opencode/doctrine/lenses/readability.md` |
| `templates/lenses/security.md` | `.opencode/doctrine/lenses/security.md` |
| `templates/lenses/simplicity.md` | `.opencode/doctrine/lenses/simplicity.md` |
| `templates/lenses/tests.md` | `.opencode/doctrine/lenses/tests.md` |
| `templates/lenses/typescript.md` | `.opencode/doctrine/lenses/typescript.md` |
| `templates/testing/DIAGNOSIS.md` | `.opencode/doctrine/testing/DIAGNOSIS.md` |
| `templates/testing/EXPERIENCE.md` | `.opencode/doctrine/testing/EXPERIENCE.md` |
| `templates/testing/JOURNEYS.md` | `.opencode/doctrine/testing/JOURNEYS.md` |
| `templates/testing/LEVELS.md` | `.opencode/doctrine/testing/LEVELS.md` |

**Do NOT modify file contents.** This is a pure copy. Path rewrites happen in the agent/command/skill files that reference these doctrine files, not in the doctrine files themselves.

## How

Run from the repo root:

```bash
SRC="plugins/kanban-flow/templates"
DST="plugins/kanban-flow/.opencode/doctrine"

cp "$SRC/AGENT-PROTOCOL.md" "$DST/"
cp "$SRC/PROTOCOL-ADDENDUM.md" "$DST/"
cp "$SRC/INTAKE.md" "$DST/"
cp "$SRC/card-template.md" "$DST/"
cp "$SRC/config.md" "$DST/"
cp "$SRC/pr-template.md" "$DST/"
cp "$SRC/design-pr-template.md" "$DST/"

cp "$SRC/board/BOARD.md" "$DST/board/"
cp "$SRC/board/KNOWLEDGE.md" "$DST/board/"
cp "$SRC/board/MILESTONES.md" "$DST/board/"

cp "$SRC/checks/_method.md" "$DST/checks/"
cp "$SRC/checks/deliver.md" "$DST/checks/"
cp "$SRC/checks/design.md" "$DST/checks/"
cp "$SRC/checks/ids.md" "$DST/checks/"
cp "$SRC/checks/intake.md" "$DST/checks/"
cp "$SRC/checks/slice.md" "$DST/checks/"
cp "$SRC/checks/split.md" "$DST/checks/"

cp "$SRC/lenses/_shared.md" "$DST/lenses/"
cp "$SRC/lenses/acceptance.md" "$DST/lenses/"
cp "$SRC/lenses/design.md" "$DST/lenses/"
cp "$SRC/lenses/experience.md" "$DST/lenses/"
cp "$SRC/lenses/functionality.md" "$DST/lenses/"
cp "$SRC/lenses/python.md" "$DST/lenses/"
cp "$SRC/lenses/readability.md" "$DST/lenses/"
cp "$SRC/lenses/security.md" "$DST/lenses/"
cp "$SRC/lenses/simplicity.md" "$DST/lenses/"
cp "$SRC/lenses/tests.md" "$DST/lenses/"
cp "$SRC/lenses/typescript.md" "$DST/lenses/"

cp "$SRC/testing/DIAGNOSIS.md" "$DST/testing/"
cp "$SRC/testing/EXPERIENCE.md" "$DST/testing/"
cp "$SRC/testing/JOURNEYS.md" "$DST/testing/"
cp "$SRC/testing/LEVELS.md" "$DST/testing/"
```

## Verification

```bash
# Count files in templates (recursive)
find plugins/kanban-flow/templates -type f | wc -l

# Count files in doctrine (recursive)
find plugins/kanban-flow/.opencode/doctrine -type f | wc -l

# Both counts must be 30 and match exactly
```

Then spot-check a few files to confirm they are byte-identical:

```bash
diff plugins/kanban-flow/templates/AGENT-PROTOCOL.md plugins/kanban-flow/.opencode/doctrine/AGENT-PROTOCOL.md
diff plugins/kanban-flow/templates/checks/_method.md plugins/kanban-flow/.opencode/doctrine/checks/_method.md
diff plugins/kanban-flow/templates/lenses/_shared.md plugins/kanban-flow/.opencode/doctrine/lenses/_shared.md
diff plugins/kanban-flow/templates/testing/LEVELS.md plugins/kanban-flow/.opencode/doctrine/testing/LEVELS.md
diff plugins/kanban-flow/templates/board/BOARD.md plugins/kanban-flow/.opencode/doctrine/board/BOARD.md
```

All diffs must be empty (no output = files are identical).

## Dependencies

Task 01 (directories created).
