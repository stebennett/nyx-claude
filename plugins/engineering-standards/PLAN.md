# engineering-standards plugin — plan

Assess a repository against the Home Projects Engineering Standards (`standards.md`, framework
v1.4) and write a scored report to `docs/assessment.md`. Two user-invoked skills: one tags the
repo with its classification, one assesses it.

Branch: `feature/engineering-standards-plugin`. Nothing is committed in target repos.

## Decisions

| # | Decision |
|---|---|
| D1 | New plugin `plugins/engineering-standards/`, registered in `.claude-plugin/marketplace.json` |
| D2 | Standards are bundled: `engineering-standards.md` is `git mv`'d to `skills/engineering-standards-assess/references/standards.md`. The bundled version is always the one scored |
| D3 | Output is `docs/assessment.md` in the target repo, in the section 7 template exactly, plus one extra `## Needs manual confirmation` section after `## Actions`. Re-runs overwrite it; a terminal summary shows the delta from the previous file |
| D4 | Two skills, both `disable-model-invocation: true`, both taking no arguments and operating on the current working directory: `engineering-standards-classify` and `engineering-standards-assess` |
| D5 | Classification lives in `.nyx.yml` at the repo root, under the `engineering_standards:` key only. Every other key in the file is preserved untouched |
| D6 | Classify infers, proposes each field with a reason, confirms with the user via `AskUserQuestion`, then writes. It is the only interactive step |
| D7 | Assess is headless. It hard-fails if `.nyx.yml` or the section is missing, `status: archived`, or `schema_version` / `framework_version` differ in any way from the bundled versions — directing the user to re-run classify |
| D8 | Unverifiable criteria are scored conservatively on the evidence that *can* be inspected (0 when nothing can be; e.g. 1 for a Dev Container that exists but whose in-container test run cannot be verified), marked `(unverified)` in the criterion table, and listed in `## Needs manual confirmation` with what a human should check. `gh` is used where authenticated; without it, `gh`-dependent criteria become unverified rather than failing |
| D9 | Hybrid scoring: bash scripts handle mechanical criteria and all arithmetic; LLM agents handle judgment criteria |
| D10 | Five category groups run in parallel. Per group: `es-checker` (haiku) runs the scripts; `es-assessor` (sonnet) scores judgment criteria. The main context merges, runs scoring, writes Actions |
| D11 | Dependencies: `jq` and mikefarah `yq` v4 (both required, checked up front). Scripts are bash 3.2 safe, no GNU-isms |
| D12 | Neither skill commits. Periodic GitHub Actions run is deferred |
| D13 | Three versions, all checked by tests: framework version (`standards.md` == `rubric.json`), `.nyx.yml` section `schema_version`, and the `framework_version` stamped into the tag |

## Layout

```
plugins/engineering-standards/
  .claude-plugin/plugin.json
  README.md
  PLAN.md                                   # this file
  agents/
    es-checker.md                           # model: haiku — runs check scripts, returns JSON
    es-assessor.md                          # model: sonnet — scores judgment criteria
  skills/
    engineering-standards-classify/SKILL.md
    engineering-standards-assess/
      SKILL.md
      references/
        standards.md                        # moved from repo root
        rubric.json                         # machine-readable rubric
  scripts/
    lib/common.sh                           # dep checks, .nyx.yml read/write, version checks, JSON emit
    lib/repo.sh                             # repo introspection: files, workflows, justfile, Dockerfiles
    lib/applicability.jq                    # applicability rules shared by score.sh and plan.sh
    tag.sh                                  # read / write / gate the .nyx.yml section
    detect.sh                               # classify signals → JSON
    plan.sh                                 # gate + applicable groups/judgment criteria + tag warnings
    checks/group-1.sh … group-5.sh          # mechanical criteria per group → JSON records
    score.sh                                # records + tag + rubric → scored JSON
    render.sh                               # scored JSON → docs/assessment.md (template embedded)
    delta.sh                                # previous docs/assessment.md vs new scores
    tests/
      helpers.bash                          # assertions (not *.sh, so CI doesn't run it as a test)
      fixtures/exemplary/                   # repo meeting every offline-verifiable script criterion
      test_*.sh
```

## Data contracts

**`.nyx.yml` section**

```yaml
engineering_standards:
  schema_version: 1
  framework_version: "1.4"
  type: service                 # service | library | cli | infrastructure
  status: active                # active | maintained | archived
  deployment_target: kubernetes # fly | cloudflare | kubernetes | none
  database: postgresql          # postgresql | sqlite | d1 | none
  lightweight: false            # meaningful only for sqlite / d1 (DAT-2)
  optional_categories: [DAT]    # matrix 'O' categories the repo has adopted
  exemptions:                   # persistent N/A, each with a justification
    - id: SEC-4
      reason: "No containers; Cloudflare Worker"
```

Read with `yq -o=json '.engineering_standards'`; written with `yq -i` on that subtree only.

**`rubric.json`** — derived from `standards.md`:
- `framework_version`
- `categories`: id, name, applicability per type (`R` / `O` / `-`)
- `criteria`: id, category, text, level (`L1`–`L3`), `method` (`script` | `judgment`),
  `applies_when` (conditions on tag fields, e.g. `deployment_target == kubernetes`,
  `database in [postgresql]`, `deployment_target != cloudflare`)
- `recipes`: section 2.1 recipe names with the types/conditions that require them
- `levels`: score thresholds 40 / 65 / 85

**Criterion record** (emitted by scripts and assessors, one per criterion):

```json
{"id":"CI-5","score":2,"evidence":"...","source":"script","unverified":false}
```

`score` is `0`, `1`, `2` or `"N/A"`; N/A requires `evidence` to hold the justification.

**Scoring** (`score.sh`):
1. Drop categories that are `-` for the type, and `O` categories not in `optional_categories`.
2. Mark criteria N/A whose `applies_when` fails, or that appear in `exemptions` (reason as evidence).
3. Category % = sum / (2 × applicable criteria) × 100. Overall = mean of applicable category %.
4. Score level from thresholds; gate level = highest level whose criteria (that level and below)
   are all `2` or N/A. Maturity = the lower of the two.
5. Blocking gate criteria = unmet criteria at or below the next level up.
6. Fail if any applicable criterion has no record, or has duplicate records.

## Criterion method split (draft — finalise in Phase 1)

Script (`es-checker`): STK-1–4 · DOC-3 · HYG-1, HYG-2, HYG-4, HYG-5 · VCS-1–5 · QUA-1–5 ·
TST-2, TST-3, TST-5 · CI-1, CI-2, CI-3, CI-4, CI-5, CI-6 · DEP-1, DEP-2, DEP-4, DEP-6, DEP-7 ·
SEC-2, SEC-3, SEC-4, SEC-6 · BLD-1, BLD-4 · CFG-3–6 · DPL-2–6, DPL-8 · DAT-3, DAT-4, DAT-6, DAT-9 ·
OBS-3, OBS-4 · AGT-1, AGT-2

Judgment (`es-assessor`): DOC-1, DOC-2, DOC-4–6 · HYG-3 · TST-1, TST-4, TST-6 · CI-7 · DEP-3,
DEP-5 · SEC-1, SEC-5 · BLD-2, BLD-3, BLD-5 · CFG-1, CFG-2, CFG-7 · DPL-1, DPL-7 · DAT-1, DAT-2,
DAT-5, DAT-7, DAT-8, DAT-10, DAT-11 · OBS-1, OBS-2, OBS-5 · OPS-1–4 · AGT-3–5

Typically unverified without external evidence: VCS-3 / CI-3 / DEP-2 (without `gh`), CFG-4 (tests
pass inside the container), SEC-5 (token scopes), OPS-3 (restore record absent).

## Category groups

| Group | Categories |
|---|---|
| 1 | STK, HYG, DOC, AGT |
| 2 | VCS, CI, DEP |
| 3 | QUA, TST, BLD |
| 4 | SEC, CFG |
| 5 | DPL, DAT, OBS, OPS |

A group whose categories are all inapplicable is skipped.

## Phases

### Phase 0 — Scaffold
- [x] Create `plugins/engineering-standards/` with `.claude-plugin/plugin.json` (version `0.1.0`)
- [x] `git mv engineering-standards.md` to `skills/engineering-standards-assess/references/standards.md`
- [x] Register the plugin in `.claude-plugin/marketplace.json`
- [x] `scripts/check-plugin.sh plugins/engineering-standards/` passes

### Phase 1 — Rubric
- [x] Write `references/rubric.json` covering every criterion, category, recipe rule and threshold
- [x] Finalise the `method` split and `applies_when` conditions
- [x] `test_rubric_consistency.sh`: every criterion ID and level in `standards.md` matches
      `rubric.json`, no extras either way, and framework versions are equal

### Phase 2 — Common library and `.nyx.yml`
- [x] `lib/common.sh`: require `jq` and `yq` v4 with install hints; read/write the
      `engineering_standards` subtree; version checks; JSON record helper
- [x] Tests: writing the section preserves other top-level keys and their comments; each version
      mismatch (schema, framework minor, framework major) and missing/archived tag hard-fails

### Phase 3 — Classify
- [x] `detect.sh`: languages from `git ls-files`, `fly.toml` / `wrangler.*` / `charts/`, `cmd/` vs
      package metadata, Dockerfile, migration dirs, PostgreSQL/SQLite drivers, existing tag → JSON
- [x] Fixture tests for `detect.sh` (one fixture per type, target and database)
- [x] `engineering-standards-classify/SKILL.md`: run detect, propose every field with a reason,
      confirm via `AskUserQuestion` (inferred value first; existing tag values as defaults), write
      only after confirmation

### Phase 4 — Mechanical checks

Note: the per-group tests cover met (exemplary fixture), partial (a broken copy) and not met (bare
repo) across the criteria, not every score of every criterion.
- [x] `checks/group-1.sh` … `group-5.sh`, one JSON record per script criterion
- [x] `gh` detection; `gh`-dependent criteria emit `unverified: true` when unavailable
- [x] Fixture repos and tests per group, covering met / partial / not met for each criterion

### Phase 5 — Scoring and rendering
- [x] `score.sh` per the scoring rules above
- [x] `render.sh`: section 7 template, `0 (unverified)` marking, `## Needs manual confirmation`
- [x] `delta.sh` (was `previous.sh`): parse the existing report and diff it against the new scores
- [x] Golden-file tests: category %, overall mean, score-vs-gate level, blocking gates, N/A
      exclusion, exemptions, missing/duplicate record failures

### Phase 6 — Agents
- [x] `agents/es-checker.md` (haiku): runs one group script, returns its JSON unaltered plus notes
- [x] `agents/es-assessor.md` (sonnet): given group, applicable judgment criteria, checker output
      and the standards text, returns one record per criterion with evidence

### Phase 7 — Assess skill
- [x] `engineering-standards-assess/SKILL.md`: dependency check → tag/version gate → applicable
      groups → parallel checker then assessor per group → merge → `score.sh` → write Actions →
      `render.sh` → terminal summary with delta (score, level, changed criteria)
- [x] Warn in the report when detected evidence contradicts the tag (e.g. `fly.toml` with
      `deployment_target: none`)

### Phase 8 — Documentation
- [x] Plugin `README.md`: purpose, dependencies (`jq`, `yq` v4), usage, `.nyx.yml` reference,
      versioning and how to update the standards
- [x] Update repo `CLAUDE.md`: current plugin list and layout (it is stale)
- [x] CI script-test job picks up `plugins/*/scripts/tests/*.sh`; added a step guaranteeing
      mikefarah `yq` v4 on both runners (first real confirmation is the PR's CI run)

### Phase 9 — Validation
- [x] Clone `stebennett/golf-tracker` into the scratchpad
- [x] Run classify; review the proposed tag (do not commit it there)
- [ ] Run assess; review `docs/assessment.md` with the user and fix any scoring or evidence issues
      — run complete (56.5, L0); script calibration fixed below; awaiting the user's review
- [x] Nothing is pushed to golf-tracker

Calibration fixes from the golf-tracker run (each now covered by a test):
- Monorepos: manifests, lockfiles, ruff/pyright config and database evidence are read from every
  workspace member, not only the repo root; detect.sh finds charts anywhere and says when several
  deployment targets exist; SQLite used only by tests does not count as a database.
- STK-2 / HYG-4: tool config modules (`*config*.js`, `vite.*.ts`, `*.test.ts`) and `docs/` are not
  source.
- CI-2: CI running `just lint` and `just test` separately scores 1, not 0.
- TST-5: recipes CI invokes (`just coverage`) are expanded when looking for coverage thresholds.
- VCS-3: a ruleset that exists but is not enforced is reported as such.
- DEP-2: self-hosted Renovate is recognised by its `renovate/` branch prefix.
- DAT-4: Fly migrations in a `[processes]` command (not `release_command`) score 1, unverified.

## Deferred

- Periodic GitHub Actions workflow running assess headlessly (and probably opening a PR with the
  updated report)
- Mirroring tag fields to GitHub topics for cross-repo querying
