# code-safely-plugin

Safety guardrails and convenience auto-approvals for [Claude Code](https://claude.com/claude-code), packaged as a plugin. It blocks irreversible and dangerous actions before they run, protects your dotfiles and credentials, keeps secrets out of git, and cuts prompt fatigue by auto-approving commands that are provably read-only.

> **Inspiration:** the hook ideas here are based on and adapted from **cc-safe-setup**. This plugin repackages that spirit as an installable Claude Code marketplace plugin, hardens the scripts for Linux + macOS portability, and tightens the auto-approval logic against command-chaining bypasses. Full credit to cc-safe-setup for the original concept.

## Requirements

- **`jq`** (required) — every hook parses the tool payload with it. `brew install jq` / `apt install jq`. Without it, the guards fail open (no-op).
- **bash** 3.2+ (works with the macOS system bash; no bash-4 features used).
- Optional, used only by `syntax-check` and auto-detected: `python3`, `node`, `npx`.
- Platform-specific, already guarded/branched: `findmnt` (Linux), `notify-send`/`osascript`/`powershell.exe`.

Scripts are portable across **Linux and macOS** — no GNU-only constructs.

## Installation

```
/plugin marketplace add stebennett/nyx-claude
/plugin install code-safely-plugin@nyx-claude
```

## How it works

Each hook is a small shell script fired on a Claude Code tool event. A hook signals its decision by:

- **exit 2** → block the action (message shown to the model), or
- **JSON on stdout** (`permissionDecision` / `decision`) → auto-approve or block, or
- **exit 0, no output** → stay out of the way (normal permission flow continues).

Guards never approve anything they aren't sure about — they only *block* or *pass through*. Auto-approvers only *approve* provably safe commands and defer everything else to the normal prompt.

## Hooks

### 🛡️ Protective guardrails — block dangerous actions

| Hook | Event / matcher | Protects against |
|---|---|---|
| `destructive-guard` | PreToolUse · Bash | `rm -rf` on `/`, `~`, `..`, `/etc`, `/usr`…; `git reset --hard`; `git clean -fd`; `git checkout/switch --force`; `chmod -R 777`; `find … -delete`; `--no-preserve-root`; destructive `sudo`; PowerShell `Remove-Item -Recurse -Force`; destructive commands hidden in `sh -c "…"` or piped to a shell; and `rm` on a path containing a mounted filesystem (NFS/Docker/bind). |
| `home-critical-bash-guard` | PreToolUse · Bash | Bash `rm`/`mv`/truncate/`chmod` targeting critical home files: `~/.bashrc`, `~/.zshrc`, `~/.ssh`, `~/.git-credentials`, `~/.gitconfig`, `~/.gnupg`, `~/.npmrc`, `~/.netrc`, `~/.docker`, `~/.kube`, `~/.aws`. |
| `dotfile-protection-guard` | PreToolUse · Edit\|Write | Edit/Write to critical dotfiles & credential stores: shell rc files, `~/.ssh/*`, `~/.git-credentials`, `~/.npmrc`, `~/.aws/credentials`, `~/.docker/config.json`, `~/.kube/config`, `~/.config/gh/hosts.yml`, … (allows Claude's own `~/.claude/*`). |
| `protect-claudemd` | PreToolUse · Edit\|Write | Edit/Write to configuration files — `CLAUDE.md`, `settings.json`, `settings.local.json`, `.claude.json` — and to `.claude/{hooks,settings,plugins}/` system dirs. |
| `scope-guard` | PreToolUse · Bash | Destructive file ops that escape the project directory — `rm` with absolute paths, `~/`, or `../`, and anything targeting `Desktop`/`Documents`/`Downloads`/`Library`/`Keychain`/`.ssh`/`.aws`. |
| `env-source-guard` | PreToolUse · Bash | Leaking `.env` into the shell environment: `source .env`, `. .env`, `export $(cat .env)` — which can cross-contaminate later commands (e.g. wiping a real DB from a test run). |
| `secret-guard` | PreToolUse · Bash | Committing secrets: `git add` of `.env*`, `*credentials*`, `*.pem`, `*.key`, `*.p12`, `id_rsa`/`id_ed25519`, and blanket `git add .`/`-A` when a `.env` is present. |
| `branch-guard` | PreToolUse · Bash | `git push` to protected branches (`main`/`master`) and **force-push on any branch** (`-f`, `--force`, `--force-with-lease`). |
| `no-sudo-guard` | PreToolUse · Bash | Any `sudo` command. |
| `skill-gate` | PreToolUse · Skill | Built-in skills that modify files without showing a diff: `update-config`, `keybindings-help`, `simplify`, `statusline-setup`. |
| `memory-write-guard` | PreToolUse · Edit\|Write | Silent writes into `~/.claude/` — logs them (and warns on settings files) so memory/config writes are visible. Warns, does not block. |

### ⚡ Convenience auto-approvals — cut prompt fatigue safely

| Hook | Event / matcher | What it auto-approves |
|---|---|---|
| `auto-approve-readonly` | PreToolUse · Bash | Wholly read-only commands (`cat`, `ls`, `grep`, `find`, `stat`, `git log/diff/status/show`, read-only pipelines, …). **Every** pipe/chain segment must be read-only; redirects, command substitution, `find -exec`/`-delete`, and exec-vectors like `env <cmd>` are refused so a read-only prefix can't smuggle a dangerous tail. |
| `auto-approve-test` | PreToolUse · Bash | Bare test-runner invocations across ecosystems (npm/yarn/pnpm/bun, jest/vitest/mocha/ava/playwright/cypress, pytest/tox, `go test`, `cargo test`, phpunit, rspec/rake, gradle/maven, `dotnet test`). |
| `auto-approve-go` | PreToolUse · Bash | `go build/test/vet/fmt/mod/run/generate/install/clean`. |
| `auto-approve-docker` | PreToolUse · Bash | Common `docker`/`docker-compose` build & read ops (`build`, `compose`, `ps`, `images`, `logs`, `inspect`, `up`, `down`, …). |
| `cd-git-allow` | PreToolUse · Bash | Exactly `cd <path> && git <read-only>` compounds (log/diff/status/branch/show/rev-parse…), which otherwise always prompt. |
| `comment-strip` | PreToolUse · Bash | *(normalizer)* Strips comment lines Claude adds to Bash commands so permission allowlists match the real command instead of `# a comment`. |

Each auto-approver only approves a **single, unchained** safe invocation; anything with extra chaining, piping, substitution, or redirection falls through to the normal permission prompt.

### 🩺 Workflow & monitoring — non-blocking

| Hook | Event / matcher | Purpose |
|---|---|---|
| `syntax-check` | PostToolUse · Edit\|Write | After an edit, syntax-checks `.py`/`.sh`/`.json`/`.yaml`/`.js`/`.ts` (using whatever checkers are installed) and reports errors immediately. Never blocks. |
| `context-monitor` | PostToolUse · (all tools) | Graduated context-window warnings (CAUTION → WARNING → CRITICAL → EMERGENCY); at critical levels writes an evacuation template to your mission file so you can hand off before `/compact`. State lives in a per-user `0700` dir under `$TMPDIR`. |
| `api-error-alert` | Stop | When a session stops on an error, logs it and fires a desktop notification (`osascript` on macOS, `notify-send` on Linux, PowerShell on WSL). |

## Configuration

Most guards work with zero config. Behavior can be tuned via environment variables:

| Variable | Hook | Effect |
|---|---|---|
| `CC_ALLOW_DESTRUCTIVE=1` | destructive-guard | Disable the destructive-command guard (not recommended). |
| `CC_SAFE_DELETE_DIRS` | destructive-guard | Colon-separated dirs that are safe to `rm -rf` (default `node_modules:dist:build:.cache:__pycache__:coverage:.next:.nuxt:tmp`). |
| `CC_BLOCK_LOG` | destructive-guard | Path to the blocked-command audit log (default `~/.claude/blocked-commands.log`). |
| `CC_PROTECT_BRANCHES` | branch-guard | Colon-separated protected branches (default `main:master`). |
| `CC_ALLOW_FORCE_PUSH=1` | branch-guard | Allow force-push. |
| `CC_CONTEXT_MISSION_FILE` | context-monitor, api-error-alert | Mission/state file for evacuation templates (default `~/mission.md`). |
| `CC_ERROR_ALERT_LOG` | api-error-alert | Session-error log path (default `~/.claude/session-errors.log`). |

## Notes & trade-offs

- The auto-approvers deliberately treat `sed`/`awk`/`tee`/`xargs`/`env` as **not** read-only (they can write files or execute other programs), and won't auto-approve chained commands like `npm test && npm run lint`. This trades a little extra prompting for closing command-smuggling bypasses.
- `docker run`/`docker exec` are on the auto-approve list; a single `docker run … sh -c '…'` still executes arbitrary code inside a container without a prompt. Tighten the allowlist if that matters for your threat model.
- `destructive-guard` records blocked commands (including their full text) to a local audit log — review it if commands may contain sensitive strings.
