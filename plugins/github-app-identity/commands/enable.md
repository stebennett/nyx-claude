---
description: Point this clone at a GitHub App identity, so its commits, pushes, and gh calls act as that bot.
argument-hint: "<profile-name>"
allowed-tools: Bash
---

# Enable a GitHub App identity in this clone

Target profile: **$1** (required — if empty, list the available profiles with
`ls "${GH_APP_PROFILE_DIR:-$HOME/.config/gh-app/profiles}"` and ask which one).

Identity is per **clone**, not per worktree: `git config --local` in a linked worktree resolves
to the clone's shared config, so every worktree of this clone inherits what you set here. Two
identities in one repository means two clones.

## 1. Enable

```bash
setup-github-app-git.sh "$1"
```

This sets the bot commit identity, switches `origin` to HTTPS, resets the credential helper
list so inherited helpers cannot answer first, and writes `gh-app.profile`.

## 2. Verify

```bash
gh-app-status.sh
```

Every line must be clean. Report the output to the user. If it reports problems, fix the setup
— never work around an auth failure with personal credentials or `gh auth login`.
