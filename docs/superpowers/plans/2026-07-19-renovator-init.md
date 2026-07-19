# renovator-init Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `renovator-init` skill to the `devtools` plugin that interactively scaffolds `.claude/renovator.json` into the current repo.

**Architecture:** A new skill directory `plugins/devtools/skills/renovator-init/` whose `SKILL.md` drives an interactive flow: idempotency guard → best-effort bot-login detection via `gh` → four prompts → write all 7 knobs to `.claude/renovator.json`. Default knob values live once in a new plugin template `plugins/devtools/templates/renovator.json`, which the skill loads and overrides. Two docs get pointer updates.

**Tech Stack:** Markdown skill instructions, JSON, `jq`, `gh` CLI (optional), bash (3.2-safe, Linux + macOS portable).

## Global Constraints

- **No test runner exists.** Plugin components are Markdown/JSON validated structurally (`jq` for JSON, `grep` for required content) and by installing the plugin — not by a unit-test framework. Copied verbatim from CLAUDE.md.
- **Portability:** target both Linux and macOS, bash-3.2-safe, no GNU-only constructs (`grep -oP`/`\K`, `find -printf`, `date -Iseconds`). Use `date -u +%Y-%m-%dT%H:%M:%SZ`, `sed -nE`, `ls -t`.
- **`jq` is required; `gh` is optional** (used only to pre-fill the login default — the skill must work fully offline).
- **Skills are auto-discovered** from `plugins/devtools/skills/` by convention — no `marketplace.json` or `plugin.json` change.
- **Single source of default knob values:** `plugins/devtools/templates/renovator.json`. Its values must match the knob-default table in both `renovator/SKILL.md` and `README.md`.
- **Config scope only:** the skill writes `.claude/renovator.json` and nothing else — no label creation, no PR processing.

---

## File Structure

- **Create** `plugins/devtools/templates/renovator.json` — authoritative default values for all 7 knobs.
- **Create** `plugins/devtools/skills/renovator-init/SKILL.md` — the interactive scaffolder skill.
- **Modify** `plugins/devtools/README.md` — add a setup pointer to `/renovator-init`.
- **Modify** `plugins/devtools/skills/renovator/SKILL.md` — Configuration section pointer to `/renovator-init`.

---

### Task 1: Default-values template

**Files:**
- Create: `plugins/devtools/templates/renovator.json`

**Interfaces:**
- Produces: the canonical default config object with keys `renovate_authors` (array), `merge_method` (string), `require_checks` (bool), `max_merges_per_pass` (number), `enable_ci_fixer` (bool), `enable_major_upgrader` (bool), `fix_attempts` (number). Task 2's skill reads this file via `${CLAUDE_PLUGIN_ROOT}/templates/renovator.json`.

- [ ] **Step 1: Write the template file**

`plugins/devtools/templates/renovator.json`:

```json
{
  "renovate_authors": ["renovate[bot]"],
  "merge_method": "squash",
  "require_checks": true,
  "max_merges_per_pass": 1,
  "enable_ci_fixer": true,
  "enable_major_upgrader": true,
  "fix_attempts": 3
}
```

- [ ] **Step 2: Verify it is valid JSON and has exactly the 7 expected keys**

Run:
```bash
jq -e '
  (keys == ["enable_ci_fixer","enable_major_upgrader","fix_attempts","max_merges_per_pass","merge_method","renovate_authors","require_checks"])
  and (.renovate_authors == ["renovate[bot]"])
  and (.merge_method == "squash")
  and (.require_checks == true)
  and (.max_merges_per_pass == 1)
  and (.enable_ci_fixer == true)
  and (.enable_major_upgrader == true)
  and (.fix_attempts == 3)
' plugins/devtools/templates/renovator.json
```
Expected: prints `true` and exits 0. (`jq keys` returns keys sorted, hence the alphabetical order above.)

- [ ] **Step 3: Cross-check against the documented defaults**

Run:
```bash
grep -n '`renovate_authors`\|`merge_method`\|`require_checks`\|`max_merges_per_pass`\|`enable_ci_fixer`\|`enable_major_upgrader`\|`fix_attempts`' plugins/devtools/skills/renovator/SKILL.md
```
Expected: the defaults shown there (`["renovate[bot]"]`, `"squash"`, `true`, `1`, `true`, `true`, `3`) match the template. If any differ, the template is the source of truth going forward — but they should already agree.

- [ ] **Step 4: Commit**

```bash
git add plugins/devtools/templates/renovator.json
git commit -m "feat(devtools): add renovator config defaults template"
```

---

### Task 2: The renovator-init skill

**Files:**
- Create: `plugins/devtools/skills/renovator-init/SKILL.md`

**Interfaces:**
- Consumes: `${CLAUDE_PLUGIN_ROOT}/templates/renovator.json` (from Task 1) for default values.
- Produces: `.claude/renovator.json` in the target repo (side effect); a skill discoverable as `renovator-init` / `/renovator-init`.

- [ ] **Step 1: Write the skill file**

Create `plugins/devtools/skills/renovator-init/SKILL.md` with this content:

````markdown
---
name: renovator-init
description: "Scaffold `.claude/renovator.json` for the renovator skill into the current repo, interactively. Detects the Renovate bot login from open PRs, prompts for the key knobs (bot login, fix-loops, merge method, no-CI safety), and writes all seven config knobs. Idempotent: never clobbers an existing config. Use when asked to set up, configure, or initialize renovator in a repository."
---

# /renovator-init — scaffold renovator config

Set up the current repository to use the `renovator` skill by writing
`.claude/renovator.json`. You write only inside the target repo; the plugin's
template is read live and never modified. You scaffold config only — you do NOT
create labels or process any PR (that is `renovator`'s job, on its own first run).

The default knob values live in `${CLAUDE_PLUGIN_ROOT}/templates/renovator.json`.
Load that as your base and apply the interactive overrides below. Never hard-code
default values in this skill — read them from the template.

## Steps

### 1. Idempotency guard (first)
If `.claude/renovator.json` already exists, STOP: report that renovator config is
already present, print the file's current contents (`cat .claude/renovator.json`),
and change nothing. Never overwrite an existing config.

### 2. Detect the Renovate bot login (best effort)
Used only to pre-fill the login prompt in step 3.
- If `gh auth status` succeeds, run:
  `gh pr list --state open --limit 100 --json author --jq '[.[].author | select(.type == "Bot" or (.login | endswith("[bot]"))) | .login] | unique'`
  Collect the distinct bot author logins.
- Use the detected list as the login prompt's default.
- If `gh` is unavailable/unauthenticated (the command errors) or the list is empty,
  fall back to `["renovate[bot]"]` and tell the user detection was skipped or found
  nothing.

`gh` is OPTIONAL — everything after this step works offline.

### 3. Prompt (four questions)
Ask the user, using the template defaults (and the step-2 detection) as defaults.
Everything not prompted keeps its template value.

| Prompt | Config key(s) | Default |
|---|---|---|
| Which author login(s) count as Renovate? | `renovate_authors` (JSON array of strings) | detected list (step 2), else `["renovate[bot]"]` |
| Enable autonomous fix-loops (red-CI fixes + major upgrades)? | sets BOTH `enable_ci_fixer` and `enable_major_upgrader` to the same yes/no | yes → both `true` |
| Merge method? (`squash` / `merge` / `rebase`) | `merge_method` | `squash` |
| Allow merging PRs with NO CI checks at all? | `require_checks` (yes ⇒ `false`, no ⇒ `true`) | no → `require_checks: true` |

For the "no CI" prompt, if the user answers yes, first surface this warning and
confirm: relaxing `require_checks` lets renovator merge dependency PRs with no CI
signal at all, unattended — only safe for repos where that is genuinely acceptable.

`max_merges_per_pass` (1) and `fix_attempts` (3) are NOT prompted — they keep the
template default but are still written (step 4) so the user can edit them later.

### 4. Write the config
- Create `.claude/` if it does not exist (`mkdir -p .claude`).
- Build the final object by starting from the template and applying the four
  overrides, then write ALL seven knobs pretty-printed. Assemble with `jq` so the
  output is valid JSON, e.g.:
  ```bash
  jq -n \
    --argjson authors "$AUTHORS_JSON" \
    --arg method "$MERGE_METHOD" \
    --argjson checks "$REQUIRE_CHECKS" \
    --argjson fixers "$ENABLE_FIXERS" \
    '{
      renovate_authors: $authors,
      merge_method: $method,
      require_checks: $checks,
      max_merges_per_pass: 1,
      enable_ci_fixer: $fixers,
      enable_major_upgrader: $fixers,
      fix_attempts: 3
    }' > .claude/renovator.json
  ```
  (`$AUTHORS_JSON` is a JSON array like `["renovate[bot]"]`; `$REQUIRE_CHECKS` and
  `$ENABLE_FIXERS` are the literal `true`/`false`. Pull `max_merges_per_pass` and
  `fix_attempts` from the template rather than re-typing them if you prefer a single
  source — either way the written values must equal the template defaults.)
- Confirm the result parses: `jq -e . .claude/renovator.json >/dev/null`.

### 5. Report next steps
- Show the path `.claude/renovator.json` and its final contents.
- Tell the user to review/edit it (knob meanings are in the devtools README — JSON
  can't carry comments).
- Tell them to invoke the `renovator` skill next (optionally under `/loop`).
- Note that `renovator` creates its own lifecycle labels on first run; init only
  wrote config.

## Rules
- Read-only toward the plugin; write only inside the target repo (`.claude/`).
- Idempotent: safe to re-run — no-ops (with a report) if `.claude/renovator.json`
  exists.
- Do not run `renovator` yourself; scaffold and hand off.
- Portable: bash-3.2-safe, Linux + macOS, no GNU-only constructs.
````

- [ ] **Step 2: Verify the frontmatter and required sections are present**

Run:
```bash
sed -n '1,6p' plugins/devtools/skills/renovator-init/SKILL.md
grep -n 'Idempotency guard\|Detect the Renovate bot login\|Write the config\|renovate_authors\|enable_ci_fixer\|enable_major_upgrader\|require_checks\|CLAUDE_PLUGIN_ROOT/templates/renovator.json' plugins/devtools/skills/renovator-init/SKILL.md
```
Expected: frontmatter has `name: renovator-init` and a `description:`; grep matches every listed anchor at least once (all four prompted keys, both fix-loop keys, the idempotency/detect/write section headers, and the template path reference).

- [ ] **Step 3: Verify the embedded jq assembly snippet is syntactically valid jq**

Run:
```bash
AUTHORS_JSON='["renovate[bot]"]'; MERGE_METHOD='squash'; REQUIRE_CHECKS='true'; ENABLE_FIXERS='true'; \
jq -n --argjson authors "$AUTHORS_JSON" --arg method "$MERGE_METHOD" --argjson checks "$REQUIRE_CHECKS" --argjson fixers "$ENABLE_FIXERS" \
  '{renovate_authors:$authors,merge_method:$method,require_checks:$checks,max_merges_per_pass:1,enable_ci_fixer:$fixers,enable_major_upgrader:$fixers,fix_attempts:3}' \
| jq -e '.renovate_authors==["renovate[bot]"] and .enable_ci_fixer==true and .enable_major_upgrader==true and .require_checks==true and .max_merges_per_pass==1 and .fix_attempts==3'
```
Expected: prints the assembled object then `true`, exit 0 — proving the exact jq invocation the skill tells the agent to run produces a valid 7-knob config.

- [ ] **Step 4: Verify the bot-detection jq filter is valid against a sample**

Run:
```bash
echo '[{"author":{"login":"renovate[bot]","type":"Bot"}},{"author":{"login":"alice","type":"User"}},{"author":{"login":"dependabot[bot]","type":"Bot"}}]' \
| jq -c '[.[].author | select(.type == "Bot" or (.login | endswith("[bot]"))) | .login] | unique'
```
Expected: `["dependabot[bot]","renovate[bot]"]` — the filter selects only bot logins and dedups.

- [ ] **Step 5: Commit**

```bash
git add plugins/devtools/skills/renovator-init/SKILL.md
git commit -m "feat(devtools): add renovator-init skill to scaffold config interactively"
```

---

### Task 3: Documentation pointers

**Files:**
- Modify: `plugins/devtools/README.md`
- Modify: `plugins/devtools/skills/renovator/SKILL.md`

**Interfaces:**
- Consumes: nothing new. Adds discoverability pointers to the Task 2 skill.

- [ ] **Step 1: Add a setup pointer to the README**

In `plugins/devtools/README.md`, in the renovator "Configuration (optional)" section, immediately under the `### Configuration (optional)` heading line, insert this paragraph before the existing "Create `.claude/renovator.json` ..." sentence:

```markdown
Run `/renovator-init` to scaffold `.claude/renovator.json` interactively — it detects the Renovate bot login from your open PRs and prompts for the key knobs. Or create the file by hand:
```

(The existing "Create `.claude/renovator.json` in the repo root to override defaults:" sentence and JSON block stay as-is, now reading as the by-hand alternative.)

- [ ] **Step 2: Add a pointer in the renovator skill's Configuration section**

In `plugins/devtools/skills/renovator/SKILL.md`, in the `## Configuration` section, append this sentence to the end of the paragraph that begins "Read `.claude/renovator.json` from the repo root if it exists" (the first paragraph under the `## Configuration` heading):

```markdown
 The `/renovator-init` skill scaffolds this file interactively.
```

- [ ] **Step 3: Verify both pointers landed**

Run:
```bash
grep -n 'renovator-init' plugins/devtools/README.md plugins/devtools/skills/renovator/SKILL.md
```
Expected: at least one match in each file.

- [ ] **Step 4: Commit**

```bash
git add plugins/devtools/README.md plugins/devtools/skills/renovator/SKILL.md
git commit -m "docs(devtools): point renovator config setup at /renovator-init"
```

---

## Self-Review

**Spec coverage:**
- Form = skill → Task 2 creates `skills/renovator-init/SKILL.md`. ✓
- Defaults template as single source → Task 1. ✓
- Idempotency guard → Task 2 step 1 (skill §1). ✓
- Bot-login detection from open PRs, gh optional → Task 2 skill §2 + verification step 4. ✓
- Four prompts with correct key mappings (fix-loops sets both keys; no-CI ⇒ require_checks:false with warning) → Task 2 skill §3. ✓
- Write all 7 knobs, create `.claude/` → Task 2 skill §4. ✓
- Report next steps, note labels are renovator's job → Task 2 skill §5. ✓
- Scope: config only, no labels/PR work → stated in skill preamble + Rules. ✓
- Docs updates (README + renovator SKILL.md) → Task 3. ✓
- No marketplace.json/plugin.json change → not touched. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every step has concrete content and a runnable verification. ✓

**Type consistency:** The 7 keys and their types are identical across Task 1's template, Task 2's jq assembly, and the verification steps. `enable_ci_fixer`/`enable_major_upgrader` both driven by one `$ENABLE_FIXERS`. ✓
