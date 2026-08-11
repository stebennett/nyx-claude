# Task 01: Directory Scaffolding

## Why

The migration from Claude Code to OpenCode requires creating a `.opencode/` directory structure in `plugins/kanban-flow/`. OpenCode auto-discovers `commands/`, `skills/`, and `agents/` subdirectories on startup. The `doctrine/` directory holds shared template files that were previously in `templates/` under the Claude Code plugin.

This task creates the empty directory tree. Subsequent tasks will populate each directory.

## What

Create the following directory structure under `plugins/kanban-flow/.opencode/`:

```
.opencode/
├── commands/
├── skills/
│   ├── kanban-orchestrator/
│   ├── adr/
│   └── req-ids/
├── agents/
└── doctrine/
    ├── board/
    ├── checks/
    ├── lenses/
    └── testing/
```

## How

Run the following commands from the repo root:

```bash
mkdir -p plugins/kanban-flow/.opencode/commands
mkdir -p plugins/kanban-flow/.opencode/skills/kanban-orchestrator
mkdir -p plugins/kanban-flow/.opencode/skills/adr
mkdir -p plugins/kanban-flow/.opencode/skills/req-ids
mkdir -p plugins/kanban-flow/.opencode/agents
mkdir -p plugins/kanban-flow/.opencode/doctrine/board
mkdir -p plugins/kanban-flow/.opencode/doctrine/checks
mkdir -p plugins/kanban-flow/.opencode/doctrine/lenses
mkdir -p plugins/kanban-flow/.opencode/doctrine/testing
```

## Verification

```bash
ls -la plugins/kanban-flow/.opencode/
ls -la plugins/kanban-flow/.opencode/commands/
ls -la plugins/kanban-flow/.opencode/skills/
ls -la plugins/kanban-flow/.opencode/skills/kanban-orchestrator/
ls -la plugins/kanban-flow/.opencode/skills/adr/
ls -la plugins/kanban-flow/.opencode/skills/req-ids/
ls -la plugins/kanban-flow/.opencode/agents/
ls -la plugins/kanban-flow/.opencode/doctrine/
ls -la plugins/kanban-flow/.opencode/doctrine/board/
ls -la plugins/kanban-flow/.opencode/doctrine/checks/
ls -la plugins/kanban-flow/.opencode/doctrine/lenses/
ls -la plugins/kanban-flow/.opencode/doctrine/testing/
```

All directories must exist and be empty.

## Dependencies

None — this is the first task.
