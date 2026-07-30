# github-app-identity: multiple bot identities

**Date:** 2026-07-30
**Status:** Approved design, not yet implemented
**Plugin:** `plugins/github-app-identity` (0.1.0 → 0.2.0)

## Problem

The plugin gives local automation a single GitHub App identity, machine-wide. One App, one
config file, one token cache, and a boolean per-repo switch (`gh-app.enabled`).

Two agents now need *different* identities in the same repository. A build agent authors
commits and pushes; a `pr-reviewer` agent reviews and merges. GitHub rejects an `APPROVE` or
`REQUEST_CHANGES` event from a pull request's own author, so a reviewer sharing the builder's
identity cannot record a real verdict — `devtools/pr-reviewer` currently works around this by
posting a `COMMENT` with the verdict hidden in an HTML marker. Distinct App identities remove
the workaround.

The intended topology is one clone per identity — a build clone (with worktrees) and a review
clone of the same repository.

### A defect found while designing this

Git accumulates credential helpers system → global → local and uses the **first** that returns
credentials. `gh auth login` writes `credential.https://github.com.helper` into the user's
global config. Today's per-repo setup *appends* its helper locally, so it is consulted last and
never reached. Verified in a sandbox against git 2.50.1:

```
CASE 1: local helper appended (today's setup-github-app-git.sh)
username=personal-user          ← personal token wins
CASE 2: local empty-reset, then our helper
username=x-access-token         ← the App
```

`git push` inside an "enabled" repo has therefore been authenticating as the personal account,
not the App — the exact failure the plugin promises cannot happen. `gh` calls are unaffected
(the shim path does not use credential helpers). The fix is in scope here because this work
rewrites that config line anyway, and it is the same wrong-identity class of bug.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Identity is selected by per-clone git config only | Ambient in the filesystem: any process in the tree — agent, subagent, shell — gets the right identity. `--local` in a linked worktree resolves to the clone's shared `.git/config`, so worktrees inherit. |
| 2 | No env-var override of the profile | An exported variable follows the user into the other clone. Nothing production-reachable may select identity. |
| 3 | Clean break from the single-App layout, with a loud legacy trap | One machine, few repos. Dual-path config resolution would double the code and tests, and a silent pass-through on legacy config would downgrade to personal auth. |
| 4 | One env file per profile | No parsing, no name mangling, bash-3.2 clean, no new dependency. `ls` enumerates identities. |
| 5 | Per-profile token cache | A shared cache lets one clone reuse the other App's token — a wrong-identity bug that succeeds silently. |
| 6 | Ship `gh-app-status.sh` | The failure mode is acting as the wrong bot, which is invisible without a way to ask. |
| 7 | The runbook stays generic on App permissions | No per-role recipe. (Note for the reader, not the runbook: merging a PR needs Contents: write, so a "reviewer cannot touch code" split would break `pr-reviewer`'s merge step.) |
| 8 | Replace the skill with two commands | Stops an agent invoking setup mid-task. The doctrine the skill carried moves into abort messages, where it reaches an agent at the moment of temptation. |
| 9 | Run the existing tests in CI | They exist and have never executed. The credential defect above is exactly what a test run would have caught. |

## Architecture

### Profile store

```
${GH_APP_PROFILE_DIR:-~/.config/gh-app/profiles}/<name>.env
```

One self-contained file per identity, holding the same five variables as today's single file:
`GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY_PATH`,
`GITHUB_APP_SLUG`, `GITHUB_APP_BOT_USER_ID`. No shared-defaults file underneath — two Apps
share none of these values, and a base/override merge would make "which App is this?" a
two-file question.

Profile names are constrained to `^[A-Za-z0-9][A-Za-z0-9._-]*$`, because a name reaches the
filesystem twice (profile file, cache file). Anything else is rejected before it becomes a
path.

Two environment variables change shape as part of the clean break:

| Today | Becomes |
|---|---|
| `GITHUB_APP_ENV` (a file) | `GH_APP_PROFILE_DIR` (a directory; file is `<dir>/<name>.env`) |
| `GITHUB_APP_TOKEN_CACHE` (a file) | `GH_APP_CACHE_DIR` (a directory; cache is `token-<name>.json`) |

### Resolution

Inside the `gh` shim:

1. Not inside a git work tree → `exec` the real `gh` unchanged.
2. `profile=$(git config --local --get gh-app.profile)`.
3. Empty, but `gh-app.enabled` exists → **abort** (legacy config).
4. Empty and no legacy key → `exec` the real `gh` unchanged.
5. Set → mint for that profile; empty or failed token → **abort**, never personal auth.

`--local` rather than plain `--get` is deliberate: it prevents a stray `--global` setting from
enabling every repo on the machine, and it is what makes worktrees inherit the clone's
identity.

### Components

**`github-app-token.sh --profile <name>`**
Profile is required — no env fallback, no default, since an implicit default is how the wrong
token gets minted. Validates the name, requires `<profile-dir>/<name>.env` to exist (so a
deleted or mistyped profile errors rather than serving a stale cached token), then checks
`<cache-dir>/token-<name>.json` and mints on miss. JWT construction, the API call, and the
atomic 0600 cache write are unchanged.

**`gh` (shim)**
Resolves the profile as above and passes `--profile` to the minter. `GH_APP_REAL_GH` stays for
tests. `GH_APP_ENABLED_OVERRIDE` is **dropped**, not renamed to a profile equivalent — it is a
production-reachable environment variable that selects identity, which decision 2 forbids.
Tests instead `git init` temporary repos and set real config.

**`git-credential-github-app.sh --profile <name>`**
Git appends the operation (`get`/`store`/`erase`) as the final argument, so the helper scans
its arguments for `--profile` instead of reading `$1`. The profile is baked into the git config
line at setup time rather than re-derived from the working directory. On a missing or invalid
profile it exits non-zero and prints no credentials.

**`setup-github-app-git.sh <profile>`**
Takes the profile as a required argument. In addition to today's work (bot identity from the
profile, HTTPS origin, `gh-app.profile`, unsetting any legacy `gh-app.enabled`) it resets the
credential helper list so inherited helpers cannot win:

```bash
git config --local --unset-all credential.https://github.com.helper || true
git config --local --add credential.https://github.com.helper ""          # clears osxkeychain + gh
git config --local --add credential.https://github.com.helper "<helper> --profile <name>"
```

Idempotent — running twice must leave one reset and one helper, not duplicates. Keeps `--parse`
for tests.

**`gh-app-status.sh`** (new)
Takes no arguments and resolves the profile from the working directory by the same five-step
rule as the shim, so it reports what `gh` and `git push` would actually do rather than what a
passed-in name claims. Outside a repo, or in a repo with no profile, it says so and exits zero
— pass-through is a valid state, not a fault.

Answers "which bot am I, here?" in one command: resolved profile and its file path, App
slug/ID/installation ID, whether the private key is readable, the commit identity git will use,
the effective credential helper list, and a live check that mints a token and confirms this
repository is in that installation's repository list. Exits non-zero on any inconsistency so an
agent can gate on it before its first push.

**`install.sh`**
Same loop, plus `gh-app-status.sh`.

### Commands

`skills/github-app-identity/SKILL.md` is deleted and replaced by:

| File | Command | Purpose |
|---|---|---|
| `commands/setup.md` | `/github-app-identity:setup [profile]` | Machine-once install, then walk the runbook to create an App and write a profile |
| `commands/enable.md` | `/github-app-identity:enable <profile>` | Enable the current clone for that identity |

Both are human-initiated setup operations. No `status` command: `gh-app-status.sh` is on `PATH`
and the abort messages name it, so wrapping it would add surface for nothing.

These are the first commands in this marketplace, so they set the convention: frontmatter
carrying `description`, `argument-hint`, and `allowed-tools`. `check-plugin.sh` validates
manifests, agents, and skills only — removing the skill leaves its skill checks vacuous for
this plugin and breaks nothing.

## Error handling

Every path fails closed. No condition results in a personal-credential fallback.

| Condition | Response |
|---|---|
| Invalid profile name | Abort; state the allowed pattern |
| Profile file missing | Abort; print the expected path and the profiles that do exist |
| Key unreadable, mint fails, or empty token | Abort; message ends with "do not retry with personal credentials or `gh auth login` — run `gh-app-status.sh`" |
| Legacy `gh-app.enabled`, no `gh-app.profile` | Abort; "legacy config, re-run `setup-github-app-git.sh <profile>`" |
| Credential helper cannot mint | Exit non-zero, print no credentials; the helper-list reset means git has no fallback and fails loudly |
| Repo outside the App's installation | `gh-app-status.sh` names it; otherwise a push 403s with nothing explaining why |

The wording of the mint-failure message is load-bearing — it is where the doctrine formerly
carried by the skill now lives.

## Testing

The existing test files under `scripts/tests/` extend wherever the profile argument reaches
them — `test_owner_repo_parse.sh` is unaffected, the other four change. New coverage:

- **Credential precedence regression** — simulate a global `gh auth git-credential` helper via
  `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`, run `git credential fill`, assert the App helper
  wins. This is the test whose absence let the defect ship.
- **Cache isolation** — mint under two profiles; assert two distinct cache files and no token
  bleed between them.
- **Two-repo resolution** — real `git init` repos carrying different `gh-app.profile` values;
  assert each invocation receives its own `--profile`. Replaces the deleted
  `GH_APP_ENABLED_OVERRIDE` escape hatch with a test of the real resolution path.
- **Legacy trap** — a repo with `gh-app.enabled` and no profile aborts rather than passing
  through.
- **Setup idempotence** — running setup twice leaves one reset and one helper.
- **Status** — with a stubbed token command, assert the report and the non-zero exit on
  inconsistency.

CI gains a job running `scripts/tests/*.sh` on both `macos-latest` and `ubuntu-latest`, added
to `.github/workflows/plugins.yml`. Both platforms matter: the repo targets bash 3.2 and
forbids GNU-only constructs, and a Linux-only run would hide exactly the breakage that rule
exists to prevent.

## Migration

One-time, documented in the runbook:

1. `mkdir -p ~/.config/gh-app/profiles`
2. Move the existing `~/.config/gh-app/github-app.env` to `profiles/<name>.env`
3. Create the second App and write `profiles/<name>.env` for it
4. Re-run `scripts/install.sh`
5. In each clone: `setup-github-app-git.sh <profile>`

A clone missed in step 5 aborts on its next `gh` call via the legacy trap rather than
misattributing work.

## Documentation

- `README.md` — rewritten around profiles and per-clone selection
- `templates/setup-runbook.md` — per-profile setup, generic permissions, migration section
- `templates/github-app.env.example` → `templates/profile.env.example`
- `templates/adr-github-app-identity.md` — records profile-based selection and the credential
  helper reset
- `.claude-plugin/plugin.json` — version 0.2.0
- `plugins/devtools/skills/pr-reviewer/SKILL.md` and `plugins/devtools/README.md` — note that
  two identities are what make a real `APPROVE` possible

## Out of scope

- GitHub Actions CI identity (use `actions/create-github-app-token`)
- Cryptographically verified commit signatures
- Any per-role App permission recipe
- A profile-listing command or a `status` slash command
