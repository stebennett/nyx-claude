# Scaffold checklist

What `engineering-standards-scaffold` generates, organised by file. Each entry says when it applies,
which criteria it satisfies, and what the file must do. These are requirements, not file contents:
write each file for the project in front of you, at current versions. The criteria themselves live
in `../../engineering-standards-assess/references/standards.md`; when a criterion changes, review
the entries that cite it.

**Worked example.** `${CLAUDE_PLUGIN_ROOT}/scripts/tests/fixtures/exemplary/` is a Go service on
Kubernetes with PostgreSQL that the check scripts score as meeting every offline script criterion.
Use it for the *shape* of the `justfile`, CI workflow, pre-commit, Renovate, Dockerfile and chart.
Its SHAs, digests and versions are placeholders — never copy them.

## Conditions

`type`, `deployment_target`, `database`, `backend` and `frontend` are the decisions-section values.
"Service with a container" means `type: service` and `deployment_target` is `fly` or `kubernetes`.
**Stack-neutral: no** entries are skipped when a kept exemption changes the stack (backend other
than Go/Python, or a database outside the enum); list them as left to the user.

## Version lookup

Pin everything to an exact, current, stable version looked up now (DEP-4). Never invent one.

| What | How |
|---|---|
| Go modules | `go list -m -versions <module>` (last entry), or `curl -s https://proxy.golang.org/<module>/@latest` |
| npm packages | `npm view <pkg> version` |
| PyPI packages | `curl -s https://pypi.org/pypi/<pkg>/json \| jq -r .info.version` |
| Tools (just, golangci-lint, gitleaks, helm, kubeconform …) | `gh api repos/<owner>/<repo>/releases/latest --jq .tag_name`, or `git ls-remote --tags --refs https://github.com/<owner>/<repo>` |
| GitHub Actions | resolve the latest release tag, then `git ls-remote https://github.com/<owner>/<repo> refs/tags/<tag>` for the full SHA; write `uses: <owner>/<repo>@<sha> # <tag>` (CI-5) |
| Image digests | `docker buildx imagetools inspect <image>:<tag>` when Docker is available. `dhi.io` needs a login; if a digest cannot be resolved, pin the tag and report DEP-7 as a gap |
| Toolchains | Go: latest stable from `https://go.dev/dl/?mode=json`; Python: latest stable minor; Node: current LTS |

## Root and tooling

### `justfile`
- **Applies when:** always. **Stack-neutral:** yes (recipes for a skipped stack call a placeholder that exits non-zero with "TODO: <recipe> for <stack>").
- **Satisfies:** CFG-3, QUA-1, QUA-2, QUA-5, TST-2, BLD-1, DAT-3, AGT-2 (with `CLAUDE.md`).
- **Requirements:**
  - Recipes per standards section 2.1 for the type: `default` (`@just --list`), `setup`, `fmt`, `lint`, `test`, `check` (`check: lint test`), `clean` always; `build` for service/library/cli; `run` for service/cli; `migrate` when `database` is not `none`; `deploy` only for `fly`/`cloudflare`.
  - `lint` includes a format check (e.g. `test -z "$(gofmt -l .)"`, `ruff format --check`, `prettier --check`) and strict type checking (pyright strict / `tsc --noEmit`).
  - `test` writes coverage output for TST-5.
  - With backend and frontend both present, each recipe runs both (e.g. `lint: lint-go lint-web`).

### `.devcontainer/devcontainer.json` (+ `.devcontainer/compose.yaml` with PostgreSQL)
- **Applies when:** always; the compose file when `database: postgresql`. **Stack-neutral:** yes.
- **Satisfies:** CFG-4, CFG-5, DAT-6, DAT-8.
- **Requirements:** image or features pinned to exact versions (DEP-4); installs `just` and every tool the recipes call at pinned versions; `"postCreateCommand": "just setup"`. With PostgreSQL: compose service `postgres:<major.minor>` with the same major as CI and production, and `DATABASE_URL` set for the app container.

### `.gitignore`
- **Applies when:** always. **Stack-neutral:** yes. **Satisfies:** HYG-1, HYG-2.
- **Requirements:** build output (`bin/`, `dist/`, `build/`, coverage files), local env (`.env`, `.env.*` but not `.env.example`), editor files (`.vscode/`, `.idea/`, `*.swp`, `.DS_Store`), dependency dirs (`node_modules/`, `.venv/`).

### `.editorconfig`
- **Applies when:** always. **Stack-neutral:** yes. **Satisfies:** HYG-5.

### `.pre-commit-config.yaml`
- **Applies when:** always. **Stack-neutral:** yes (formatter/linter hooks only for generated stacks).
- **Satisfies:** QUA-4, SEC-2, VCS-5.
- **Requirements:** hooks for the formatter and linter of each language; `gitleaks`; a Conventional Commits commit-msg hook (e.g. `conventional-pre-commit`). Pin each hook `rev` exactly. `just setup` installs the hooks.

## Languages

### Go — `go.mod`, `go.sum`, `cmd/<name>/main.go`, `internal/`, `.golangci.yml`
- **Applies when:** `backend: go`. **Stack-neutral:** no.
- **Satisfies:** STK-1, STK-4, HYG-4, QUA-1, QUA-2, DEP-1, DEP-4.
- **Requirements:** `go` directive and `toolchain` line; module path from the GitHub repo if known, else ask; `cmd/<name>/` entry point and code under `internal/`; `golangci-lint` config committed; `go.sum` produced by `go mod tidy`. Library type: packages at the root or `pkg/`, no `cmd/` unless it ships a binary.

### Python — `pyproject.toml`, `.python-version`, `src/<package>/`, `uv.lock`
- **Applies when:** `backend: python`. **Stack-neutral:** no.
- **Satisfies:** STK-1, STK-4, HYG-4, QUA-1, QUA-2, QUA-5, DEP-1, DEP-4.
- **Requirements:** `requires-python` and `.python-version`; `src/<package>/` layout; `ruff` (format + lint) and `pyright` in strict mode configured in `pyproject.toml`; dependencies pinned with `==` (library type: bounded ranges for published `dependencies`, exact dev dependencies); `uv.lock` committed.

### TypeScript — `package.json`, lockfile, `.nvmrc`, `.npmrc`, `tsconfig.json`, linter/formatter config, `src/`
- **Applies when:** `frontend` is not `none`, or a TypeScript-only library/CLI. **Stack-neutral:** no.
- **Satisfies:** STK-2, STK-3, STK-4, HYG-4, QUA-1, QUA-2, QUA-5, DEP-1, DEP-4.
- **Requirements:** start from the chosen framework's minimal official starter, then: `engines.node` plus `.nvmrc`; `.npmrc` with `save-exact=true`; exact versions in `package.json`; `"strict": true`; no hand-written `.js`/`.jsx` (config JS is fine); eslint/prettier or biome; a test runner with one passing test.
- **Layout with a backend too:** backend at the repo root per its language; frontend under `web/` with its own `package.json` and `web/src/`.

## CI

### `.github/workflows/ci.yml`
- **Applies when:** always. **Stack-neutral:** yes (steps for skipped stacks omitted).
- **Satisfies:** CI-1, CI-2, CI-5, CI-6, QUA-3, TST-3, TST-5, SEC-2, SEC-3, SEC-6, DAT-6, BLD-4 (dhi.io login), DPL-3.
- **Requirements:**
  - Triggers: `push` to `main` and `pull_request`. Top-level `permissions: contents: read`; widen per job only where needed.
  - Every action pinned to a full SHA with the tag as a comment.
  - Steps call recipes: `just check`, `just build` — never duplicate their commands.
  - Coverage reported with a failing threshold (e.g. `go-test-coverage`, `pytest --cov-fail-under`, vitest thresholds); start at 60%.
  - `gitleaks` scan; a vulnerability scan per ecosystem (`govulncheck`, `pip-audit`, `npm audit --audit-level=high`).
  - Container builds: log in to `dhi.io` with `docker/login-action` using secrets `DHI_USERNAME`/`DHI_TOKEN` (not created by scaffold), and scan the built image with Trivy, `severity: CRITICAL`, `ignore-unfixed: true`, `exit-code: 1`.
  - PostgreSQL: a `postgres:<same major.minor>` service for integration tests.
  - Kubernetes: `helm lint charts/<app>` and `helm template charts/<app> | kubeconform -strict`.

### `.github/workflows/deploy.yml`
- **Applies when:** `deployment_target` is `fly` or `cloudflare`. **Stack-neutral:** yes.
- **Satisfies:** CI-4, CI-7, DAT-4 (Cloudflare: migrations step), DPL-8.
- **Requirements:** on push to `main`, run `just deploy` with the platform token from secrets (`FLY_API_TOKEN` / `CLOUDFLARE_API_TOKEN`); on pull requests, a preview deployment. Least-privilege `permissions`, SHA-pinned actions.

### Kubernetes release workflow (in `ci.yml` or `release.yml`)
- **Applies when:** `deployment_target: kubernetes`. **Stack-neutral:** yes.
- **Satisfies:** CI-4, BLD-2, BLD-3.
- **Requirements:** on a `vX.Y.Z` tag, build and push the image tagged with the version and the commit SHA, and package/push the chart; `packages: write` only on that job.

## Dependencies

### `renovate.json`
- **Applies when:** always. **Stack-neutral:** yes.
- **Satisfies:** DEP-2 (config only), DEP-3, DEP-4, DEP-6, DEP-7.
- **Requirements:** `"rangeStrategy": "pin"`; managers for every ecosystem present (language packages, Dockerfile, GitHub Actions, Helm, Dev Container features, and a `customManagers` regex for tool versions pinned in the `justfile`/Dev Container); `hostRules` for `dhi.io` referencing an encrypted or app-level secret, never a literal credential; `packageRules` automerging `minor` and `patch`; digest pinning enabled for Docker. Library type: `rangeStrategy: "widen"` scoped to published dependencies.

## Container and deploy

### `Dockerfile` (+ `.dockerignore`)
- **Applies when:** service with a container. **Stack-neutral:** no.
- **Satisfies:** BLD-4, SEC-4, DEP-7.
- **Requirements:** multi-stage; build stage may use a `dhi.io/<lang>:<ver>-dev` image; runtime stage `FROM` a non-dev `dhi.io` variant — `dhi.io/static` for Go, `dhi.io/python:<ver>` for Python — pinned by tag and digest; runs as a non-root `USER`; no `scratch`, `distroless` or Docker Official Images in the runtime stage.

### `charts/<app>/` — `Chart.yaml`, `values.yaml`, `templates/`
- **Applies when:** `deployment_target: kubernetes`. **Stack-neutral:** yes, except the image reference.
- **Satisfies:** DPL-2, DPL-4, DPL-5, DPL-7, SEC-4, DAT-4, DAT-9, OBS-3.
- **Requirements:** `Chart.yaml` `version: 0.1.0`, `appVersion` equal to the app version; image tag defaults to `.Chart.AppVersion`; Deployment with resource requests/limits, pod and container `securityContext` (`runAsNonRoot`, `readOnlyRootFilesystem: true`), liveness on `/healthz` and readiness on `/readyz`, all set from `values.yaml`; every `values.yaml` key commented. Database: a migration Job annotated `helm.sh/hook: pre-install,pre-upgrade`, and `DATABASE_URL` from an `ExternalSecret`. SQLite: a Longhorn PVC, `replicas: 1`, `strategy: Recreate`.

### `fly.toml`
- **Applies when:** `deployment_target: fly`. **Stack-neutral:** yes.
- **Satisfies:** DPL-2, DAT-4, DAT-9, OBS-3.
- **Requirements:** HTTP health check on `/healthz`; `[deploy] release_command` running migrations when there is a database; SQLite: a `[mounts]` volume and a note in the README that the app is scaled to one Machine.

### `wrangler.toml`
- **Applies when:** `deployment_target: cloudflare`. **Stack-neutral:** yes.
- **Satisfies:** DPL-2, DAT-3 (D1 migrations directory).
- **Requirements:** Pages or Worker config as the frontend/backend dictates; D1 binding and `migrations_dir` when `database: d1`. `BLD-4` and `OBS-3` are N/A for Workers and Pages.

## Walking skeleton

### Service
- **Applies when:** `type: service`. **Stack-neutral:** no.
- **Satisfies:** TST-1, TST-2, CFG-1, CFG-2, CFG-7, OBS-1, OBS-2, OBS-3, OBS-4, DAT-3, DAT-7, DAT-10.
- **Requirements:**
  - Config read from environment variables into one typed config object, validated at startup; a missing or invalid value exits non-zero with a message naming the variable. No hard-coded hosts or credentials.
  - Structured logging to stdout with levels (`log/slog` JSON handler; `structlog` or `logging` with a JSON formatter).
  - HTTP server on `PORT` with `/healthz` (process alive) and `/readyz` (dependencies reachable, e.g. a DB ping), plus `/metrics` in Prometheus format.
  - PostgreSQL: a pool from `DATABASE_URL` (`pgxpool`, `psycopg_pool`/SQLAlchemy pool); SQLite: every connection sets `journal_mode=WAL`, `busy_timeout`, `foreign_keys=ON`.
  - Migrations directory with one empty initial migration, applied by `just migrate` with the chosen tool.
  - Tests: one unit test of config validation (missing variable → error) and one handler test of `/healthz`.
- **Static frontend-only site** (`backend: none`): the framework starter page and one component test; no health endpoints.

### Library
- **Applies when:** `type: library`. **Stack-neutral:** no.
- **Satisfies:** TST-1, TST-2, BLD-1, BLD-2.
- **Requirements:** one exported function relevant to the spec's domain with a doc comment and a test; `just build` produces the package (`go build ./...` + module tag, `uv build`, `npm pack`); version `0.1.0`.

### CLI
- **Applies when:** `type: cli`. **Stack-neutral:** no.
- **Satisfies:** TST-1, TST-2, BLD-1, CFG-2, OBS-1.
- **Requirements:** one command with `--version` and `--help`, logging to stderr with levels, a test of `--version`; `just build` produces the binary or package.

## Docs and agent context

### `README.md`
- **Applies when:** always. **Stack-neutral:** yes.
- **Satisfies:** DOC-1, DOC-2, DOC-3 (if unlicensed), HYG-3, DPL-1, DAT-2, OPS-1.
- **Requirements:** first paragraph says what the project is and why it exists, taken from the spec; `Status: active` (or the decided status); "Getting started": open the Dev Container, then `just setup`, `just run`, `just test`; the deployment target by name; for SQLite/D1, a statement that the deployment meets the three lightweight conditions; a "Deploy and rollback" section for the target (ArgoCD sync/rollback; `fly deploy` / `fly releases` rollback; `wrangler deploy` / rollback); a link to the spec.

### `LICENSE`
- **Applies when:** the user chose a licence (ask: a named licence, or private and unlicensed). If unlicensed, the README states it and no file is written. **Satisfies:** DOC-3.

### `.env.example`
- **Applies when:** the walking skeleton reads any setting. **Stack-neutral:** yes. **Satisfies:** CFG-6.
- **Requirements:** every variable the config object reads, with a safe placeholder and a comment; no real secrets.

### `CLAUDE.md`
- **Applies when:** always. **Stack-neutral:** yes. **Satisfies:** AGT-1, AGT-2, AGT-3, AGT-4.
- **Requirements:** tells the agent to use `just` recipes for build, test, lint and run (list them); coding conventions for the chosen languages and frameworks (layout, logging, config, error handling, test placement); project-specific patterns from the spec; a "Do not change" list (`.nyx.yml` engineering_standards section — use classify; `migrations/` already applied; `charts/<app>/Chart.yaml` version without bumping; lockfiles by hand); a pointer to the spec and to `docs/adr/`.

### `docs/adr/0001-technology-choices.md`
- **Applies when:** always. **Stack-neutral:** yes. **Satisfies:** DOC-4.
- **Requirements:** Cognitect format (Title, Status: Accepted, Context, Decision, Consequences); records the decisions table — the constrained and open choices with their reasons — and every exemption with its criterion and reason.

## Out of scope for scaffold (report as follow-ups)

VCS-3 (ruleset), the `dhi.io` Actions secrets, installing the Renovate app (DEP-2 "opening PRs"),
the ArgoCD Application in the GitOps repo (DPL-6), CI-3 (needs real runs), OPS-2/OPS-3/OPS-4,
OBS-5, DOC-5/DOC-6, and VCS-4 release tags.
