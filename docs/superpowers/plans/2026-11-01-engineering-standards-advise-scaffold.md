# engineering-standards advise + scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two skills to `plugins/engineering-standards`. `engineering-standards-advise` checks
a spec's technology decisions against the standards. `engineering-standards-scaffold` builds a
standards-conformant skeleton in an empty or docs-only repo and commits it locally.

**Architecture:** The deterministic parts are two new bash scripts, each with a plain-bash test:
- `scaffold-preflight.sh` decides whether a repo is empty, docs-only or populated, and whether
  it's in a secondary worktree.
- `scaffold-verify.sh` runs the existing check groups and reports the applicable script criteria
  that are not yet met.

The skills are Markdown and do the judgment work. They share one format reference for the spec's
`## Technology decisions` section. Scaffold generates files from a criterion-cited checklist
rather than from templates.

**Tech Stack:** bash 3.2, jq, mikefarah yq v4, the existing `scripts/lib/*`, and Claude Code
skills (Markdown + frontmatter).

**Spec:** `docs/superpowers/specs/2026-11-01-engineering-standards-advise-scaffold-design.md`

## Global Constraints

- All new scripts are bash 3.2 compatible: no `mapfile`/`readarray`/`declare -A`, and no GNU-only
  constructs (`grep -oP`, `find -printf`, `date -Iseconds`). They must run on macOS and Linux.
- No `pipefail` in any script that pipes into `grep -q`. Never let `cat`/`grep` see an empty file
  list. Tests run scripts with `< /dev/null`.
- No apostrophes inside single-quoted jq programs, including in comments.
- No new hard dependencies beyond `jq` and mikefarah `yq` v4. Source `lib/common.sh` and call
  `es_require_deps`.
- Every `.json` under the plugin must parse. Test fixtures are built in temp dirs by the tests,
  not committed.
- `bash scripts/check-plugin.sh plugins/engineering-standards/` must pass.
- kanban-flow and superpowers are not modified.
- Scaffold never pushes, and never creates or overwrites a file that already exists.
- Plugin version `0.1.0` → `0.2.0`.

## Review Focus

1. **Filenames with spaces.** A spec named `docs/My Spec.md` must not break the preflight
   verdict, or appear split into two files. The test is in Task 1.
2. **A repo with files but no commits.** Specs are often untracked when Claude first sees the
   repo. Preflight must count untracked (non-ignored) files, not just `git ls-files`. Test in
   Task 1.
3. **Gitignored clutter.** A local `node_modules/` or `.venv/` that is gitignored must not turn
   a docs-only repo into "populated". Test in Task 1.
4. **Spec in a non-Markdown format at the root.** `spec.pdf` or `notes.txt` at the root is still
   documentation. It must be classed as docs-only, not populated. Test in Task 1.
5. **Verify on untracked output.** The check scripts read only `git ls-files`, so scaffold must
   stage before verifying. `scaffold-verify.sh` must be correct on a repo with staged files and
   no commits. Test in Task 2.

---

### Task 1: `scaffold-preflight.sh`

**Files:**
- Create: `plugins/engineering-standards/scripts/scaffold-preflight.sh`
- Test: `plugins/engineering-standards/scripts/tests/test_scaffold_preflight.sh`

**Interfaces:**
- Consumes: `lib/common.sh` (`es_die`, `es_require_deps`).
- Produces: `scaffold-preflight.sh <repo>`, which prints one JSON object:
  `{"git": bool, "commits": bool, "worktree": "main"|"secondary"|"none", "files": [string], "non_doc_files": [string], "verdict": "empty"|"docs-only"|"populated"}`.
  Exit 0 on success, 2 on usage or a missing dependency. The verdict is data, not an exit code.

**Rules (from the spec):**
- `files`: in a git repo, `git ls-files --cached --others --exclude-standard -z`, so untracked
  files count and gitignored ones don't. Outside git, every file except under `.git/`. Build the
  JSON array NUL-safely (e.g. `tr '\0' '\n'` is unsafe for newlines, so use
  `jq -R -s 'split("\u0000") | map(select(length > 0))'` on the `-z` output).
- A file is documentation when it matches one allowlist, kept in a single place in the script:
  - anything under `docs/`
  - `*.md`, `*.markdown`, `*.txt`, `*.rst`, `*.adoc` or `*.pdf` anywhere
  - `LICENSE*`, `.gitignore`, `.gitattributes` or `.nyx.yml`
  - anything under `.claude/` or `.github/ISSUE_TEMPLATE/`
- `verdict`: `empty` when `files` is empty; `docs-only` when `non_doc_files` is empty; otherwise
  `populated`.
- `worktree`: `none` outside git. `secondary` when `git rev-parse --git-dir` differs from
  `git rev-parse --git-common-dir` (resolved to absolute paths). Otherwise `main`.
- `commits`: `git rev-parse --verify -q HEAD` succeeds.

- [ ] **Step 1: Write the failing test.** Follow `test_tag.sh`: source `helpers.bash`, use a
  `mktemp -d` work dir with a trap, and finish with `finish`. Cases, each built in its own subdir:
  - empty non-git dir → `verdict` `empty`, `git` false, `worktree` `none`
  - `git init -b main` with nothing in it → `empty`, `git` true, `commits` false
  - untracked `docs/spec.md` + `README.md` (no commit) → `docs-only`, and `files` length 2
  - `docs/My Spec.md` → `docs-only`, and `files` contains exactly `"docs/My Spec.md"`
  - gitignored `node_modules/x.js` (with `.gitignore` containing `node_modules/`) plus
    `docs/spec.md` → `docs-only`
  - root `spec.pdf` + `notes.txt` → `docs-only`
  - `go.mod` + `docs/spec.md` → `populated`, and `non_doc_files` == `["go.mod"]`
  - committed docs, then `git worktree add ../wt` → preflight on `wt` gives `worktree`
    `secondary`, and on the original gives `main` with `commits` true
  - missing argument → `assert_exit` 2

  Use `git -c user.name=t -c user.email=t@example.com` for commits, as `test_checks.sh` does.

- [ ] **Step 2: Run it and confirm it fails.**
  Run: `bash plugins/engineering-standards/scripts/tests/test_scaffold_preflight.sh < /dev/null`
  Expected: it fails because `scaffold-preflight.sh` doesn't exist.

- [ ] **Step 3: Implement `scaffold-preflight.sh`** to the rules above. Use the header comment
  style of `tag.sh`/`detect.sh` (usage, output, exit codes). Use `set -eu` (no pipefail) and
  source `lib/common.sh`. Apply the doc allowlist as one jq `test()` regex over the file array.

- [ ] **Step 4: Run the test and confirm it passes.** Same command. Expected:
  `test_scaffold_preflight.sh: all N assertions passed`.

- [ ] **Step 5: Commit.**
  `git add plugins/engineering-standards/scripts/scaffold-preflight.sh plugins/engineering-standards/scripts/tests/test_scaffold_preflight.sh`
  then `git commit -m "feat(engineering-standards): add scaffold preflight script"`.

### Task 2: `scaffold-verify.sh`

**Files:**
- Create: `plugins/engineering-standards/scripts/scaffold-verify.sh`
- Test: `plugins/engineering-standards/scripts/tests/test_scaffold_verify.sh`

**Interfaces:**
- Consumes:
  - `lib/common.sh`: `es_tag_gate`, `ES_RUBRIC`, `ES_LIB_DIR`
  - `lib/applicability.jq`: `criteria($r; $tag)`
  - `checks/group-{1..5}.sh <repo>`, each printing a JSON array of
    `{id, score, evidence, source, unverified}`
- Produces: `scaffold-verify.sh <repo>`, which prints
  `{"met": [id], "gaps": [{"id", "level", "text", "score", "evidence", "unverified"}]}`. It
  covers only criteria that are `method == "script"` and applicable under the tag (category
  applicable, `applies_when` holds, not exempt). `met` means score 2. `gaps` is everything else,
  sorted by level then id. Exit codes match the gate: 0 ok, 2 usage/dependency, 3–5 from
  `es_tag_gate`. It respects `ES_NO_GH`, which passes through to the check scripts.

- [ ] **Step 1: Write the failing test.** Set `export ES_NO_GH=1`. Cases:
  - a dir with no `.nyx.yml` → `assert_exit` 3
  - copy `fixtures/exemplary`, then `git init -b main && git add -A` with **no commit**. Run
    verify:
    - `met` contains `STK-1`, `CI-2`, `BLD-4` and `DPL-2`
    - no `id` in `met` or `gaps` is a judgment criterion (`DOC-1` absent)
    - `STK-2` is in neither list (N/A records are excluded: STK-2 is N/A in the fixture)
  - the same copy with a tag whose `exemptions` contains `{"id":"BLD-4","reason":"x"}` (written
    with `tag.sh write`) → `BLD-4` is in neither list
  - a bare repo containing only a tag (service/kubernetes/postgresql) and staged → `gaps`
    contains `CFG-3` with `level` `"L1"`, and `met` is empty

- [ ] **Step 2: Run it and confirm it fails.**
  Run: `bash plugins/engineering-standards/scripts/tests/test_scaffold_verify.sh < /dev/null`
  Expected: it fails because the script is missing.

- [ ] **Step 3: Implement `scaffold-verify.sh`.**
  1. Gate with `es_tag_gate`.
  2. Run the five groups with `< /dev/null` into one temp file, merged with `jq -s add`.
  3. Join the records against `criteria($r; $tag)` with `jq -L "$ES_LIB_DIR"` (as `plan.sh`
     does), keeping applicable script criteria.
  4. Drop records whose score is `"N/A"`.
  5. Split them into `met` and `gaps`.

  Use `set -eu` and no pipefail. If a group script exits non-zero on a repo with no commits (for
  example `git log` in group 2), fix that group script so it scores the criterion 0 instead of
  failing. Add that case to `test_checks.sh`.

- [ ] **Step 4: Run the test and confirm it passes.** Same command, plus the full suite:
  `for t in plugins/engineering-standards/scripts/tests/test_*.sh; do bash "$t" < /dev/null || echo "FAILED $t"; done`
  Expected: every file reports all assertions passed, and there are no `FAILED` lines.

- [ ] **Step 5: Commit.**
  `git commit -m "feat(engineering-standards): add scaffold verify script"`, with both files.

### Task 3: Decisions-section format and the advise skill

**Files:**
- Create: `plugins/engineering-standards/skills/engineering-standards-advise/references/decisions-format.md`
- Create: `plugins/engineering-standards/skills/engineering-standards-advise/SKILL.md`

**Interfaces:**
- Produces: the `## Technology decisions` section format, which Task 5 consumes:
  - a preface line `Checked against Engineering Standards v<framework_version>.`
  - a table `| Field | Value | Source |`
  - required rows, in this order: `type`, `status`, `backend`, `frontend`, `deployment_target`,
    `database`, `lightweight`
  - then one row per open choice, with `Field` a short kebab-case name (e.g. `web-framework`,
    `migration-tool`)
  - `Source` ∈ `mandated` | `user` | `advisor-suggestion-accepted` | `spec`
  - an optional `### Exemptions` sub-list with lines `- <CRITERION-ID>: <reason>`

  Allowed values:
  - `type`: service | library | cli
  - `status`: active | maintained | archived
  - `backend`: go | python | none, or another language only with matching exemptions
  - `frontend`: none or `typescript (<framework>)`
  - `deployment_target`: fly | cloudflare | kubernetes | none
  - `database`: postgresql | sqlite | d1 | none, or another DB only with matching exemptions
  - `lightweight`: true | false, followed when sqlite/d1 by a one-line answer to each of the
    three DAT conditions

  It also holds a mapping table from these fields to the `.nyx.yml` tag keys, including the rule
  that an out-of-enum database maps to `database: none` and its exemption reason names the actual
  database.

- [ ] **Step 1: Write `decisions-format.md`** with the format above and one complete filled-in
  example: a Go service on Kubernetes with PostgreSQL, `web-framework: chi (advisor-suggestion-accepted)`
  and no exemptions. Also include a second, minimal example with a kept MySQL exemption
  (`DAT-1`), showing its tag mapping.

- [ ] **Step 2: Write `SKILL.md`.** Frontmatter `name: engineering-standards-advise`. No
  `disable-model-invocation`. The `description` must say to use it whenever a spec, design or
  requirements document (including during brainstorming or kanban-flow refine/requirement) is
  written or revised and it chooses or implies languages, frameworks, databases, deployment
  targets, packaging, CI or dependency tooling. It may also be invoked by hand to check an
  existing spec. The body follows the classify skill's shape (intro, then numbered steps, each
  ending with "The step is done when …"). The steps:
  1. **Read the standards.** Read
     `${CLAUDE_PLUGIN_ROOT}/skills/engineering-standards-assess/references/standards.md`
     (sections 2, 3 and the DAT preamble).
  2. **Extract** every technology decision the spec makes or implies, and the ones it still needs
     (every required row in `references/decisions-format.md`).
  3. **Classify** each decision as Mandated, Constrained or Open, using the spec's table and
     examples (Kubernetes → Helm, ArgoCD and no `deploy` recipe; SQLite/D1 → three lightweight
     conditions).
  4. **Raise conflicts.** For each one, name the criterion IDs that would fail, offer compliant
     alternatives, and ask via `AskUserQuestion`: change the spec, or keep it as an exemption (a
     reason is required). Never resolve a conflict silently.
  5. **Ask** the Constrained and Open questions with `AskUserQuestion`. A recommended option goes
     first and is labelled "(Recommended)". When the user hands a choice over, record it as
     `advisor-suggestion-accepted`.
  6. **Record** the section per `references/decisions-format.md`. If no spec file exists yet,
     hold the decisions and write the section when the spec is written. Edit other spec text
     only to resolve a conflict the user agreed to, and never touch REQ id markers.
  7. **Report** the decisions, any exemptions, and that nothing was committed.

  State the scope: it writes only the spec document.

- [ ] **Step 3: Validate.**
  Run: `bash scripts/check-plugin.sh plugins/engineering-standards/`
  Expected: exit 0, and no error mentioning `engineering-standards-advise` or
  `decisions-format.md`.

- [ ] **Step 4: Commit.**
  `git commit -m "feat(engineering-standards): add engineering-standards-advise skill"`.

### Task 4: Scaffold checklist reference

**Files:**
- Create: `plugins/engineering-standards/skills/engineering-standards-scaffold/references/scaffold-checklist.md`

**Interfaces:**
- Produces: a checklist organised by file, consumed by Task 5. Each entry has:
  - **Path**
  - **Applies when**: conditions over `type`, `deployment_target`, `database`, `backend`,
    `frontend`
  - **Satisfies**: criterion IDs
  - **Requirements**: bullet requirements, not literal contents
  - **Stack-neutral**: yes/no. `no` entries are skipped when a stack-changing exemption is kept,
    per the spec's "Kept deviations"

- [ ] **Step 1: Write the checklist.** Cover every bullet in the spec's "What the skeleton
  contains" section, with the criterion IDs the spec gives. That means the entries below.
  - Root and tooling:
    - `justfile`: the recipe set per section 2.1, conditioned on type, target and database
    - `.devcontainer/devcontainer.json`, plus a compose file for PostgreSQL
    - `.gitignore`, `.editorconfig`
    - `.pre-commit-config.yaml`, including gitleaks and a commit-message hook
  - Per language:
    - Go: `go.mod` with `go` + `toolchain`, `cmd/<name>/main.go`, `internal/`,
      `.golangci.yml`, and a lockfile
    - Python: `pyproject.toml` with `requires-python`, `.python-version`, `src/<package>/`,
      ruff and pyright strict config, and `uv.lock`
    - TypeScript: `package.json` with `engines.node`, `.nvmrc`, `.npmrc` with `save-exact=true`,
      `tsconfig.json` with `strict`, linter/formatter config, a lockfile, and `src/`
    - The backend + frontend layout convention: backend at the root, frontend under `web/`
      with its own `src/` (*builder's call*, recorded here)
  - CI:
    - `.github/workflows/ci.yml`
    - Kubernetes chart lint in CI
    - a deploy workflow for Fly/Cloudflare
  - `renovate.json`
  - Container and deploy:
    - `Dockerfile`
    - `charts/<app>/` (Chart.yaml, values.yaml documented, templates with probes, resources,
      securityContext, and a migration pre-upgrade Job when there is a DB)
    - `fly.toml` with `release_command`
    - `wrangler.toml`
  - Walking skeleton for each type, with config validation, structured logging,
    `/healthz` + `/readyz`, DB connection setup, an initial migration, and one test
  - Docs: `README.md`, `LICENSE` (ask), `.env.example`, `CLAUDE.md`,
    `docs/adr/0001-technology-choices.md`

  Add a section at the top, "Version lookup". It says how to get current exact versions at
  scaffold time:
  - `go list -m -versions <mod>`
  - `npm view <pkg> version`
  - `curl -s https://pypi.org/pypi/<pkg>/json | jq -r .info.version`
  - `gh api repos/<o>/<r>/releases/latest` or `git ls-remote --tags` for tools
  - `git ls-remote https://github.com/<o>/<r> refs/tags/<tag>` for action SHAs
  - `docker buildx imagetools inspect` for image digests, when available. Otherwise pin the tag
    and report DEP-7 as a gap.

- [ ] **Step 2: Cross-check criteria coverage.** For each criterion ID the spec lists under "What
  the skeleton contains", confirm it appears in some entry's **Satisfies**:
  `for id in STK-3 STK-4 HYG-4 QUA-1 QUA-2 QUA-3 QUA-5 VCS-5 DEP-1 DEP-3 DEP-4 DEP-6 DEP-7 CI-1 CI-2 CI-5 CI-6 TST-1 TST-2 TST-3 SEC-2 SEC-3 SEC-4 BLD-4 CFG-2 CFG-5 CFG-6 CFG-7 DPL-1 DPL-2 DPL-3 DPL-4 DPL-5 DPL-7 DAT-2 DAT-3 DAT-4 DAT-6 DAT-7 DAT-8 DAT-10 OBS-1 OBS-2 OBS-3 DOC-1 DOC-2 DOC-3 DOC-4 HYG-3 OPS-1 AGT-1 AGT-2 AGT-3 AGT-4; do grep -q "$id" plugins/engineering-standards/skills/engineering-standards-scaffold/references/scaffold-checklist.md || echo "missing $id"; done`
  Expected: no output.

- [ ] **Step 3: Commit.**
  `git commit -m "docs(engineering-standards): add scaffold checklist reference"`.

### Task 5: The scaffold skill

**Files:**
- Create: `plugins/engineering-standards/skills/engineering-standards-scaffold/SKILL.md`

**Interfaces:**
- Consumes:
  - `scripts/scaffold-preflight.sh` (Task 1 JSON)
  - `scripts/scaffold-verify.sh` (Task 2 JSON)
  - `scripts/tag.sh write . <file>`
  - `../engineering-standards-advise/references/decisions-format.md` (Task 3)
  - `references/scaffold-checklist.md` (Task 4)
  - the advise skill's flow, for the backstop

- [ ] **Step 1: Write `SKILL.md`.** Frontmatter `name: engineering-standards-scaffold`. No
  `disable-model-invocation`. The `description` says:
  - use it when asked to start implementing in a repository that is empty or holds only
    specification/design documentation
  - it records the classification in `.nyx.yml` and builds a standards-conformant skeleton,
    committed locally
  - **do not use it from a subagent or inside a kanban-flow card worktree**: run it in the main
    session before `/kanban`

  The body follows the classify shape, with `$P` = `${CLAUDE_PLUGIN_ROOT}`. The steps mirror the
  spec's steps 1–8:
  1. **Preflight.** Run `bash "$P/scripts/scaffold-preflight.sh" . < /dev/null`.
     - `populated`: stop, and point the user at classify and assess.
     - `worktree: secondary`: stop, and explain why.
     - `git: false`: run `git init -b main`.
  2. **Decisions.** Find the spec with `## Technology decisions` (ask if there are several). If
     the section is missing, incomplete or stamped with another framework version, run the
     advise flow from `../engineering-standards-advise/SKILL.md`.
  3. **Confirm.** Show the decisions and the file list from the checklist, ask about `LICENSE` vs
     private/unlicensed, and wait for confirmation.
  4. **Tag.** Map the decisions to tag JSON per `decisions-format.md`, then run `tag.sh write`.
  5. **Generate.** Work through the checklist entries that apply. Look up versions per
     "Version lookup". Skip any path that already exists and report it. When a kept exemption
     changes the stack, generate only `Stack-neutral: yes` entries, and list the skipped ones.
  6. **Verify.**
     - Run `git add -A`.
     - Run `bash "$P/scripts/scaffold-verify.sh" . < /dev/null`. For each gap that a checklist
       entry should satisfy, fix it and re-run. Gaps that need GitHub or a human are reported,
       not fixed.
     - If `just` and the toolchain exist on the host, run `just setup` and `just check` and fix
       failures. Otherwise say plainly that they weren't run, and should be run in the Dev
       Container.
  7. **Commit.**
     - If there are no commits, make the initial commit on `main`.
     - Otherwise run `git switch -c chore/scaffold` first.
     - Message: `chore: scaffold <name> per engineering standards`, with the session's
       attribution trailer.
     - Never push.
  8. **Hand off.** Summarise what was created, which criteria are met and which are gaps (from
     verify), and the remote follow-ups: the ruleset, the `dhi.io` Actions secret, the Renovate
     app, and the ArgoCD Application. Suggest `/engineering-standards-assess`, then kanban-flow
     or a plan.

- [ ] **Step 2: Validate.**
  Run: `bash scripts/check-plugin.sh plugins/engineering-standards/`
  Expected: exit 0. Every `references/...md` path in both new SKILL.md files resolves.

- [ ] **Step 3: Commit.**
  `git commit -m "feat(engineering-standards): add engineering-standards-scaffold skill"`.

### Task 6: Plugin metadata and docs

**Files:**
- Modify: `plugins/engineering-standards/.claude-plugin/plugin.json` (version `0.2.0`, and the
  description mentions advise and scaffold)
- Modify: `.claude-plugin/marketplace.json` (the engineering-standards description, if it lists
  the skills)
- Modify: `plugins/engineering-standards/README.md`
- Modify: `CLAUDE.md` (the engineering-standards section)

- [ ] **Step 1: Update the README.**
  - Usage: describe the new skills. They are model-invoked as well as runnable by hand, unlike
    classify and assess.
  - Add a "Technology decisions section" subsection that points at `decisions-format.md`.
  - Add scaffold's remote follow-ups.
  - Add a step to "Versioning and updating the standards": review `scaffold-checklist.md` when
    criteria change.
  - Add the two new test files to "Tests".
- [ ] **Step 2: Update `CLAUDE.md`'s engineering-standards section** with one line: scaffold
  generates from `scaffold-checklist.md` (not templates), and the checklist cites criterion IDs,
  so it must change with the standards.
- [ ] **Step 3: Validate everything.**
  Run: `bash scripts/check-plugin.sh plugins/engineering-standards/ && for t in plugins/engineering-standards/scripts/tests/test_*.sh; do bash "$t" < /dev/null || echo "FAILED $t"; done && jq . .claude-plugin/marketplace.json plugins/engineering-standards/.claude-plugin/plugin.json > /dev/null`
  Expected: exit 0, and no `FAILED` lines.
- [ ] **Step 4: Commit.**
  `git commit -m "docs(engineering-standards): document advise and scaffold, bump to 0.2.0"`.

### Task 7: Exercise the skills on throwaway repos

**Files:** none in this repo. Throwaway repos go under the scratchpad.

- [ ] **Step 1: Advise.** In a scratch repo, add `docs/spec.md` describing a small API that names
  "Node.js + Express" and "MySQL". Invoke `/engineering-standards-advise`.
  Expected:
  - it names STK-1 and DAT-1
  - it offers alternatives
  - it writes `## Technology decisions` only after you answer
- [ ] **Step 2: Scaffold a Go service on Kubernetes with PostgreSQL** (a spec with a complete
  decisions section). Invoke `/engineering-standards-scaffold`.
  Expected:
  - `.nyx.yml` is written
  - one local commit, on `main`
  - `scaffold-verify.sh` gaps are limited to criteria that need GitHub or a human
  - `just check` passes, or the skill says it wasn't run
- [ ] **Step 3: Scaffold a Python library with no deployment.** Same expectations. In addition:
  no Dockerfile, no chart, and no `deploy` recipe.
- [ ] **Step 4: Scaffold a TypeScript frontend on Cloudflare Pages** (`backend: none`). Expected:
  Wrangler config, a deploy workflow, and no `/healthz`.
- [ ] **Step 5: Refusal paths.**
  - a repo with `go.mod` → scaffold refuses
  - a `git worktree add` copy of a docs-only repo → scaffold refuses
- [ ] **Step 6: Record results.** Save each repo's `scaffold-verify.sh` output and the
  observations in the scratchpad, ready for the PR description. Fix any skill wording problems
  found, re-run the affected exercise, and commit the fixes:
  `git commit -m "fix(engineering-standards): <what changed>"`.
