# kanban-flow Plugin-Owned Doctrine — P2 (`/migrate`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the one-time `/migrate` skill that upgrades a repo initialized by an older kanban-flow to the plugin-owned-doctrine model (P1) — deleting redundant doctrine/template copies, folding local customizations into `PROTOCOL-ADDENDUM.md`, preserving customized templates via `template_overrides`, adding missing config keys, stamping `kanban_flow_version`, and shipping a PR. Idempotent.

**Architecture:** Documentation/skill authoring only — no code, no test runner. `/migrate` is a Markdown SKILL.md (auto-discovered from `skills/`). Verification is `grep` + read-through + confirming the skill's plugin-owned-file list, config keys, and version handling **match P1's** (built on this same branch: `templates/config.md`, `skills/kanban-init/SKILL.md`, `skills/kanban/SKILL.md`). This is **P2 of 2** and lands on the **same branch as P1** (`feat/kanban-plugin-owned-doctrine`) so both ship in PR #4.

**Tech Stack:** Markdown, `git`, `grep`. No build tooling.

## Global Constraints

- **Paths** are relative to repo root `/Users/stevebennett/Code/nyx-claude`; all edits under `plugins/kanban-flow/`.
- **The plugin-owned file set** (must be named identically to P1's `kanban-init` "Do not copy" note and `kanban/SKILL.md` migration-check scan): `AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `card-template.md`, `pr-template.md`, `design-pr-template.md`.
- **Config keys** (from P1): `kanban_flow_version` (string), `template_overrides` (map from a template filename → repo-relative path). Spell them exactly.
- **Preserve placeholders verbatim:** `${CLAUDE_PLUGIN_ROOT}`, `<board_dir>`, `{gh_command}`. The current plugin version is read at runtime from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` `version` (do not hardcode a value in the skill prose).
- **`/migrate` writes only inside the target repo, on a migration branch, and opens a PR** — it never commits to `main`, never touches board state (`BOARD.md`/`KNOWLEDGE.md`/`MILESTONES.md`/cards/ADRs), and is read-only toward the plugin.
- **Commits:** Conventional Commits ending with the trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Same branch as P1 — the controller handles the (already-open) PR; each task just commits.
- **RTK proxy:** if an `rtk`-wrapped `grep`/`git` rejects a flag, use `rtk proxy <command>`.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `plugins/kanban-flow/skills/migrate/SKILL.md` | New: the one-time cutover skill | Create |
| `plugins/kanban-flow/README.md` | Plugin overview | Add `migrate` to Skills; add an "Upgrading an existing repo" note |

**Not changed:** P1 already added the migration **nudge** (`kanban/SKILL.md`), the config keys, and the `PROTOCOL-ADDENDUM.md` template — P2 only adds the skill that acts on the nudge, plus docs.

---

## Task 1: Author the `/migrate` skill

**Files:**
- Create: `plugins/kanban-flow/skills/migrate/SKILL.md`

**Interfaces:**
- Consumes (from P1, on this branch): `template_overrides` / `kanban_flow_version` in `config.md`; the `PROTOCOL-ADDENDUM.md` template; the plugin-owned file set as named in `kanban-init` and `kanban`'s migration check.
- Produces: the `/migrate` skill the P1 nudge ("run `/migrate`") points at.

- [ ] **Step 1: Create the skill file**

Create `plugins/kanban-flow/skills/migrate/SKILL.md` with exactly this content:
```markdown
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
```

- [ ] **Step 2: Verify the skill file**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
M=plugins/kanban-flow/skills/migrate/SKILL.md
test -f $M && echo "file OK"
grep -nF 'name: migrate' $M
grep -nF 'template_overrides["<name>"]' $M
grep -nF 'kanban_flow_version' $M
grep -nF '## [migrate-<plugin-version>] from <name>' $M
grep -nF 'Never touch board state' $M
# the plugin-owned file set must be named (all five):
for f in AGENT-PROTOCOL.md REVIEW-LENSES.md card-template.md pr-template.md design-pr-template.md; do grep -qF "$f" $M && echo "names $f"; done
```
Expected: `file OK`, each `grep` matches, and all five `names <f>` print.

- [ ] **Step 3: Confirm consistency with P1 (same branch)**

Read (do not edit) and confirm the skill's assumptions match what P1 built:
- `plugins/kanban-flow/skills/kanban-init/SKILL.md` "Do not copy" note names the **same five** plugin-owned files.
- `plugins/kanban-flow/skills/kanban/SKILL.md` Section 1 migration check scans the **same five** and compares `kanban_flow_version`; Section 7 nudge says "run `/migrate`".
- `plugins/kanban-flow/templates/config.md` defines `kanban_flow_version` and `template_overrides` with these exact names; `plugins/kanban-flow/templates/PROTOCOL-ADDENDUM.md` exists (Step 3 copies it).

If any mismatch (a file name, a key name) is found, the defect is in THIS new skill — align the skill's wording to P1's (P1 is merged-in on this branch and is the source of truth) and re-verify. Note the confirmation in the report.

- [ ] **Step 4: Commit**

```bash
git add plugins/kanban-flow/skills/migrate/SKILL.md
git commit -m "feat(kanban-flow): add /migrate — one-time cutover to plugin-owned doctrine

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Document `/migrate` in the README

**Files:**
- Modify: `plugins/kanban-flow/README.md` (Skills line ~18; new "Upgrading an existing repo" section)

**Interfaces:**
- Consumes: the `/migrate` skill from Task 1.

- [ ] **Step 1: Add `migrate` to the Skills list**

Replace:
```
- **Skills:** `kanban` (orchestrator), `refine` (backlog intake), `retro` (process improvement), `adr` (ADR persistence), `kanban-init` (project scaffolder).
```
with:
```
- **Skills:** `kanban` (orchestrator), `refine` (backlog intake), `retro` (process improvement), `adr` (ADR persistence), `kanban-init` (project scaffolder), `migrate` (one-time upgrade of an existing repo to plugin-owned doctrine).
```

- [ ] **Step 2: Add an "Upgrading an existing repo" section**

Immediately after the `## Contents` block (i.e. before the next `##` heading, or at end of file if none follows), insert:
```
## Upgrading an existing repo

Doctrine and templates are **plugin-owned** and read live, so updating the plugin
updates every project automatically — no per-repo action for an uncustomized board.

A repo initialized by an **older** kanban-flow still has copies of the doctrine and
templates in its board dir; those copies are now ignored, and any local customization
in them stops taking effect. `/kanban` detects this and nudges you to run **`/migrate`**
— a one-time, idempotent cutover that deletes the redundant copies, folds any local
doctrine edits into `PROTOCOL-ADDENDUM.md`, preserves a customized template via
`template_overrides`, adds any new `config.md` keys, stamps `kanban_flow_version`, and
opens a PR for you to review and merge.
```

- [ ] **Step 3: Verify**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
grep -nF '`migrate` (one-time upgrade' plugins/kanban-flow/README.md
grep -nF '## Upgrading an existing repo' plugins/kanban-flow/README.md
grep -nF 'run **`/migrate`**' plugins/kanban-flow/README.md
```
Expected: all three match.

- [ ] **Step 4: Commit**

```bash
git add plugins/kanban-flow/README.md
git commit -m "docs(kanban-flow): document /migrate and repo upgrading in the README

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Discovery + coherence sweep

**Files:**
- Read-only review (edit + commit only if a defect is found)

- [ ] **Step 1: Confirm skill discovery shape**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
test -f plugins/kanban-flow/skills/migrate/SKILL.md && echo "at skills/migrate/SKILL.md"
head -4 plugins/kanban-flow/skills/migrate/SKILL.md   # valid frontmatter: name + description
ls plugins/kanban-flow/skills/          # migrate/ sits alongside kanban/, kanban-init/, etc.
```
Expected: the file is at `skills/migrate/SKILL.md` with `name:`/`description:` frontmatter, alongside the other skills — so it is auto-discovered (no `marketplace.json`/manifest edit needed).

- [ ] **Step 2: End-to-end coherence — the nudge points at a skill that does what P1 expects**

Read as a fresh reviewer:
- `kanban/SKILL.md` Section 1 migration check + Section 7 nudge → confirm the condition that sets `migration_needed` (version behind OR leftover copy) is exactly the condition `/migrate` Step 1 detects and acts on, and the nudge names `/migrate`.
- `/migrate` Steps 4–6 delete/fold/preserve/stamp exactly the file set + keys P1 introduced — no file P1 keeps is deleted, no key P1 didn't define is written.
- `/migrate` never writes board state or the plugin (Rules).

Fix inline + commit if a gap is found; otherwise no commit.

- [ ] **Step 3: No stale "copies doctrine" claims remain after P2**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
grep -rnF 'copies into your repo' plugins/kanban-flow/    # must be EMPTY (P1 fixed the README line)
grep -rn 'docs/cards/AGENT-PROTOCOL.md\|docs/cards/REVIEW-LENSES.md' plugins/kanban-flow/   # must be EMPTY
```
Expected: both return nothing (P2 introduces no regressions; `/migrate` refers to copies as things it *removes*, not reads).

---

## Self-Review (completed during planning)

**Spec coverage (spec §4 `/migrate` steps + §5):**
- Detect (version + leftover copies; up-to-date → stop) → Task 1 Step 1 (skill Step 1). ✓
- Doctrine files: identical→delete, differs→fold into addendum (driver-approved) → skill Step 4. ✓
- Templates: identical→delete, differs→preserve via `template_overrides` → skill Step 5. ✓
- Config: additive keys + stamp `kanban_flow_version` → skill Step 6. ✓
- Ship as branch + PR listing everything → skill Steps 2 & 7. ✓
- Addendum stub created if missing (older repos) → skill Step 3 (a gap the spec implied — an old repo has no addendum; added explicitly). ✓
- README `/migrate` + upgrade docs (spec's P2 file list) → Task 2. ✓
- Skill auto-discovery (no manifest edit) → Task 3 Step 1. ✓

**Placeholder scan:** No `TBD`/`TODO`. `${CLAUDE_PLUGIN_ROOT}`, `<board_dir>`, `{gh_command}`, `<name>`, `<plugin-version>` are intentional runtime placeholders in the skill prose, preserved verbatim. ✓

**Consistency:** The plugin-owned five-file set and the key names (`kanban_flow_version`, `template_overrides`) are stated identically in the skill (Task 1), and Task 1 Step 3 + Task 3 Step 2 explicitly cross-check them against P1's `kanban-init`/`kanban`/`config.md` on this same branch — the seam most likely to drift. ✓
