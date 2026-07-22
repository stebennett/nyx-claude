# Contributing to nyx-claude

Thanks for your interest in contributing. This repository is a **Claude Code plugin marketplace** —
a collection of plugins (skills, agents, commands, and hooks) installed into Claude Code. Plugin
components are **Markdown and JSON**, not compiled code, so contributing is mostly editing text files
and validating them by installing the plugin into Claude Code and exercising it.

- New here? Read the [root `README.md`](README.md) for what the marketplace is and how it's installed.
- Working on a specific plugin? Each has its own `README.md` under `plugins/<name>/`.

## Prerequisites

- **[Claude Code](https://claude.com/claude-code)** — the runtime you test against.
- **`git`** — standard workflow below.
- **`jq`** — required by `code-safely-plugin`'s hook scripts (every guard parses its payload with it).
  Optional per-plugin tools are guarded with `command -v` and noted in that plugin's docs.

There is **no build step and no test runner.** "Testing" means installing the plugin locally and
running it — see [Testing locally](#testing-locally).

## Repository layout

```
.claude-plugin/
  marketplace.json          # Marketplace manifest — lists every published plugin
plugins/
  <plugin>/
    .claude-plugin/plugin.json   # Plugin manifest (name, version, description, author)
    commands/ agents/ skills/    # Optional, auto-discovered components
    hooks/hooks.json             # Optional event hooks
    README.md                    # Per-plugin docs
```

A plugin is discovered only once it is **both** present under `plugins/` **and** registered in
`.claude-plugin/marketplace.json`. See [Adding or changing a plugin](#adding-or-changing-a-plugin).

## Development workflow

1. **Branch** off `main` — `git checkout -b <type>/<short-description>` (e.g. `feat/kanban-pump-gate`,
   `fix/destructive-guard-macos`).
2. **Make your change** under `plugins/<name>/` (and register it in `marketplace.json` if it's new).
3. **Test it locally** against Claude Code (below). Since there's no CI test suite, this is the only
   validation — do it before opening the PR, and describe what you exercised in the PR body.
4. **Commit** with a [Conventional Commit](https://www.conventionalcommits.org/) message
   (`feat(kanban-flow): …`, `fix(code-safely-plugin): …`, `docs: …`, `chore: …`). Keep commits scoped
   to one plugin where possible.
5. **Bump the version** in the plugin's `plugin.json` when you change its behavior (semver:
   patch for fixes, minor for features, major for breaking changes).
6. **Open a PR** against `main`. Explain what changed, why, and **how you tested it**. There is no PR
   template — write a clear description.

## Testing locally

The core loop is: point Claude Code at a **local checkout** of this repo as a marketplace, install the
plugin, exercise it, edit, refresh, repeat. Installing from a local path (rather than
`stebennett/nyx-claude` on GitHub) is what lets you test **uncommitted or unmerged** changes.

### 1. Add your working checkout as a local marketplace

From inside Claude Code:

```
/plugin marketplace add /absolute/path/to/nyx-claude
/plugin install <plugin>@nyx-claude
```

Confirm the version you expect with `/plugin` (it lists installed plugins and versions).

### 2. Iterate

After editing files in your checkout, refresh the marketplace so Claude Code re-reads them:

```
/plugin marketplace update nyx-claude
```

If a change doesn't appear, reinstall the plugin (`/plugin`, uninstall, then
`/plugin install <plugin>@nyx-claude`). Restarting the Claude Code session also forces a clean reload.

### 3. Testing an unmerged branch (e.g. a PR under review)

The GitHub install (`/plugin marketplace add stebennett/nyx-claude`) tracks the default branch
(`main`), so it won't show branch-only changes. To test a branch, check it out in your local clone and
use the **local** marketplace:

```bash
git fetch origin
git checkout <branch-name>
```
```
/plugin marketplace update nyx-claude    # re-reads the checkout at the new branch
```

### 4. Exercise the plugin

What "exercising" means depends on the plugin — a few examples:

- **`code-safely-plugin`** — run a command the guards should catch (a destructive `rm`, an edit to a
  protected dotfile) and confirm it's blocked, and a read-only/test command and confirm it's
  auto-approved. Hook behavior is exit-code/stdout-JSON based; watch the tool-call decision.
- **`kanban-flow`** — in a scratch repo, run `/kanban-init` to scaffold `docs/cards/`, edit
  `config.md`, `/refine` to create a card or two, then `/kanban` to drive the board. To test an
  **upgrade** path on a repo that already has an older board, run `/migrate`. For loop/cost behavior,
  run `/loop /kanban` on a quiet vs. active board.
- **Other plugins** — trigger the skill or command per that plugin's `README.md`.

Use a **throwaway repo or branch** as the target when a plugin writes files (kanban-flow scaffolds a
board; some plugins open PRs) so you don't mix test artifacts into real work.

## Adding or changing a plugin

1. Create `plugins/<name>/.claude-plugin/plugin.json` with `name`, `version`, `description`, and
   `author` (see an existing plugin for the shape).
2. Add the components you need — `commands/` (one `.md` per command), `agents/` (one `.md` per agent,
   with `name`/`description`/`tools`/`model` frontmatter), `skills/<skill>/SKILL.md`,
   `hooks/hooks.json`, `.mcp.json`. All are optional and auto-discovered by directory name.
3. **Register it** in `.claude-plugin/marketplace.json` under `plugins` with a `source` pointing at
   its directory — a plugin not listed here is not discoverable.
4. Reference in-plugin paths with **`${CLAUDE_PLUGIN_ROOT}`** so they resolve regardless of where the
   plugin is installed (in hook commands, MCP configs, and any dispatch prompt that names a plugin file).
5. Add a `plugins/<name>/README.md`, and a row in the root `README.md` plugin table.

## Conventions

- **`${CLAUDE_PLUGIN_ROOT}`** for every in-plugin path — never a hardcoded or install-relative path.
- **Semver** in `plugin.json`; bump it in the same change that alters behavior.
- **Hook script portability** (`code-safely-plugin`, and any future hook-based plugin): scripts target
  **both Linux and macOS** and are written for **bash 3.2** (the macOS default). Avoid GNU-only
  constructs (`grep -oP` / `\K`, `find -printf`, `date -Iseconds`) and bash-4 features
  (`mapfile`/`readarray`/`declare -A`); prefer `sed -nE`, `ls -t`, and
  `date +%Y-%m-%dT%H:%M:%S%z`. A dev machine with GNU coreutils in `PATH` will silently accept
  GNU-isms that break on stock macOS — write to the portable subset. Platform-specific tools must be
  guarded (`command -v`) or branched.
- **Dependencies:** `jq` is assumed present for hook guards; anything else optional must be
  `command -v`-guarded and documented.
- **Keep doctrine plugin-owned.** Where a plugin ships reference material agents read at runtime (e.g.
  `kanban-flow`'s `templates/`), keep it in the plugin and read it live via `${CLAUDE_PLUGIN_ROOT}` —
  don't copy it into consuming repos, so a plugin update reaches every project.

## Where the deeper docs live

- **Per-plugin `README.md`** — user-facing behavior and configuration.
- **`plugins/kanban-flow/RATIONALE.md`** — the *why* behind kanban-flow's load-bearing rules; read it
  before changing that plugin's doctrine.
- **`docs/superpowers/`** — design specs and plans for larger features.
- **`CLAUDE.md`** — guidance for Claude Code when working in this repo (also a good orientation for
  human contributors).

## Questions

Open an issue or start a discussion on the PR. For anything that changes a plugin's behavior, prefer a
short design note in the PR description over a large unexplained diff.
