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

Adopt the `github-app-identity` plugin. A dedicated GitHub App is installed on the account; a
global directory-aware `gh` shim, a git credential helper, and per-repo git config make
commits, pushes, and `gh`/API calls act as the App **only inside repos with
`git config gh-app.enabled true`**. The shim aborts rather than fall back to personal auth if a
token cannot be minted. App config lives in `~/.config/gh-app/github-app.env`. Commits are
bot-authored but not cryptographically "Verified". GitHub Actions CI is out of scope.

## Consequences

Easier: machine work is attributable to the App, not a person; no per-call-site wrapping and no
silent personal-auth fallback; one shared App/config across repos. Harder: a one-time
per-machine install + App setup is required; the shim relies on `PATH` precedence; the shared
App is a single revocation point.
