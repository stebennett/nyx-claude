---
name: migrate
description: One-time cutover that upgrades a repo initialized by an older kanban-flow to the plugin-owned-doctrine model. Deletes the now-redundant doctrine/template copies from the board dir, folds any local customizations into PROTOCOL-ADDENDUM.md, preserves customized templates via template_overrides, adds missing config keys, stamps kanban_flow_version, and opens a PR. Idempotent. Run when /kanban nudges you, or after updating the plugin.
---

# /migrate — bring an existing repo onto plugin-owned doctrine

Older `/kanban-init` runs copied the doctrine (`AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`)
and the templates (`card-template.md`, `pr-template.md`, `design-pr-template.md`) into
`<board_dir>`. Those files are now **plugin-owned** and read live, so the copies are
stale and ignored — and any **local customization** baked into them (e.g. `/retro`
edits) silently stops taking effect. This one-time cutover retires the copies while
preserving anything local, and stamps the repo as current. It is **idempotent** — safe
to re-run.

Resolve `board_dir` from the argument, else `docs/cards`. The plugin's current files
live at `${CLAUDE_PLUGIN_ROOT}/templates/`; the current plugin version is the `version`
field of `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. You write only inside the
target repo, on a migration branch, and you never modify the plugin.

## Steps

1. **Resolve + detect.** Read `<board_dir>/config.md`: its `kanban_flow_version` (empty
   on a pre-versioning repo) and its `template_overrides`. Read the installed plugin
   version. Scan `<board_dir>` for leftover plugin-owned copies: `AGENT-PROTOCOL.md`,
   `REVIEW-LENSES.md`, `card-template.md`, `pr-template.md`, `design-pr-template.md`. **If
   the version is already current AND no copy is present → report "already migrated" and
   stop** (do nothing destructive).

2. **Branch.** Create `task/migrate-<plugin-version>` off the current branch — every
   change rides one PR. Never commit migration changes straight to `main`.

3. **Ensure the addendum exists.** If `<board_dir>/PROTOCOL-ADDENDUM.md` is absent (an
   older repo never had one), create it from
   `${CLAUDE_PLUGIN_ROOT}/templates/PROTOCOL-ADDENDUM.md` first, so Step 4's appends have
   a home.

4. **Doctrine copies** — for each of `AGENT-PROTOCOL.md` and `REVIEW-LENSES.md` present in
   `<board_dir>`, diff it against the plugin's current
   `${CLAUDE_PLUGIN_ROOT}/templates/<name>`:
   - **Equivalent** (identical bar trailing whitespace) → the copy is redundant; `git rm`
     it.
   - **Differs** → the difference is local customization. Extract **only what the repo
     copy adds or changes over the plugin version** (a project rule; a tuned lens brief),
     rewrite it as an addendum rule (it layers on the plugin doctrine — never paste the
     whole file), and **present that extracted delta to the driver for approval**. On
     approval, append it to `<board_dir>/PROTOCOL-ADDENDUM.md` under a dated heading
     (`## [migrate-<plugin-version>] from <name>`), then `git rm` the copy. If the driver
     rejects the extraction or you cannot confidently isolate the delta, **stop and
     surface it** rather than deleting the copy — a wrong extraction loses process history.

5. **Template copies** — for each of `card-template.md`, `pr-template.md`,
   `design-pr-template.md` present in `<board_dir>`, diff against the plugin's current
   `${CLAUDE_PLUGIN_ROOT}/templates/<name>`:
   - **Equivalent** → `git rm` it.
   - **Differs** → the repo shaped this template; **keep the file** and set
     `config.md`'s `template_overrides["<name>"]` to its repo-relative path so the skills
     keep using the project's version. A template is a fill-in artifact, not prose
     doctrine — it never goes in the addendum.

6. **Config.** In `<board_dir>/config.md`, add any key present in the plugin's current
   `${CLAUDE_PLUGIN_ROOT}/templates/config.md` frontmatter but missing here (**additive
   only** — never change an existing value, nor a `template_overrides` entry you set in
   Step 5). Then set `kanban_flow_version` to the installed plugin version.

7. **Ship a PR.** Commit the deletions, the addendum appends, the `template_overrides`
   wiring, and the config changes (Conventional Commits + the project's `Co-Authored-By`
   trailer). Push and open a PR against `main` via `{gh_command} pr create`. The PR body
   lists explicitly: every file deleted, every customization folded into the addendum
   (with its text), every template preserved via `template_overrides`, and the config
   keys added plus the version bump. Process changes get the same human review as code.

8. **Report.** Give the driver the PR url and a one-line summary; the migration takes
   effect when they merge it.

## Rules

- **Idempotent:** a re-run after the PR merges finds the version current and no copies →
  no-op. Safe to run any time `/kanban` nudges you.
- Read-only toward the plugin; write only inside the target repo, on the migration branch.
- **Never touch board state** — `BOARD.md`, `KNOWLEDGE.md`, `MILESTONES.md`, cards, ADRs.
  Only the doctrine/template copies, `PROTOCOL-ADDENDUM.md`, and `config.md`.
- Never delete a **customized** template — preserve it via `template_overrides`; never
  fold a template into the addendum.
- Never silently drop a local **doctrine** customization — extract it to the addendum with
  driver approval, or stop and surface it.
- Do not run `/kanban` or `/refine`; just migrate and hand off the PR.
