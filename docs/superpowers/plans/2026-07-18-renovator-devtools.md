# renovator (devtools plugin) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v1 of a new `devtools` plugin whose `renovator` skill autonomously merges provably-safe green patch/minor Renovate PRs and parks the rest with PR state annotations.

**Architecture:** A thin orchestrator **skill** (`renovator`) classifies each open Renovate PR (bump type × CI status) and dispatches a cheap **haiku agent** (`renovate-merger`) — one at a time — to independently re-verify and squash-merge each green patch/minor PR. Major versions and red-CI PRs are parked (labels + a sticky comment). The orchestrator's context holds only the PR list and one-line verdicts; per-PR `gh` noise stays inside the throwaway agent context.

**Tech Stack:** Claude Code plugin components (Markdown skills/agents + JSON manifests). Runtime deps: `gh` CLI (authenticated) and `jq`. No application code, no test runner.

## Testing note (read before Task 1)

This repo has **no build/test tooling** — plugin components are Markdown/JSON, validated by static checks and by installing/exercising the plugin (CLAUDE.md). The TDD cycle is adapted accordingly, and this adaptation is faithful to red→green:

- **"Write the failing test"** = write a concrete **validation command** (e.g. `jq -e ...`, a `grep` for a required rule) that asserts the deliverable's key property.
- **"Run to verify it fails"** = run it *before* creating the file → it fails (file absent / property missing).
- **"Implement"** = create the file with the shown content.
- **"Run to verify it passes"** = re-run the same command → it passes.
- Task 5 adds a **live exercise** against a real repo, which is the only end-to-end check available.

## Global Constraints

Copied verbatim from the spec and CLAUDE.md — every task's requirements implicitly include these:

- **Portability:** any shell shown (in skill/agent bodies or validation) must run on **bash 3.2 (macOS default) and Linux**. No GNU-only constructs: no `grep -oP`/`\K`, no `find -printf`, no `date -Iseconds`. Use `date -u +%Y-%m-%dT%H:%M:%SZ`, `sed -nE`, `ls -t`.
- **Runtime deps:** `gh` (authenticated) and `jq` are required. Do not introduce new hard deps.
- **Registration:** every plugin under `plugins/` MUST be registered in `.claude-plugin/marketplace.json` or Claude Code will not discover it.
- **Renovate identity is configurable:** never hardcode `renovate[bot]`. Use the `renovate_authors` list (default `["renovate[bot]"]`) everywhere an author is matched — both the orchestrator's filter and the merger's backstop.
- **Conservative bias:** anything not provably a safe, green patch/minor is parked, never merged. Ambiguous bump ⇒ `major`. Zero checks (when `require_checks`) ⇒ skip.
- **Merge default:** `squash`, via the `merge_method` knob.
- **Serialize merges:** at most `max_merges_per_pass` (default 1) merge per pass; drain the rest via active rebase.
- **RTK proxy:** this machine rewrites `cat`/`grep`/`find`/`git`; if an `rtk`-wrapped command rejects a flag, fall back to `rtk proxy <command>`.

## File structure

| File | Responsibility |
|---|---|
| `plugins/devtools/.claude-plugin/plugin.json` | Plugin manifest (name, version, description, author) |
| `.claude-plugin/marketplace.json` (modify) | Register `devtools` for discovery |
| `plugins/devtools/agents/renovate-merger.md` | haiku agent: re-verify + squash-merge ONE PR |
| `plugins/devtools/skills/renovator/references/classification.md` | Bump-type × CI → bucket rules + worked examples |
| `plugins/devtools/skills/renovator/SKILL.md` | Orchestrator: preflight, fetch, classify, dispatch, rebase-drain, park, annotate, report |
| `plugins/devtools/README.md` | Plugin overview + `.claude/renovator.json` config example |

Build order: manifest/registration first (makes the plugin discoverable), then the agent (its input contract is what the orchestrator dispatches), then the classification reference (consumed by the orchestrator), then the orchestrator, then README + live exercise.

---

### Task 1: Plugin manifest + marketplace registration

**Files:**
- Create: `plugins/devtools/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json` (add one entry to `plugins[]`)

**Interfaces:**
- Produces: a discoverable plugin named `devtools` at `./plugins/devtools`. Later tasks add components under it that are auto-discovered by directory convention.

- [ ] **Step 1: Write the failing validation**

Run this — it asserts the manifest exists and is valid with the right name. It MUST fail now (file absent):

```bash
jq -e '.name == "devtools" and .version and .description' plugins/devtools/.claude-plugin/plugin.json
```

Expected: FAIL — `jq: error ... No such file or directory`.

- [ ] **Step 2: Create the manifest**

Create `plugins/devtools/.claude-plugin/plugin.json`:

```json
{
  "name": "devtools",
  "description": "Developer-workflow automation for Claude Code. Its first skill, 'renovator', autonomously drains a repository's open Renovate dependency PRs — merging provably-safe green patch/minor updates through a cheap haiku agent and parking major-version and red-CI updates with PR state annotations for review.",
  "version": "0.1.0",
  "author": { "name": "Steve Bennett" },
  "license": "MIT",
  "keywords": ["devtools", "renovate", "dependencies", "automation", "github", "agents"]
}
```

- [ ] **Step 3: Verify the manifest passes**

Run the Step 1 command again. Expected: prints `true`, exit 0.

- [ ] **Step 4: Write the failing registration check**

Run — asserts the marketplace lists `devtools` pointing at the right source. MUST fail now:

```bash
jq -e '.plugins[] | select(.name == "devtools") | .source == "./plugins/devtools"' .claude-plugin/marketplace.json
```

Expected: FAIL — no output / exit 1 (entry absent).

- [ ] **Step 5: Register the plugin**

Add this object to the `plugins` array in `.claude-plugin/marketplace.json` (append after the existing `productivity` entry — mind the comma):

```json
    {
      "name": "devtools",
      "source": "./plugins/devtools",
      "description": "Developer-workflow automation. First skill 'renovator' autonomously merges provably-safe green patch/minor Renovate dependency PRs and parks major-version and red-CI updates with PR state annotations."
    }
```

- [ ] **Step 6: Verify registration + whole-file validity**

```bash
jq -e '.plugins[] | select(.name == "devtools") | .source == "./plugins/devtools"' .claude-plugin/marketplace.json && jq empty .claude-plugin/marketplace.json && echo "marketplace OK"
```

Expected: `true` then `marketplace OK` (whole file still valid JSON — a stray comma here breaks discovery of every plugin).

- [ ] **Step 7: Commit**

```bash
git add plugins/devtools/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "feat(devtools): scaffold plugin and register in marketplace"
```

---

### Task 2: `renovate-merger` agent (haiku)

**Files:**
- Create: `plugins/devtools/agents/renovate-merger.md`

**Interfaces:**
- Consumes (from the orchestrator's dispatch): `pr` (number), `bump` (`patch`|`minor`), `renovate_authors` (JSON array), `merge_method` (`squash`|`merge`|`rebase`).
- Produces (return contract the orchestrator reads): a single-line JSON object
  `{ "pr": <n>, "outcome": "merged" | "aborted", "reason": "merged"|"behind"|"conflict"|"not-green"|"bump-mismatch"|"identity" }`.

- [ ] **Step 1: Write the failing validation**

Asserts the agent file exists, is pinned to haiku, and grants only `Bash, Read`. MUST fail now:

```bash
test -f plugins/devtools/agents/renovate-merger.md \
  && grep -qx 'model: haiku' plugins/devtools/agents/renovate-merger.md \
  && grep -qx 'tools: Bash, Read' plugins/devtools/agents/renovate-merger.md \
  && echo "frontmatter OK"
```

Expected: FAIL (file absent, no output).

- [ ] **Step 2: Create the agent**

Create `plugins/devtools/agents/renovate-merger.md`:

```markdown
---
name: renovate-merger
description: Independently re-verifies that one Renovate patch/minor PR is still a safe, green, cleanly-mergeable bot PR, then squash-merges it. Mechanical gh-only work — never edits files, never fixes CI, never touches any PR but the one it is given. Dispatched one-at-a-time by the renovator skill.
model: haiku
tools: Bash, Read
---

# renovate-merger — verify & merge one Renovate PR

You merge exactly one Renovate dependency PR, or you abort. You never edit files, never fix CI, never touch any PR but the one you were given. Your caller (the `renovator` skill) already classified this PR as a green patch/minor candidate — you do NOT trust that. You re-verify everything live, because you are the last gate before an **unattended** merge. Two independent classifications (the orchestrator's and yours) must agree, or nothing merges.

## Input (from your dispatch)
- `pr` — the PR number.
- `bump` — the expected bump type, `patch` or `minor`.
- `renovate_authors` — JSON array of accepted author logins (default `["renovate[bot]"]`).
- `merge_method` — `squash` | `merge` | `rebase` (default `squash`).

## Do
1. Re-fetch the PR live:
   `gh pr view <pr> --json number,author,title,mergeStateStatus,statusCheckRollup,baseRefName`
2. Independently re-verify ALL of the following. If ANY fails, abort — do NOT merge:
   - **identity** — `author.login` is a member of `renovate_authors`. Else abort `identity`.
   - **bump** — re-parse the version transition from `title`; the bump is still `patch` or `minor` and equals the `bump` you were given. If the old and new versions cannot both be extracted and compared with confidence, that is a mismatch. Else abort `bump-mismatch`.
   - **green** — every entry in `statusCheckRollup` is `SUCCESS` (none `FAILURE`/`ERROR`/`CANCELLED`/`PENDING`/`IN_PROGRESS`). Else abort `not-green`.
   - **mergeable** — `mergeStateStatus` is `CLEAN`. If `BEHIND` abort `behind`; if `DIRTY` abort `conflict`; anything else (`BLOCKED`, `UNKNOWN`, …) abort `not-green`.
3. Merge: `gh pr merge <pr> --<merge_method> --delete-branch`.

## Judgment rules
- A non-zero exit from `gh pr merge` is a failure: return `aborted` with the closest reason (`conflict` if the merge reports a conflict, else `not-green`). NEVER report `merged` for a merge that did not complete.
- Never re-run a red or pending check hoping it turns green — report the state you observed.
- You verify and merge; you never decide policy. When anything is ambiguous, abort — parking is safe, a wrong unattended merge is not.
- Do not comment on, label, or rebase the PR — the orchestrator owns all annotation. Your job ends at merge-or-abort.

## Return (exactly one line of JSON — no prose)
`{ "pr": <n>, "outcome": "merged" | "aborted", "reason": "merged" | "behind" | "conflict" | "not-green" | "bump-mismatch" | "identity" }`
```

- [ ] **Step 3: Verify frontmatter passes**

Re-run the Step 1 command. Expected: `frontmatter OK`.

- [ ] **Step 4: Verify the safety checks and return contract are present**

```bash
grep -q 'abort `identity`' plugins/devtools/agents/renovate-merger.md \
  && grep -q 'abort `bump-mismatch`' plugins/devtools/agents/renovate-merger.md \
  && grep -q 'abort `behind`' plugins/devtools/agents/renovate-merger.md \
  && grep -q 'abort `conflict`' plugins/devtools/agents/renovate-merger.md \
  && grep -q 'delete-branch' plugins/devtools/agents/renovate-merger.md \
  && echo "checks OK"
```

Expected: `checks OK` — all four independent re-verification aborts and the merge command are documented.

- [ ] **Step 5: Commit**

```bash
git add plugins/devtools/agents/renovate-merger.md
git commit -m "feat(devtools): add renovate-merger haiku agent"
```

---

### Task 3: Classification reference

**Files:**
- Create: `plugins/devtools/skills/renovator/references/classification.md`

**Interfaces:**
- Produces: the canonical bucket definitions `GREEN_SAFE`, `MAJOR`, `RED`, `PENDING` and the rules mapping a PR to one. The orchestrator (Task 4) points here instead of restating the rules.

- [ ] **Step 1: Write the failing validation**

Asserts the reference exists and defines all four buckets. MUST fail now:

```bash
f=plugins/devtools/skills/renovator/references/classification.md
test -f "$f" && for b in GREEN_SAFE MAJOR RED PENDING; do grep -q "$b" "$f" || { echo "missing $b"; break; }; done && echo "buckets OK"
```

Expected: FAIL (file absent).

- [ ] **Step 2: Create the reference**

Create `plugins/devtools/skills/renovator/references/classification.md`:

```markdown
# Renovate PR classification

`renovator` sorts each open Renovate PR into ONE bucket from two axes — **bump type** and **CI status**.

## Bump type — from the PR title

Renovate titles are structured. Extract the old and new versions and compare them as semver `MAJOR.MINOR.PATCH`:

- `MAJOR` differs → **major**
- `MAJOR` equal, `MINOR` differs → **minor**
- `MAJOR` and `MINOR` equal, `PATCH` differs → **patch**

**Ambiguity rule (conservative):** if the old and new versions cannot BOTH be extracted and compared with confidence — digests, pinned SHAs, version ranges, non-semver tags, or a grouped PR whose members bump differently — classify as **major** (the park bucket). Never guess "safe".

**Grouped PRs** (several deps in one PR): if ANY member is major or unparseable, the whole PR is **major**.

When the title names only the new version, read the old version from the dependency's current entry in the manifest/lockfile on the base branch. If that cannot be read confidently, treat as ambiguous → **major**.

### Worked examples
| Title | old → new | bump |
|---|---|---|
| `Update dependency lodash to v4.17.21` | 4.17.20 → 4.17.21 (old from lockfile) | patch |
| `chore(deps): update react to 18.3.0` | 18.2.0 → 18.3.0 | minor |
| `Update dependency next to v15` | 14.2.0 → 15.0.0 | major |
| `fix(deps): update dependency axios from 1.6.2 to 1.6.8` | 1.6.2 → 1.6.8 | patch |
| `Update actions/checkout digest to a1b2c3d` | digest, no semver | major (ambiguous) |
| `Update dependency foo (major)` grouped with `bar (patch)` | mixed | major |

## CI status — from the check rollup
- every check `SUCCESS` → **green**
- any `FAILURE` / `ERROR` / `CANCELLED` → **red**
- any `PENDING` / `IN_PROGRESS`, OR zero checks when `require_checks` is true → **pending**

## Bucket = f(bump, CI)
|  | green | red | pending |
|---|---|---|---|
| **patch / minor** | `GREEN_SAFE` | `RED` | `PENDING` |
| **major / ambiguous** | `MAJOR` | `MAJOR` | `MAJOR` |

Bucket → action:
- `GREEN_SAFE` → dispatch `renovate-merger` (subject to `max_merges_per_pass`).
- `MAJOR` → park (v1) / dispatch major-upgrader (v2).
- `RED` → park (v1) / dispatch ci-fixer (v2).
- `PENDING` → skip this pass; re-evaluated next pass.
```

- [ ] **Step 3: Verify buckets present**

Re-run the Step 1 command. Expected: `buckets OK`.

- [ ] **Step 4: Verify the conservative ambiguity rule is stated**

```bash
grep -qi 'ambiguity rule' plugins/devtools/skills/renovator/references/classification.md \
  && grep -qi 'Never guess' plugins/devtools/skills/renovator/references/classification.md \
  && echo "conservative rule OK"
```

Expected: `conservative rule OK`.

- [ ] **Step 5: Commit**

```bash
git add plugins/devtools/skills/renovator/references/classification.md
git commit -m "docs(devtools): add renovator PR classification reference"
```

---

### Task 4: `renovator` orchestrator skill

**Files:**
- Create: `plugins/devtools/skills/renovator/SKILL.md`

**Interfaces:**
- Consumes: the classification rules in `references/classification.md`; dispatches `renovate-merger` with `{ pr, bump, renovate_authors, merge_method }` and reads back its `{ pr, outcome, reason }`.
- Produces: the user-facing `/renovator` skill and the per-pass behavior (preflight → fetch → classify → merge → rebase-drain → park → annotate → report).

- [ ] **Step 1: Write the failing validation**

Asserts the skill exists with a valid `name` in frontmatter. MUST fail now:

```bash
test -f plugins/devtools/skills/renovator/SKILL.md \
  && grep -qx 'name: renovator' plugins/devtools/skills/renovator/SKILL.md \
  && echo "skill frontmatter OK"
```

Expected: FAIL (file absent).

- [ ] **Step 2: Create the skill**

Create `plugins/devtools/skills/renovator/SKILL.md`:

```markdown
---
name: renovator
description: Autonomously drain a repository's open Renovate dependency PRs — merge the provably-safe green patch/minor ones and park the rest with state annotations. Each invocation is one full pass; safe to run under /loop. Dispatches a haiku merger agent per merge so this orchestrator's context stays flat regardless of PR count. Use when asked to process, merge, or triage Renovate dependency update PRs.
---

# renovator — drain the Renovate PR queue

You are the coordinator. You classify each open Renovate PR and dispatch work; you NEVER merge or edit a branch yourself — the `renovate-merger` agent performs merges in its own isolated context. Keep your context lean: hold only the PR list and one-line verdicts, not per-PR `gh` output.

**v1 scope:** auto-merge green patch/minor PRs; PARK everything else (major versions, red CI). The major-upgrade and red-CI fix-loops are a later phase — do not attempt them.

Runs fully autonomously, including under `/loop`. The human's window into a pass is the after-action report (step 8) plus the per-PR state annotations.

## Configuration
Read `.claude/renovator.json` from the repo root if it exists; otherwise use these defaults. Unknown keys are ignored; missing keys fall back to the default.

| knob | default | meaning |
|---|---|---|
| `renovate_authors` | `["renovate[bot]"]` | author logins that count as Renovate (override for self-hosted / on-prem Renovate) |
| `merge_method` | `"squash"` | `gh pr merge` method |
| `require_checks` | `true` | a PR with zero checks is skipped, never merged |
| `max_merges_per_pass` | `1` | merges performed per pass (serialize-and-rebase throttle) |

Read it with, e.g.:
`jq -r '.renovate_authors // ["renovate[bot]"]' .claude/renovator.json 2>/dev/null` (fall back to defaults if the file or key is absent).

## Pass procedure

### 1. Preflight
- Confirm `gh auth status` succeeds and you are in a git repo with an `origin` remote (`git remote get-url origin`). If either fails, STOP and report exactly what is missing — do nothing else.
- Ensure the three lifecycle labels exist (idempotent; `--force` updates an existing label):
  - `gh label create renovator:working --color FBCA04 --description "renovator is processing this PR" --force`
  - `gh label create renovator:skipped --color EDEDED --description "renovator skipped this PR; will retry" --force`
  - `gh label create renovator:parked --color D93F0B --description "renovator parked this PR for review / v2" --force`

### 2. Fetch candidate PRs
- `gh pr list --state open --limit 100 --json number,title,author,headRefName,mergeStateStatus,statusCheckRollup,labels`
- Keep only PRs whose `author.login` is a member of `renovate_authors`. These are your candidates.

### 3. Skip locked PRs
- Any candidate already carrying the `renovator:working` label is owned by another run/agent — skip it this pass (do not touch it).

### 4. Classify
- Assign each remaining candidate a bucket per `references/classification.md` (bump type × CI status): `GREEN_SAFE`, `MAJOR`, `RED`, or `PENDING`. Record the bump type and version transition for the report and annotation.

### 5. Merge green candidates (serialized)
Process `GREEN_SAFE` PRs, performing at most `max_merges_per_pass` merges this pass (default 1), one at a time — never concurrently (siblings share lockfiles):
- Set state → working: add `renovator:working`, remove any other `renovator:*` label, and upsert the sticky comment with state `working` (see State annotation).
- Dispatch a `renovate-merger` subagent, passing `{ pr, bump, renovate_authors, merge_method }`.
- On return, remove `renovator:working`, then:
  - `outcome: merged` → upsert the sticky comment's final line "merged by renovator"; the PR closes on merge.
  - `outcome: aborted`, `reason: behind` or `not-green` → set `renovator:skipped`, upsert comment with the reason (transient — will retry).
  - `outcome: aborted`, `reason: conflict` → set `renovator:parked`, upsert comment "merge conflict — needs manual resolution".
  - `outcome: aborted`, `reason: bump-mismatch` or `identity` → set `renovator:parked`, upsert comment with the reason (the merger disagreed with classification — a human should look).

### 6. Drain the rest (active rebase)
- After this pass's merge lands, for every remaining `GREEN_SAFE` candidate NOT merged this pass: run `gh pr update-branch <n>` so it rebases onto the new base and CI re-runs. Set `renovator:skipped` and upsert the comment (state `skipped`, reason "rebasing after sibling merge"). They are re-evaluated next pass.
- If no merge happened this pass (nothing was `GREEN_SAFE`), skip this step.

### 7. Park the rest
- `MAJOR` → set `renovator:parked`, upsert comment: bucket `major`, the version transition, reason "major version — needs manual upgrade (renovator v2 will automate this)".
- `RED` → set `renovator:parked`, upsert comment: bucket `red`, reason "CI failing — needs manual fix (renovator v2 will automate this)".
- `PENDING` → set `renovator:skipped`, upsert comment: reason "CI in progress — will retry".

### 8. Report
Print a compact table — one row per candidate: `PR # | title | bump | bucket | outcome` (outcome ∈ merged / parked / skipped / rebasing / locked). This is the human's after-action view of the pass.

## State annotation

Two layers per PR:

- **Labels** — mutually exclusive: exactly one of `renovator:working` / `renovator:skipped` / `renovator:parked` at a time. Before adding one, remove the others:
  `gh pr edit <n> --add-label renovator:parked --remove-label renovator:working --remove-label renovator:skipped`
- **Sticky comment** — exactly ONE renovator comment per PR, found by the hidden marker `<!-- renovator-state -->` on its first line. Upsert it:
  1. Find it: `gh pr view <n> --json comments --jq '.comments[] | select(.body | startswith("<!-- renovator-state -->")) | .url'` (empty ⇒ none yet).
  2. If none, create: `gh pr comment <n> --body "<body>"`.
  3. If one exists, edit it in place via the REST API using its id (derive the numeric id from the comment url, then `gh api -X PATCH repos/{owner}/{repo}/issues/comments/{id} -f body="<body>"`).
  Never post a second renovator comment.

  Comment `<body>` template (first line is the marker):
  ```
  <!-- renovator-state -->
  **renovator** · state: `<working|skipped|parked>` · <reason>
  - update: `<dep>` <old> → <new> (<bump>)
  - CI: <last conclusion>
  - updated: <UTC timestamp>
  ```
  Timestamp via `date -u +%Y-%m-%dT%H:%M:%SZ` (portable; do NOT use `date -Iseconds`).

- **Idempotent by construction:** every pass sets labels to the target state and upserts the one comment, so re-running never duplicates.

## Under /loop
Each invocation is one full pass. `PENDING`/rebasing/parked PRs resolve over subsequent passes as Renovate rebases and CI re-runs. No state persists outside the PRs themselves (labels + the one comment).

## Never do (v1)
- Never merge more than `max_merges_per_pass` per pass.
- Never merge a `MAJOR`, `RED`, or `PENDING` PR.
- Never edit a branch, resolve a conflict, or fix CI — that is v2.
- Never merge a PR whose author is not in `renovate_authors`.
```

- [ ] **Step 3: Verify frontmatter passes**

Re-run the Step 1 command. Expected: `skill frontmatter OK`.

- [ ] **Step 4: Verify the pass procedure covers every required behavior**

```bash
f=plugins/devtools/skills/renovator/SKILL.md
grep -q 'gh auth status' "$f" \
  && grep -q 'renovate_authors' "$f" \
  && grep -q 'max_merges_per_pass' "$f" \
  && grep -q 'update-branch' "$f" \
  && grep -q 'renovator-state' "$f" \
  && grep -q 'date -u +%Y-%m-%dT%H:%M:%SZ' "$f" \
  && grep -q 'renovator:working' "$f" \
  && echo "procedure OK"
```

Expected: `procedure OK` — preflight, config, throttle, active-rebase drain, sticky-comment marker, portable timestamp, and the lock label are all present.

- [ ] **Step 5: Verify no forbidden GNU-ism slipped into shown commands**

```bash
f=plugins/devtools/skills/renovator/SKILL.md
if grep -q 'date -Iseconds' "$f" || grep -q 'grep -oP' "$f"; then echo "FAIL: GNU-ism present"; else echo "portability OK"; fi
```

Expected: `portability OK`.

- [ ] **Step 6: Commit**

```bash
git add plugins/devtools/skills/renovator/SKILL.md
git commit -m "feat(devtools): add renovator orchestrator skill"
```

---

### Task 5: README, config example, and live exercise

**Files:**
- Create: `plugins/devtools/README.md`

**Interfaces:**
- Consumes: everything above (documents the assembled plugin).
- Produces: user-facing docs incl. a `.claude/renovator.json` example; final end-to-end confidence via a live exercise.

- [ ] **Step 1: Write the failing validation**

Asserts the README exists and documents the config file. MUST fail now:

```bash
test -f plugins/devtools/README.md \
  && grep -q '.claude/renovator.json' plugins/devtools/README.md \
  && echo "readme OK"
```

Expected: FAIL (file absent).

- [ ] **Step 2: Create the README**

Create `plugins/devtools/README.md`:

```markdown
# devtools

Developer-workflow automation skills for Claude Code.

## renovator

Autonomously drains a repository's open [Renovate](https://docs.renovatebot.com/) dependency PRs. Each run is one full pass over the queue and is safe to run repeatedly (e.g. under `/loop`).

**v1 behavior:**
- **Merges** patch/minor Renovate PRs whose CI is green and whose branch is cleanly mergeable — one merge per pass, then rebases the rest so the next pass continues.
- **Parks** everything else — major versions, red CI, conflicts — with a label and a sticky status comment for review. (Automating those is planned for v2.)

Every candidate is classified independently twice — once by the orchestrator, once by the `renovate-merger` agent right before it merges — so an unattended merge only ever happens on a PR both agree is a safe, green, bot-authored patch/minor.

### Requirements
- `gh` CLI, authenticated (`gh auth status`).
- `jq`.
- The repo's CI reports status checks to GitHub.

### Usage
Invoke the `renovator` skill from within the target repository (its `origin` remote is the repo acted on).

### Configuration (optional)
Create `.claude/renovator.json` in the repo root to override defaults:

    {
      "renovate_authors": ["renovate[bot]"],
      "merge_method": "squash",
      "require_checks": true,
      "max_merges_per_pass": 1
    }

| knob | default | meaning |
|---|---|---|
| `renovate_authors` | `["renovate[bot]"]` | author logins that count as Renovate. Set this for self-hosted / on-prem Renovate whose bot login differs. |
| `merge_method` | `"squash"` | merge method passed to `gh pr merge`. |
| `require_checks` | `true` | when true, a PR with zero CI checks is skipped rather than merged. |
| `max_merges_per_pass` | `1` | merges performed per pass; the rest are rebased and picked up next pass. |

### PR annotations
`renovator` labels each PR it touches — `renovator:working` (being processed / lock), `renovator:skipped` (transient, will retry), `renovator:parked` (needs review) — and maintains a single sticky status comment per PR.
```

- [ ] **Step 3: Verify README passes + config example is valid JSON**

```bash
grep -q '.claude/renovator.json' plugins/devtools/README.md && echo "readme OK"
# Extract the fenced JSON example and confirm it parses:
sed -n '/^    {$/,/^    }$/p' plugins/devtools/README.md | sed -E 's/^    //' | jq empty && echo "config example valid JSON"
```

Expected: `readme OK` then `config example valid JSON`.

- [ ] **Step 4: Commit**

```bash
git add plugins/devtools/README.md
git commit -m "docs(devtools): add plugin README with renovator config"
```

- [ ] **Step 5: Full static sweep**

Confirm the whole plugin is structurally sound:

```bash
jq empty .claude-plugin/marketplace.json plugins/devtools/.claude-plugin/plugin.json && echo "all JSON valid"
for req in \
  plugins/devtools/.claude-plugin/plugin.json \
  plugins/devtools/agents/renovate-merger.md \
  plugins/devtools/skills/renovator/SKILL.md \
  plugins/devtools/skills/renovator/references/classification.md \
  plugins/devtools/README.md; do
  test -f "$req" && echo "present: $req" || echo "MISSING: $req"
done
```

Expected: `all JSON valid` and `present:` for all five files.

- [ ] **Step 6: Live exercise (end-to-end)**

This is the only true end-to-end check — it needs a real GitHub repo with `gh` authenticated. Perform in a repo that has (or can have) a Renovate PR:

1. Install locally: add this marketplace (`/plugin marketplace add <path-to-this-repo>`) and `/plugin install devtools@nyx-claude`. Confirm the `renovator` skill and `renovate-merger` agent are discovered (`/plugin` list, or that `/renovator` is invocable).
2. **Empty-queue path:** in a repo with no open Renovate PRs, invoke `renovator`. Expected: preflight passes, labels get created, the report table is empty, nothing is merged. Confirms the happy no-op path and label creation.
3. **Merge path (if a green patch/minor Renovate PR exists):** invoke `renovator`. Expected: exactly one PR merges (squash, branch deleted); its sticky comment ends "merged by renovator"; any sibling green PRs are labeled `renovator:skipped` and show as rebasing in the report.
4. **Park path (if a major or red-CI Renovate PR exists):** expected: it is NOT merged; it gets `renovator:parked` and a sticky comment naming the reason and version transition.
5. Re-invoke once more and confirm **idempotence**: no duplicate comments appear, labels reflect current state, and no PR is double-processed.

Record what was observed (which paths were exercisable given available PRs). If only the empty-queue path was available, note that the merge/park paths remain to be exercised against a live Renovate PR.

- [ ] **Step 7: Commit any doc fixes surfaced by the exercise**

```bash
git add -A
git commit -m "docs(devtools): note live-exercise findings for renovator" || echo "nothing to commit"
```

---

## Self-review (completed during authoring)

**Spec coverage** — every spec section maps to a task:
- Plugin & component layout → Task 1 (manifest/registration), files created across Tasks 2–5.
- Configuration knobs → Task 4 (skill reads them) + Task 5 (README documents them).
- Orchestrator control flow (preflight→fetch→lock→classify→dispatch→rebase→park→report) → Task 4.
- Classification (bump × CI, ambiguity→major, no-checks→skip) → Task 3.
- Concurrency & staleness (serialize, live re-verify, active rebase) → Task 4 steps 5–6 + Task 2 merger re-verify.
- `renovate-merger` agent (haiku, independent re-verify, squash, structured return) → Task 2.
- PR state annotation (labels + sticky marker comment, lock, idempotent) → Task 4 State annotation section.
- Model tiering → Task 2 pins haiku; orchestrator inherits session (documented).
- Safety invariants → enforced across Tasks 2 (re-verify, identity backstop) and 4 (serialize, conservative park, lock, report).
- v2 extension points / out of scope → intentionally NOT built; SKILL.md "Never do (v1)" and README state the boundary.

**Placeholder scan:** no TBD/TODO; every file shown in full; every step has a concrete command with expected output.

**Type/name consistency:** dispatch payload `{ pr, bump, renovate_authors, merge_method }` and return `{ pr, outcome, reason }` match between Task 2 (agent) and Task 4 (orchestrator). Label names, the `renovator-state` marker, bucket names (`GREEN_SAFE`/`MAJOR`/`RED`/`PENDING`), and the four config knobs are identical across Tasks 3, 4, and 5.
