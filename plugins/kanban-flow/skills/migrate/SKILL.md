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
   `REVIEW-LENSES.md`, `card-template.md`, `pr-template.md`, `design-pr-template.md` — but
   a template file already registered in `template_overrides` (pointing at that path) is a
   deliberately-preserved override, **not** a leftover; only an *unregistered* copy counts.
   Also check each `docs/cards/CARD-*/card.md` for a legacy scalar or missing `reworks`,
   **or a card still carrying a scalar `pr_url` (present or absent — either form means the
   `pr_urls`/`split_slices` rewrite in Step 6 has not run on it)**, and compare the plugin's
   current `config.md` frontmatter keys against the repo's to detect any missing
   (additive-only).
   **If the version is already current AND no unregistered copy is present AND no card
   needs its frontmatter migrated AND no config key is missing → report "already migrated"
   and stop** (do nothing destructive). The version records what a previous run *intended*,
   not what it *achieved*; detect the work itself — a card still carrying a scalar `pr_url`
   is itself a trigger, version stamp notwithstanding.

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

6. **Card frontmatter — the `reworks` map, and the `pr_urls`/`split_slices` shape.** For every
   `docs/cards/CARD-*/card.md`, rewrite a legacy scalar `reworks: N` as the per-producer map:

   ```yaml
   reworks:
     slice: 0
     design: 0
     implement: N     # the old counter only ever counted test/review→implement loops
     deliver: 0
   ```

   A card with **no** `reworks` key gets the all-zero map. Also backfill `estimated_lines: ""`,
   `actual_lines: ""`, and `review_lenses_failed: []` on every card lacking them (missing
   `review_lenses_failed` is safe — the full lens panel runs — so this is hygiene, not a bug fix).

   This is the **one** exception to the "never touch board state" rule below, and it is a pure shape
   change: no status, phase, dependency or content is altered, and `implement: N` preserves the exact
   budget the card had. Cards at `status: review` need no special handling — `review.md` is absent, so
   the next `/kanban` pump dispatches the new lens panel for them.

   **Same step, the `pr_urls`/`split_slices` rewrite.** A legacy scalar `pr_url: <url>` becomes
   **`pr_urls: [<url>]`**; an empty or absent `pr_url` becomes **`pr_urls: []`**. Either way, also
   backfill **`split_slices: 0`** (0 = the card was not split; it ships as one PR) if the key is
   missing. A card that shipped as one PR is the **N=1 case, not a special case** — this is a rename
   plus a list-wrap, nothing more. **Do not touch `design_pr_url`** — the design PR is a separate,
   unaffected scalar field; `pr-splitter` never runs against it and this rewrite has nothing to say
   about it.

7. **Config.** In `<board_dir>/config.md`, add any key present in the plugin's current
   `${CLAUDE_PLUGIN_ROOT}/templates/config.md` frontmatter but missing here (**additive
   only** — never change an existing value, nor a `template_overrides` entry you set in
   Step 5). Then set `kanban_flow_version` to the installed plugin version.

   This run adds `checks`, `check_budget`, `size_limit` and `size_exclude` (all with plugin defaults —
   every check `on`, budgets 2 except `deliver: 1`, `size_limit: 500`). **Tell the driver in the PR
   body what `size_limit` means for them:** from the next `/kanban` pump, `card-slice-checker` will
   *force a split* on any card it projects over 500 changed lines including tests. That is a real
   behaviour change on an existing backlog, and it must not arrive as a surprise.

8. **Ship a PR.** Commit the deletions, the addendum appends, the `template_overrides`
   wiring, and the config changes (Conventional Commits + the project's `Co-Authored-By`
   trailer). Push and open a PR against `main` via `{gh_command} pr create`. The PR body
   lists explicitly: every file deleted, every customization folded into the addendum
   (with its text), every template preserved via `template_overrides`, and the config
   keys added plus the version bump. Process changes get the same human review as code.

9. **Report.** Give the driver the PR url and a one-line summary; the migration takes
   effect when they merge it.

## Rules

- **Idempotent:** a re-run after the PR merges finds the version current and no copies →
  no-op. Safe to run any time `/kanban` nudges you.
- Read-only toward the plugin; write only inside the target repo, on the migration branch.
- **Never touch board state** — `BOARD.md`, `KNOWLEDGE.md`, `MILESTONES.md`, ADRs, and any card's
  status, phase, dependencies or content. The doctrine/template copies, `PROTOCOL-ADDENDUM.md` and
  `config.md` are yours. **One exception:** the mechanical frontmatter edits in Step 6 — reshaping
  `reworks`, backfilling `estimated_lines`, `actual_lines` and `review_lenses_failed`, and rewriting a
  scalar `pr_url` into `pr_urls`/`split_slices` — all shape/backfill changes that preserve the card's
  existing budget and delivery history exactly and alter nothing else. `design_pr_url` is untouched by
  any of this — it is not a legacy field, just a scalar that was never part of the split.
- Never delete a **customized** template — preserve it via `template_overrides`; never
  fold a template into the addendum.
- Never silently drop a local **doctrine** customization — extract it to the addendum with
  driver approval, or stop and surface it.
- Do not run `/kanban` or `/refine`; just migrate and hand off the PR.
