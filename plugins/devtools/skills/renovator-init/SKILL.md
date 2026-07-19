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
