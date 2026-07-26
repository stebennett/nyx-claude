# pr-reviewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `pr-reviewer` skill in the `devtools` plugin — an autonomous PR reviewer that reviews open pull requests through a three-lens agent panel and either requests changes with concrete recommendations or approves and merges.

**Architecture:** A thin orchestrating skill (`skills/pr-reviewer/SKILL.md`) running in the main loop resolves a target repo/PR, selects candidates, and dispatches three specialist agents: `pr-review-lens` (sonnet, ×3 in parallel, one per lens), `pr-review-verdict` (opus, adjudicates their findings), and `pr-merger` (haiku, re-verifies gates and merges). Review doctrine lives in `references/` files the agents read by absolute path from their dispatch. The orchestrator never holds a diff. All state is derived from GitHub's own reviews API plus two labels.

**Tech Stack:** Markdown + JSON plugin components for Claude Code. Bash for the structural checker. `gh` CLI and `jq` at runtime; `git` for worktrees and clones.

**Source spec:** `docs/superpowers/specs/2026-07-26-pr-reviewer-design.md` — read it before starting. This plan implements it; where the two disagree, the spec wins.

**Branch:** `feature/pr-reviewer-skill` (already created; the spec is committed on it).

## Global Constraints

Every task's requirements implicitly include this section.

- **Portability:** bash 3.2 (macOS default) — no `mapfile`, `readarray`, `declare -A`, or `${var,,}`. No GNU-only flags: no `grep -oP` / `\K`, no `find -printf`, no `date -Iseconds`, no `sed -i` without a backup arg. Use `sed -nE`, `awk`, `grep -oE`, `ls -t`, `date -u +%Y-%m-%dT%H:%M:%SZ`.
- **Runtime dependencies:** `gh` (authenticated), `jq`, `git`. No others.
- **Agent models are fixed:** `pr-review-lens` → `sonnet`; `pr-review-verdict` → `opus`; `pr-merger` → `haiku`.
- **Agent frontmatter `name:` must equal the filename stem**, and every agent must be referenced by name in `SKILL.md`. The checker enforces both.
- **Skill frontmatter `name:` must equal its directory name** (`pr-reviewer`).
- **Label names, exactly:** `reviewer:working` (color `FBCA04`), `reviewer:parked` (color `D93F0B`).
- **Hidden verdict marker, exactly this shape, as the first line of every review body:**
  `<!-- pr-reviewer: verdict=<approve|request-changes|park> round=<n> sha=<short_sha> -->`
- **Config defaults, verbatim:** `renovate_authors` `["renovate[bot]"]`, `exclude_authors` `[]`, `require_label` `null`, `max_reviews_per_pass` `3`, `max_merges_per_pass` `1`, `max_rounds` `3`, `merge_method` `"squash"`, `max_merge_lines` `800`, `max_review_lines` `3000`, `ignore_paths` `["*.lock", "package-lock.json", "**/generated/**"]`, `update_branch_after_merge` `false`, `clone_cache_dir` `null`.
- **Lens names, exactly:** `requirements`, `correctness`, `craft`.
- **Verdict values, exactly:** `approve`, `request-changes`, `park`.
- **Severity values, exactly:** `blocking`, `advisory`.
- **`pr-merger` reason values, exactly:** `merged`, `behind`, `conflict`, `blocked`, `not-green`, `threads-open`.
- **Never** write a file that instructs an agent to run tests, fix code, or push to a contributor's branch.
- **Commit style:** Conventional Commits, scoped `pr-reviewer`. Every commit ends with the two trailer lines used elsewhere in this repo:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01DjogvputUg2dezHUDmGJvV
  ```

## File Structure

| File | Responsibility |
|---|---|
| `scripts/check-plugin.sh` | **New.** Structural validation of any plugin directory: manifest keys, JSON parse, agent/skill frontmatter, reference-path existence, agent-reference existence. The gate every later task runs. |
| `CLAUDE.md` | **Modify.** Replace the "no build/test tooling" note with the checker's usage. |
| `plugins/devtools/templates/pr-reviewer.json` | Config scaffold carrying all twelve defaults. |
| `plugins/devtools/skills/pr-reviewer/references/target-resolution.md` | Argument → `target_repo`/`target_pr`; local-vs-remote worktree and clone recipes; cleanup. |
| `plugins/devtools/skills/pr-reviewer/references/lenses/_shared.md` | Etiquette and method binding all three lenses; the finding JSON schema. |
| `plugins/devtools/skills/pr-reviewer/references/lenses/requirements.md` | Requirements-conformity lens brief. |
| `plugins/devtools/skills/pr-reviewer/references/lenses/correctness.md` | Edge-case and correctness lens brief. |
| `plugins/devtools/skills/pr-reviewer/references/lenses/craft.md` | Simplicity, style, consistency lens brief. |
| `plugins/devtools/skills/pr-reviewer/references/verdict.md` | Adjudication doctrine, review body format, hidden marker spec. |
| `plugins/devtools/agents/pr-review-lens.md` | Sonnet agent, dispatched three times with a different brief path. |
| `plugins/devtools/agents/pr-review-verdict.md` | Opus adjudicator. Receives findings, never the diff. |
| `plugins/devtools/agents/pr-merger.md` | Haiku merger. Re-verifies every gate live, merges or aborts. |
| `plugins/devtools/skills/pr-reviewer/SKILL.md` | Orchestrator. Built across two tasks: steps 1–6 then steps 7–11. |
| `plugins/devtools/.claude-plugin/plugin.json` | **Modify.** Version bump, description, keywords. |
| `plugins/devtools/README.md` | **Modify.** `pr-reviewer` section. |
| `.claude-plugin/marketplace.json` | **Modify.** `devtools` description. |

Doctrine files are separated from agent definitions so a lens's judgement bar can be tuned without touching the agent, and so all three lenses share one agent definition.

---

### Task 1: Structural checker

The gate for every later task. Without it, a mistyped agent name or a broken `references/` path fails silently at runtime.

**Files:**
- Create: `scripts/check-plugin.sh`
- Modify: `CLAUDE.md` (the "Working in this repo" section)

**Interfaces:**
- Consumes: nothing.
- Produces: `bash scripts/check-plugin.sh <plugin-dir>` — exit 0 on pass, exit 1 on any structural failure (each printed as `FAIL: <message>` on stderr), exit 2 on usage error. Every later task runs `bash scripts/check-plugin.sh plugins/devtools` as its verification step.

- [ ] **Step 1: Write the failing test — a broken fixture the checker must reject**

Build a temporary plugin that violates four rules at once, and confirm the checker does not yet exist:

```bash
FIX=$(mktemp -d)
mkdir -p "$FIX/.claude-plugin" "$FIX/agents" "$FIX/skills/demo"
# manifest missing the "author" key
printf '{"name":"demo","version":"0.1.0","description":"d"}\n' > "$FIX/.claude-plugin/plugin.json"
# invalid JSON elsewhere
printf '{ this is not json }\n' > "$FIX/broken.json"
# agent whose frontmatter name disagrees with its filename
printf -- '---\nname: wrong-name\ndescription: d\n---\nbody\n' > "$FIX/agents/demo-agent.md"
# skill referencing a file that does not exist, and never naming the agent
printf -- '---\nname: demo\ndescription: d\n---\nSee `references/missing.md`.\n' > "$FIX/skills/demo/SKILL.md"
echo "$FIX"
```

Keep `$FIX` for the next steps.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash scripts/check-plugin.sh "$FIX"`
Expected: FAIL — `bash: scripts/check-plugin.sh: No such file or directory`, exit 127.

- [ ] **Step 3: Write the checker**

Create `scripts/check-plugin.sh`:

```bash
#!/usr/bin/env bash
# check-plugin.sh — structural validation for a Claude Code plugin directory.
#
# Checks:
#   1. .claude-plugin/plugin.json exists, parses, and carries name/version/description/author
#   2. every *.json under the plugin parses
#   3. every agents/*.md has frontmatter whose `name:` equals the filename stem
#   4. every skills/*/SKILL.md has frontmatter whose `name:` equals its directory name
#   5. every `references/...md` path named in a SKILL.md exists, resolved either
#      relative to that skill's directory or relative to the plugin root
#      (a ${CLAUDE_PLUGIN_ROOT}-style path). Both forms are in use in this repo.
#   6. every agents/*.md stem is referenced by at least one SKILL.md in the plugin
#
# Exit: 0 pass, 1 structural failure, 2 usage error.
#
# bash 3.2 compatible. No GNU-only constructs.

set -u

plugin="${1:-}"
if [ -z "$plugin" ] || [ ! -d "$plugin" ]; then
  echo "usage: check-plugin.sh <plugin-dir>" >&2
  exit 2
fi
plugin="${plugin%/}"

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# Read one frontmatter key from a markdown file. Empty output means absent
# or the file has no frontmatter block starting on line 1.
fm_get() {
  awk -v k="$2" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, k ":") == 1 {
      sub("^" k ":[ \t]*", "")
      sub("[ \t]+$", "")
      print
      exit
    }
  ' "$1"
}

# 1. manifest
manifest="$plugin/.claude-plugin/plugin.json"
if [ ! -f "$manifest" ]; then
  err "missing $manifest"
elif ! jq -e . "$manifest" >/dev/null 2>&1; then
  err "$manifest is not valid JSON"
else
  for key in name version description author; do
    jq -e "has(\"$key\")" "$manifest" >/dev/null 2>&1 \
      || err "$manifest missing required key: $key"
  done
fi

# 2. every JSON parses
while IFS= read -r f; do
  jq -e . "$f" >/dev/null 2>&1 || err "$f is not valid JSON"
done < <(find "$plugin" -type f -name '*.json')

# 3. agents
while IFS= read -r f; do
  stem=$(basename "$f" .md)
  name=$(fm_get "$f" name)
  desc=$(fm_get "$f" description)
  [ -n "$name" ] || err "$f has no frontmatter 'name:'"
  [ -n "$desc" ] || err "$f has no frontmatter 'description:'"
  if [ -n "$name" ] && [ "$name" != "$stem" ]; then
    err "$f frontmatter name '$name' does not match filename stem '$stem'"
  fi
done < <(find "$plugin/agents" -type f -name '*.md' 2>/dev/null)

# 4 & 5. skills
while IFS= read -r f; do
  skilldir=$(dirname "$f")
  dirname_=$(basename "$skilldir")
  name=$(fm_get "$f" name)
  desc=$(fm_get "$f" description)
  [ -n "$name" ] || err "$f has no frontmatter 'name:'"
  [ -n "$desc" ] || err "$f has no frontmatter 'description:'"
  if [ -n "$name" ] && [ "$name" != "$dirname_" ]; then
    err "$f frontmatter name '$name' does not match directory '$dirname_'"
  fi
  # The regex must capture any leading path segments — a reference may be
  # ../sibling-skill/references/x.md or skills/foo/references/x.md, and
  # matching from "references/" onward would silently drop the prefix.
  while IFS= read -r rel; do
    if [ ! -f "$skilldir/$rel" ] && [ ! -f "$plugin/$rel" ]; then
      err "$f references missing file: $rel"
    fi
  done < <(grep -oE '(\.\./)*([A-Za-z0-9_.-]+/)*references/[A-Za-z0-9_./-]+\.md' "$f" \
             | sort -u)
done < <(find "$plugin/skills" -type f -name 'SKILL.md' 2>/dev/null)

# 6. orphan agents — also catches a dispatch-name typo in a SKILL.md,
#    because the correct stem then appears nowhere.
while IFS= read -r f; do
  stem=$(basename "$f" .md)
  if ! grep -rqF -- "$stem" "$plugin/skills" 2>/dev/null; then
    err "agent '$stem' is never referenced by any SKILL.md in $plugin"
  fi
done < <(find "$plugin/agents" -type f -name '*.md' 2>/dev/null)

if [ "$fail" -ne 0 ]; then
  echo "check-plugin: FAILED ($plugin)" >&2
  exit 1
fi
echo "check-plugin: OK ($plugin)"
exit 0
```

Then `chmod +x scripts/check-plugin.sh`.

- [ ] **Step 4: Run it against the broken fixture to verify it fails correctly**

Run: `bash scripts/check-plugin.sh "$FIX"; echo "exit=$?"`

Expected: exit 1, and all four of these on stderr:
- `missing required key: author`
- `broken.json is not valid JSON`
- `frontmatter name 'wrong-name' does not match filename stem 'demo-agent'`
- `references missing file: references/missing.md`
- `agent 'demo-agent' is never referenced by any SKILL.md`

If any is absent, the check for it is wrong — fix the script, not the fixture.

- [ ] **Step 5: Run it against the real plugins to verify it passes**

Run:
```bash
for p in plugins/*/; do bash scripts/check-plugin.sh "$p"; done
```
Expected: `check-plugin: OK` for all five plugins (`code-safely-plugin`, `devtools`, `github-app-identity`, `kanban-flow`, `productivity`), exit 0 throughout. This script was smoke-tested against them while the plan was written, so any failure here is a regression you introduced.

If a plugin does fail, **investigate before concluding anything**. Both failures encountered while developing this checker turned out to be bugs in the checker, not defects in the plugin: `productivity` uses a `../sibling-skill/references/…` reference, and `kanban-flow` uses a `${CLAUDE_PLUGIN_ROOT}`-relative one — the two resolution forms rule 5 now handles. Only once you have confirmed the checker is right is a failure a real plugin defect; report it and do not fix that plugin in this task.

Then clean up: `rm -rf "$FIX"`.

- [ ] **Step 6: Document the tooling in CLAUDE.md**

In `CLAUDE.md`, under "Working in this repo", replace the bullet reading:

> - **No build/test tooling** exists yet. Plugin components (commands, agents, skills) are Markdown/JSON and are validated by installing the plugin into Claude Code and exercising it, not by a test runner. Add build/lint/test instructions here if and when tooling is introduced.

with:

```markdown
- **Structural check**: `bash scripts/check-plugin.sh plugins/<name>` validates a plugin's
  manifest keys, JSON parseability, agent and skill frontmatter (frontmatter `name:` must
  match the filename stem / directory name), that every `references/…md` path a `SKILL.md`
  mentions exists, and that every agent is referenced by some `SKILL.md`. Run it over every
  plugin before committing:
  `for p in plugins/*/; do bash scripts/check-plugin.sh "$p" || break; done`
- **No behavioural test tooling** exists. The checker is structural only; a plugin's actual
  behaviour is validated by installing it into Claude Code and exercising it.
```

- [ ] **Step 7: Commit**

```bash
git add scripts/check-plugin.sh CLAUDE.md
git commit -m "$(cat <<'EOF'
build: add structural plugin checker

Validates manifest keys, JSON parseability, agent/skill frontmatter, and
reference-path and agent-reference integrity. Catches the silent failure
modes of a markdown-defined plugin: a mistyped dispatch name or a broken
doctrine path.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DjogvputUg2dezHUDmGJvV
EOF
)"
```

---

### Task 2: Config template and target-resolution doctrine

The input-side contract: what the skill can be configured with, and how it turns an argument into a repo, a PR, and a tree to grep.

**Files:**
- Create: `plugins/devtools/templates/pr-reviewer.json`
- Create: `plugins/devtools/skills/pr-reviewer/references/target-resolution.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the twelve config keys named in Global Constraints, read by `SKILL.md` (Task 7). `target-resolution.md` produces the variable names `target_repo` (`owner/repo`), `target_pr` (integer or empty), `self_login`, `workdir`, and `worktree` — Tasks 7 and 8 use exactly these names.

- [ ] **Step 1: Write the failing test**

Save this as `/tmp/t2-check.sh`:

```bash
#!/usr/bin/env bash
set -u
fail=0
T=plugins/devtools/templates/pr-reviewer.json
R=plugins/devtools/skills/pr-reviewer/references/target-resolution.md

jq -e . "$T" >/dev/null 2>&1 || { echo "FAIL: $T not valid JSON"; fail=1; }

# every default must match the spec exactly
check() {  # check <jq-filter> <expected>
  got=$(jq -c "$1" "$T" 2>/dev/null)
  [ "$got" = "$2" ] || { echo "FAIL: $1 = $got, expected $2"; fail=1; }
}
check '.renovate_authors'         '["renovate[bot]"]'
check '.exclude_authors'          '[]'
check '.require_label'            'null'
check '.max_reviews_per_pass'     '3'
check '.max_merges_per_pass'      '1'
check '.max_rounds'               '3'
check '.merge_method'             '"squash"'
check '.max_merge_lines'          '800'
check '.max_review_lines'         '3000'
check '.ignore_paths'             '["*.lock","package-lock.json","**/generated/**"]'
check '.update_branch_after_merge' 'false'
check '.clone_cache_dir'          'null'
n=$(jq -r 'keys | length' "$T" 2>/dev/null)
[ "$n" = "12" ] || { echo "FAIL: expected 12 config keys, got $n"; fail=1; }

for s in 'all digits' 'is a repo reference' 'blobless' 'refs/pr-reviewer/' \
         'worktree remove' 'update-ref -d' 'gh pr diff'; do
  grep -qF -- "$s" "$R" 2>/dev/null || { echo "FAIL: $R missing: $s"; fail=1; }
done
exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/t2-check.sh; echo "exit=$?"`
Expected: exit 1, with `FAIL:` lines for the missing files.

- [ ] **Step 3: Write the config template**

Create `plugins/devtools/templates/pr-reviewer.json`:

```json
{
  "renovate_authors": ["renovate[bot]"],
  "exclude_authors": [],
  "require_label": null,
  "max_reviews_per_pass": 3,
  "max_merges_per_pass": 1,
  "max_rounds": 3,
  "merge_method": "squash",
  "max_merge_lines": 800,
  "max_review_lines": 3000,
  "ignore_paths": ["*.lock", "package-lock.json", "**/generated/**"],
  "update_branch_after_merge": false,
  "clone_cache_dir": null
}
```

- [ ] **Step 4: Write the target-resolution doctrine**

Create `plugins/devtools/skills/pr-reviewer/references/target-resolution.md`. It must contain, in this order:

1. **A heading and one-line purpose.**
2. **The resolution table** — the seven rows from the spec's Invocation section, verbatim (no argument; all digits; `https://github.com/o/r/pull/42`; `o/r#42`; `https://github.com/o/r`; `git@github.com:o/r.git`; `o/r`), each mapping to `target_repo`, `target_pr`, and mode.
3. **The disambiguation rule, stated as absolute:** an argument that is all digits is a PR number; an argument that contains a `/` is a repo reference. No argument and no git repo in the working directory is a hard stop.
4. **Extraction recipes** as runnable snippets:
   ```bash
   # from a git remote URL (https or ssh) → owner/repo
   # Two stages on purpose: BSD ERE has no non-greedy quantifier, so a
   # `([^/]+/[^/]+?)(\.git)?$` form is a hard parse error on stock macOS.
   # Match first, strip the optional .git second.
   origin_repo() {
     git remote get-url origin 2>/dev/null \
       | sed -nE 's#^(https://github\.com/|git@github\.com:)([^/]+/[^/]+)$#\2#p' \
       | sed -E 's#\.git$##'
   }

   # from a PR URL → owner/repo and number
   # https://github.com/o/r/pull/42 → "o/r 42"
   parse_pr_url() {
     printf '%s\n' "$1" \
       | sed -nE 's#^https://github\.com/([^/]+/[^/]+)/pull/([0-9]+).*$#\1 \2#p'
   }
   ```
5. **`self_login`:** `self_login=$(gh api user --jq .login)`. State that this is what the self-review downgrade compares against, and that it is resolved once per pass.
6. **Locality decision:** the target is *local* when the working directory is a git repo whose `origin_repo` equals `target_repo`; otherwise *remote*. State that a remote target must never touch the working directory's repo.
7. **Local worktree recipe**, verbatim:
   ```bash
   git -C "$repo" fetch origin "pull/$n/head:refs/pr-reviewer/$n" --force
   git -C "$repo" worktree add --detach "$workdir/tree" "refs/pr-reviewer/$n"
   ```
   With the explicit note: this touches no branch, no index, and no checked-out file in the user's working tree.
8. **Remote clone recipe**, verbatim, with the cache path rule (`clone_cache_dir` if set, else the session scratchpad):
   ```bash
   git clone --filter=blob:none --no-checkout \
     "https://github.com/$target_repo.git" "$cache/$owner-$repo"
   ```
   State that the clone is blobless so blobs arrive on demand, that it is reused across PRs in a pass and across passes under `/loop`, and that reuse is a `git fetch`, never a re-clone.
9. **Cleanup, mandatory after each PR**, verbatim:
   ```bash
   git -C "$repo" worktree remove --force "$workdir/tree"
   git -C "$repo" update-ref -d "refs/pr-reviewer/$n"
   ```
   With: a local target must be left exactly as found, including on failure.
10. **The diff is canonical from GitHub.** `gh pr diff --repo "$target_repo" "$n" > "$workdir/pr-$n.diff"`. State the reason explicitly — inline comments must anchor to lines GitHub recognises as part of the diff, so using GitHub's own rendering guarantees the line numbers match — and that the worktree exists *only* for surrounding-code context, never to compute the diff.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash /tmp/t2-check.sh; echo "exit=$?"`
Expected: exit 0, no output.

Then run: `bash scripts/check-plugin.sh plugins/devtools`
Expected: `check-plugin: OK`. (No `SKILL.md` exists yet, so rule 5 has nothing to check and rule 6 sees no new agents — this passes.)

- [ ] **Step 6: Commit**

```bash
git add plugins/devtools/templates/pr-reviewer.json \
        plugins/devtools/skills/pr-reviewer/references/target-resolution.md
git commit -m "$(cat <<'EOF'
feat(pr-reviewer): add config template and target-resolution doctrine

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DjogvputUg2dezHUDmGJvV
EOF
)"
```

---

### Task 3: Lens doctrine — shared etiquette and three lens briefs

Four files, one deliverable: `_shared.md` is meaningless without the lenses, and a lens brief is meaningless without the etiquette that bounds it. This is the content that decides whether the review is useful or noise.

**Files:**
- Create: `plugins/devtools/skills/pr-reviewer/references/lenses/_shared.md`
- Create: `plugins/devtools/skills/pr-reviewer/references/lenses/requirements.md`
- Create: `plugins/devtools/skills/pr-reviewer/references/lenses/correctness.md`
- Create: `plugins/devtools/skills/pr-reviewer/references/lenses/craft.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the finding JSON schema below, emitted by `pr-review-lens` (Task 4) and consumed by `pr-review-verdict` (Task 5). Field names and enum values are fixed by Global Constraints.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/t3-check.sh`:

```bash
#!/usr/bin/env bash
set -u
fail=0
L=plugins/devtools/skills/pr-reviewer/references/lenses

for f in _shared requirements correctness craft; do
  [ -f "$L/$f.md" ] || { echo "FAIL: missing $L/$f.md"; fail=1; }
done

# the six etiquette rules must all be present in _shared
for s in 'path:line' 'not the code you would have written' 'linter' \
         'pre-existing' 'stated consequence' 'do not re-raise'; do
  grep -qiF -- "$s" "$L/_shared.md" 2>/dev/null \
    || { echo "FAIL: _shared.md missing rule: $s"; fail=1; }
done

# the schema must name every field, with no stray enum values
for s in '"severity"' '"failure_scenario"' '"side"' '"claim"' \
         '"consequence"' '"fix"' 'blocking' 'advisory' 'RIGHT' 'LEFT' \
         'needs-input'; do
  grep -qF -- "$s" "$L/_shared.md" 2>/dev/null \
    || { echo "FAIL: _shared.md missing schema token: $s"; fail=1; }
done

# each lens brief must carry the four required sections and a worked example
for f in requirements correctness craft; do
  for s in '## Your lens' '## Walk' '## Blocking bar' '## Example finding'; do
    grep -qF -- "$s" "$L/$f.md" 2>/dev/null \
      || { echo "FAIL: $f.md missing section: $s"; fail=1; }
  done
done

# no lens may duplicate another's territory by naming it as its own
grep -qi 'not your lens' "$L/requirements.md" || { echo "FAIL: requirements.md lacks a scope fence"; fail=1; }
grep -qi 'not your lens' "$L/correctness.md"  || { echo "FAIL: correctness.md lacks a scope fence"; fail=1; }
grep -qi 'not your lens' "$L/craft.md"        || { echo "FAIL: craft.md lacks a scope fence"; fail=1; }
exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/t3-check.sh; echo "exit=$?"`
Expected: exit 1, four `missing` lines plus the content checks.

- [ ] **Step 3: Write `_shared.md`**

It must contain:

**Etiquette — the six rules, each with its reason.** Copy these verbatim as the rule text:

1. Anchor every finding to a `path:line` inside the diff. Observation → consequence → concrete fix. A finding a reader cannot act on is not a finding.
2. Review the diff as written, not the code you would have written. Taste is not a finding.
3. Do not flag what a linter, formatter, type checker, or CI already enforces — that noise trains authors to ignore you.
4. Do not flag pre-existing code the diff does not touch. The author is answerable for their change, not the file's history.
5. Blocking requires a stated consequence a reasonable author would accept. If you cannot name what goes wrong, it is advisory.
6. When a prior round's recommendation was addressed, say so and do not re-raise it. Re-raising a resolved point is how a review loop becomes infinite.

**Method:** a map pass first — read the whole diff and the requirements, write nothing — then a line pass through your lens only. Use the worktree (Read/Grep/Glob) for context the hunk hides: a change that looks correct in isolation may break a caller or violate an invariant visible one screen away.

**Scope fence:** you are one of three lenses. Findings outside your lens belong to another agent; do not file them. Overlap wastes the adjudicator's budget.

**The return schema**, given as a fenced JSON block exactly as in the spec:

```json
{
  "lens": "correctness",
  "status": "complete",
  "findings": [
    {
      "path": "src/foo.ts",
      "line": 42,
      "side": "RIGHT",
      "severity": "blocking",
      "claim": "one sentence: what is wrong",
      "consequence": "what goes wrong as a result",
      "failure_scenario": "concrete inputs or state → wrong output or crash",
      "fix": "what right looks like",
      "addressed_prior": false
    }
  ],
  "notes": "one-line summary of the pass"
}
```

With the field rules stated beneath it:
- `severity` is `blocking` or `advisory`. Nothing else.
- `failure_scenario` is **required** when `severity` is `blocking` on the correctness lens; optional elsewhere.
- `side` is `RIGHT` for an added or context line, `LEFT` for a deleted one.
- `line` must be a line the diff touches, or the comment will be rejected by GitHub.
- `addressed_prior` is `true` only when this finding restates a prior-round recommendation the author has now fixed — set it and mark the finding `advisory`.
- `status` is `complete`, or `needs-input` when you could not review at all (unreadable worktree, empty diff). Finding nothing is `complete` with an empty `findings` array — never `needs-input`.
- Return exactly one JSON object and no prose.

- [ ] **Step 4: Write `requirements.md`**

- `## Your lens` — does the diff do what the resolved requirements say: all of it, and nothing undisclosed. You are given `requirements` (resolved from the PR body, linked issues, or referenced specs) and the PR body.
- `## Not your lens` — whether the code is correct, elegant, or idiomatic. Only whether it is *the change that was promised*.
- `## Walk` — (1) list every discrete requirement as a checklist; (2) for each, find the code that serves it and cite `path:line`; (3) list every behavioural change the diff makes and check each traces back to a requirement; (4) flag the residue in both directions.
- `## Blocking bar` — a requirement with no implementing code; behaviour that contradicts stated intent; a behavioural change no requirement asked for and the body does not disclose. **And: when `requirements` is `null` or too vague to check against, file one blocking finding at the PR level (`path` the most-changed file, `line` its first changed line) stating that the PR's intent is not written down anywhere and so conformity cannot be verified.** A PR whose intent is unrecorded does not merge unattended.
- `## Not blocking` — a requirement implemented differently than you would have; extra tests; documentation the requirements did not ask for.
- `## Example finding` — a worked example in the schema, showing a requirement with no implementing code.

- [ ] **Step 5: Write `correctness.md`**

- `## Your lens` — edge cases, error paths, boundaries, concurrency, resource lifecycle. The failure modes a happy-path read misses.
- `## Not your lens` — style, naming, structure, or whether the change was asked for.
- `## Walk` — for each changed function: (1) empty, zero, negative, one, and maximum inputs; (2) null/undefined/missing-key paths; (3) every error path — is it handled, swallowed, or propagated, and is that right; (4) every resource acquired — is it released on the failure path too; (5) concurrent or re-entrant callers, if the surrounding code has any; (6) the boundary of every loop and slice; (7) grep the worktree for callers of every changed signature and check each still holds.
- `## Blocking bar` — you can state a concrete failure scenario: these inputs or this state produce this wrong output or this crash. **No scenario, no block** — file it advisory.
- `## Not blocking` — a theoretically possible input the surrounding code prevents; a defensive check against something the type system already excludes.
- `## Example finding` — a worked example with a populated `failure_scenario`.

- [ ] **Step 6: Write `craft.md`**

- `## Your lens` — simplicity, style, and consistency with the surrounding code.
- `## Not your lens` — correctness, and whether the change was asked for.
- `## Walk` — (1) does each new unit have one clear purpose; (2) is there needless indirection, state, or generality the requirements did not call for; (3) grep the worktree — does this duplicate something that already exists; (4) does it follow the conventions of the files it sits in (naming, error handling, module layout, comment density); (5) could a reader understand it without holding more than a few things in their head.
- `## Blocking bar` — deliberately high, because most craft findings are advisory: needless complexity a reader must hold in their head to follow the change; duplication of an existing utility rather than reuse; a convention break that would mislead the next reader into copying it. Nothing else blocks.
- `## Not blocking` — naming you would have chosen differently; formatting; ordering; anything a linter owns; a pattern that is merely unfamiliar rather than misleading.
- `## Example finding` — a worked advisory example and a worked blocking example, so the bar between them is concrete.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bash /tmp/t3-check.sh; echo "exit=$?"`
Expected: exit 0.

Run: `bash scripts/check-plugin.sh plugins/devtools`
Expected: `check-plugin: OK`.

- [ ] **Step 8: Commit**

```bash
git add plugins/devtools/skills/pr-reviewer/references/lenses/
git commit -m "$(cat <<'EOF'
feat(pr-reviewer): add lens doctrine — shared etiquette and three briefs

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DjogvputUg2dezHUDmGJvV
EOF
)"
```

---

### Task 4: The `pr-review-lens` agent

One agent definition serving all three lenses, parameterised by its brief path.

**Files:**
- Create: `plugins/devtools/agents/pr-review-lens.md`

**Interfaces:**
- Consumes: `references/lenses/_shared.md` and `references/lenses/<lens>.md` from Task 3, both by **absolute path supplied in the dispatch** — never a relative path, never a hardcoded one.
- Produces: dispatch parameter names, which Task 8 must use exactly: `lens`, `pr`, `target_repo`, `diff_path`, `worktree`, `requirements`, `pr_body`, `prior_recommendations`, `shared_brief_path`, `lens_brief_path`. Returns the finding JSON object defined in `_shared.md`.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/t4-check.sh`:

```bash
#!/usr/bin/env bash
set -u
fail=0
A=plugins/devtools/agents/pr-review-lens.md
[ -f "$A" ] || { echo "FAIL: missing $A"; exit 1; }

grep -qE '^model: sonnet$' "$A" || { echo "FAIL: model must be sonnet"; fail=1; }
grep -qE '^tools: ' "$A"        || { echo "FAIL: no tools line"; fail=1; }
grep -qE '^tools:.*Bash' "$A"   && { echo "FAIL: lens must not have Bash"; fail=1; }
grep -qE '^tools:.*(Edit|Write)' "$A" && { echo "FAIL: lens must not write"; fail=1; }

for p in lens pr target_repo diff_path worktree requirements pr_body \
         prior_recommendations shared_brief_path lens_brief_path; do
  grep -qF -- "\`$p\`" "$A" || { echo "FAIL: dispatch param not documented: $p"; fail=1; }
done

for s in 'absolute path' 'exactly one JSON object' 'never edit' 'never merge'; do
  grep -qiF -- "$s" "$A" || { echo "FAIL: missing: $s"; fail=1; }
done
exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/t4-check.sh; echo "exit=$?"`
Expected: exit 1, `FAIL: missing plugins/devtools/agents/pr-review-lens.md`.

- [ ] **Step 3: Write the agent**

Create `plugins/devtools/agents/pr-review-lens.md`. Frontmatter exactly:

```markdown
---
name: pr-review-lens
description: One lens of the pr-reviewer panel — reviews a pull request's diff through its single assigned lens (requirements, correctness, or craft) and returns structured findings. Reads the diff from a file and the surrounding code from a read-only worktree. Never edits code, never touches GitHub, never merges. Dispatched three times in parallel per PR by the pr-reviewer skill.
model: sonnet
tools: Read, Grep, Glob
---
```

Note the tool set: no `Bash`, no `Edit`, no `Write`. The lens has no business running commands or changing anything, and withholding the tools is more reliable than instructing it not to.

Body must contain:

1. **Role** — you are one expert on a three-lens panel. You review the whole diff through your assigned lens *only*. Together the panel is the author's reviewer; separately, none of you is.
2. **Input** — the ten dispatch parameters, each in backticks with one line of meaning:
   - `lens` — `requirements`, `correctness`, or `craft`. Your assignment.
   - `pr` — the PR number, for reference in your notes.
   - `target_repo` — `owner/repo`, for reference.
   - `diff_path` — absolute path to the canonical diff, as GitHub renders it. **This is your diff. Do not compute one.**
   - `worktree` — absolute path to a read-only checkout at the PR head, for surrounding-code context only.
   - `requirements` — the resolved requirements text, or `null` when none could be found.
   - `pr_body` — the PR description as written.
   - `prior_recommendations` — the previous round's numbered recommendations, or empty on round 1.
   - `shared_brief_path` — absolute path to `_shared.md`. Read it first; it binds you.
   - `lens_brief_path` — absolute path to your lens's brief. Read it second; its Walk is your procedure and its Example finding is your calibration bar.
3. **Do** — read the two briefs at the **absolute paths given in your dispatch** (never a relative or remembered path); read `diff_path`; map pass; line pass per your brief's Walk; use the worktree for context.
4. **Never** — never edit a file, never merge, never comment on GitHub, never review outside your lens, never invent a line number that is not in the diff.
5. **Return** — exactly one JSON object per the schema in `_shared.md`, and no prose.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash /tmp/t4-check.sh; echo "exit=$?"`
Expected: exit 0.

Run: `bash scripts/check-plugin.sh plugins/devtools`
Expected: **FAIL** — `agent 'pr-review-lens' is never referenced by any SKILL.md`. This is correct: `SKILL.md` does not exist until Task 7. Record the failure and continue; Task 7's verification is where it must clear.

- [ ] **Step 5: Commit**

```bash
git add plugins/devtools/agents/pr-review-lens.md
git commit -m "$(cat <<'EOF'
feat(pr-reviewer): add pr-review-lens agent

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DjogvputUg2dezHUDmGJvV
EOF
)"
```

---

### Task 5: Verdict doctrine and the `pr-review-verdict` agent

**Files:**
- Create: `plugins/devtools/skills/pr-reviewer/references/verdict.md`
- Create: `plugins/devtools/agents/pr-review-verdict.md`

**Interfaces:**
- Consumes: the finding schema from Task 3.
- Produces: dispatch parameters `pr`, `target_repo`, `pr_title`, `pr_body`, `requirements`, `prior_recommendations`, `round`, `head_sha`, `findings`, `verdict_doctrine_path`; and the verdict return object below, consumed by Task 8.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/t5-check.sh`:

```bash
#!/usr/bin/env bash
set -u
fail=0
V=plugins/devtools/skills/pr-reviewer/references/verdict.md
A=plugins/devtools/agents/pr-review-verdict.md
for f in "$V" "$A"; do [ -f "$f" ] || { echo "FAIL: missing $f"; fail=1; }; done
[ "$fail" = 1 ] && exit 1

grep -qE '^model: opus$' "$A" || { echo "FAIL: verdict agent must be opus"; fail=1; }
grep -qE '^tools:.*(Bash|Edit|Write)' "$A" && { echo "FAIL: verdict agent must not act"; fail=1; }
grep -qiF 'never the diff' "$A" || { echo "FAIL: agent must be told it gets no diff"; fail=1; }

for s in approve request-changes park; do
  grep -qF -- "$s" "$V" || { echo "FAIL: verdict.md missing verdict: $s"; fail=1; }
done
for s in 'at least one surviving blocking finding' 'must not be re-raised' \
         'pr-reviewer: verdict=' 'dedup' 'downgrade'; do
  grep -qiF -- "$s" "$V" || { echo "FAIL: verdict.md missing: $s"; fail=1; }
done
for p in pr target_repo pr_title pr_body requirements prior_recommendations \
         round head_sha findings verdict_doctrine_path; do
  grep -qF -- "\`$p\`" "$A" || { echo "FAIL: dispatch param not documented: $p"; fail=1; }
done
exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/t5-check.sh; echo "exit=$?"`
Expected: exit 1, two `missing` lines.

- [ ] **Step 3: Write `verdict.md`**

Sections required:

**Purpose** — you adjudicate claims, not code. You are given every lens's findings and never the diff. That is deliberate: giving you the code invites a fourth, unaccountable review, and the panel has already done the reading.

**Procedure, in order:**
1. **Dedup.** Craft and correctness routinely land on the same hunk. Merge findings that name the same defect at the same `path:line`, keeping the highest severity and the clearest fix.
2. **Downgrade.** Move to `advisory`: matters of taste; speculation without a concrete scenario; anything a linter, formatter, or type checker owns; a defensive check against something already impossible; a blocking finding whose `consequence` field is empty or circular.
3. **Compare against the prior round.** A recommendation the author addressed must not be re-raised — if a lens raised it again, drop it and note it as resolved. A recommendation they ignored is re-raised and stated more plainly.
4. **Decide.**

**The decision rule, stated as absolute:** `request-changes` requires at least one surviving blocking finding carrying a stated consequence. If none survives, the verdict is `approve`, and the surviving advisory findings still go out as inline comments *on the approving review*. Comment, and merge.

**`park`** is a third verdict, distinct from `request-changes`. Use it when the PR needs a human decision rather than a rework: an architectural fork with no obviously right answer; a product or policy call; a security-sensitive surface (authentication, authorisation, cryptography, secret handling, or a change to the deployment or CI configuration itself) where an unattended approval is inappropriate regardless of how the code looks. State plainly which of these it is.

**Review body format** — a fenced template:

```markdown
<!-- pr-reviewer: verdict=request-changes round=2 sha=abc1234 -->
**pr-reviewer** — changes requested

<one-paragraph summary of what the PR does and the shape of the concern>

### Required changes
1. `path/to/file.ts:42` — <what is wrong> → <what right looks like>
2. …

### Advisory
- `path/to/other.ts:88` — <observation> → <suggestion>

### Resolved since the last round
- <prior recommendation now addressed>
```

With the rules: the hidden marker is the **first line, always**, in exactly that shape — the next pass reads the verdict from it, because a self-review downgrade erases the verdict from GitHub's review state. `sha` is the short head SHA reviewed. Omit the `### Required changes` section entirely on an approve; omit `### Advisory` and `### Resolved since the last round` when empty. Never include a section with no items.

**Return schema:**

```json
{
  "verdict": "approve",
  "reason": "one line for the orchestrator's report",
  "body": "the full markdown body INCLUDING the hidden marker first line",
  "comments": [
    { "path": "src/foo.ts", "line": 42, "side": "RIGHT", "body": "…" }
  ],
  "blocker_count": 0
}
```

With: `blocker_count` must be `0` when `verdict` is `approve` and ≥ 1 when it is `request-changes` — a mismatch is a bug in your adjudication, not a valid output. Every entry in `comments` must carry a `path`, `line`, and `side` copied unchanged from a surviving finding; never invent one.

- [ ] **Step 4: Write the agent**

Create `plugins/devtools/agents/pr-review-verdict.md`. Frontmatter exactly:

```markdown
---
name: pr-review-verdict
description: Adjudicates the pr-reviewer lens panel's findings into a single verdict — approve, request-changes, or park — and authors the GitHub review body and inline comments. Sees the findings and the requirements, never the diff. Never touches GitHub or the filesystem. Dispatched once per PR by the pr-reviewer skill.
model: opus
tools: Read
---
```

`Read` only, so it can read the doctrine file and nothing else.

Body must contain: the role (you are the single place the blocking-versus-advisory judgement lives); the ten dispatch parameters each in backticks with a line of meaning; the instruction to read `verdict_doctrine_path` (**an absolute path from your dispatch**) first and follow it exactly; an explicit statement that you receive **never the diff** and must not ask for one or speculate about code you cannot see; and the return contract — exactly one JSON object per the doctrine's schema, no prose.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash /tmp/t5-check.sh; echo "exit=$?"`
Expected: exit 0.

Run: `bash scripts/check-plugin.sh plugins/devtools`
Expected: FAIL on two unreferenced agents (`pr-review-lens`, `pr-review-verdict`) — still correct until Task 7.

- [ ] **Step 6: Commit**

```bash
git add plugins/devtools/skills/pr-reviewer/references/verdict.md \
        plugins/devtools/agents/pr-review-verdict.md
git commit -m "$(cat <<'EOF'
feat(pr-reviewer): add verdict doctrine and adjudicator agent

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DjogvputUg2dezHUDmGJvV
EOF
)"
```

---

### Task 6: The `pr-merger` agent

The last gate before an irreversible, unattended action. It re-verifies everything the orchestrator already checked, because two independent agreements are the point.

**Files:**
- Create: `plugins/devtools/agents/pr-merger.md`

**Interfaces:**
- Consumes: dispatch parameters `pr`, `target_repo`, `merge_method`, `self_login`, `max_merge_lines`, `ignore_paths`.
- Produces: `{ "pr": <n>, "outcome": "merged" | "aborted", "reason": "<reason>" }` with `reason` ∈ `merged`, `behind`, `conflict`, `blocked`, `not-green`, `threads-open`, `too-large`. Task 8 routes on these exact strings.

Note: `too-large` is added to the spec's list. The orchestrator already enforces `max_merge_lines`, but the merger re-verifies every other gate independently and this one must not be the exception.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/t6-check.sh`:

```bash
#!/usr/bin/env bash
set -u
fail=0
A=plugins/devtools/agents/pr-merger.md
[ -f "$A" ] || { echo "FAIL: missing $A"; exit 1; }

grep -qE '^model: haiku$' "$A" || { echo "FAIL: must be haiku"; fail=1; }
grep -qE '^tools:.*(Edit|Write)' "$A" && { echo "FAIL: merger must not write files"; fail=1; }

for s in merged behind conflict blocked not-green threads-open too-large; do
  grep -qF -- "\"$s\"" "$A" || { echo "FAIL: reason not documented: $s"; fail=1; }
done
for s in 'reviewThreads' 'mergeStateStatus' 'statusCheckRollup' 'CLEAN' \
         'never comment' 'never label' 'gh pr merge'; do
  grep -qiF -- "$s" "$A" || { echo "FAIL: missing: $s"; fail=1; }
done
grep -qiF 'NEVER report' "$A" || { echo "FAIL: missing the no-false-merge rule"; fail=1; }
exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/t6-check.sh; echo "exit=$?"`
Expected: exit 1, `FAIL: missing plugins/devtools/agents/pr-merger.md`.

- [ ] **Step 3: Write the agent**

Create `plugins/devtools/agents/pr-merger.md`. Frontmatter exactly:

```markdown
---
name: pr-merger
description: Independently re-verifies every merge gate on one approved pull request — CI green, cleanly mergeable, no unresolved human review threads, within the size ceiling — then merges it. Mechanical gh-only work; never edits files, never comments, never labels, never touches any PR but the one it is given. Dispatched one at a time by the pr-reviewer skill.
model: haiku
tools: Bash, Read
---
```

Body must contain:

1. **Role** — you merge exactly one PR, or you abort. Your caller has already reviewed and approved it; you do **not** trust that. You re-verify live, because you are the last gate before an unattended merge. Two independent agreements must hold, or nothing merges.
2. **Input** — the six dispatch parameters in backticks.
3. **Do**, as a numbered procedure with the exact commands:
   - Re-fetch live:
     `gh pr view "$pr" --repo "$target_repo" --json number,author,title,isDraft,mergeStateStatus,statusCheckRollup,reviews`
   - **not-draft** — `isDraft` is false. Else abort `blocked`.
   - **green** — inspect `statusCheckRollup`. Each entry is either a CheckRun (has `status` and `conclusion`) or a legacy StatusContext (has `state`). Any entry `FAILURE`/`ERROR`/`CANCELLED`/`TIMED_OUT`/`ACTION_REQUIRED`/`STARTUP_FAILURE`, or any still settling (`QUEUED`/`IN_PROGRESS`/`PENDING`/`WAITING`/`STALE`) → abort `not-green`. Otherwise green requires at least one `SUCCESS`; `SKIPPED` and `NEUTRAL` are non-blocking but do not count as the required success. An empty rollup → abort `not-green`.
   - **threads** — two checks, both must pass:
     ```bash
     gh api graphql -f query='
       query($owner:String!,$repo:String!,$pr:Int!){
         repository(owner:$owner,name:$repo){
           pullRequest(number:$pr){
             reviewThreads(first:100){
               nodes{ isResolved isOutdated comments(first:1){ nodes{ author{ login } } } }
             }
           }
         }
       }' -F owner="$owner" -F repo="$repo" -F pr="$pr"
     ```
     Any thread that is unresolved, not outdated, and whose first comment's author is not `self_login` → abort `threads-open`. Separately, any user other than `self_login` whose **latest** review state is `CHANGES_REQUESTED` → abort `threads-open`.
   - **size** — recompute:
     ```bash
     gh api "repos/$target_repo/pulls/$pr/files" --paginate \
       --jq '.[] | [.filename, .changes] | @tsv'
     ```
     Sum `.changes` over files not matching `ignore_paths`. Over `max_merge_lines` → abort `too-large`.
   - **mergeable** — `mergeStateStatus` `CLEAN` → proceed. `BEHIND` → abort `behind`. `DIRTY` → abort `conflict`. `BLOCKED` → abort `blocked`. Anything else (`UNKNOWN`, `UNSTABLE`, …) → abort `not-green`.
   - Merge: `gh pr merge "$pr" --repo "$target_repo" --"$merge_method" --delete-branch`
4. **Judgment rules** — a non-zero exit from `gh pr merge` is a failure: return `aborted` with the closest reason (`conflict` if it reports a conflict, else `not-green`). **NEVER report `merged` for a merge that did not complete.** Never re-run a red or pending check hoping it turns green. Never comment, never label, never rebase — the orchestrator owns all annotation. When anything is ambiguous, abort: parking is safe, a wrong unattended merge is not.
5. **Return** — exactly one line of JSON, no prose, per the Interfaces block above.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash /tmp/t6-check.sh; echo "exit=$?"`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/devtools/agents/pr-merger.md
git commit -m "$(cat <<'EOF'
feat(pr-reviewer): add pr-merger agent

Independently re-verifies CI, mergeability, human review threads, and the
size ceiling before an unattended merge.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DjogvputUg2dezHUDmGJvV
EOF
)"
```

---

### Task 7: Orchestrator, part 1 — frontmatter and pass steps 1–6

The intake half: preflight, config, selection, triage, requirements, and review context. A reviewer can reject the state model here while approving the routing in Task 8, which is why these are separate tasks.

**Files:**
- Create: `plugins/devtools/skills/pr-reviewer/SKILL.md`

**Interfaces:**
- Consumes: `references/target-resolution.md` (Task 2) and the config keys it defines.
- Produces, for Task 8 to consume: the per-PR variables `target_repo`, `target_pr`, `self_login`, `can_merge`, `n` (PR number), `head_sha`, `round`, `prior_recommendations`, `requirements`, `pr_body`, `size`, `workdir`, `worktree`, `diff_path`.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/t7-check.sh`:

```bash
#!/usr/bin/env bash
set -u
fail=0
S=plugins/devtools/skills/pr-reviewer/SKILL.md
[ -f "$S" ] || { echo "FAIL: missing $S"; exit 1; }

grep -qE '^name: pr-reviewer$' "$S" || { echo "FAIL: frontmatter name"; fail=1; }
grep -qE '^description: ' "$S"      || { echo "FAIL: frontmatter description"; fail=1; }

for s in '### 1. Preflight' '### 2. Configuration' '### 3. Select candidates' \
         '### 4. Triage' '### 5. Resolve requirements' '### 6. Prepare review context'; do
  grep -qF -- "$s" "$S" || { echo "FAIL: missing section: $s"; fail=1; }
done
for s in 'gh auth status' 'gh api user --jq .login' 'reviewer:working' 'reviewer:parked' \
         'FBCA04' 'D93F0B' 'references/target-resolution.md' \
         'max_review_lines' 'max_reviews_per_pass' 'unchanged since last review' \
         '--paginate' 'single-PR mode'; do
  grep -qF -- "$s" "$S" || { echo "FAIL: missing: $s"; fail=1; }
done
exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/t7-check.sh; echo "exit=$?"`
Expected: exit 1, `FAIL: missing plugins/devtools/skills/pr-reviewer/SKILL.md`.

- [ ] **Step 3: Write the frontmatter and header**

Create `plugins/devtools/skills/pr-reviewer/SKILL.md` starting with:

```markdown
---
name: pr-reviewer
description: Review open pull requests and merge the ones that are ready. Runs a three-lens agent panel (requirements-conformity, correctness and edge cases, craft) over a PR's diff, posts one GitHub review with inline comments, then either requests changes with concrete recommendations or approves and merges. Bare invocation drains the current repo's open-PR queue; pass a PR number, a PR URL, or a repo URL to target something else. Each invocation is one pass; safe under /loop. Excludes Renovate PRs, which the renovator skill owns. Use when asked to review, triage, approve, or merge pull requests.
---

# pr-reviewer — review open PRs and merge what is ready

You are the coordinator. You classify and route; you never review a diff yourself and you never
merge yourself. The `pr-review-lens` agents review, `pr-review-verdict` adjudicates, and
`pr-merger` merges — each in its own context. Keep your own context lean: hold PR metadata and
structured findings only, never a diff.

Runs fully autonomously, including under `/loop`. The human's window into a pass is the
after-action report (step 11) plus the review each PR carries.

This skill is a sibling to `renovator`, not a replacement: `renovator` owns dependency PRs,
`pr-reviewer` owns everything else, and the two never touch the same PR.
```

Then the invocation table (seven rows from the spec's Invocation section) and this paragraph:

> **Single-PR mode** — an argument naming one PR bypasses the selection filters of step 3 (draft status, `renovate_authors`, `require_label`, the `reviewer:parked` exclusion) and all three triage skips of step 4 (unchanged SHA, `max_rounds`, CI pending). Naming a PR is an instruction to review it. The `max_review_lines` ceiling and every merge gate still apply in full; when one of them prevents a merge, say which in the report.

- [ ] **Step 4: Write pass steps 1–6**

Append these six sections. Each must carry the runnable commands, not a description of them.

**`### 1. Preflight`**
- `gh auth status` succeeds, else STOP and report exactly what is missing — do nothing else.
- Resolve the target per `references/target-resolution.md` (join this skill's base directory with that relative path to get the absolute path; the base directory is given to you when the skill is invoked). Sets `target_repo`, `target_pr`, `self_login`.
- Merge permission: `gh api "repos/$target_repo" --jq '.permissions'`. Set `can_merge` true when `push`, `maintain`, or `admin` is true. When false the pass runs **review-only**: every PR is still reviewed and commented, and each would-be merge is reported `no-permission` rather than attempted. Say so once in the report header. A target that 404s here is a hard stop, before any agent is dispatched.
- Ensure the two labels exist (idempotent):
  ```bash
  gh label create reviewer:working --repo "$target_repo" --color FBCA04 \
    --description "pr-reviewer is processing this PR" --force
  gh label create reviewer:parked --repo "$target_repo" --color D93F0B \
    --description "pr-reviewer parked this PR for a human" --force
  ```

**`### 2. Configuration`** — the twelve-row knob table from the spec, verbatim, plus both read recipes:
```bash
# local target
jq -r '.max_rounds // 3' .claude/pr-reviewer.json 2>/dev/null

# remote target — before any clone
gh api "repos/$target_repo/contents/.claude/pr-reviewer.json" --jq .content 2>/dev/null \
  | base64 -d
```
State: read from the **target repo, never the working directory** — a config governing one repository must not silently govern another. A 404 means no config. Absent file or key falls back to the default; unknown keys are ignored.

**`### 3. Select candidates`** (queue mode only; single-PR mode goes straight to step 4):
```bash
gh pr list --repo "$target_repo" --state open --limit 100 \
  --json number,title,author,headRefName,headRefOid,isDraft,mergeStateStatus,labels
```
Drop in order, recording the reason: drafts; authors in `renovate_authors` or `exclude_authors`; PRs lacking `require_label` when it is set; PRs labelled `reviewer:parked` (terminal until a human clears it); PRs labelled `reviewer:working` (another run owns it — outcome `locked`).

**`### 4. Triage before spending an agent`**
```bash
gh api "repos/$target_repo/pulls/$n/reviews" --paginate \
  --jq "[.[] | select(.user.login == \"$self_login\")]"
```
From that one array: `round` is its length; the last-reviewed SHA is the last entry's `commit_id`; `prior_recommendations` is the last entry's `body`. Read the prior verdict from the hidden marker on the body's first line (`<!-- pr-reviewer: verdict=… -->`), falling back to the review `state` when the marker is absent.

Skip without dispatching anything — **queue mode only; single-PR mode runs none of these three**:
- head SHA equals the last-reviewed SHA → outcome `skipped`, reason "unchanged since last review";
- `round` ≥ `max_rounds` and the last verdict was `request-changes` → label `reviewer:parked`, reason "review rounds exhausted";
- CI still settling → outcome `skipped`, reason "CI in progress".

Then size, in **both** modes:
```bash
gh api "repos/$target_repo/pulls/$n/files" --paginate \
  --jq '.[] | [.filename, .changes] | @tsv'
```
Sum `.changes` over files not matching `ignore_paths` → `size`. Over `max_review_lines`: post a COMMENT review saying the PR is too large to review meaningfully and should be split, label `reviewer:parked`, outcome `too-large`, move on. An honest refusal beats a shallow rubber-stamp. Keep `size`; step 10 needs it for the merge ceiling.

Process at most `max_reviews_per_pass` survivors, oldest PR first. Before dispatching anything for a PR, take the lock: add `reviewer:working` and remove `reviewer:parked`. Release it when the PR is done, **always, including on failure**.

**`### 5. Resolve requirements`** — resolve in order, stopping at the first substantive result: the PR body; then linked issues (`Closes #n` / `Fixes #n` / `Resolves #n` in the body, plus GitHub's linked-issue field — fetch each issue's title and body); then spec or design documents the body or branch name references, read from the worktree. Nothing substantive → `requirements` is `null`, and the requirements lens turns that into a blocking finding. The other two lenses review as normal.

**`### 6. Prepare review context`** — per `references/target-resolution.md`: create `workdir`, write the canonical diff to `$workdir/pr-$n.diff` with `gh pr diff --repo "$target_repo" "$n"`, and create the worktree (local target) or reuse the blobless clone (remote target). Restate here, because it is the rule most easily lost: **the diff comes from GitHub, never from a local `git diff`** — inline comments must anchor to lines GitHub recognises as part of the diff, and its own rendering is what guarantees that. The worktree exists only for surrounding-code context. Clean it up after the PR is processed, always.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash /tmp/t7-check.sh; echo "exit=$?"`
Expected: exit 0.

Run: `bash scripts/check-plugin.sh plugins/devtools`
Expected: FAIL — the three agents are still unreferenced (`SKILL.md` does not name them until Task 8), and `references/verdict.md` and the lens briefs are not yet referenced either. Rule 5 checks only that referenced files *exist*, so `target-resolution.md` must resolve cleanly; if it reports that one missing, the path is wrong — fix it now.

- [ ] **Step 6: Commit**

```bash
git add plugins/devtools/skills/pr-reviewer/SKILL.md
git commit -m "$(cat <<'EOF'
feat(pr-reviewer): add orchestrator intake — preflight through review context

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DjogvputUg2dezHUDmGJvV
EOF
)"
```

---

### Task 8: Orchestrator, part 2 — pass steps 7–11, state model, and guardrails

The acting half: dispatch, adjudicate, deliver, merge, report. This is where the skill becomes capable of an irreversible action.

**Files:**
- Modify: `plugins/devtools/skills/pr-reviewer/SKILL.md` (append)

**Interfaces:**
- Consumes: every variable Task 7 produces; the dispatch parameter names from Tasks 4, 5, and 6; the return schemas from Tasks 3, 5, and 6.
- Produces: the finished skill.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/t8-check.sh`:

```bash
#!/usr/bin/env bash
set -u
fail=0
S=plugins/devtools/skills/pr-reviewer/SKILL.md

for s in '### 7. Review' '### 8. Adjudicate' '### 9. Deliver the review' \
         '### 10. Route to an outcome' '### 11. Report' \
         '## State model' '## Under /loop' '## Never do'; do
  grep -qF -- "$s" "$S" || { echo "FAIL: missing section: $s"; fail=1; }
done

# all three agents must be dispatched by exact name
for a in pr-review-lens pr-review-verdict pr-merger; do
  grep -qF -- "$a" "$S" || { echo "FAIL: agent never dispatched: $a"; fail=1; }
done
# all doctrine files must be referenced
for r in references/verdict.md references/lenses/_shared.md \
         references/lenses/requirements.md references/lenses/correctness.md \
         references/lenses/craft.md; do
  grep -qF -- "$r" "$S" || { echo "FAIL: doctrine never referenced: $r"; fail=1; }
done
for s in 'REQUEST_CHANGES' 'APPROVE' 'COMMENT' '422' 'commit_id' \
         'pr-reviewer: verdict=' 'github-app-identity' 'in parallel' \
         'max_merges_per_pass' 'update_branch_after_merge' 'no-permission'; do
  grep -qF -- "$s" "$S" || { echo "FAIL: missing: $s"; fail=1; }
done
exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/t8-check.sh; echo "exit=$?"`
Expected: exit 1, with every section and agent reported missing.

- [ ] **Step 3: Write pass steps 7–11**

Append to `SKILL.md`:

**`### 7. Review — the three-lens panel`** — dispatch **three `pr-review-lens` agents in parallel, in a single message**, one per lens (`requirements`, `correctness`, `craft`), each with:

`{ lens, pr, target_repo, diff_path, worktree, requirements, pr_body, prior_recommendations, shared_brief_path, lens_brief_path }`

State that `shared_brief_path` and `lens_brief_path` are **absolute**, formed by joining this skill's base directory with `references/lenses/_shared.md` and `references/lenses/<lens>.md` — the same convention `renovator` uses for `fix_loop_path`. A relative path will not resolve in the agent's context. Name all five doctrine paths explicitly so the dependency is visible.

A lens returning `status: needs-input` is not a finding: note it in the report and continue with the lenses that succeeded. All three returning `needs-input` → outcome `skipped`, reason "could not review".

**`### 8. Adjudicate`** — dispatch one `pr-review-verdict` with:

`{ pr, target_repo, pr_title, pr_body, requirements, prior_recommendations, round, head_sha, findings, verdict_doctrine_path }`

where `findings` is the concatenation of every lens's `findings` array and `verdict_doctrine_path` is the absolute path to `references/verdict.md`. State: **pass it the findings, never the diff** — withholding the diff is deliberate, because giving it the code invites a fourth, unaccountable review.

**`### 9. Deliver the review`** — submit exactly one review per round:

```bash
jq -n --arg c "$head_sha" --arg b "$body" --arg e "$event" \
      --argjson cm "$comments" \
      '{commit_id:$c, body:$b, event:$e, comments:$cm}' > "$workdir/review.json"
gh api -X POST "repos/$target_repo/pulls/$n/reviews" --input "$workdir/review.json"
```

`commit_id` pins the review to the SHA actually reviewed — this is what makes step 4's triage reliable.

**The self-review downgrade.** GitHub returns 422 for `APPROVE` or `REQUEST_CHANGES` when the reviewer is the PR author. Detect it up front by comparing the PR's `author.login` to `self_login`, rather than catching the error:

| verdict | event (normal) | event (self-authored) |
|---|---|---|
| `approve` | `APPROVE` | `COMMENT` |
| `request-changes` | `REQUEST_CHANGES` | `COMMENT` |
| `park` | `COMMENT` | `COMMENT` |

A downgraded review loses the verdict from GitHub's review *state*, which is why the hidden marker on the body's first line is authoritative. Note that installing this repo's **github-app-identity** plugin gives `gh` a distinct App identity, so real `APPROVE` and `REQUEST_CHANGES` records work on your own PRs.

**Inline-comment robustness.** A single comment anchored outside the diff 422s the *entire* review POST. On a 422 whose message implicates the comments array, retry **once** with `comments` removed and the findings appended to the body as a `path:line — finding` list. An unattended pass must not lose a whole review to one bad line number. A 422 for any other reason is a failure: release the lock, report it, move on.

Note that a newer review from the same user supersedes the older one, so an `APPROVE` after a prior `REQUEST_CHANGES` clears our own block without an explicit dismissal.

**`### 10. Route to an outcome`** — the seven-row routing table from the spec, verbatim (`approve` × gates pass / CI pending / unresolved human threads / over `max_merge_lines` / no merge permission; `request-changes`; `park`), each with its label action and outcome string.

Then the four mechanical gates the orchestrator checks before dispatching `pr-merger` — CI green and `mergeStateStatus` `CLEAN`; no unresolved human review threads (both the GraphQL `reviewThreads` query and the latest-review-per-other-user check, exactly as in `pr-merger`); `size` ≤ `max_merge_lines`; `can_merge` true.

Then: dispatch `pr-merger` with `{ pr, target_repo, merge_method, self_login, max_merge_lines, ignore_paths }` and route its return by `reason` — `merged` → outcome `merged`; `behind` or `not-green` → outcome `skipped` (transient, retries next pass); `conflict`, `blocked`, `threads-open`, or `too-large` → label `reviewer:parked` with that reason. Add the doctrine line: `pr-merger` re-verifies every gate live because two independent agreements gate an unattended merge; when the merger disagrees with the orchestrator, the merger wins and the PR parks.

At most `max_merges_per_pass` merges per pass (default 1), **serialized, never concurrent** — a merge invalidates other PRs' mergeability and re-triggers their CI. Remaining approved PRs are left untouched and resurface next pass, unless `update_branch_after_merge` is true, in which case each gets `gh pr update-branch --repo "$target_repo" <n>`; an error there is non-fatal. It defaults to false because pushing a merge commit onto a contributor's branch is not this skill's business by default.

Release the `reviewer:working` lock for every PR before moving to the next.

**`### 11. Report`** — one table, one row per candidate:

`PR # | title | lines | round | verdict | outcome`

with `outcome` ∈ `merged` / `approved-pending-ci` / `approved-blocked-by-human` / `approved-too-large` / `changes-requested` / `parked` / `skipped` / `locked` / `too-large` / `no-permission`. When `can_merge` is false, say so once in the header.

- [ ] **Step 4: Write the state model, /loop note, and guardrails**

Append three more sections:

**`## State model`** — deliberately thinner than `renovator`'s, because GitHub's reviews API already *is* the state store. One call per PR yields round count, last-reviewed SHA, prior recommendations, and — via the hidden marker — the prior verdict. There is no sticky comment.

Two labels persist only what GitHub cannot tell us:
- `reviewer:working` — a momentary lock held while a PR is processed, so an overlapping run or a `/loop` re-entry cannot double-process it. Added before the panel is dispatched, removed when the PR is done, always, including on failure.
- `reviewer:parked` — terminal. Excluded from selection until a human removes it.

They are mutually exclusive; adding one removes the other:
```bash
gh pr edit "$n" --repo "$target_repo" \
  --add-label reviewer:parked --remove-label reviewer:working
```

Idempotent by construction: every pass sets labels to the target state and posts at most one review per PR per head SHA, so re-running never duplicates.

**`## Under /loop`** — each invocation is one full pass. A PR whose CI was pending, whose author has since pushed, or that was skipped for throughput resurfaces next pass. Parked PRs stay parked until a human clears the label. The unchanged-SHA skip in step 4 means an idle queue costs one `gh pr list` plus one reviews call per candidate and dispatches nothing.

**`## Never do`** — the seven rules from the spec, verbatim:
- Never merge a PR the verdict did not approve.
- Never merge over an unresolved human objection.
- Never merge a PR above `max_merge_lines`, or review one above `max_review_lines`.
- Never request changes without at least one blocking finding carrying a stated consequence.
- Never touch a PR authored by `renovate_authors`, or a draft.
- Never modify the user's working tree, branches, or index; worktrees are detached and removed.
- Never post more than one review per PR per round.

Plus two the orchestrator specifically owns:
- Never run tests, fix code, or push to a contributor's branch. Someone owns this PR; you review it.
- Never review a diff yourself or merge yourself — those belong to the agents.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash /tmp/t8-check.sh; echo "exit=$?"`
Expected: exit 0.

Run: `bash scripts/check-plugin.sh plugins/devtools`
Expected: **`check-plugin: OK`** — this is the first point at which all three agents are referenced and every doctrine path resolves. If it still fails, a dispatch name or a `references/` path is misspelled. That is exactly the bug class Task 1 exists to catch: fix the spelling, do not weaken the checker.

Also re-run every earlier task's check to confirm nothing regressed:
```bash
for t in /tmp/t2-check.sh /tmp/t3-check.sh /tmp/t4-check.sh /tmp/t5-check.sh \
         /tmp/t6-check.sh /tmp/t7-check.sh /tmp/t8-check.sh; do
  bash "$t" || echo "REGRESSED: $t"
done
```
Expected: no `REGRESSED` line.

- [ ] **Step 6: Commit**

```bash
git add plugins/devtools/skills/pr-reviewer/SKILL.md
git commit -m "$(cat <<'EOF'
feat(pr-reviewer): add orchestrator routing — panel, verdict, delivery, merge

Completes the skill: parallel lens dispatch, adjudication, one-review-per-round
delivery with the self-review downgrade and 422 fallback, merge gating, and the
label-plus-reviews-API state model.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DjogvputUg2dezHUDmGJvV
EOF
)"
```

---

### Task 9: Plugin registration and documentation

Without this the skill exists but is not discoverable, and nobody knows how to configure it.

**Files:**
- Modify: `plugins/devtools/.claude-plugin/plugin.json`
- Modify: `plugins/devtools/README.md`
- Modify: `.claude-plugin/marketplace.json`

**Interfaces:**
- Consumes: everything built so far.
- Produces: a discoverable, documented plugin.

- [ ] **Step 1: Write the failing test**

Save as `/tmp/t9-check.sh`:

```bash
#!/usr/bin/env bash
set -u
fail=0
P=plugins/devtools/.claude-plugin/plugin.json
R=plugins/devtools/README.md
M=.claude-plugin/marketplace.json

jq -e . "$P" >/dev/null 2>&1 || { echo "FAIL: $P invalid JSON"; fail=1; }
jq -e . "$M" >/dev/null 2>&1 || { echo "FAIL: $M invalid JSON"; fail=1; }

v=$(jq -r .version "$P" 2>/dev/null)
[ "$v" = "0.2.0" ] || { echo "FAIL: version is '$v', expected 0.2.0"; fail=1; }
jq -e '.description | test("pr-reviewer")' "$P" >/dev/null 2>&1 \
  || { echo "FAIL: plugin.json description does not mention pr-reviewer"; fail=1; }
jq -e '.keywords | index("code-review")' "$P" >/dev/null 2>&1 \
  || { echo "FAIL: plugin.json missing 'code-review' keyword"; fail=1; }
jq -e '.plugins[] | select(.name=="devtools") | .description | test("pr-reviewer")' \
  "$M" >/dev/null 2>&1 || { echo "FAIL: marketplace devtools description stale"; fail=1; }

for s in '## pr-reviewer' 'renovator' 'reviewer:parked' 'max_merge_lines' \
         'github-app-identity' 'o/r#42'; do
  grep -qF -- "$s" "$R" || { echo "FAIL: README missing: $s"; fail=1; }
done
exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/t9-check.sh; echo "exit=$?"`
Expected: exit 1 — version still `0.1.0`, no `pr-reviewer` anywhere.

- [ ] **Step 3: Update the plugin manifest**

Rewrite `plugins/devtools/.claude-plugin/plugin.json`:

```json
{
  "name": "devtools",
  "description": "Developer-workflow automation for Claude Code. 'renovator' autonomously drains a repository's open Renovate dependency PRs. 'pr-reviewer' reviews everything else — a three-lens agent panel reviews each open PR's diff for requirements-conformity, correctness, and craft, posts one GitHub review with inline comments, then either requests changes with concrete recommendations or approves and merges.",
  "version": "0.2.0",
  "author": { "name": "Steve Bennett" },
  "license": "MIT",
  "keywords": ["devtools", "renovate", "dependencies", "automation", "github", "agents", "code-review", "pull-requests"]
}
```

- [ ] **Step 4: Update the marketplace description**

In `.claude-plugin/marketplace.json`, replace the `devtools` entry's `description` with:

```
Developer-workflow automation. 'renovator' merges provably-safe green patch/minor Renovate dependency PRs and parks the rest; 'pr-reviewer' runs a three-lens agent panel over every other open PR and either requests changes with concrete recommendations or approves and merges.
```

Leave `name` and `source` untouched.

- [ ] **Step 5: Add the README section**

Append a `## pr-reviewer` section to `plugins/devtools/README.md`, matching the existing `## renovator` section's tone and depth, containing:

1. **What it does** — one paragraph. Include the sentence: sibling to `renovator`, not a replacement — `renovator` owns dependency PRs, `pr-reviewer` owns everything else, and the two never touch the same PR.
2. **Usage** — the seven-row invocation table (no argument; `42`; PR URL; `o/r#42`; repo URL; ssh URL; `o/r`), and the note that a repo URL target is cloned bloblessly into a scratch directory and the working directory's repo is never touched.
3. **The three lenses** — the table from the spec, and the sentence that most craft findings are advisory by design.
4. **How it decides** — `request-changes` requires at least one surviving blocking finding with a stated consequence; otherwise it approves, and advisory findings still go out as inline comments on the approving review.
5. **Merge gates** — CI green and cleanly mergeable; no unresolved human review threads; within `max_merge_lines`; merge permission held. Plus: `pr-merger` re-verifies all of them live, so two independent agreements gate every unattended merge.
6. **Self-review caveat**, stated plainly: GitHub rejects `APPROVE` and `REQUEST_CHANGES` on your own PR, so on a PR you authored the review posts as a `COMMENT` and the verdict travels in a hidden marker. Installing this repo's `github-app-identity` plugin gives `gh` a distinct App identity, which restores real approve and request-changes records.
7. **Requirements** — `gh` authenticated, `jq`, `git`.
8. **Configuration** — the twelve-row knob table, and the `.claude/pr-reviewer.json` path with a note that it is read from the *target* repo.
9. **PR annotations** — `reviewer:working` (momentary lock) and `reviewer:parked` (terminal; clear it by hand to re-enable review).

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash /tmp/t9-check.sh; echo "exit=$?"`
Expected: exit 0.

Run: `for p in plugins/*/; do bash scripts/check-plugin.sh "$p" || break; done`
Expected: `check-plugin: OK` for every plugin.

- [ ] **Step 7: Commit**

```bash
git add plugins/devtools/.claude-plugin/plugin.json \
        plugins/devtools/README.md .claude-plugin/marketplace.json
git commit -m "$(cat <<'EOF'
docs(pr-reviewer): register the skill and document it

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DjogvputUg2dezHUDmGJvV
EOF
)"
```

---

### Task 10: Live acceptance

Everything so far is structural. This is the only task that proves the skill works, and the only one that touches real PRs.

**Files:**
- Modify: `docs/superpowers/specs/2026-07-26-pr-reviewer-design.md` (mark validated scenarios)

**Interfaces:**
- Consumes: the installed plugin.
- Produces: a validated skill, or a defect list.

**Prerequisite:** install the plugin locally — `/plugin marketplace add /Users/stevebennett/Code/nyx-claude` then `/plugin install devtools@nyx-claude` (or reload if already installed) — and confirm `pr-reviewer` appears in the skills list.

- [ ] **Step 1: Run the read-only scenarios first**

These cannot mutate anything, so run them before granting the skill a real merge. Use a scratch repo with two or three open PRs.

| # | Scenario | Expected |
|---|---|---|
| 3 | Remote by PR URL — invoke with `https://github.com/<o>/<r>/pull/<n>` from an unrelated directory | Reviews that PR; clones bloblessly into the scratchpad; `git status` in the unrelated directory is unchanged |
| 4 | Remote by repo URL | Full queue pass on a repo not checked out locally |
| 10 | No merge permission — target a public repo you cannot push to | Reviews cleanly, reports `no-permission`, does not error |
| 13 | Idempotence — run twice with no intervening push | Second run posts no review and changes no labels |

For scenario 3, verify the working directory is untouched: `git -C <unrelated-repo> status --porcelain` must be empty and `git -C <unrelated-repo> worktree list` must show only the main worktree.

- [ ] **Step 2: Run the mutating scenarios**

Each of these posts a review or merges. Run them deliberately, on a scratch repo, one at a time.

| # | Scenario | Expected |
|---|---|---|
| 1 | Local queue pass with several open PRs | Renovate PRs and drafts untouched; at most `max_reviews_per_pass` reviewed; report matches GitHub |
| 2 | Single PR by number, on one already labelled `reviewer:parked` | Reviews it anyway |
| 5 | Self-review downgrade — a PR you authored | Review posts as `COMMENT`; hidden marker carries the verdict; next pass reads it back |
| 6 | Approve and merge — a small, green, well-described PR | Approving review recorded **first**, then merged |
| 7 | Request changes, then re-review — a PR with a real defect | Numbered recommendations; after a fix is pushed, next pass re-reviews, confirms the blocker resolved, does **not** re-raise it, and merges |
| 8 | Rounds exhausted | Parked after `max_rounds`, not looped |
| 9 | Both size ceilings | Over `max_merge_lines`: reviewed and approved, not merged. Over `max_review_lines`: parked unreviewed |
| 11 | Unresolved human thread | Approving verdict does not merge while a colleague's unresolved thread is open |
| 12 | Bad inline anchor | Review falls back to body-only with findings inlined as text |

Scenario 12 is the hardest to provoke naturally. Force it by temporarily setting `max_review_lines` high and reviewing a PR with a large rename or a mode-only change, where a lens is most likely to cite a line outside the diff. If it will not reproduce, note it as unverified rather than claiming it passed.

- [ ] **Step 3: Judge the review quality, not just the mechanics**

Mechanics passing does not mean the skill is useful. On the PRs from scenarios 1, 6, and 7, read the reviews as their author would and answer:

- Did any blocking finding lack a real consequence? (Etiquette rule 5 failing → tighten the lens brief's Blocking bar.)
- Did the panel produce duplicate findings the adjudicator failed to merge? (→ tighten `verdict.md`'s dedup step.)
- Did any lens stray outside its territory? (→ tighten that brief's `## Not your lens`.)
- Did it flag anything a linter owns? (→ etiquette rule 3 failing.)
- Would you have merged what it merged, and reworked what it blocked?

The last question is the real gate. A skill that passes all thirteen scenarios but merges code you would have rejected is not finished.

- [ ] **Step 4: Record results and file defects**

In the spec's `## Validation` section, mark each scenario `verified`, `failed`, or `unverified`, with a one-line note for anything not verified. Anything that failed becomes a defect to fix before the branch merges — fix it in the file that owns the behaviour, then re-run that scenario and `bash scripts/check-plugin.sh plugins/devtools`.

Do not mark a scenario verified you did not actually run.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-07-26-pr-reviewer-design.md
git commit -m "$(cat <<'EOF'
docs(pr-reviewer): record live acceptance results

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DjogvputUg2dezHUDmGJvV
EOF
)"
```

- [ ] **Step 6: Open the PR**

```bash
git push -u origin feature/pr-reviewer-skill
gh pr create --title "feat(devtools): add pr-reviewer skill" --body "$(cat <<'EOF'
Adds `pr-reviewer` to the devtools plugin: an autonomous PR reviewer that runs a
three-lens agent panel over open pull requests and either requests changes with
concrete recommendations or approves and merges.

Design: `docs/superpowers/specs/2026-07-26-pr-reviewer-design.md`
Plan: `docs/superpowers/plans/2026-07-26-pr-reviewer.md`

Also adds `scripts/check-plugin.sh`, a structural checker for any plugin
directory, and documents it in CLAUDE.md.

Acceptance results are recorded in the spec's Validation section.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01DjogvputUg2dezHUDmGJvV
EOF
)"
```

---

## Self-review notes

**Spec coverage.** Every spec section maps to a task: Purpose/Scope → Task 7 header; Invocation → Tasks 2 and 7; Architecture → Tasks 4–8; pass steps 1–6 → Task 7; steps 7–11 → Task 8; Configuration → Tasks 2 and 9; the three lenses → Task 3; adjudication → Task 5; merge gates → Tasks 6 and 8; State model, Under /loop, Never do → Task 8; Files → all; Portability → Global Constraints; Validation → Task 10.

**Two deliberate deviations from the spec, both flagged where they occur:**
1. `scripts/check-plugin.sh` and the `CLAUDE.md` update (Task 1) are new tooling the spec does not call for. Rationale is in Task 1's preamble: without a gate, the likeliest bugs in a markdown-defined plugin are silent.
2. `pr-merger` returns an extra reason, `too-large` (Task 6). The spec lists six; the merger re-verifies every other gate independently, and the size ceiling should not be the exception.

**Naming consistency, checked across tasks:** `target_repo`, `target_pr`, `self_login`, `can_merge`, `head_sha`, `round`, `prior_recommendations`, `requirements`, `pr_body`, `size`, `workdir`, `worktree`, `diff_path`, `shared_brief_path`, `lens_brief_path`, `verdict_doctrine_path`, `blocker_count`, `addressed_prior`. Lens names `requirements`/`correctness`/`craft`; verdicts `approve`/`request-changes`/`park`; severities `blocking`/`advisory`; merger reasons `merged`/`behind`/`conflict`/`blocked`/`not-green`/`threads-open`/`too-large`. Labels `reviewer:working`/`reviewer:parked`.

**Expected intermediate failures.** `check-plugin.sh` fails in Tasks 4–7 because rule 6 requires every agent to be referenced by a `SKILL.md` that does not exist until Task 7 and does not name the agents until Task 8. Each of those tasks says so explicitly. Task 8 step 5 is the first clean run — if it is not clean there, a name is misspelled.
