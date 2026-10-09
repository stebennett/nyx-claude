# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repository is a **Claude Code plugin marketplace** — it hosts a collection of plugins authored by the owner for use with Claude Code. It is consumed via `/plugin marketplace add <this-repo>` followed by `/plugin install <name>@<marketplace>`.

Registered plugins: `code-safely-plugin`, `kanban-flow`, `github-app-identity`, `productivity`, `devtools` and `engineering-standards`. Each has its own README; the sections below record only what is non-obvious.

## Repository layout

```
.claude-plugin/
  marketplace.json       # Marketplace manifest — lists every plugin (required for discovery)
plugins/
  code-safely-plugin/    # Safety-guardrail + auto-approval hooks (migrated from ~/.claude/hooks)
    .claude-plugin/plugin.json
    hooks/hooks.json     # Wires the *.sh guards to PreToolUse/PostToolUse/Stop events
    hooks/*.sh           # 20 hook scripts
  kanban-flow/           # Card-driven kanban orchestrator + specialist agents
  github-app-identity/   # GitHub App identity: gh shim, token minter, credential helper (scripts/tests/)
  productivity/          # handoff / continue / task-observer / token-usage skills
  devtools/              # renovator and pr-reviewer skills + their agents
  engineering-standards/ # Standards assessment: classify + assess skills, check scripts, rubric (scripts/tests/)
scripts/check-plugin.sh  # Structural validation of a plugin directory (run in CI for every plugin)
```

### code-safely-plugin

Hook scripts communicate via exit code and stdout JSON: **exit 2** blocks the tool call (stderr shown to the model); a JSON object with `permissionDecision`/`decision` on stdout auto-approves or blocks; **exit 0** with no output is a pass-through. Scripts read the tool payload as JSON on stdin (`.tool_input.command`, `.tool_input.file_path`, etc.). They are grouped by matcher in `hooks/hooks.json`: `Bash` guards, `Edit|Write` file guards, and a `Skill` gate. Scripts are invoked as `bash "${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh"` so they resolve regardless of install location.

Portability: scripts target both Linux and macOS. Avoid GNU-only constructs (`grep -oP`/`\K`, `find -printf`, `date -Iseconds`) — use `sed -nE`, `ls -t`, and `date +%Y-%m-%dT%H:%M:%S%z` instead. Note that a dev machine with GNU coreutils/findutils in PATH will silently accept GNU-isms, hiding breakage that only appears on stock macOS. Written for bash 3.2 compatibility (macOS default) — no `mapfile`/`readarray`/`declare -A`. Stay bash-3.2-safe.

Dependencies: **`jq` is required** (every guard parses the hook payload with it). `python3`/`node`/`npx` are optional and used only by `syntax-check.sh`, guarded by `command -v`. Platform-specific tools are already guarded/branched: `findmnt` (Linux, `destructive-guard`), and `notify-send`/`osascript`/`powershell.exe` (`api-error-alert`).

This plugin is the source of truth — the copies under `~/.claude/hooks/` are now unwired and may drift.

### engineering-standards

The assessment is split between deterministic bash (`scripts/`) and agents: `checks/group-N.sh` emit one JSON record per *script* criterion, the `es-assessor` agent scores *judgment* criteria, and `score.sh` does all arithmetic. `references/rubric.json` is the machine form of `references/standards.md` — `test_rubric_consistency.sh` fails if their criterion IDs, levels or versions diverge, so change both together. Applicability rules live once, in `scripts/lib/applicability.jq`.

Gotchas these scripts already hit:
- **No `pipefail` in `checks/*.sh` or `detect.sh`.** They pipe into `grep -q`, which exits on the first match and SIGPIPEs the producer; under `pipefail` that race intermittently reads as "no match". Each check block writes to a temp file instead, so `set -e` still catches real failures.
- **Never let `cat`/`grep` see an empty file list** — they fall back to stdin and hang. Prefix with `/dev/null` (`cat /dev/null $(workflows)`), and run the scripts with `< /dev/null`.
- **`yq`'s comma binds looser than `|`**: write `.on | (a, b, c)`, not `.on | a, b, c`.
- **No apostrophes inside single-quoted jq programs** (comments included) — bash ends the string there.
- **Monorepos are the norm** — read manifests with `manifests pyproject.toml package.json` (every workspace member), never a bare root `pyproject.toml`.
- Every `.json` under a plugin must parse (`check-plugin.sh`), so test fixtures use plain JSON, not JSONC.

### Marketplace manifest (`.claude-plugin/marketplace.json`)

This file is what turns the repo into an installable marketplace. It names the marketplace and enumerates each plugin with a `source` pointing at its directory:

```json
{
  "name": "nyx-claude",
  "owner": { "name": "Steve Bennett" },
  "plugins": [
    { "name": "kanban", "source": "./plugins/kanban", "description": "..." }
  ]
}
```

Every new plugin added under `plugins/` must also be registered here, or Claude Code will not discover it.

### Plugin structure (per directory under `plugins/`)

A plugin is a directory containing a manifest plus any of the component folders Claude Code auto-discovers. Only `.claude-plugin/plugin.json` is required; the rest are optional and included only when the plugin uses them:

```
plugins/<name>/
  .claude-plugin/plugin.json   # Manifest: name, version, description, author
  commands/                    # Slash commands — one .md file per command
  agents/                      # Subagents — one .md file per agent (frontmatter: name, description, tools)
  skills/<skill>/SKILL.md      # Skills — one directory per skill with a SKILL.md
  hooks/hooks.json             # Event hooks (PreToolUse, PostToolUse, etc.)
  .mcp.json                    # MCP servers bundled with the plugin
```

Component files are discovered by convention from these directory names, so the manifest generally does not need to list them individually. Use `${CLAUDE_PLUGIN_ROOT}` in hook/MCP configs to reference paths inside the plugin regardless of where it is installed.

## Working in this repo

- **RTK proxy**: This machine runs Rust Token Killer, which rewrites common shell commands (`ls`, `cat`, `grep`, `find`, `git`). `.claude/settings.local.json` pre-allows `Bash(rtk proxy *)`. If an `rtk`-wrapped command rejects a flag (e.g. `find -not`/`-exec`), fall back to `rtk proxy <command>` to run it unfiltered.
- **Validation and tests.** `bash scripts/check-plugin.sh plugins/<name>/` checks a plugin's structure (manifest, JSON, agent/skill frontmatter, referenced files, orphan agents). Plugins with scripts keep plain-bash tests in `plugins/<name>/scripts/tests/test_*.sh`; CI (`.github/workflows/plugins.yml`) runs both on Ubuntu and macOS. Markdown components (commands, agents, skills) are otherwise validated by installing the plugin and exercising it.
