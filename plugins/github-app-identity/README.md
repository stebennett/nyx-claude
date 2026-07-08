# github-app-identity

Give local automation (Claude Code, agents, your own scripts) a dedicated **GitHub App**
identity instead of your personal credentials — inside repos you opt in, with no silent
fallback to personal auth.

## How it works

- A global **`gh` shim** on `PATH` is directory-aware: inside a repo with
  `git config gh-app.enabled true`, it mints a short-lived App installation token and runs
  the real `gh` as the App; everywhere else it passes straight through. If the token can't be
  minted it **aborts** rather than fall back to your personal identity.
- A **git credential helper** does the same for `git push`/`fetch` over HTTPS.
- Bot-authored commits come from per-repo git config (`user.name`/`user.email`).

All App-specific values live in one shared file, `~/.config/gh-app/github-app.env`
(overridable via `$GITHUB_APP_ENV`), written once and shared by every repo.

## Setup

Run the `github-app-identity` skill and follow it:

1. **Once per machine:** create the App (`templates/setup-runbook.md`), fill
   `~/.config/gh-app/github-app.env`, then `scripts/install.sh` puts the scripts on `PATH`.
2. **Per repo:** run `setup-github-app-git.sh` — sets the bot identity, switches `origin` to
   HTTPS, registers the credential helper, and sets the `gh-app.enabled` marker.

Commits are bot-authored (not cryptographically "Verified"). GitHub Actions CI is out of scope.
