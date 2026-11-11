# engineering-standards: advise and scaffold skills — design

Date: 2026-11-01
Plugin: `plugins/engineering-standards` (both skills live here; kanban-flow is not modified)

## Intent

New repositories usually start as specification and design documents, and those documents already
make technology decisions. Today nothing checks those decisions against the Home Projects
Engineering Standards until a repo is assessed after the fact. By then a non-standard choice (an
Express backend, MySQL) is baked into code.

Two skills close that gap:

1. **`engineering-standards-advise`** checks technology decisions against the standards *while the
   spec is being written*. It raises any conflicts with the user and records the agreed decisions
   in the spec.
2. **`engineering-standards-scaffold`** turns those decisions into a standards-conformant
   repository skeleton when Claude is about to start implementing in an empty or
   documentation-only repo.

## Goals

- Raise standards conflicts at spec time, when changing the decision is cheap.
- The user always decides. A conflict is raised, explained and resolved by the user: they either
  change the spec or keep the choice as a recorded exemption.
- Ask the user only about what the standards leave open: choices among permitted options, project
  type, and anything the standards don't cover, such as frameworks.
- When scaffold finishes: `.nyx.yml` exists (the minimum, written first), the tooling and deploy
  skeleton is in place, a walking skeleton passes `just check`, and a first
  `/engineering-standards-assess` comes out at L1 or close to it.
- The scaffold is committed locally.

## Non-goals

- Implementing any of the spec's features. Those are left to kanban-flow or a plan.
- Anything remote: pushing, creating the GitHub repo, setting up rulesets (VCS-3), adding Actions
  secrets (the `dhi.io` token), creating the ArgoCD Application (DPL-6), and Renovate actually
  opening PRs (DEP-2).
- Infrastructure-type repos (*designer's call*: the request is about applications, libraries and
  services).
- Changing kanban-flow or superpowers. Both skills trigger from their own descriptions.
- Re-scaffolding or upgrading existing, populated repositories.

## Anti-goals (failure even if it "works")

- Silently overriding a technology choice the spec made, in either direction: quietly
  "correcting" it to the standard, or quietly accepting a violation.
- Overwriting or deleting existing files, especially the spec documents.
- Blocking the user from keeping a deviation they've consciously chosen.
- Scaffolding that claims L1 without having run the checks.

## Skill 1: `engineering-standards-advise`

**Invocation.** Model-invocable (no `disable-model-invocation`) and also user-invocable. The
description must make it fire whenever a spec, design or requirements document is being written
or revised and it chooses or implies languages, frameworks, databases, deployment targets,
packaging, CI or dependency tooling. This covers superpowers brainstorming and kanban-flow
`/refine` / `/requirement` sessions without changing either. It can also be run by hand against
an existing spec ("check this spec against the standards").

**Source of truth.** `${CLAUDE_PLUGIN_ROOT}/skills/engineering-standards-assess/references/standards.md`
(and `rubric.json` where it helps). The skill doesn't restate the standards.

**Behaviour.** For each technology decision the spec makes or needs, classify it:

| Class | Meaning | Action |
|---|---|---|
| Mandated | The standards fix it (`just`, GitHub Actions, Renovate, DHI runtime images, Dev Container, Helm for k8s, exact pinning) | Write it into the decisions section. Don't ask |
| Constrained | The standards allow a short list: backend Python or Go; deployment Fly.io / Cloudflare / Kubernetes; database PostgreSQL or SQLite/D1; project type | Ask, with the consequences of each option (e.g. Kubernetes → Helm chart, ArgoCD, no `deploy` recipe; SQLite/D1 → must meet all three DAT lightweight conditions, single instance, Litestream-style backups) |
| Open | The standards are silent (web framework, ORM, frontend framework, queue, auth library) | Ask, or propose a default when the user hands it over. Record it as the user's choice or as "advisor's suggestion, accepted" |

**Conflicts.** When the spec states a choice that the standards forbid, the advisor:

1. names the choice and the criteria it would fail (e.g. "Express backend → STK-1; MySQL → DAT-1"),
2. offers compliant alternatives with their trade-offs,
3. lets the user choose: **change the spec** (the advisor edits the spec text where the choice
   appears, with the user's agreement) or **keep it as an exemption**, recorded with the
   criterion IDs and a one-line reason from the user.

The advisor never resolves a conflict on its own.

**Output.** It adds or updates a section in the spec document being written, under the fixed
heading `## Technology decisions`. The section holds a short preface noting the standards version
it was checked against (e.g. "Checked against Engineering Standards v1.4"), and a table:

| Field | Value | Source |
|---|---|---|

The rows are, at minimum: `type` (service/library/cli), `status` (default `active`), `backend`
(go / python / none), `frontend` (typescript + framework / none), `deployment_target`
(fly / cloudflare / kubernetes / none), `database` (postgresql / sqlite / d1 / none),
`lightweight` (true/false, with the three DAT conditions answered when sqlite/d1), then one row
per open-category choice (framework, ORM/migration tool, etc.). `Source` is one of: `mandated`,
`user`, `advisor-suggestion-accepted`, `spec`. A separate `### Exemptions` sub-list records each
kept deviation as `- <CRITERION-ID>: <reason>`.

The field names and enums for type/status/deployment_target/database/lightweight deliberately
match the `.nyx.yml` tag, so scaffold maps them across directly.

**When no spec file exists yet** (e.g. mid-brainstorming, where the document is written at the
end): the advisor resolves conflicts and choices in conversation, and the decisions section is
added when the spec document is written (*designer's call*).

**Editing boundaries** (*designer's call*): the advisor owns only the `## Technology decisions`
section. It edits other spec text only to resolve a conflict, only with the user's agreement, and
never touches REQ id markers (`req-ids` owns those).

**Scope.** Advice only. It writes nothing outside the spec document and commits nothing.

## Skill 2: `engineering-standards-scaffold`

**Invocation.** Model-invocable and user-invocable. The description must make it fire when Claude
has been asked to start implementing and the repository is empty or contains only specification
and design documentation.

**Steps.**

1. **Preflight (deterministic).** A new script, `scripts/scaffold-preflight.sh <repo>`, reports
   JSON: whether the repo is a git repo, whether it has commits, the tracked and untracked files,
   and a verdict of `empty`, `docs-only` or `populated`. `docs-only` means every file is Markdown
   or under `docs/`, plus at most `LICENSE`, `.gitignore`, `.nyx.yml`, `.claude/` and
   `.github/ISSUE_TEMPLATE` (the builder may refine this list; keep it in one place in the script).
   On `populated`, stop and explain that scaffold is only for new repos. Point the user at
   `/engineering-standards-classify` and `/engineering-standards-assess` instead. If there is no
   git repo, `git init -b main` (*designer's call*: local and reversible).
2. **Find the decisions.** Locate the spec. Search `docs/` and the root for Markdown containing
   `## Technology decisions`. If there are several candidates, ask which one. If the section is
   missing, incomplete or checked against a different standards version, run the advisor's flow
   now (the backstop for specs written without it), including the conflict check on the spec
   text. That updates the spec before anything is built.
3. **Confirm the build.** Show the user the resolved decisions and the list of files and
   directories about to be created. Use `AskUserQuestion` for anything still open. Nothing is
   written until the user confirms.
4. **Write the tag first.** Build the tag JSON from the decisions (type, status,
   deployment_target, database, lightweight, `optional_categories` derived from the matrix and
   the decisions, exemptions from `### Exemptions`) and run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/tag.sh" write . <file>`. This makes the minimum
   deliverable exist even if a later step fails.
5. **Generate the skeleton** from `references/scaffold-checklist.md` (see below). Files are
   generated by Claude rather than copied from fixed templates, because exact pinned versions go
   stale. Look up current stable versions at scaffold time (e.g. `go list -m -versions`,
   `npm view <pkg> version`, PyPI JSON API, GitHub releases for tools and actions, including the
   commit SHA for each pinned action). Never create or overwrite a file that already exists. If a
   checklist file collides with an existing one, report it and skip it.
6. **Verify.** Stage the generated files first (`git add`), because the check scripts read only
   `git ls-files`.
   - Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/checks/group-{1..5}.sh"` against the repo
     (`< /dev/null`), using the same invocation as `es-checker`. Fix anything flagged that is in
     scope, and re-run.
   - If `just` and the language toolchain are available on the host, run `just setup` and
     `just check` and fix failures. If they aren't, say plainly that `just check` was not run, and
     that it should be run inside the Dev Container.
   - Report which in-scope criteria the checks show as met, and which are left (with the reason:
     needs GitHub, needs a human, out of scope).
7. **Commit locally.** Use a Conventional Commit (`chore: scaffold <name> per engineering
   standards`) with the session's attribution trailer. If the repo has no commits, this is the
   initial commit on `main`. If `main` already has commits (the spec), commit on a new branch
   `chore/scaffold` so it can go through a PR (*designer's call*). Never push.
8. **Hand off.** Summarise what was created, what must be done remotely (ruleset, `dhi.io`
   secret, Renovate app, ArgoCD Application), and suggest `/engineering-standards-assess`, then
   kanban-flow or a plan for the features.

### What the skeleton contains

Driven by the applicable criteria for the decided type, target and database. Target: every
applicable L1 criterion that can be satisfied from inside the repo, plus the cheap L2/L3 ones
listed here.

- **Tooling.** A `justfile` with the section 2.1 recipes that apply; tool versions pinned in it.
  `.devcontainer/devcontainer.json` that installs `just` and every recipe tool at pinned versions,
  with `postCreateCommand: just setup`. For PostgreSQL, a Compose service in the Dev Container
  with the major version pinned and matching CI (DAT-6, DAT-8). Also `.gitignore`,
  `.editorconfig`, `.pre-commit-config.yaml` (formatter, linter, gitleaks), and a commit-message
  check (VCS-5).
- **Language.** Toolchain pins (STK-4). Layout per HYG-4 (Go `cmd/<name>/` + `internal/`, Python
  `src/<package>/` + `pyproject.toml`, TS `src/`). Formatter, linter and strict type-check config
  (QUA-1, QUA-2, QUA-5, STK-3). A committed lockfile (DEP-1). Exact pins (DEP-4), with the library
  exception for published metadata. `.npmrc` with `save-exact=true` when there is a frontend. When
  there is both a backend and a frontend, how the components are laid out is the builder's call,
  documented in the checklist.
- **CI.** `.github/workflows/` running `just check` and `just build` on push and PR, with actions
  pinned by SHA, explicit least-privilege `permissions:`, gitleaks, and a vulnerability scan
  (CI-1, CI-2, CI-5, CI-6, TST-3, QUA-3, SEC-2, SEC-3). For Kubernetes, also `helm lint`,
  `helm template` and kubeconform (DPL-3).
- **Dependencies.** `renovate.json` covering every ecosystem present, with `rangeStrategy: "pin"`,
  `dhi.io` hostRules (the credential is referenced, not committed), and patch/minor automerge
  (DEP-2 config, DEP-3, DEP-6).
- **Build and deploy** (services). A multi-stage Dockerfile with a DHI runtime stage
  (`dhi.io/static` for Go), non-root, and a base pinned by digest (BLD-4, SEC-4, DEP-7). Deploy
  config for the target: a `charts/<app>/` Helm chart with resources, securityContext, probes and
  documented values, plus a migration pre-upgrade hook when there's a DB (DPL-2, DPL-4, DPL-5,
  DPL-7, DAT-4); or `fly.toml` with a `release_command` for migrations; or Wrangler config. A
  `deploy` recipe and workflow only for Fly/Cloudflare.
- **Walking skeleton.**
  - Service: an entry point that reads and validates config from the environment (CFG-2, CFG-7),
    logs in structured form to stdout (OBS-1, OBS-2), and serves `/healthz` and `/readyz` (OBS-3).
    With a database: a pooled connection from `DATABASE_URL` (DAT-7) or SQLite pragmas (DAT-10),
    an empty initial migration and `just migrate` (DAT-3).
  - Library: one exported function. CLI: one command with `--version`.
  - Each has at least one passing test (TST-1, TST-2).
- **Docs and agent context.**
  - `README.md`: the first paragraph comes from the spec, plus status, Dev Container getting
    started, deployment target, the lightweight statement when applicable, and deploy/rollback
    steps (DOC-1, DOC-2, HYG-3, DPL-1, DAT-2, OPS-1).
  - `LICENSE`, or a private/unlicensed statement. Ask the user which.
  - `.env.example` (CFG-6).
  - `CLAUDE.md` pointing the agent at the `just` recipes, setting out conventions, and listing
    do-not-touch paths (AGT-1, AGT-2, AGT-3, AGT-4).
  - `docs/adr/0001-technology-choices.md` recording the decisions and any exemptions (DOC-4)
    (*designer's call*).

### Kept deviations (user's decision)

When the decisions include an exemption that changes the stack (a non-Python/Go backend, a
non-PostgreSQL/SQLite database), scaffold builds only the stack-neutral parts: the `justfile`
recipe shell, CI, Renovate, docs, `CLAUDE.md`, `.nyx.yml` and the ADR. It names the language and
database parts it left to the user. The tag schema and `tag.sh` validation are not changed. For
a database outside the tag enum, the tag records `database: none`, and the exemption reason names
the actual database (*designer's call*). Exemptions are written into the tag as usual, so assess
scores those criteria N/A.

### Agent and worktree contexts (user's decision)

Scaffold runs only in the top-level session. Its description must say not to use it from a
subagent or inside a kanban-flow card worktree. Kanban-flow users run scaffold before `/kanban`
starts implementing. If scaffold finds it is running inside a git worktree other than the main
one, it stops and says so.

### Supported combinations (*designer's call*)

Every combination the standards permit is in scope. Where the checklist has no guidance for a
combination (e.g. a Python Worker on Cloudflare), scaffold builds the stack-neutral parts, says
which parts it skipped, and leaves them to the user rather than guessing. A frontend's skeleton is
the minimal starter of the framework chosen in the decisions (an open choice), with TypeScript
`strict`, its tooling wired into the `just` recipes, and one passing test. A frontend-only static
site has no `/healthz`. Verification must cover at least the two throwaway repos in Tests, plus a
TypeScript frontend on Cloudflare Pages.

### `references/scaffold-checklist.md`

A new reference under the scaffold skill, organised by file. It says which criteria each file
satisfies, when the file applies (type × target × database × backend × frontend), and the content
requirements. It states requirements ("runtime stage FROM a `dhi.io` non-dev variant, pinned by
digest, `USER` non-root"), not literal file contents. It cites criterion IDs instead of restating
the standards, so it changes when the standards change. Add a line to the README's "updating the
standards" steps: review the checklist when criteria change.

## Constraints

- Follow the repo's plugin conventions in `CLAUDE.md`:
  - bash 3.2 and macOS/Linux portability for `scaffold-preflight.sh`
  - none of the `pipefail`/empty-file-list traps described there
  - no apostrophes in single-quoted jq
- `jq` and mikefarah `yq` v4 are already plugin dependencies. Don't add new hard dependencies.
- Skill frontmatter and structure must pass `scripts/check-plugin.sh plugins/engineering-standards/`.
- Bump the plugin version (`0.1.0` → `0.2.0`) and update the plugin description and README
  (usage, the new skills, the decisions-section format).

## Tests

- `scripts/tests/test_scaffold_preflight.sh`: verdicts for an empty dir, no-git, docs-only (spec
  under `docs/`, root `README.md`), and populated (a `go.mod`, a `src/` file), plus robustness
  with spaces in filenames. Fixtures are built in temp dirs by the test, not committed.
- Existing tests keep passing. `check-plugin.sh` passes.
- The skills are Markdown and are validated by exercising them. Before calling it done, run
  scaffold on at least two throwaway repos: a Go service on Kubernetes with PostgreSQL, and a
  Python library with no deployment. Run the check groups on each result and record the outcome
  in the PR description.

## Left to the builder

- The exact wording of both skill descriptions (they must meet the triggers above).
- The final docs-only allowlist, and the multi-component layout convention.
- How much of the checklist is split per language versus shared.
- Default open-category suggestions (e.g. which Go HTTP router or Python web framework to propose
  when the user hands the choice over). They must be presented as suggestions, never applied
  silently.
