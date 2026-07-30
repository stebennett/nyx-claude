# github-app-identity

Give local automation (Claude Code, agents, your own scripts) dedicated **GitHub App**
identities instead of your personal credentials — several of them, one per clone, with no
silent fallback to personal auth.

Typical use: a build clone commits and pushes as one bot, a review clone reviews and merges as
another. Because GitHub rejects an `APPROVE` from a pull request's own author, two identities
are what make a real review verdict possible.

## How it works

- Each identity is a **profile**: one env file under `~/.config/gh-app/profiles/<name>.env`
  naming a GitHub App, its installation, and its key. Each identity needs its own App.
- A clone opts in with `git config --local gh-app.profile <name>`. A global `gh` **shim** on
  `PATH` reads that marker, mints a short-lived installation token for that profile, and runs
  the real `gh` as the App. Everywhere else it passes straight through. If the token cannot be
  minted it **aborts** rather than fall back to your personal identity.
- A **git credential helper** does the same for `git push`/`fetch` over HTTPS. Enabling a repo
  resets the credential helper list first, so helpers inherited from your global config
  (`gh auth login`) or the system config (osxkeychain) cannot answer before it.
- Bot-authored commits come from per-repo `user.name`/`user.email`.
- Tokens are cached **per profile**, so two clones can never reuse each other's identity.

Identity is per clone, not per worktree: `git config --local` in a linked worktree resolves to
the clone's shared config, so every worktree inherits the clone's identity. Two identities in
one repository means two clones.

## Setup

1. **Per identity:** `/github-app-identity:setup <profile>` — create the App (see
   `templates/setup-runbook.md`), write `~/.config/gh-app/profiles/<profile>.env`, and put the
   scripts on `PATH` with `scripts/install.sh`.
2. **Per clone:** `/github-app-identity:enable <profile>` — bot identity, HTTPS origin,
   credential helper reset, and the `gh-app.profile` marker.

## Checking

```bash
gh-app-status.sh    # which bot am I here, and can it actually see this repo?
```

An auth failure means setup is incomplete. Fix the setup — never work around it with personal
credentials or `gh auth login`.

Commits are bot-authored (not cryptographically "Verified"). GitHub Actions CI is out of scope:
use `actions/create-github-app-token` there.
