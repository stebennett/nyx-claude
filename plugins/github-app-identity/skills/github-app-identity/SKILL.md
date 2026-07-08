---
name: github-app-identity
description: Use to give a repo's local automation a dedicated GitHub App identity — bot-authored commits, App-authenticated pushes, and gh/API calls that act as the App inside the repo — via a global directory-aware gh shim, with no fallback to personal credentials. Invoke to set up the machine once and to enable a repo.
---

# github-app-identity

Make local automation act as a dedicated **GitHub App** instead of personal credentials,
inside repos you opt in. A global `gh` shim, a git credential helper, and per-repo git config
do the work; there is nothing to wire per call site and no silent fallback to personal auth.

## When to use

- The user wants machine/agent commits, pushes, and `gh` calls to be attributed to a bot App.
- Setting up a new machine, or enabling the App identity in a new repo.

## Mechanism (what you are configuring)

- A global **`gh` shim** on `PATH` (installed at `${GH_APP_BIN:-~/.local/bin}/gh`) checks, for
  the current repo, `git config --get gh-app.enabled`. If `true`, it mints an App installation
  token and `exec`s the real `gh` with `GH_TOKEN`; otherwise it passes through unchanged. On an
  empty/failed token it **aborts** — never personal-auth fallback.
- A **git credential helper** does the same for `git push`/`fetch`.
- Bot commit identity is per-repo git config.
- All App values come from one shared file, `${GITHUB_APP_ENV:-~/.config/gh-app/github-app.env}`.

## Machine setup (once per machine)

Follow `templates/setup-runbook.md`:
1. Create the App (Contents + Pull requests: write; Metadata: read), generate a key, install on
   the account.
2. `cp templates/github-app.env.example ~/.config/gh-app/github-app.env` and fill in the five
   values.
3. `scripts/install.sh` (installs `gh`, `github-app-token.sh`, `git-credential-github-app.sh`,
   `setup-github-app-git.sh` into `${GH_APP_BIN:-~/.local/bin}`). Confirm that dir precedes the
   real `gh` on `PATH` (`type -a gh`).

## Enable a repo

Inside the target repo: `setup-github-app-git.sh`. It sets the bot identity, switches `origin`
to HTTPS, registers the credential helper, and sets `gh-app.enabled true` (owner/repo derived
from the remote). Idempotent.

## Using it (agents & humans)

Just run `gh …` and `git push` normally. Inside an enabled repo they act as the App
automatically; elsewhere they are unchanged. **Never** work around a token error by using
personal auth — a failure means setup is incomplete (config missing, key unreadable). Fix
setup; the shim aborting is by design.

## Verify

```bash
gh api /installation/repositories --jq '.repositories[].full_name'   # enabled repo → the App
```

## kanban-flow interop

A repo using the `kanban-flow` plugin no longer needs a wrapper in `gh_command` — `gh` alone
acts as the App via the shim.

## Scope

Local tooling only; GitHub Actions CI is out of scope (use `actions/create-github-app-token`
there). Commits are bot-authored but not cryptographically "Verified".
