# renovator-init — interactive config scaffolder

**Date:** 2026-07-19
**Plugin:** `devtools`
**Status:** Approved design

## Problem

The `renovator` skill reads optional configuration from `.claude/renovator.json`
in the repo root. Today a user must hand-author that file from the knob table in
the docs. There is no guided way to create it, and the knob defaults live only in
prose. We want a first-run setup step that writes a correct, complete config file
interactively.

## Goal

Add a new skill, `renovator-init`, to the `devtools` plugin that interactively
scaffolds `.claude/renovator.json` into the current repository. Scope is the
config file only — it does not create labels or process PRs (that remains
`renovator`'s job).

## Non-goals

- No label creation, no PR fetching/merging/fixing. `renovator` still owns all of
  that (it creates its five lifecycle labels on its own first run).
- No `marketplace.json` change — skills are auto-discovered by convention from
  `plugins/devtools/skills/`. `devtools` is already registered in the manifest.
- No new config *version* field — the renovator config is unversioned and stays so.

## Form: a skill (not a slash command)

Packaged as `plugins/devtools/skills/renovator-init/SKILL.md`, invokable both
explicitly (`/renovator-init`) and by auto-discovery when a request matches its
description (e.g. "set up renovator in this repo"). This matches the sibling
precedent — `kanban-flow`'s `kanban-init` is a skill — and the fact that
`renovator` itself is a skill. A slash command would run only on an exact
`/`-invocation and would introduce a `commands/` pattern no other plugin here uses.

## Source of default knob values

Ship `plugins/devtools/templates/renovator.json` containing **all 7 knobs at their
documented defaults**. This is the single authoritative source of defaults,
mirroring how `kanban-init` reads from `${CLAUDE_PLUGIN_ROOT}/templates/`. The skill
loads this template, applies interactive overrides, and writes the merged result.

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

**Sync constraint:** these values must match the knob-default table in
`renovator/SKILL.md` (§ Configuration) and in `README.md`. The spec and both docs
call this out so a future default change is made in all places. The template is the
value source; the skill code contains no hard-coded default values of its own.

## Flow

The skill performs these steps in order.

### 1. Idempotency guard (first)

If `.claude/renovator.json` already exists → STOP. Report that renovator config is
already present here, print the file's current contents, and change nothing. Never
overwrite an existing config. (Mirrors `kanban-init`'s guard on `config.md`.)

### 2. Detect the Renovate bot login

Best-effort, to pre-fill the login prompt:

- If `gh auth status` succeeds, run
  `gh pr list --state open --limit 100 --json author` and collect the **distinct**
  author logins that look like bots — login ends in `[bot]`, or the author `type`
  is `Bot`.
- Use the detected login(s) as the default for the login prompt in step 3.
- If `gh` is unavailable/unauthenticated, or no bot author is found → fall back to
  `["renovate[bot]"]` and tell the user detection was skipped/empty.

`gh` is **optional**: it is used only to pre-fill this default. The skill works
fully offline; nothing else in the flow needs `gh`.

### 3. Prompt (four questions)

Prompt for these; everything else takes the template default.

| Prompt | Config key(s) | Default |
|---|---|---|
| Renovate bot login(s) | `renovate_authors` | detected value (step 2), else `["renovate[bot]"]` |
| Enable autonomous fix-loops? (red-CI + major upgrades) | `enable_ci_fixer` **and** `enable_major_upgrader` (one yes/no sets both) | yes (`true`/`true`) |
| Merge method | `merge_method` | `squash` (choices: squash / merge / rebase) |
| Allow merging PRs with **no CI** at all? | `require_checks` (yes ⇒ `false`) | no (keeps `require_checks: true`) |

The "no CI" prompt, when the user answers yes, surfaces the README's warning:
relaxing `require_checks` lets renovator merge dependency PRs with no CI signal at
all, unattended — only safe for repos where that is genuinely acceptable.

### 4. Write the config

Create `.claude/` if missing. Write `.claude/renovator.json` containing **all 7
knobs** — the five prompted values plus the two defaulted-and-not-prompted
(`max_merges_per_pass: 1`, `fix_attempts: 3`) — so every knob is visible and
editable afterward. Pretty-printed JSON.

### 5. Report next steps

- Point at the written `.claude/renovator.json` and invite the user to review/edit
  it (reference the knob table in the README for meanings — JSON can't carry
  comments).
- Tell the user to invoke the `renovator` skill next (optionally under `/loop`).
- Note that `renovator` creates its own labels on first run; init only wrote config.

## Rules

- Read-only toward the plugin; write only inside the target repo (`.claude/`).
- Idempotent: safe to re-run — no-ops (with a report) if `.claude/renovator.json`
  already exists.
- Do not run `renovator` itself; just scaffold and hand off.
- Portability: target both Linux and macOS, bash-3.2-safe, no GNU-only constructs
  (per the repo's plugin conventions). `jq` is available for JSON assembly.

## Docs to update

- `plugins/devtools/README.md` — add a "Setup: run `/renovator-init`" line to the
  renovator Configuration section.
- `plugins/devtools/skills/renovator/SKILL.md` — Configuration section gains a
  pointer that `.claude/renovator.json` can be scaffolded via `/renovator-init`.

## Files

- **New:** `plugins/devtools/skills/renovator-init/SKILL.md`
- **New:** `plugins/devtools/templates/renovator.json`
- **Edit:** `plugins/devtools/README.md`
- **Edit:** `plugins/devtools/skills/renovator/SKILL.md`

No `marketplace.json` or `plugin.json` change required.
