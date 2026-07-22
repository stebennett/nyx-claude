# nyx-claude

[github.com/stebennett/nyx-claude](https://github.com/stebennett/nyx-claude)

A personal [Claude Code](https://claude.com/claude-code) **plugin marketplace** — a small collection of plugins used with Claude Code, published so they can be installed the same way as any other marketplace.

## Using this marketplace

Add the marketplace, then install the plugins you want:

```
/plugin marketplace add stebennett/nyx-claude
/plugin install <plugin>@nyx-claude
```

Once added, plugins appear in `/plugin` and update when the marketplace is refreshed.

## Plugins

| Plugin | What it does |
|---|---|
| [`code-safely-plugin`](plugins/code-safely-plugin/) | Safety guardrails + convenience auto-approvals: blocks destructive commands, protects dotfiles/credentials, keeps secrets out of git, prevents force-pushes, and auto-approves provably read-only/test/build commands. See its [README](plugins/code-safely-plugin/README.md). |
| [`kanban-flow`](plugins/kanban-flow/) | Autonomous, card-driven kanban development: an orchestrator and specialist agents run each backlog card through slice → design → implement → test → review, shipping design and implementation as two reviewable PRs per card. See its [README](plugins/kanban-flow/README.md). |
| [`github-app-identity`](plugins/github-app-identity/) | Give local automation a dedicated GitHub App identity: a global directory-aware `gh` shim (plus a git credential helper and per-repo git config) makes commits, pushes, and `gh`/API calls act as the App inside opted-in repos — never falling back to personal credentials. See its [README](plugins/github-app-identity/README.md). |
| [`productivity`](plugins/productivity/) | Work more productively across sessions: `handoff` distils the current session into one self-contained document before context runs out, `continue` reads it back in a fresh session and proposes a resumption plan for approval, and `task-observer` watches task sessions for skill-improvement opportunities and runs skill creation/refinement reviews. See its [README](plugins/productivity/README.md). |

## Repository layout

```
.claude-plugin/
  marketplace.json          # Marketplace manifest — lists every published plugin
plugins/
  <plugin>/
    .claude-plugin/plugin.json   # Plugin manifest (name, version, description)
    commands/ agents/ skills/    # Optional, auto-discovered components
    hooks/hooks.json             # Optional event hooks
```

A plugin is discovered only once it is both present under `plugins/` **and** listed in `.claude-plugin/marketplace.json`.

## Adding a plugin

1. Create `plugins/<name>/.claude-plugin/plugin.json` with `name`, `version`, and `description`.
2. Add the plugin's components (`commands/`, `agents/`, `skills/`, `hooks/hooks.json`, `.mcp.json` — all optional).
3. Register it in `.claude-plugin/marketplace.json` under `plugins` with a `source` pointing at its directory.
4. Reference in-plugin paths with `${CLAUDE_PLUGIN_ROOT}` so they resolve regardless of install location.
