---
title: Local automation acts as a dedicated GitHub App
status: Accepted
date: YYYY-MM-DD
---

# ADR: Local automation acts as a dedicated GitHub App

## Context

Local automation (Claude Code, agents, scripts) committed, pushed, and made `gh`/API calls as
a personal account. We want machine-generated work to carry a distinct, auditable identity and
to never silently use personal credentials.

## Decision

Adopt the `github-app-identity` plugin with one **profile** per bot identity. Each profile is
an env file under `~/.config/gh-app/profiles/<name>.env` naming its own GitHub App, and a clone
opts in with `git config --local gh-app.profile <name>`. A global directory-aware `gh` shim, a
git credential helper, and per-repo git config make commits, pushes, and `gh`/API calls act as
that App inside that clone only. The shim aborts rather than fall back to personal auth if a
token cannot be minted, and tokens are cached per profile so identities cannot bleed.

Enabling a repo resets git's credential helper list before registering the App helper: git
consults helpers system → global → local and uses the first that answers, so an appended helper
loses to the github.com helper `gh auth login` writes into `~/.gitconfig`. The registered value
carries a leading `!` — `!"<abs path>/git-credential-github-app.sh" --profile <name>` — which
forces git to run it through a shell; this is the only form that survives a space anywhere in
the plugin's install path (verified against git 2.50.1), and it is the same shape `gh auth
login` writes.

Identity is per clone, not per worktree — `--local` in a linked worktree resolves to the
clone's shared config. Two identities in one repository means two clones. Commits are
bot-authored but not cryptographically "Verified". GitHub Actions CI is out of scope.

## Consequences

Easier: machine work is attributable to a specific bot, not a person; a reviewer identity
distinct from the author identity restores real `APPROVE`/`REQUEST_CHANGES` verdicts; no
per-call-site wrapping and no silent personal-auth fallback. Harder: one App and one profile
per identity to create and maintain; a one-time per-machine install; the shim relies on `PATH`
precedence; each App is its own revocation point; and running two identities against one
repository requires two clones.
