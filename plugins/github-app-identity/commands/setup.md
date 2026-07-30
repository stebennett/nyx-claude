---
description: Set up this machine for GitHub App bot identities, and add a named App profile.
argument-hint: "[profile-name]"
allowed-tools: Bash, Read, Edit
---

# Set up a GitHub App bot identity

Target profile: **$1** (if empty, ask which identity is being created — e.g. `builder`,
`pr-reviewer` — before doing anything).

Profile names must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`: letters, digits, dot and dash only.

## 0. Resolve the plugin root

This command references files inside the `github-app-identity` plugin. When the plugin is installed
elsewhere (not in this repo), relative paths like `plugins/github-app-identity/templates/...` do
not exist. Resolve the plugin root first:

```bash
if [ -n "$CLAUDE_PLUGIN_ROOT" ] && [ -d "$CLAUDE_PLUGIN_ROOT" ]; then
  PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
elif [ -d "plugins/github-app-identity" ]; then
  PLUGIN_ROOT="plugins/github-app-identity"
else
  echo "github-app-identity plugin not found in either location."
fi
```

These steps run via the Bash tool, which has no stdin — a shell `read` here would always
resolve empty and never actually ask anyone. If `PLUGIN_ROOT` is still unset after the check
above, **ask the user directly** (a normal conversational question, not a shell prompt) where
the plugin is installed. Once they answer, verify it's a directory before continuing; if it
isn't, report that and stop.

Every step below uses `$PLUGIN_ROOT` to find the plugin's templates and scripts.

## 1. Check what already exists

```bash
ls "${GH_APP_PROFILE_DIR:-$HOME/.config/gh-app/profiles}" 2>/dev/null
type -a gh
```

If the profile file already exists, stop and report it — do not overwrite an identity.

## 2. Walk the user through creating the App

The user must do this part in a browser; you cannot. Point them at
`$PLUGIN_ROOT/templates/setup-runbook.md` and wait for the values it produces. Each identity needs its
**own** App: two agents sharing one App share one identity, which defeats the purpose.

Collect five values: App ID, installation ID, private key path, App slug, bot user id.

## 3. Write the profile

```bash
mkdir -p "${GH_APP_PROFILE_DIR:-$HOME/.config/gh-app/profiles}"
cp "$PLUGIN_ROOT/templates/profile.env.example" \
   "${GH_APP_PROFILE_DIR:-$HOME/.config/gh-app/profiles}/<profile>.env"
```

Fill in all five values. The private key belongs outside any repo, `chmod 600`.

## 4. Install the scripts

```bash
bash "$PLUGIN_ROOT/scripts/install.sh"
```

Confirm the shim wins on `PATH` — `type -a gh` must list `~/.local/bin/gh` first. `install.sh`
warns when it does not; that warning is not optional to fix, since a losing shim means every
`gh` call silently uses personal auth.

## 5. Enable a clone

Setup does not enable any repository. Tell the user to run `/github-app-identity:enable
<profile>` inside each clone that should use this identity — typically one clone per identity.
