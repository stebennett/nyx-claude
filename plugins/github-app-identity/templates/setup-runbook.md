# GitHub App identity — setup runbook

One-time, human-run setup so local automation (Claude Code, agents, your scripts) acts as
dedicated **GitHub Apps** inside clones you opt in. Each bot identity is a **profile** backed
by its own App — run sections 1–5 once per identity, then section 7 once per clone. Scope is
local tooling only (not GitHub Actions — see the end).

## 1. Create the App

GitHub → Settings → Developer settings → **GitHub Apps** → **New GitHub App**.

- **Name:** anything (note the resulting **slug** in the App URL, e.g. `my-bot`).
- **Homepage URL:** any URL you own.
- **Webhook:** **uncheck Active** (not needed for local use).
- **Repository permissions:** grant what this identity's role actually needs. `Metadata:
  Read-only` is always required. Beyond that it depends on what the agent does, so decide per
  App rather than copying a recipe.
- **Where can this app be installed:** Only on this account.

Create it, then note the **App ID** on the settings page.

## 2. Generate a private key

On the App settings page, **Generate a private key**; a `.pem` downloads. Move it somewhere
outside any repo:

```bash
mkdir -p ~/.config/gh-app
mv ~/Downloads/<app-slug>.*.private-key.pem ~/.config/gh-app/<profile>.pem
chmod 600 ~/.config/gh-app/<profile>.pem
```

Naming the key after the profile keeps two Apps from colliding on one filename.

## 3. Install the App on your account

Install the App on your account (all repos, or select repos — you can add more later).
Capture the **Installation ID** from the install-settings URL
(`.../installations/<INSTALLATION_ID>`), or once the key exists:

```bash
gh api /users/<your-account>/installation --jq .id
```

## 4. Find the bot user id

```bash
gh api /users/<app-slug>[bot] --jq .id
```

This numeric id builds the commit email `<id>+<app-slug>[bot]@users.noreply.github.com`.

## 5. Write the profile

```bash
mkdir -p ~/.config/gh-app/profiles
cp templates/profile.env.example ~/.config/gh-app/profiles/<profile>.env
$EDITOR ~/.config/gh-app/profiles/<profile>.env   # fill in all five values
```

Profile names must match `^[A-Za-z0-9][A-Za-z0-9._-]*$` — `builder`, `pr-reviewer`. Repeat
sections 1–5 for each identity you want.

## 6. Install the scripts on PATH (once per machine)

```bash
scripts/install.sh    # installs into ~/.local/bin (override with GH_APP_BIN=...)
```

Ensure the install dir precedes your real `gh` on `PATH` (`type -a gh` — the shim should be
first). install.sh warns if not.

## 7. Enable a clone

Inside each clone you want to opt in:

```bash
setup-github-app-git.sh <profile>   # bot identity, HTTPS origin, credential reset, marker
```

This registers the credential helper as
`!"<abs path>/git-credential-github-app.sh" --profile <profile>` — the leading `!` forces git
to run the value through a shell, which is the only form that survives a space anywhere in the
plugin's install path (verified against git 2.50.1: the unquoted and plain double-quoted forms
both silently fail to produce credentials). It is the same shape `gh auth login` writes.

Identity is per clone, not per worktree — every worktree of a clone inherits it. Two identities
in one repository means two clones.

## 8. Verify

```bash
# a) inside an enabled clone, everything agrees and the App can see the repo
gh-app-status.sh

# b) git will actually use the App, not an inherited helper
printf 'protocol=https\nhost=github.com\n\n' | git credential fill | grep username
#    expected: username=x-access-token

# c) outside any enabled clone, gh is unchanged
cd /tmp && gh auth status   # your personal identity, untouched
```

## Troubleshooting

**`setup-github-app-git.sh` refuses with "this repo's HTTPS URL is rewritten ... by a
url.\*.insteadOf rule".** A `url.<base>.insteadOf` rule in your git config (often from a
personal dotfile) rewrites URLs before git uses them — for example
`url.git@github.com:.insteadOf https://github.com/` turns the HTTPS origin this plugin just set
back into an SSH URL. Pushes would then go out over SSH under your personal key, and the App
credential helper would never be consulted at all — the repo would look configured for the App
identity while every push was actually personal. `setup-github-app-git.sh` checks for this with
`git ls-remote --get-url` *before* writing any config, and refuses rather than leave the repo
half set up. `gh-app-status.sh` reports the same condition if a rule like this is added after
the fact. The remedy is to narrow or remove the rule, e.g.:

```bash
git config --global --unset-all url.<base>.insteadof
# or scope it to the hosts that actually need it instead of removing it outright
```

Then re-run `setup-github-app-git.sh <profile>`.

## Migrating from the single-App layout

Earlier versions kept one App in `~/.config/gh-app/github-app.env` and marked repos with
`gh-app.enabled`. To move:

```bash
mkdir -p ~/.config/gh-app/profiles
mv ~/.config/gh-app/github-app.env ~/.config/gh-app/profiles/<profile>.env
bash scripts/install.sh
```

Then, in every clone that was enabled: `setup-github-app-git.sh <profile>`.

A clone you miss aborts on its next `gh` call — `gh-app.enabled` without `gh-app.profile` is
treated as broken config, not as a reason to pass through to your personal identity.

## Future: GitHub Actions CI

For CI, mint the token in-workflow with
[`actions/create-github-app-token`](https://github.com/actions/create-github-app-token) using
the same App (App ID + private key as repo secrets) — do not reuse a personal PAT. This plugin
covers local tooling only.
