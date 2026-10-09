#!/usr/bin/env bash
# group-3.sh — mechanical checks for QUA, TST and BLD.
#
#   group-3.sh <repo>
#
# Prints a JSON array of criterion records.
# No pipefail: many checks pipe into `grep -q`, which exits on the first match
# and SIGPIPEs the producer; pipefail would turn that race into a false "no".
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/common.sh"
. "$here/../lib/repo.sh"
es_require_deps
repo="${1:-}"; [ -n "$repo" ] && [ -d "$repo" ] || es_die 2 "usage: group-3.sh <repo>"
cd "$repo"

formatters='gofmt|goimports|gofumpt|golangci-lint fmt|ruff format|black|prettier|biome (format|check)|dprint|treefmt|terraform fmt|tofu fmt|shfmt'
linters='golangci-lint|ruff( check)?|eslint|biome (lint|check)|flake8|pylint|tflint|helm lint|yamllint|shellcheck|kube-linter|actionlint|go vet|staticcheck'
format_checks='gofmt -l|gofmt -d|ruff format --check|black --check|prettier (--check|-c)|biome (check|ci)|dprint check|treefmt --fail-on-change|terraform fmt -check|shfmt -d|golangci-lint fmt --diff'
test_runners='go test|gotestsum|pytest|vitest|jest|node --test|playwright|bats|npm (run )?test|pnpm (run )?test|uv run pytest|helm unittest'
build_tools='go build|goreleaser|ko build|uv build|python -m build|hatch build|npm run build|pnpm (run )?build|vite build|tsc|docker (buildx )?build|buildx bake|wrangler (deploy --dry-run|build)|helm package|astro build|next build'

lint_body="$(just_body lint)"
fmt_body="$(just_body fmt)"
test_body="$(just_body test)"
build_body="$(just_body build)"

out="$(mktemp)"; trap 'rm -f "$out"' EXIT
{
# QUA-1 — formatter configured and run by just fmt.
if ! just_has fmt; then es_rec QUA-1 0 "No just fmt recipe"
elif printf '%s' "$fmt_body" | grep -Eq "$formatters"; then
  es_rec QUA-1 2 "just fmt runs: $(printf '%s' "$fmt_body" | grep -Eo "$formatters" | sort -u | summarise 4)"
else es_rec QUA-1 1 "just fmt exists but runs no recognised formatter"
fi

# QUA-2 — linter with committed config, run by just lint, including a format check.
configs="$(files_matching '(^|/)(\.golangci\.ya?ml|\.golangci\.toml|ruff\.toml|\.ruff\.toml|eslint\.config\.[a-z]+|\.eslintrc[^/]*|biome\.jsonc?|\.yamllint[^/]*|\.tflint\.hcl|\.shellcheckrc|\.kube-linter\.ya?ml)$' | grep -v node_modules || true)"
for f in $(manifests pyproject.toml); do
  grep -q '^\[tool\.ruff' "$f" && configs="$configs
$f[tool.ruff]"
done
if ! just_has lint; then es_rec QUA-2 0 "No just lint recipe"
elif ! printf '%s' "$lint_body" | grep -Eq "$linters"; then es_rec QUA-2 1 "just lint exists but runs no recognised linter"
else
  found="$(printf '%s' "$lint_body" | grep -Eo "$linters" | sort -u | summarise 4)"
  has_cfg=false; [ -n "$(printf '%s' "$configs" | sed '/^$/d')" ] && has_cfg=true
  has_fmt_check=false; printf '%s' "$lint_body" | grep -Eq "$format_checks" && has_fmt_check=true
  if $has_cfg && $has_fmt_check; then es_rec QUA-2 2 "just lint runs $found with committed config ($(printf '%s\n' "$configs" | summarise 3)) and a format check"
  else es_rec QUA-2 1 "just lint runs $found; committed linter config: $has_cfg; format check in lint: $has_fmt_check"
  fi
fi

# QUA-3 — CI runs just lint (directly or via just check) and fails on violations.
qua3="$(wf_grep 'just +(lint|check)')"
if [ -n "$qua3" ]; then es_rec QUA-3 2 "CI runs just lint/check: $(printf '%s\n' "$qua3" | summarise 3)"
else es_rec QUA-3 0 "No workflow runs just lint or just check"
fi

# QUA-4 — pre-commit hooks run formatter and linter.
hookcfg="$(first_of .pre-commit-config.yaml lefthook.yml lefthook.yaml .lefthook.yml .husky/pre-commit || true)"
if [ -z "$hookcfg" ]; then es_rec QUA-4 0 "No pre-commit hook configuration"
else
  f=false; l=false
  grep -Eiq "$formatters|ruff-format|just fmt|just check|just lint|trailing-whitespace|end-of-file" "$hookcfg" && f=true
  grep -Eiq "$linters|just lint|just check" "$hookcfg" && l=true
  if $f && $l; then es_rec QUA-4 2 "$hookcfg runs formatter and linter"
  else es_rec QUA-4 1 "$hookcfg present; formatter: $f, linter: $l"
  fi
fi

# QUA-5 — strict static type checking in just lint (Python: pyright/mypy --strict; TS: tsc --noEmit).
ok=""; bad=""
if lang_python; then
  if printf '%s' "$lint_body" | grep -Eq 'mypy.*--strict'; then ok="$ok mypy--strict"
  elif printf '%s' "$lint_body" | grep -Eq 'pyright|basedpyright'; then
    if grep -Eqs 'typeCheckingMode"?[[:space:]]*[=:][[:space:]]*"strict"' /dev/null $(manifests pyproject.toml pyrightconfig.json); then ok="$ok pyright-strict"
    else bad="$bad pyright-not-strict"; fi
  elif printf '%s' "$lint_body" | grep -q 'mypy' && grep -Eqs '^strict[[:space:]]*=[[:space:]]*true' /dev/null $(manifests pyproject.toml mypy.ini); then ok="$ok mypy-strict-config"
  else bad="$bad python-type-check-missing"; fi
fi
if lang_ts; then
  if printf '%s' "$lint_body" | grep -Eq '(vue-)?tsc.*--noEmit|tsc -b|tsc --build'; then ok="$ok tsc--noEmit"
  else bad="$bad tsc--noEmit-missing"; fi
fi
if [ -z "$ok$bad" ]; then es_rec QUA-5 N/A "No Python or TypeScript"
elif [ -z "$bad" ]; then es_rec QUA-5 2 "just lint type-checks:$ok"
elif [ -n "$ok" ]; then es_rec QUA-5 1 "Type-checked:$ok; gaps:$bad"
else
  case "$bad" in *pyright-not-strict*) es_rec QUA-5 1 "Type checking without strict mode:$bad" ;;
    *) es_rec QUA-5 0 "No strict type checking in just lint:$bad" ;; esac
fi

# TST-2 — just test runs the suite.
if ! just_has test; then es_rec TST-2 0 "No just test recipe"
elif printf '%s' "$test_body" | grep -Eq "$test_runners"; then
  es_rec TST-2 2 "just test runs: $(printf '%s' "$test_body" | grep -Eo "$test_runners" | sort -u | summarise 3)"
else es_rec TST-2 1 "just test exists but runs no recognised test runner"
fi

# TST-3 — CI runs tests on every push and pull request.
tst3="$(wf_runs_on_push_and_pr 'just +(test|check)')"
case "$tst3" in
  both) es_rec TST-3 2 "CI runs just test/check on push and pull_request" ;;
  partial) es_rec TST-3 1 "CI runs just test/check, but not on both push and pull_request" ;;
  *) es_rec TST-3 0 "No workflow runs just test or just check" ;;
esac

# TST-5 — CI reports coverage with a failing threshold.
# What CI actually runs: workflow text plus the body of every recipe it invokes.
ci_text="$(cat /dev/null $(workflows))"
for r in $(printf '%s\n' "$ci_text" | sed -nE 's/.*just +([A-Za-z_][A-Za-z0-9_-]*).*/\1/p' | sort -u); do
  just_has "$r" && ci_text="$ci_text
$(just_body "$r")"
done
threshold="$( { printf '%s\n' "$test_body"; printf '%s\n' "$ci_text"; } | grep -Eo -- '--cov-fail-under[= ]?[0-9]+|fail_under|coverageThreshold|go-test-coverage|--fail-under[= ]?[0-9]+|thresholds' | head -1 || true)"
[ -z "$threshold" ] && threshold="$(grep -Eohs 'fail_under|coverageThreshold|thresholds:' /dev/null $(manifests pyproject.toml .coveragerc package.json vitest.config.ts vitest.config.mts jest.config.ts jest.config.js .testcoverage.yml) | head -1 || true)"
coverage="$( { printf '%s\n' "$test_body"; printf '%s\n' "$ci_text"; } | grep -Eo -- '--cov|coverprofile|--coverage|coverage (run|report)|c8 |nyc ' | head -1 || true)"
if [ -n "$threshold" ] && [ -n "$coverage" ]; then es_rec TST-5 2 "Coverage measured ($coverage) with a failing threshold ($threshold)"
elif [ -n "$coverage" ]; then es_rec TST-5 1 "Coverage measured ($coverage) but no failing threshold found"
else es_rec TST-5 0 "No coverage measurement in just test or CI"
fi

# BLD-1 — just build produces the release artefact.
if ! just_has build; then es_rec BLD-1 0 "No just build recipe"
elif printf '%s' "$build_body" | grep -Eq "$build_tools"; then
  es_rec BLD-1 2 "just build runs: $(printf '%s' "$build_body" | grep -Eo "$build_tools" | sort -u | summarise 3)"
else es_rec BLD-1 1 "just build exists but runs no recognised build tool"
fi

# BLD-4 — multi-stage Dockerfile with a DHI runtime stage; CI logs in to dhi.io.
dfs="$(dockerfiles)"
target="$(tag_field deployment_target)"
if [ -z "$dfs" ]; then
  if [ "$target" = kubernetes ] || [ "$target" = fly ]; then es_rec BLD-4 0 "Deploys to $target but has no Dockerfile"
  else es_rec BLD-4 N/A "No container image is built"
  fi
else
  problems=""
  for d in $dfs; do
    final="$(docker_final_image "$d")"
    [ "$(docker_stage_count "$d")" -ge 2 ] || problems="$problems
$d: single-stage"
    case "$final" in
      dhi.io/*-dev*|dhi.io/*:*-dev*) problems="$problems
$d: runtime stage is a -dev variant ($final)" ;;
      dhi.io/*) if lang_go && ! lang_python && ! lang_node && [ "${final%%:*}" != dhi.io/static ]; then problems="$problems
$d: Go runtime should be dhi.io/static ($final)"; fi ;;
      *) problems="$problems
$d: runtime stage is not dhi.io ($final)" ;;
    esac
  done
  login="$(wf_grep 'registry:[[:space:]]*["'\'']?dhi\.io|docker login.*dhi\.io')"
  [ -n "$login" ] || problems="$problems
CI: no docker login to dhi.io"
  hard="$(printf '%s\n' "$problems" | grep -E 'not dhi.io|-dev variant' || true)"
  if [ -z "$(printf '%s' "$problems" | sed '/^$/d')" ]; then es_rec BLD-4 2 "Multi-stage builds with DHI runtime stages; CI logs in to dhi.io"
  elif [ -z "$hard" ]; then es_rec BLD-4 1 "DHI runtime, but: $(printf '%s\n' "$problems" | summarise 4)"
  else es_rec BLD-4 0 "$(printf '%s\n' "$problems" | summarise 4)"
  fi
fi
} > "$out"
jq -s . "$out"
