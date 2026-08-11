# Task 06: opencode.json Registration

## Why

OpenCode auto-discovers agents in `.opencode/agents/*.md` and commands in `.opencode/commands/*.md`, and model assignment is done in frontmatter. However, three producer agents need explicit write permissions because their frontmatter `permission:` block may not be sufficient to override defaults:

- `card-implementer` — primary code producer
- `card-deliverer` — pushes branches, opens PRs
- `pr-splitter` — creates branches

Additionally, the orchestrator dispatches subagents that may themselves dispatch further agents (e.g., the orchestrator dispatches `card-lens-reviewer`, which may use the Task tool to read files). This requires increasing the `subagent_depth` from the default.

This task creates/writes the `opencode.json` configuration. The migration plan specifies the file lives under `plugins/kanban-flow/.opencode/` but since `.opencode/` is the source of truth for plugin distribution, the `opencode.json` should be placed adjacent at `plugins/kanban-flow/opencode.json` so it's usable when the plugin is installed into a project (via symlink or copy).

## What

Create `plugins/kanban-flow/opencode.json` with:

1. Permission overrides for the three producer agents
2. `subagent_depth: 2` for nested agent dispatch

## How

Write the file with this content:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "subagent_depth": 2,
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

**Notes:**
- All other agents are auto-discovered with their frontmatter-configured models
- Default permissions for agents without explicit overrides: `edit: deny`, `bash: ask`
- The `$schema` field is optional but helps with editor validation

## Verification

1. **File exists and is valid JSON:**

```bash
python3 -c "import json; json.load(open('plugins/kanban-flow/opencode.json'))" && echo "Valid JSON"
```

2. **Contains all required keys:**

```bash
python3 -c "
import json
cfg = json.load(open('plugins/kanban-flow/opencode.json'))
assert cfg['subagent_depth'] == 2
assert cfg['agent']['card-implementer']['permission']['edit'] == 'allow'
assert cfg['agent']['card-implementer']['permission']['bash'] == 'allow'
assert cfg['agent']['card-deliverer']['permission']['edit'] == 'allow'
assert cfg['agent']['card-deliverer']['permission']['bash'] == 'allow'
assert cfg['agent']['pr-splitter']['permission']['edit'] == 'allow'
assert cfg['agent']['pr-splitter']['permission']['bash'] == 'allow'
print('All assertions passed')
"
```

## Dependencies

Task 03 (agent files exist with correct frontmatter — the permission overrides here must match the agent names used in agent frontmatter).
