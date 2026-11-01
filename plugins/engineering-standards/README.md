# engineering-standards

Apply the **Home Projects Engineering Standards** from the first spec onwards. Check a spec's
technology decisions before anything is built, scaffold a new repository that meets the standards,
and assess any repository to get a scored report: category percentages, an overall score, a
maturity level (L0–L3), the criteria blocking the next level, and a concrete action for every gap.

The standards are bundled at
[`skills/engineering-standards-assess/references/standards.md`](skills/engineering-standards-assess/references/standards.md)
(framework **v1.4**). The plugin always scores against the bundled version.

## Usage

### New projects: advise, then scaffold

These two skills are model-invoked: Claude uses them on its own at the right moment, and you can
also run them by hand.

```
/engineering-standards-advise      # while a spec is being written, or to check an existing one
/engineering-standards-scaffold    # in an empty or docs-only repo, before implementation starts
```

1. **Advise.** Whenever a spec or design document chooses languages, frameworks, databases or
   deployment targets (for example during brainstorming or kanban-flow `/refine`), the advisor
   checks each choice against the standards:
   - **Mandated** choices are recorded without asking.
   - **Constrained** choices (Go or Python, Fly/Cloudflare/Kubernetes, PostgreSQL or SQLite/D1):
     it asks you to pick, and explains what each brings with it.
   - **Open** choices (frameworks, ORMs): it asks or suggests.
   - **Conflicts**, where the spec breaks a standard: it names the criteria that would fail, and
     you decide whether to change the spec or keep the choice as an exemption with a reason.

   The result is a `## Technology decisions` section in the spec, in the format in
   [`decisions-format.md`](skills/engineering-standards-advise/references/decisions-format.md).
   It writes only the spec and commits nothing.
2. **Scaffold.** When Claude is asked to start implementing in a repository that holds nothing but
   documentation, scaffold:
   - refuses repositories that already have code, and secondary git worktrees;
   - runs the advise flow first if the spec has no current decisions section;
   - shows you what it will build and waits for go-ahead;
   - writes `.nyx.yml` first;
   - generates the files listed in
     [`scaffold-checklist.md`](skills/engineering-standards-scaffold/references/scaffold-checklist.md),
     at versions looked up at the time: the `justfile`, Dev Container, CI, Renovate, pre-commit,
     Dockerfile and deploy config, `README.md`, `CLAUDE.md`, an ADR of the technology choices,
     and a walking skeleton (for a service: config, structured logging, health endpoints and one
     test);
   - checks the result with the standards check scripts (`scripts/scaffold-verify.sh`) and, when
     the toolchain is available, `just check`;
   - commits locally: the initial commit on `main`, or a `chore/scaffold` branch if `main` already
     has commits. It never pushes and never overwrites a file.

   If you keep an exemption that changes the stack (another backend language or database),
   scaffold builds only the parts that don't depend on it and leaves the rest to you. Run scaffold
   in the main session, before `/kanban` starts implementing: it is not meant to run inside a
   kanban-flow card worktree.

   Afterwards, these steps are yours:
   - push and open a PR
   - add the `main` branch ruleset
   - add the `DHI_USERNAME`/`DHI_TOKEN` Actions secrets for `dhi.io`
   - install the Renovate app
   - add the ArgoCD Application (Kubernetes)
   - add platform deploy tokens (Fly.io/Cloudflare)

### Existing projects: classify, then assess

Both skills run on the current working directory and are invoked by hand. Neither one commits
anything.

```
/engineering-standards-classify    # once per repo, and again whenever its shape changes
/engineering-standards-assess      # as often as you like
```

1. **Classify.** `/engineering-standards-classify` inspects the repo and proposes:
   - the project type
   - the status
   - the deployment target
   - the database
   - which optional categories the repo has adopted
   - any criteria you want permanently exempted

   You confirm each value. Then it writes the `engineering_standards:` section of `.nyx.yml`.
2. **Assess.** `/engineering-standards-assess` works in four stages:
   - It reads that section and refuses to run if the section is missing, invalid, archived, or
     stamped with a different framework or schema version. In those cases it tells you to
     re-classify.
   - It scores every applicable criterion.
   - It writes `docs/assessment.md` in the section 7 template.
   - It prints a summary, including what changed since the previous report.

## Dependencies

- **`jq`**: `brew install jq` / `apt-get install jq`
- **mikefarah `yq` v4**: `brew install yq` / `snap install yq`. The Python `yq` wrapper won't
  work.
- **`gh`** is optional. When it's authenticated, the assessment checks:
  - branch rulesets
  - CI status and duration on `main`
  - Renovate PR activity

  Without it, those criteria are scored conservatively and listed under "Needs manual
  confirmation".

## How scoring works

| Piece | Role |
|---|---|
| `scripts/plan.sh` | Gates on the tag, works out which category groups and judgment criteria apply, and flags where the repo contradicts the tag |
| `scripts/checks/group-1.sh` … `group-5.sh` | Score the mechanical criteria: file presence, `justfile` recipes, workflow steps, pinning, Dockerfiles, charts and so on |
| `es-checker` agent (Haiku) | Runs one check group and saves its records |
| `es-assessor` agent (Sonnet) | Scores one group's judgment criteria, such as README quality, ADRs, critical-path coverage and least privilege, from evidence in the repo |
| `scripts/score.sh` | Applies the rubric: applicability matrix, N/A, exemptions, category %, overall mean, score level vs gate level, blocking criteria |
| `scripts/render.sh`, `scripts/delta.sh` | Write `docs/assessment.md` and compare it with the previous report |

The five groups run in parallel:
1. STK, HYG, DOC, AGT
2. VCS, CI, DEP
3. QUA, TST, BLD
4. SEC, CFG
5. DPL, DAT, OBS, OPS

Each criterion is either a `script` or a `judgment` criterion. That method lives in
[`rubric.json`](skills/engineering-standards-assess/references/rubric.json), alongside the
applicability matrix, the `just` recipe rules and the level thresholds.

**Unverified criteria.** Some evidence can't be inspected from the repo, such as tests passing
inside the Dev Container, token scopes or restore tests. These criteria are scored on what can be
verified and marked `(unverified)`. They're also listed in the report's extra
`## Needs manual confirmation` section, along with what a human should check.

## `.nyx.yml`

```yaml
engineering_standards:
  schema_version: 1            # shape of this section (stamped by classify)
  framework_version: "1.4"     # standards version it was classified against (stamped)
  type: service                # service | library | cli | infrastructure
  status: active               # active | maintained | archived (archived repos are not assessed)
  deployment_target: kubernetes  # fly | cloudflare | kubernetes | none
  database: postgresql         # postgresql | sqlite | d1 | none
  lightweight: false           # SQLite/D1 only: meets the DAT lightweight-deployment conditions
  optional_categories: []      # 'O' categories in the section 3 matrix that the repo has adopted
  exemptions:                  # criteria marked N/A, each with its justification
    - id: SEC-4
      reason: "No containers; Cloudflare Worker"
```

Other tools may keep their own top-level keys in `.nyx.yml`. Classify only replaces the
`engineering_standards` section.

## Versioning and updating the standards

There are three versions, and they must agree:
- the framework version in `standards.md`
- the framework version in `rubric.json`
- the version stamped into the tag

To update the standards:

1. Edit `references/standards.md`.
2. Mirror the change in `references/rubric.json`. A changed criterion needs its ID, level, text,
   `method` and `applies_when` updated. A new script criterion also needs a check in the right
   `checks/group-N.sh`.
3. Run the tests. `test_rubric_consistency.sh` fails if the markdown and the rubric disagree.
4. Review `skills/engineering-standards-scaffold/references/scaffold-checklist.md`: its entries cite
   criterion IDs, so a changed criterion may change what scaffold generates.
5. Bump the plugin version. Repositories then need re-classifying: assess refuses tags stamped
   with any other framework version.

If the shape of the `.nyx.yml` section changes, bump `schema_version` in `rubric.json`.

## Tests

```
for t in plugins/engineering-standards/scripts/tests/test_*.sh; do bash "$t" < /dev/null; done
```

The tests are plain bash, bash 3.2 compatible, and run on Linux and macOS in CI. They cover:
- tag read, write and gating
- detection
- every check group, against the `fixtures/exemplary` repo, a deliberately broken copy of it and
  a bare repo
- scoring arithmetic and gates
- rendering and the delta
- scaffold preflight (empty / docs-only / populated, untracked and ignored files, worktrees) and
  scaffold verify (applicable script criteria on a staged, uncommitted repo)

The fixture holds its own `go.mod`, `Dockerfile` and workflow. If this repository adopts
Renovate, add `plugins/*/scripts/tests/fixtures/**` to `ignorePaths`.
