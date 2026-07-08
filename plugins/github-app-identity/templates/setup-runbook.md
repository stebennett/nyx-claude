# GitHub App identity — setup runbook

One-time, human-run setup so local automation (Claude Code, agents, your scripts) acts as a
dedicated **GitHub App** inside repos you opt in. Scope is local tooling only (not GitHub
Actions — see the end).

## 1. Create the App

GitHub → Settings → Developer settings → **GitHub Apps** → **New GitHub App**.

- **Name:** anything (note the resulting **slug** in the App URL, e.g. `my-bot`).
- **Homepage URL:** any URL you own.
- **Webhook:** **uncheck Active** (not needed for local use).
- **Repository permissions:** **Contents → Read & write**, **Pull requests → Read & write**,
  **Metadata → Read-only**. No account permissions.
- **Where can this app be installed:** Only on this account.

Create it, then note the **App ID** on the settings page.

## 2. Generate a private key

On the App settings page, **Generate a private key**; a `.pem` downloads. Move it somewhere
outside any repo:

```bash
mkdir -p ~/.config/gh-app
mv ~/Downloads/<app-slug>.*.private-key.pem ~/.config/gh-app/app.pem
chmod 600 ~/.config/gh-app/app.pem
```

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

## 5. Write the shared config

```bash
cp templates/github-app.env.example ~/.config/gh-app/github-app.env
$EDITOR ~/.config/gh-app/github-app.env   # fill in all five values
```

## 6. Install the scripts on PATH (once per machine)

```bash
scripts/install.sh    # installs into ~/.local/bin (override with GH_APP_BIN=...)
```

Ensure the install dir precedes your real `gh` on `PATH` (`type -a gh` — the shim should be
first). install.sh warns if not.

## 7. Enable a repo

Inside each repo you want to opt in:

```bash
setup-github-app-git.sh   # bot identity, HTTPS origin, credential helper, gh-app.enabled
```

## 8. Verify

```bash
# a) inside an enabled repo, gh authenticates as the App
gh api /installation/repositories --jq '.repositories[].full_name'

# b) commits are bot-authored
git config user.name; git config user.email

# c) outside any enabled repo, gh is unchanged
cd /tmp && gh auth status   # your personal identity, untouched
```

## Future: GitHub Actions CI

For CI, mint the token in-workflow with
[`actions/create-github-app-token`](https://github.com/actions/create-github-app-token) using
the same App (App ID + private key as repo secrets) — do not reuse a personal PAT. This plugin
covers local tooling only.
