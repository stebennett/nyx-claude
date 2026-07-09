# kanban-flow Plugin-Owned Doctrine — P1 (Re-architecture) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, and the three templates plugin-owned (read live via orchestrator-injected absolute paths); give repos a layered `PROTOCOL-ADDENDUM.md` and a `kanban_flow_version` stamp; stop `/kanban-init` copying doctrine; reroute `/retro`.

**Architecture:** Documentation/doctrine change only — no code, no test runner (CLAUDE.md: plugins are "validated by installing the plugin, not by a test runner"). Verification is `grep` assertions (old repo-path reads gone, new plugin-path wording present) plus read-through. This is **P1 of 2**; `/migrate` (P2) is a separate plan written after P1 lands, because its exact edits depend on P1's final wording.

**Tech Stack:** Markdown, `git`, `grep`. No build tooling.

## Global Constraints

- **Plugin root:** all edited files are under `plugins/kanban-flow/`. Paths below are relative to repo root `/Users/stevebennett/Code/nyx-claude`.
- **Plugin-owned files live at `${CLAUDE_PLUGIN_ROOT}/templates/`** and are resolvable from any skill/orchestrator context — `kanban-init` already uses `${CLAUDE_PLUGIN_ROOT}/templates/` in Bash, which proves it. Keep `${CLAUDE_PLUGIN_ROOT}` **verbatim** in doctrine text (it is a runtime placeholder, not something to resolve to a concrete path).
- **Doctrine delivery model:** the `/kanban` orchestrator resolves the plugin doctrine dir once per pump and passes absolute paths into each dispatch. Agents read the **plugin `AGENT-PROTOCOL.md` first, then the repo `PROTOCOL-ADDENDUM.md`** (addendum layers on top). Never make an agent depend on inheriting `${CLAUDE_PLUGIN_ROOT}` as an env var — it reads the absolute path the dispatch gives it.
- **`kanban_flow_version`** is sourced from the plugin's `plugin.json` `version` (currently `0.1.0`). Use the string `0.1.0` where a concrete value is needed.
- **Preserve these placeholders verbatim** wherever they already appear: `{gh_command}`, `{board_dir}`, `<board_dir>`, `<adr_dir>`, `${CLAUDE_PLUGIN_ROOT}`, `{owner}`/`{repo}`/`{n}`.
- **Do not touch board state** (`BOARD.md`/`KNOWLEDGE.md`/`MILESTONES.md`/cards/ADRs) semantics, the card lifecycle, or `AGENT-PROTOCOL.md`'s doctrine *content* — this plan changes only *where doctrine is read from* and *what init scaffolds*.
- **RTK proxy:** if an `rtk`-wrapped `grep`/`git` rejects a flag, fall back to `rtk proxy <command>`.
- **Commits:** Conventional Commits ending with the trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. This is a plugin change → it will ship as a branch + PR (the controller handles branch/PR at the end; each task just commits).

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `plugins/kanban-flow/templates/PROTOCOL-ADDENDUM.md` | New: repo-owned layered project doctrine stub | Create |
| `plugins/kanban-flow/templates/config.md` | Project tunables | Add `kanban_flow_version` + `template_overrides` (frontmatter + docs) |
| `plugins/kanban-flow/skills/kanban-init/SKILL.md` | Scaffolder | Stop copying the 5 plugin-owned files; scaffold addendum + version stamp |
| `plugins/kanban-flow/templates/AGENT-PROTOCOL.md` | The shared contract | Add the injected doctrine paths to "On dispatch you receive" |
| `plugins/kanban-flow/agents/*.md` (7 files) | Phase agents | Doctrine read-path → injected plugin path + addendum |
| `plugins/kanban-flow/skills/kanban/SKILL.md` | Orchestrator | Resolve/inject doctrine + lens paths; repoint REVIEW-LENSES; template resolution; migration nudge |
| `plugins/kanban-flow/skills/refine/SKILL.md` | Backlog intake | Read `card-template.md` from plugin/override |
| `plugins/kanban-flow/skills/retro/SKILL.md` | Process improvement | Reroute lessons: addendum (project) / plugin PR (universal) |

---

## Task 1: Foundation — addendum stub + config keys

**Files:**
- Create: `plugins/kanban-flow/templates/PROTOCOL-ADDENDUM.md`
- Modify: `plugins/kanban-flow/templates/config.md` (frontmatter + docs)

**Interfaces:**
- Produces (used by all later tasks): the file `PROTOCOL-ADDENDUM.md` (agents read it after plugin doctrine); the config keys `kanban_flow_version` (string) and `template_overrides` (map from `card-template.md`|`pr-template.md`|`design-pr-template.md` → repo path).

- [ ] **Step 1: Create the addendum stub**

Create `plugins/kanban-flow/templates/PROTOCOL-ADDENDUM.md` with exactly:
```markdown
# Protocol Addendum (project-specific)

Project-specific doctrine that layers **on top of** the plugin's `AGENT-PROTOCOL.md`.
Every phase agent reads the plugin protocol first, then this file. Rules here refine
or add to the shared contract for **this repository only** — they never override the
structured-return format or the sole-writer invariant.

`/retro` appends project-specific process lessons here, each prefixed
`[retro-YYYY-MM-DD]`. Universal lessons belong in the plugin instead — `/retro`
flags those as a plugin PR rather than writing them here.

<!-- No project-specific rules yet. -->
```

- [ ] **Step 2: Add the two config keys to the frontmatter**

In `plugins/kanban-flow/templates/config.md`, replace:
```
adr_dir: docs/adrs
wip_limit: 3
```
with:
```
adr_dir: docs/adrs
kanban_flow_version: "0.1.0"
template_overrides: {}
wip_limit: 3
```

- [ ] **Step 3: Document the two keys**

In `plugins/kanban-flow/templates/config.md`, replace:
```
- **wip_limit** — max cards in flight at once.
```
with:
```
- **kanban_flow_version** — the plugin version this board's config and scaffold
  were last synced to. `/kanban-init` stamps it; `/migrate` updates it. `/kanban`
  compares it to the installed plugin version to nudge you to run `/migrate`.
- **template_overrides** — optional map from a template name (`card-template.md` |
  `pr-template.md` | `design-pr-template.md`) to a repo-relative path. When an entry
  is set, the skills read that file instead of the plugin's template; leave empty
  (`{}`) to use the plugin templates. `/migrate` sets an entry automatically if it
  finds a template you had customized.
- **wip_limit** — max cards in flight at once.
```

- [ ] **Step 4: Verify**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
test -f plugins/kanban-flow/templates/PROTOCOL-ADDENDUM.md && echo "addendum OK"
grep -nF 'kanban_flow_version: "0.1.0"' plugins/kanban-flow/templates/config.md
grep -nF 'template_overrides: {}' plugins/kanban-flow/templates/config.md
grep -nF '**kanban_flow_version**' plugins/kanban-flow/templates/config.md
grep -nF '**template_overrides**' plugins/kanban-flow/templates/config.md
```
Expected: every line prints a match.

- [ ] **Step 5: Commit**

```bash
git add plugins/kanban-flow/templates/PROTOCOL-ADDENDUM.md plugins/kanban-flow/templates/config.md
git commit -m "feat(kanban-flow): add PROTOCOL-ADDENDUM stub and config version/override keys

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `/kanban-init` stops copying doctrine

**Files:**
- Modify: `plugins/kanban-flow/skills/kanban-init/SKILL.md` (description frontmatter, Scaffold step 3)

**Interfaces:**
- Consumes (from Task 1): `PROTOCOL-ADDENDUM.md`, the `kanban_flow_version` key.

- [ ] **Step 1: Update the description frontmatter**

Replace:
```
description: Scaffold a repository for the kanban-flow system. Copies the doctrine, templates, config, and empty board starters into the target repo's board directory (default docs/cards/). Idempotent — never clobbers an existing board. Run once per project, before /refine.
```
with:
```
description: Scaffold a repository for the kanban-flow system. Copies config, an empty project-doctrine addendum, and empty board starters into the target repo's board directory (default docs/cards/); doctrine and templates stay plugin-owned and are read live. Idempotent — never clobbers an existing board. Run once per project, before /refine.
```

- [ ] **Step 2: Rewrite the Scaffold step**

Replace the whole of step 3:
```
3. **Scaffold.** Create `<board_dir>/` and copy from `${CLAUDE_PLUGIN_ROOT}/templates/`:
   - `config.md`, `AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `card-template.md`,
     `pr-template.md`, `design-pr-template.md` → `<board_dir>/`
   - `board/BOARD.md`, `board/KNOWLEDGE.md`, `board/MILESTONES.md` → `<board_dir>/`
   - Create the ADR directory (`adr_dir`, default `docs/adrs/`). Only if
     `<adr_dir>/README.md` does not already exist, create it as a stub containing
     an empty ADR index heading — a repo with pre-existing ADRs must not have its
     index clobbered.
```
with:
```
3. **Scaffold.** Create `<board_dir>/` and copy from `${CLAUDE_PLUGIN_ROOT}/templates/`:
   - `config.md` → `<board_dir>/config.md`, then stamp its `kanban_flow_version`
     to the installed plugin version (read `version` from the plugin's
     `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`).
   - `PROTOCOL-ADDENDUM.md` → `<board_dir>/` (the empty project-doctrine stub
     `/retro` will append project-specific rules to).
   - `board/BOARD.md`, `board/KNOWLEDGE.md`, `board/MILESTONES.md` → `<board_dir>/`
   - Create the ADR directory (`adr_dir`, default `docs/adrs/`). Only if
     `<adr_dir>/README.md` does not already exist, create it as a stub containing
     an empty ADR index heading — a repo with pre-existing ADRs must not have its
     index clobbered.

   **Do not copy** `AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `card-template.md`,
   `pr-template.md`, or `design-pr-template.md`. These are **plugin-owned** and
   read live at runtime (the orchestrator injects their absolute paths into every
   dispatch); copying them into the repo would re-create the per-repo doctrine
   drift this design removes.
```

- [ ] **Step 3: Verify**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
grep -nF 'PROTOCOL-ADDENDUM.md' plugins/kanban-flow/skills/kanban-init/SKILL.md
grep -nF 'stamp its `kanban_flow_version`' plugins/kanban-flow/skills/kanban-init/SKILL.md
grep -nF '**Do not copy**' plugins/kanban-flow/skills/kanban-init/SKILL.md
grep -nF 'AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `card-template.md',' plugins/kanban-flow/skills/kanban-init/SKILL.md
# stale: init must no longer COPY the doctrine files into board_dir
grep -nF 'REVIEW-LENSES.md`, `card-template.md`,
     `pr-template.md`, `design-pr-template.md` → `<board_dir>/`' plugins/kanban-flow/skills/kanban-init/SKILL.md
```
Expected: the first three match; the fifth (old copy list) returns **nothing**. (The fourth is a loose check that the "Do not copy" list names the files — if it does not match due to wrapping, confirm by reading the step.)

- [ ] **Step 4: Commit**

```bash
git add plugins/kanban-flow/skills/kanban-init/SKILL.md
git commit -m "feat(kanban-flow): kanban-init scaffolds addendum + version, stops copying doctrine

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Agents read plugin doctrine + addendum

Changes the doctrine read-path in all 7 agents and documents the injected paths in the protocol's "On dispatch you receive".

**Files:**
- Modify: `plugins/kanban-flow/agents/card-implementer.md` (line 12)
- Modify: `plugins/kanban-flow/agents/card-designer.md` (line 12)
- Modify: `plugins/kanban-flow/agents/card-tester.md` (line 12)
- Modify: `plugins/kanban-flow/agents/card-reviewer.md` (line 12)
- Modify: `plugins/kanban-flow/agents/card-deliverer.md` (line 12)
- Modify: `plugins/kanban-flow/agents/card-slicer.md` (line 12)
- Modify: `plugins/kanban-flow/agents/pr-expert-reviewer.md` (lines 15, 17)
- Modify: `plugins/kanban-flow/templates/AGENT-PROTOCOL.md` ("On dispatch you receive")

**Interfaces:**
- Consumes (from Task 1): `PROTOCOL-ADDENDUM.md`. Consumes (from Task 4, forward): the dispatch injects the absolute `AGENT-PROTOCOL.md` / `REVIEW-LENSES.md` paths. This task writes the agent-side "read the path your dispatch provides"; Task 4 writes the orchestrator-side injection. They meet at the dispatch prompt.

- [ ] **Step 1: Five agents with the identical read clause**

In each of `card-implementer.md`, `card-designer.md`, `card-tester.md`, `card-reviewer.md`, `card-deliverer.md`, replace the clause:
```
First read `docs/cards/AGENT-PROTOCOL.md` and obey it.
```
with:
```
First read the plugin protocol at the `AGENT-PROTOCOL.md` absolute path your dispatch provides, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both (the addendum layers project-specific rules on the shared contract).
```
(Each file has exactly one occurrence; the rest of each line is unchanged.)

- [ ] **Step 2: card-slicer (different trailing text)**

In `card-slicer.md`, replace:
```
First, read `docs/cards/AGENT-PROTOCOL.md` and obey it exactly
```
with:
```
First, read the plugin protocol at the `AGENT-PROTOCOL.md` absolute path your dispatch provides, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both exactly
```

- [ ] **Step 3: pr-expert-reviewer (protocol + lens paths)**

In `pr-expert-reviewer.md`, replace:
```
First read `docs/cards/AGENT-PROTOCOL.md` (Doctrine included) and obey it. Then read **only**:
```
with:
```
First read the plugin protocol at the `AGENT-PROTOCOL.md` absolute path your dispatch provides (Doctrine included), then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both. Then read **only**:
```
Then, in the same file, replace:
```
`docs/cards/REVIEW-LENSES.md`;
```
with:
```
the plugin `REVIEW-LENSES.md` at the absolute path your dispatch provides;
```

- [ ] **Step 4: Document the injected paths in the protocol**

In `plugins/kanban-flow/templates/AGENT-PROTOCOL.md`, in the "## On dispatch you receive" list, replace the first bullet:
```
- `card_id` (e.g. CARD-001), `card_dir` (e.g. docs/cards/CARD-001-slug), `worktree` (absolute path
  to this card's git worktree), the full text of `card.md`, and the prior phase docs **your phase
  needs** (the orchestrator sends only those — don't expect all of them).
```
with:
```
- `card_id` (e.g. CARD-001), `card_dir` (e.g. docs/cards/CARD-001-slug), `worktree` (absolute path
  to this card's git worktree), the full text of `card.md`, and the prior phase docs **your phase
  needs** (the orchestrator sends only those — don't expect all of them).
- **Doctrine paths:** the absolute path to the plugin's `AGENT-PROTOCOL.md` (this file) and the
  repo's `PROTOCOL-ADDENDUM.md`; `pr-expert-reviewer` also receives the plugin's `REVIEW-LENSES.md`
  path. Read the protocol here, then layer the addendum — never read a `docs/cards/` copy.
```

- [ ] **Step 5: Verify**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
# no agent still reads the repo-copy protocol/lens path:
grep -rnF 'docs/cards/AGENT-PROTOCOL.md' plugins/kanban-flow/agents/
grep -rnF 'docs/cards/REVIEW-LENSES.md' plugins/kanban-flow/agents/
# new wording present in every agent:
grep -rlF 'AGENT-PROTOCOL.md` absolute path your dispatch provides' plugins/kanban-flow/agents/ | wc -l
grep -nF 'Doctrine paths:' plugins/kanban-flow/templates/AGENT-PROTOCOL.md
```
Expected: the two `grep -rn` return **nothing**; the `wc -l` prints **7**; the last matches.

- [ ] **Step 6: Commit**

```bash
git add plugins/kanban-flow/agents/ plugins/kanban-flow/templates/AGENT-PROTOCOL.md
git commit -m "feat(kanban-flow): agents read plugin doctrine + PROTOCOL-ADDENDUM via injected paths

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Orchestrator resolves + injects doctrine, template resolution, migration nudge

The substantive orchestrator change. All edits are in `skills/kanban/SKILL.md`.

**Files:**
- Modify: `plugins/kanban-flow/skills/kanban/SKILL.md` (Section 1 load; dispatch section ~line 76; panel section ~line 109; deliver/design template refs lines 42, 60; report ~line 134)

**Interfaces:**
- Consumes (from Tasks 1, 3): `PROTOCOL-ADDENDUM.md`, `kanban_flow_version`, `template_overrides`; agents that read "the path your dispatch provides".
- Produces: the dispatch now carries the doctrine paths; a `migration_needed` flag surfaced in the report; a single template-resolution rule other skills mirror.

- [ ] **Step 1: Resolve doctrine dir + migration check in Load state**

In Section 1, immediately after the line ending `Compute each milestone's progress = done members / total members.`, insert a new paragraph:
```
Resolve the **plugin doctrine directory** once this pump: `${CLAUDE_PLUGIN_ROOT}/templates/` (the same path `/kanban-init` uses). You pass absolute paths from it into every dispatch (Section 5) — agents never read a `docs/cards/` doctrine copy. **Template resolution rule** (used wherever a skill fills a template): for `card-template.md`, `pr-template.md`, or `design-pr-template.md`, read `config.md`'s `template_overrides[<name>]` if set (a repo-relative path), else the plugin's `${CLAUDE_PLUGIN_ROOT}/templates/<name>`. **Migration check:** compare `config.md`'s `kanban_flow_version` to the installed plugin version and scan `<board_dir>` for leftover plugin-owned copies (`AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `card-template.md`, `pr-template.md`, `design-pr-template.md`). If the version is behind or any copy exists, set `migration_needed` for the report (Section 7).
```

- [ ] **Step 2: Inject doctrine paths into the dispatch prompt**

In the dispatch section, replace:
```
In the dispatch prompt include: `card_id`, `card_dir`, the full `card.md`, and **only the phase docs the phase needs**: slicer → none; designer → slice.md; implementer → design.md (+ findings on rework); tester → design.md's test strategy + implement.md; reviewer → design.md + implement.md + test.md; deliverer → the PR body file path and mode (design / implementation). Include `worktree` once it exists.
```
with:
```
In the dispatch prompt include: `card_id`, `card_dir`, the full `card.md`, and **only the phase docs the phase needs**: slicer → none; designer → slice.md; implementer → design.md (+ findings on rework); tester → design.md's test strategy + implement.md; reviewer → design.md + implement.md + test.md; deliverer → the PR body file path and mode (design / implementation). Include `worktree` once it exists. **Always include the doctrine paths** every agent reads: the absolute `${CLAUDE_PLUGIN_ROOT}/templates/AGENT-PROTOCOL.md` and the repo's `<board_dir>/PROTOCOL-ADDENDUM.md` (for `pr-expert-reviewer` dispatches also the absolute `${CLAUDE_PLUGIN_ROOT}/templates/REVIEW-LENSES.md` — see Section 6b).
```

- [ ] **Step 3: Repoint the lens-brief reference and panel dispatch**

In Section 6b, replace:
```
assemble the panel from the PR's changed files (`{gh_command} pr diff <url> --name-only`) and dispatch one `pr-expert-reviewer` **per lens, in parallel**, passing each its `lens`, `pr_url`, `worktree`, `card_id`, and `card.md`. Lens briefs live in `docs/cards/REVIEW-LENSES.md`; each expert reads only its own section.
```
with:
```
assemble the panel from the PR's changed files (`{gh_command} pr diff <url> --name-only`) and dispatch one `pr-expert-reviewer` **per lens, in parallel**, passing each its `lens`, `pr_url`, `worktree`, `card_id`, `card.md`, and the doctrine paths (`${CLAUDE_PLUGIN_ROOT}/templates/AGENT-PROTOCOL.md`, `${CLAUDE_PLUGIN_ROOT}/templates/REVIEW-LENSES.md`, and `<board_dir>/PROTOCOL-ADDENDUM.md`). Lens briefs live in the plugin's `REVIEW-LENSES.md` (the injected path); each expert reads only its own section.
```

- [ ] **Step 4: Normalize the two template references (drop stale dot-prefix)**

In the deliver-gate bullet, replace:
```
assemble the implementation PR body (fill `.pr-template.md` from the card's docs and acceptance criteria) into `card_dir/pr-body.md`
```
with:
```
assemble the implementation PR body (fill the `pr-template.md` template — resolved per Section 1's template-resolution rule — from the card's docs and acceptance criteria) into `card_dir/pr-body.md`
```
Then, in the design-PR-open step, replace:
```
assemble the design PR body from `.design-pr-template.md`;
```
with:
```
assemble the design PR body from the `design-pr-template.md` template (resolved per Section 1's template-resolution rule);
```

- [ ] **Step 5: Surface the migration nudge in the report**

In Section 7, replace:
```
Warn on `MILESTONES.md` drift (a `/refine` fix — surface, don't edit). **Every 5 cards done**, suggest `/retro`.
```
with:
```
Warn on `MILESTONES.md` drift (a `/refine` fix — surface, don't edit). If `migration_needed` (Section 1), warn prominently: **"Un-migrated doctrine copies or a stale `kanban_flow_version` detected — run `/migrate`."** **Every 5 cards done**, suggest `/retro`.
```

- [ ] **Step 6: Verify**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
K=plugins/kanban-flow/skills/kanban/SKILL.md
grep -nF 'plugin doctrine directory' $K
grep -nF 'Template resolution rule' $K
grep -nF 'Migration check:' $K
grep -nF 'Always include the doctrine paths' $K
grep -nF 'migration_needed' $K            # appears in Section 1 and Section 7
grep -nF 'run `/migrate`' $K
# stale references gone:
grep -nF 'docs/cards/REVIEW-LENSES.md' $K
grep -nF '.pr-template.md' $K
grep -nF '.design-pr-template.md' $K
```
Expected: the first six match (`migration_needed` twice); the last three return **nothing**.

- [ ] **Step 7: Commit**

```bash
git add plugins/kanban-flow/skills/kanban/SKILL.md
git commit -m "feat(kanban-flow): orchestrator injects live doctrine paths, template resolution, migrate nudge

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `/refine` reads `card-template.md` from the plugin

**Files:**
- Modify: `plugins/kanban-flow/skills/refine/SKILL.md` (card-creation step, line ~30)

**Interfaces:**
- Consumes (from Tasks 1, 4): `template_overrides`, the template-resolution rule.

- [ ] **Step 1: Point card creation at the resolved template**

In `plugins/kanban-flow/skills/refine/SKILL.md`, replace:
```
create `docs/cards/CARD-NNN-slug/card.md` from `card-template.md`
```
with:
```
create `docs/cards/CARD-NNN-slug/card.md` from the `card-template.md` template — resolved as `config.md`'s `template_overrides["card-template.md"]` if set, else `${CLAUDE_PLUGIN_ROOT}/templates/card-template.md`
```

- [ ] **Step 2: Verify**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
grep -nF '${CLAUDE_PLUGIN_ROOT}/templates/card-template.md' plugins/kanban-flow/skills/refine/SKILL.md
grep -nF 'from `card-template.md`
' plugins/kanban-flow/skills/refine/SKILL.md
```
Expected: the first matches; the second (the bare old phrasing on its own) returns nothing. If unsure, read the step to confirm the old bare reference is gone.

- [ ] **Step 3: Commit**

```bash
git add plugins/kanban-flow/skills/refine/SKILL.md
git commit -m "feat(kanban-flow): refine reads card-template from the plugin (or override)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `/retro` reroutes process lessons

**Files:**
- Modify: `plugins/kanban-flow/skills/retro/SKILL.md` (the process-lesson targets bullet, line 42)

**Interfaces:**
- Consumes (from Task 1): `PROTOCOL-ADDENDUM.md`. Depends on the design: universal lessons become a flagged plugin PR, not an in-repo doctrine edit.

- [ ] **Step 1: Rewrite the process-lesson targets bullet**

In `plugins/kanban-flow/skills/retro/SKILL.md`, replace:
```
- Edits to `.claude/agents/*.md`, `.claude/skills/*/SKILL.md`, `docs/cards/AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `card-template.md`, or the `BOARD.md` header tunables (WIP limit, gate policy) — for process lessons.
```
with:
```
- Process lessons route by scope: **project-specific** ones → append to `<board_dir>/PROTOCOL-ADDENDUM.md` (prefix `[retro-YYYY-MM-DD]`; it layers on the plugin's shared doctrine for this repo only). **Universal** ones — anything that belongs in the plugin's `AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, templates, agents, or skills — must **not** be edited in place: describe the exact change and flag it as a **plugin PR** in the retro output for the human to raise against the plugin repo. The `BOARD.md` header tunables (WIP limit, gate policy) remain editable in-repo.
```

- [ ] **Step 2: Verify**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
grep -nF 'PROTOCOL-ADDENDUM.md' plugins/kanban-flow/skills/retro/SKILL.md
grep -nF 'flag it as a **plugin PR**' plugins/kanban-flow/skills/retro/SKILL.md
# retro must no longer instruct editing the repo doctrine copy:
grep -nF 'docs/cards/AGENT-PROTOCOL.md' plugins/kanban-flow/skills/retro/SKILL.md
```
Expected: the first two match; the third returns **nothing**.

- [ ] **Step 3: Commit**

```bash
git add plugins/kanban-flow/skills/retro/SKILL.md
git commit -m "feat(kanban-flow): retro routes lessons to addendum (project) or plugin PR (universal)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Whole-plugin consistency sweep

Catch any doctrine/template read that still points at a `docs/cards/` copy, and read the new dispatch/read flow end-to-end.

**Files:**
- Read-only review of `plugins/kanban-flow/` (edit + commit only if a stale reference is found)

- [ ] **Step 1: Sweep for stale repo-copy doctrine/template reads**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
grep -rnF 'docs/cards/AGENT-PROTOCOL.md' plugins/kanban-flow/
grep -rnF 'docs/cards/REVIEW-LENSES.md' plugins/kanban-flow/
grep -rn 'docs/cards/[a-z-]*template' plugins/kanban-flow/
grep -rnF '.pr-template.md' plugins/kanban-flow/
grep -rnF '.design-pr-template.md' plugins/kanban-flow/
```
Expected: **all** return nothing. Any hit is a read this plan missed — reword it to the plugin-path / template-resolution model, commit with a `feat(kanban-flow): …` message + trailer, and re-run. (Note: the design spec/plan under `docs/superpowers/` legitimately *describe* these strings — restrict the sweep to `plugins/kanban-flow/` as written.)

- [ ] **Step 2: Confirm the new model is wired end-to-end**

Read, as a fresh reviewer:
- `plugins/kanban-flow/skills/kanban/SKILL.md` Section 1 (doctrine dir + template rule + migration check), the dispatch section, Section 6b, and Section 7 (nudge).
- One agent (`card-implementer.md`) + `pr-expert-reviewer.md` — confirm they read "the path your dispatch provides", and the orchestrator supplies exactly those paths.
- `AGENT-PROTOCOL.md` "On dispatch you receive" lists the doctrine paths.

Confirm the chain is closed: orchestrator injects `AGENT-PROTOCOL.md` + `REVIEW-LENSES.md` (panel) + `PROTOCOL-ADDENDUM.md` paths → agents read exactly those. Fix inline + commit if a gap is found; otherwise no commit.

- [ ] **Step 3: Confirm init/plugin coherence**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
# init no longer copies the 5 plugin-owned files anywhere:
grep -nF 'AGENT-PROTOCOL.md' plugins/kanban-flow/skills/kanban-init/SKILL.md   # only in the "Do not copy" note
grep -nF 'PROTOCOL-ADDENDUM.md' plugins/kanban-flow/skills/kanban-init/SKILL.md
test -f plugins/kanban-flow/templates/PROTOCOL-ADDENDUM.md && echo "addendum template present"
```
Expected: `AGENT-PROTOCOL.md` appears only inside the "Do not copy" sentence; `PROTOCOL-ADDENDUM.md` is scaffolded; the template file exists.

---

## Self-Review (completed during planning)

**Spec coverage:**
- Ownership split (5 files plugin-owned) → Tasks 2 (stop copying), 3/4/5 (read from plugin). ✓
- Path injection (orchestrator resolves + injects; agents read plugin then addendum) → Task 4 Steps 1–3 + Task 3. ✓
- `PROTOCOL-ADDENDUM.md` (new, layered) → Task 1 + Task 3 read composition. ✓
- `kanban-init` changes → Task 2. ✓
- Agents read-path (7) → Task 3. ✓
- Orchestrator inject / repoint lenses / detection nudge → Task 4. ✓
- `retro` reroute → Task 6. ✓
- `config.md` `kanban_flow_version` + `template_overrides` (built) → Task 1; template resolution consumed in Tasks 4 & 5. ✓
- Backward-compat nudge → Task 4 Steps 1 & 5. ✓
- Spec omission caught: `refine` also consumes `card-template.md` → added as Task 5 (the spec's file list did not name refine; the card-template move requires it).

**Placeholder scan:** No `TBD`/`TODO`/"handle edge cases". `${CLAUDE_PLUGIN_ROOT}`, `<board_dir>`, `{gh_command}` are intentional doctrine placeholders preserved verbatim per Global Constraints. ✓

**Consistency:** The injected set — `AGENT-PROTOCOL.md` + `PROTOCOL-ADDENDUM.md` (all agents) + `REVIEW-LENSES.md` (pr-expert only) — is named identically in Task 3 (agent side), Task 4 Steps 2–3 (orchestrator side), and `AGENT-PROTOCOL.md`'s "On dispatch you receive" (Task 3 Step 4). The template-resolution rule is defined once (Task 4 Step 1) and referenced by Tasks 4 (Step 4) and 5. `kanban_flow_version`/`template_overrides` spellings match across Tasks 1, 2, 4, 5. ✓
