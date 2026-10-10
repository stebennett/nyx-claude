# Home Projects Engineering Standards

Version 1.4 — 2026-10-06

## 1. Purpose and scope

This framework defines the engineering standards for personal and home-lab repositories. It also gives a repeatable method for assessing each repository against them. It applies to every repository that is not archived.

Each standard is a set of criteria with IDs (for example `DOC-1`). An assessment scores each criterion, then rolls the results up to a category score and an overall maturity level.

## 2. Mandated technology stack

These choices are fixed. A repository that departs from them fails the related criteria, which are mostly in the STK and DPL categories.

| Concern | Standard |
|---|---|
| Backend language | Python or Go |
| Frontend language | TypeScript (`strict` mode). Plain JavaScript source is not permitted; generated or config JS (for example `*.config.js`) is exempt |
| Task runner | [`just`](https://github.com/casey/just), with a `justfile` at the repo root using the standard recipe names (section 2.1) |
| CI/CD | GitHub Actions, workflows in `.github/workflows/` |
| Dependency versions | Pinned to exact versions (DEP-4) |
| Dependency updates | Renovate. Dependabot version updates are not used |
| Container base images | Docker Hardened Images (`dhi.io`) for the runtime stage of every production image. Build stages and Dev Containers may use other images |
| Deployment targets | Fly.io, Cloudflare Pages / Workers, or the local Kubernetes cluster |
| Kubernetes packaging | Helm chart in `charts/<app>/` for every application deployed to Kubernetes |
| Development environment | Dev Container in `.devcontainer/devcontainer.json` |
| Relational database | PostgreSQL; SQLite (or Cloudflare D1) for lightweight deployments as defined in DAT |

### 2.1 Standard `just` recipes

Recipes with these names must exist where they apply, and must behave as described. Projects may add extra recipes. They must not rename these.

| Recipe | Behaviour | Required for |
|---|---|---|
| `default` | Runs `just --list` | All |
| `setup` | Installs toolchain dependencies and project dependencies | All |
| `fmt` | Formats code in place | All |
| `lint` | Runs linters and type checks without modifying files, including a format check | All |
| `test` | Runs the automated test suite | All except Infrastructure |
| `check` | Runs `lint` then `test`; CI runs this recipe | All |
| `build` | Produces the release artefact (binary, package, container image, static site) | Service, Library, CLI |
| `run` | Runs the application locally | Service, CLI |
| `migrate` | Applies pending database migrations to the configured database | Service or CLI with a relational database |
| `deploy` | Deploys to the target environment | Service deployed to Fly.io or Cloudflare |
| `clean` | Removes build output and caches | All |

Kubernetes-deployed services do not have a `deploy` recipe, because ArgoCD syncs them from Git (DPL-6).

## 3. Project types

Every repository is classified as one primary type. The type determines which categories apply.

| Type | Description |
|---|---|
| **Service** | Deployed application (API, web app, worker, agent, static site) |
| **Library** | Code consumed by other projects as a dependency |
| **CLI** | Tool run on demand from a terminal or script |
| **Infrastructure** | Kubernetes manifests, GitOps configuration, Helm charts for third-party software, IaC |

### Applicability matrix

`R` = required, `O` = optional (scored only if adopted), `—` = not applicable

| Category | Service | Library | CLI | Infrastructure |
|---|---|---|---|---|
| STK — Technology stack | R | R | R | O |
| DOC — Documentation | R | R | R | R |
| HYG — Repository hygiene | R | R | R | R |
| VCS — Version control | R | R | R | R |
| QUA — Code quality | R | R | R | R |
| TST — Testing | R | R | R | O |
| CI — CI/CD | R | R | R | R |
| DEP — Dependency management | R | R | R | R |
| SEC — Security | R | R | R | R |
| BLD — Build and packaging | R | R | R | — |
| CFG — Configuration and environment | R | R | R | R |
| DPL — Deployment | R | — | — | O |
| DAT — Data | R | O | O | O |
| OBS — Observability | R | — | O | O |
| OPS — Operability and data | R | — | — | R |
| AGT — AI agent context | R | R | R | R |

## 4. Scoring model

### Criterion scores

| Score | Meaning |
|---|---|
| 2 — Met | The criterion is fully satisfied, and is enforced or can be verified |
| 1 — Partial | The criterion is partly satisfied, or is satisfied but not enforced |
| 0 — Not met | The criterion is absent |
| N/A | The criterion does not apply; this needs a one-line justification |

### Category score

`category score = sum of criterion scores / (2 × number of applicable criteria) × 100`

Criteria marked N/A are excluded from the denominator.

### Overall maturity level

The overall score is the mean of the applicable category scores. The maturity level is the lower of two levels: the one implied by the overall score and the one implied by the gate criteria.

| Level | Overall score | Gate |
|---|---|---|
| **L0 — Ad hoc** | < 40 | — |
| **L1 — Baseline** | ≥ 40 | All `L1` criteria met |
| **L2 — Managed** | ≥ 65 | All `L1` and `L2` criteria met |
| **L3 — Exemplary** | ≥ 85 | All criteria met or N/A |

Each criterion below is tagged with the lowest level that requires it.

## 5. Standards

### STK — Technology stack

| ID | Criterion | Level |
|---|---|---|
| STK-1 | All backend code is Python or Go | L1 |
| STK-2 | All frontend code is TypeScript; no hand-written `.js` / `.jsx` source files | L1 |
| STK-3 | `tsconfig.json` has `"strict": true` | L1 |
| STK-4 | Language toolchain versions pinned: `go` directive and `toolchain` in `go.mod`; `requires-python` in `pyproject.toml` plus `.python-version`; `engines.node` in `package.json` plus `.nvmrc` or `.node-version` | L2 |

**Evidence:** file extensions in `git ls-files`, `tsconfig.json`, `go.mod`, `pyproject.toml`, `package.json`.

### DOC — Documentation

| ID | Criterion | Level |
|---|---|---|
| DOC-1 | The first paragraph of the README says what the project is and why it exists | L1 |
| DOC-2 | The README documents how to get started by opening the Dev Container and running `just setup`, `just run` and `just test` | L1 |
| DOC-3 | A licence file is present, or the README states explicitly that the repo is private and unlicensed | L1 |
| DOC-4 | Significant design decisions are recorded as ADRs in `docs/adr/` | L2 |
| DOC-5 | Projects with more than one component have an architecture overview (diagram or text) | L2 |
| DOC-6 | `CHANGELOG.md` is maintained, or release notes are generated from commits | L3 |

**Evidence:** README, `LICENSE`, `docs/adr/`, `CHANGELOG.md`.

### HYG — Repository hygiene

| ID | Criterion | Level |
|---|---|---|
| HYG-1 | `.gitignore` excludes build output, local environment files and editor files | L1 |
| HYG-2 | No build artefacts, generated files or binaries over 1 MB are committed, unless required and documented | L1 |
| HYG-3 | The README declares the project status: active, maintained or archived | L1 |
| HYG-4 | Layout follows language conventions: Go uses `cmd/<name>/` and `internal/`; Python uses the `src/<package>/` layout with `pyproject.toml`; TypeScript code lives in `src/` | L2 |
| HYG-5 | `.editorconfig` present | L3 |

**Evidence:** repository tree, `git ls-files`, README.

### VCS — Version control

| ID | Criterion | Level |
|---|---|---|
| VCS-1 | The default branch is `main`, and it is always in a deployable or releasable state | L1 |
| VCS-2 | Commit messages follow Conventional Commits | L2 |
| VCS-3 | `main` is protected by a branch ruleset that blocks force-push and requires CI status checks to pass before merge | L2 |
| VCS-4 | Releases are tagged with semantic version tags (`vX.Y.Z`) | L2 |
| VCS-5 | The commit message format is enforced by a hook or a CI check | L3 |

**Evidence:** GitHub ruleset settings, `git log`, tags, commitlint or equivalent config.

### QUA — Code quality

| ID | Criterion | Level |
|---|---|---|
| QUA-1 | A formatter is configured and runs through `just fmt` (for example `gofmt`/`goimports`, `ruff format`, `prettier` or `biome`) | L1 |
| QUA-2 | A linter is configured with its config committed, and runs through `just lint` (for example `golangci-lint`, `ruff`, `eslint` or `biome`) | L1 |
| QUA-3 | CI runs `just lint`, and a violation fails the build | L2 |
| QUA-4 | Pre-commit hooks run the formatter and linter locally | L2 |
| QUA-5 | Python static type checking runs in `just lint` in strict mode (`pyright` or `mypy --strict`); TypeScript runs `tsc --noEmit` | L3 |

**Evidence:** `.pre-commit-config.yaml`, linter config files, `justfile`, CI workflow.

### TST — Testing

| ID | Criterion | Level |
|---|---|---|
| TST-1 | Automated tests exist | L1 |
| TST-2 | `just test` runs the full test suite | L1 |
| TST-3 | CI runs the tests on every push and pull request | L2 |
| TST-4 | Critical paths are identified and covered, or line coverage is at least 60% | L2 |
| TST-5 | CI reports coverage, with a threshold that fails the build | L3 |
| TST-6 | External interfaces (APIs, databases, CLIs) have integration or end-to-end tests | L3 |

**Evidence:** test directories, `justfile`, CI workflow, coverage reports.

### CI — CI/CD

| ID | Criterion | Level |
|---|---|---|
| CI-1 | GitHub Actions workflows are committed in `.github/workflows/` | L1 |
| CI-2 | CI runs `just check` and `just build` on every push and pull request; workflows call `just` recipes rather than duplicating their commands | L1 |
| CI-3 | The pipeline completes in under 10 minutes | L2 |
| CI-4 | Release and deployment are automated: Fly.io and Cloudflare targets deploy from a workflow; Kubernetes targets publish the image and chart, and ArgoCD syncs them | L2 |
| CI-5 | Every third-party action is pinned to a full commit SHA | L2 |
| CI-6 | Every workflow sets `permissions:` explicitly, with least privilege | L2 |
| CI-7 | No manual step sits between merge and deploy or release | L3 |

**Evidence:** `.github/workflows/`, ArgoCD Application definitions.

### DEP — Dependency management

| ID | Criterion | Level |
|---|---|---|
| DEP-1 | A lockfile is committed: `go.sum`, `uv.lock` (or `poetry.lock`), `package-lock.json` or `pnpm-lock.yaml` | L1 |
| DEP-2 | Renovate is configured with `renovate.json` (or `.github/renovate.json5`) and is opening PRs | L1 |
| DEP-3 | Renovate covers every ecosystem in the repo: language packages, Dockerfile base images, GitHub Actions, Helm chart dependencies, Dev Container features, and the tool versions pinned in the `justfile`. Renovate has `hostRules` credentials for `dhi.io` so it can update hardened base images | L2 |
| DEP-4 | Every dependency is pinned to an exact version: no `^`, `~`, `>=`, `*`, `latest`, bare major tags or unversioned entries. This covers language packages (`==` in `pyproject.toml`; exact versions in `package.json` with `save-exact=true` in `.npmrc`; Go `go.mod` versions are exact by design), Docker image tags, Helm chart dependencies, Dev Container images and features, and tool versions. Renovate sets `rangeStrategy: "pin"`. **Library exception:** published dependency metadata (`pyproject.toml` `dependencies`, `package.json` `dependencies` and `peerDependencies`) uses bounded ranges; dev dependencies and the lockfile are exact | L1 |
| DEP-5 | The repo has no unused dependencies | L2 |
| DEP-6 | Renovate automerges patch and minor updates once CI passes | L3 |
| DEP-7 | Base images are pinned by digest, and Renovate maintains the digests | L3 |

**Evidence:** lockfiles, `pyproject.toml`, `package.json`, `.npmrc`, Renovate config, Renovate PR history, Dockerfiles, `.devcontainer/`, `Chart.yaml`.

### SEC — Security

| ID | Criterion | Level |
|---|---|---|
| SEC-1 | Git history contains no secrets. Secrets are held in 1Password and injected through External Secrets Operator (Kubernetes), `fly secrets` (Fly.io), or Wrangler secrets (Cloudflare) | L1 |
| SEC-2 | Secret scanning runs in CI or in pre-commit (for example `gitleaks`) | L2 |
| SEC-3 | CI runs a dependency vulnerability scan: `govulncheck`, `pip-audit`, `npm audit` or Trivy | L2 |
| SEC-4 | Containers run as a non-root user, with a read-only root filesystem wherever possible | L2 |
| SEC-5 | Credentials, API tokens and service accounts are scoped to least privilege | L2 |
| SEC-6 | CI scans container images, and the build fails on any critical vulnerability that has a fix available | L3 |

**Evidence:** `gitleaks` output, CI workflow, Dockerfile `USER`, Helm `securityContext`, ExternalSecret manifests, token scopes.

### BLD — Build and packaging

| ID | Criterion | Level |
|---|---|---|
| BLD-1 | `just build` produces the release artefact | L1 |
| BLD-2 | Artefacts are versioned with semantic versioning | L2 |
| BLD-3 | Container images are tagged with both the version and the commit SHA, and the deployed reference is never `latest` | L2 |
| BLD-4 | A multi-stage Dockerfile builds the image, and the final (runtime) stage is `FROM` a Docker Hardened Images runtime variant on `dhi.io`, never a `-dev` variant. Go binaries use `dhi.io/static`; `scratch`, `distroless` and Docker Official Images are not used for the runtime stage. Build stages may use DHI `-dev` variants. CI authenticates to `dhi.io` with a Docker access token held as a GitHub Actions secret. N/A for Cloudflare targets | L1 |
| BLD-5 | Builds are reproducible: the same commit produces the same artefact | L3 |

**Evidence:** `justfile`, Dockerfile `FROM` lines, registry tags, release workflow.

### CFG — Configuration and environment

| ID | Criterion | Level |
|---|---|---|
| CFG-1 | Code contains no hard-coded hostnames, credentials or environment-specific values | L1 |
| CFG-2 | Configuration comes from environment variables or config files | L1 |
| CFG-3 | A `justfile` at the repo root defines every recipe that section 2.1 requires for the project type | L1 |
| CFG-4 | `.devcontainer/devcontainer.json` is present, and the project builds and its tests pass inside the container | L1 |
| CFG-5 | The Dev Container installs `just` and every tool the recipes call, at pinned versions, and `postCreateCommand` runs `just setup` | L2 |
| CFG-6 | An example config file is committed (`.env.example` or `config.example.yaml`) that lists every setting | L2 |
| CFG-7 | The application validates config at startup, and exits with a clear error if a value is missing or invalid | L3 |

**Evidence:** source code, `justfile`, `.devcontainer/`, example config files.

### DPL — Deployment

| ID | Criterion | Level |
|---|---|---|
| DPL-1 | The deployment target is Fly.io, Cloudflare Pages / Workers, or the local Kubernetes cluster, and the README names it | L1 |
| DPL-2 | Target configuration is committed: `fly.toml` for Fly.io; `wrangler.toml` or `wrangler.jsonc` for Cloudflare; a Helm chart in `charts/<app>/` for Kubernetes | L1 |
| DPL-3 | Kubernetes only: CI runs `helm lint` and `helm template` on the chart, validating the rendered output with `kubeconform` | L2 |
| DPL-4 | Kubernetes only: `Chart.yaml` `version` follows semver and is bumped on every chart change; `appVersion` tracks the application version; the image tag defaults to `appVersion` | L2 |
| DPL-5 | Kubernetes only: chart templates set resource requests and limits, `securityContext`, and liveness and readiness probes, all configurable through `values.yaml` | L2 |
| DPL-6 | Kubernetes only: an ArgoCD Application references the chart; ArgoCD deploys it, not `helm install` run by hand | L2 |
| DPL-7 | Every `values.yaml` key is documented, either with comments or with a generated README such as `helm-docs` | L3 |
| DPL-8 | Cloudflare and Fly.io only: preview deployments are created for pull requests | L3 |

**Evidence:** `fly.toml`, Wrangler config, `charts/`, ArgoCD Application manifests, CI workflow.

### DAT — Data

Score DAT only for projects that persist relational data. Criteria marked *PostgreSQL only* or *SQLite only* are N/A for projects using the other database.

A **lightweight deployment** is one that meets all three conditions:

- It runs as a single instance with one writer process.
- No other service reads or writes its data.
- Losing data written since the last backup is acceptable.

Any deployment that fails one of these conditions uses PostgreSQL.

| ID | Criterion | Level |
|---|---|---|
| DAT-1 | Relational data is stored in PostgreSQL or SQLite. No other relational database is used (for example MySQL or MariaDB) | L1 |
| DAT-2 | SQLite, including Cloudflare D1, is used only for lightweight deployments, and the README states that the deployment qualifies. SQLite is also allowed for single-user local state in CLIs and for test fixtures | L1 |
| DAT-3 | Schema changes go through versioned migrations committed to the repo, and `just migrate` applies them. Example tools: `goose` or `golang-migrate` for Go, Alembic for Python, `wrangler d1 migrations` for D1 | L1 |
| DAT-4 | Deployment runs migrations automatically before the new version serves traffic: a Helm `pre-upgrade` hook Job on Kubernetes, `release_command` on Fly.io, or a workflow step on Cloudflare | L2 |
| DAT-5 | Every migration has a tested down path, or is documented as forward-only with its recovery procedure | L3 |
| DAT-6 | *PostgreSQL only:* the major version is pinned, and is the same in the Dev Container, in CI and in production | L1 |
| DAT-7 | *PostgreSQL only:* the connection string comes from `DATABASE_URL`, which is sourced from the secret store. The application uses a connection pool: `pgxpool` for Go, `psycopg_pool` or the SQLAlchemy pool for Python, Hyperdrive for Cloudflare Workers | L2 |
| DAT-8 | *PostgreSQL only:* the Dev Container provides PostgreSQL as a Docker Compose service, and integration tests run against a real PostgreSQL instance (that service, or Testcontainers) | L2 |
| DAT-9 | *SQLite only:* the database file is on persistent storage, and only one instance can run at a time. On Kubernetes that means a Longhorn PVC, `replicas: 1` and the `Recreate` deployment strategy. On Fly.io it means a Fly volume with the app scaled to one Machine | L1 |
| DAT-10 | *SQLite only:* the application sets WAL mode, `busy_timeout` and `foreign_keys = ON` on every connection | L2 |
| DAT-11 | *SQLite only:* backups use Litestream, or a scheduled `sqlite3 .backup` or `VACUUM INTO`. The live database file is never copied directly. D1 databases use Time Travel plus a scheduled `wrangler d1 export` | L2 |

**Evidence:** migration directory, `justfile`, Helm hooks and Deployment spec, `fly.toml`, `.devcontainer/` compose file, connection setup code, backup job definitions.

### OBS — Observability

| ID | Criterion | Level |
|---|---|---|
| OBS-1 | Logs go to stdout/stderr with log levels | L1 |
| OBS-2 | Logs are structured: JSON or logfmt (`log/slog` for Go, `structlog` or `logging` with a JSON formatter for Python) | L2 |
| OBS-3 | Long-running services expose health (liveness) and readiness endpoints; Cloudflare Workers are N/A | L2 |
| OBS-4 | Metrics are exposed in Prometheus format | L2 |
| OBS-5 | The repo defines alert rules or dashboards for key failure modes, and failures route to Apprise | L3 |

**Evidence:** logging setup, `/healthz` and `/readyz` handlers, `/metrics`, `PrometheusRule` or dashboard JSON.

### OPS — Operability and data

| ID | Criterion | Level |
|---|---|---|
| OPS-1 | The deploy and rollback procedure for the target platform is documented | L1 |
| OPS-2 | Stateful data is backed up on a schedule | L1 |
| OPS-3 | A backup restore has been tested within the last 6 months, and the date is recorded | L3 |
| OPS-4 | A runbook covers the most likely failure modes | L3 |

**Evidence:** `docs/runbook.md`, backup job definitions, restore test record.

### AGT — AI agent context

| ID | Criterion | Level |
|---|---|---|
| AGT-1 | `CLAUDE.md` (or an equivalent) is present | L1 |
| AGT-2 | The agent file tells the agent to use `just` recipes for build, test, lint and run | L1 |
| AGT-3 | The agent file sets out coding conventions and project-specific patterns | L2 |
| AGT-4 | The agent file lists the files, directories or operations the agent must not change or run | L2 |
| AGT-5 | The agent file is reviewed whenever recipes or conventions change, and its contents match the current repo | L3 |

**Evidence:** `CLAUDE.md`, `AGENTS.md`, `.claude/` directory.

## 6. Assessment process

1. Classify the repository by type (section 3).
2. Use the applicability matrix to remove categories that do not apply.
3. Score each criterion in the remaining categories, and record evidence for every score.
4. Mark an individual criterion N/A only with a written justification.
5. Calculate the category scores, overall score and maturity level (section 4).
6. Record the assessment in `docs/assessment.md` in the repository, or in a central register.
7. Reassess after significant changes, and every 6 months for active projects.

Archived repositories are not assessed.

## 7. Assessment template

```markdown
# Engineering Standards Assessment

- **Repository:** <name>
- **Type:** Service | Library | CLI | Infrastructure
- **Deployment target:** Fly.io | Cloudflare | Kubernetes | none
- **Status:** Active | Maintained
- **Assessed:** YYYY-MM-DD
- **Framework version:** 1.4

## Summary

| Category | Score (%) | Notes |
|---|---|---|
| STK | | |
| DOC | | |
| HYG | | |
| VCS | | |
| QUA | | |
| TST | | |
| CI  | | |
| DEP | | |
| SEC | | |
| BLD | | |
| CFG | | |
| DPL | | |
| DAT | | |
| OBS | | |
| OPS | | |
| AGT | | |

- **Overall score:** <n>
- **Maturity level:** L0 | L1 | L2 | L3
- **Blocking gate criteria:** <IDs preventing the next level>

## Criterion scores

| ID | Score | Evidence / justification |
|---|---|---|
| STK-1 | | |
| ... | | |

## Actions

| ID | Action | Target level |
|---|---|---|
| | | |
```

## 8. Changing the standards

- A change to criteria or to the mandated stack increments the minor version (1.4 → 1.5).
- A change to the scoring model or the levels increments the major version (1.x → 2.0).
- Each assessment records the framework version it was scored against. Assessments cannot be compared across major versions.

## Changelog

- **1.4** — Required exact version pinning for all dependencies (DEP-4), with an exception for libraries' published metadata. Required Docker Hardened Images for production runtime stages (BLD-4, now L1). Added `dhi.io` credentials to the Renovate criterion (DEP-3).
- **1.3** — Removed Kafka. Allowed SQLite (including Cloudflare D1) for lightweight deployments, with SQLite-specific criteria. Renamed DAT to "Data" and renumbered its criteria.
- **1.2** — Mandated PostgreSQL for relational data and Kafka for messaging. Added the DAT category and the `migrate` recipe. Moved the migration criterion from OPS into DAT and renumbered OPS-4 and OPS-5 to OPS-3 and OPS-4.
- **1.1** — Added a mandated stack (Python/Go, TypeScript, `just`, GitHub Actions, Renovate, Fly.io / Cloudflare / Kubernetes, Helm, Dev Containers). Added the STK and DPL categories. Rewrote criteria to reference `just` recipes and the mandated tools. Moved deployment manifests from OPS into DPL. Applied CFG to Library repos.
- **1.0** — Initial version.
