#!/usr/bin/env bash
# Tests for checks/group-*.sh against two repos: the committed "exemplary"
# fixture (meets every scripted criterion that can be verified offline) and a
# bare repo built here (meets almost nothing). gh is disabled with ES_NO_GH so
# results never depend on the machine's GitHub auth.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/helpers.bash"
checks="$here/../checks"
export ES_NO_GH=1
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

git_repo() { # <dir> — commit everything with Conventional Commit messages
  ( cd "$1"
    git init -q -b main
    git -c user.name=t -c user.email=t@example.com add -A
    git -c user.name=t -c user.email=t@example.com commit -qm "feat: initial import"
    git -c user.name=t -c user.email=t@example.com commit -qm "chore: empty" --allow-empty
    git tag v1.2.0 )
}
run_all() { # <dir> -> merged records
  for g in 1 2 3 4 5; do bash "$checks/group-$g.sh" "$1"; done | jq -s 'add'
}
expect() { # <records> <label> <id=score>...
  local recs="$1" label="$2" pair id want
  shift 2
  for pair in "$@"; do
    id="${pair%%=*}"; want="${pair#*=}"
    assert_eq "$label $id" "$want" "$(score_of "$recs" "$id")"
  done
}

# --- exemplary ------------------------------------------------------------------
cp -R "$here/fixtures/exemplary" "$work/ex"
git_repo "$work/ex"
ex="$(run_all "$work/ex")"

# Every script criterion is emitted exactly once, and nothing else.
want_ids="$(jq -r '.criteria[] | select(.method == "script") | .id' "$here/../../skills/engineering-standards-assess/references/rubric.json" | sort)"
assert_eq "one record per script criterion" "$want_ids" "$(printf '%s' "$ex" | jq -r '.[].id' | sort)"
assert_eq "records are well-formed" "true" "$(printf '%s' "$ex" | jq 'all(.[]; (.score == "N/A" or (.score | IN(0, 1, 2))) and (.evidence | length > 0) and .source == "script")')"

expect "$ex" exemplary \
  STK-1=2 STK-2=N/A STK-3=N/A STK-4=2 DOC-3=2 HYG-1=2 HYG-2=2 HYG-4=2 HYG-5=2 AGT-1=2 AGT-2=2 \
  VCS-2=2 VCS-4=2 VCS-5=2 CI-1=2 CI-2=2 CI-5=2 CI-6=2 \
  DEP-1=2 DEP-4=2 DEP-6=2 DEP-7=2 \
  QUA-1=2 QUA-2=2 QUA-3=2 QUA-4=2 QUA-5=N/A TST-2=2 TST-3=2 TST-5=2 BLD-1=2 BLD-4=2 \
  SEC-2=2 SEC-3=2 SEC-4=2 SEC-6=2 CFG-3=2 CFG-4=2 CFG-5=2 \
  DPL-2=2 DPL-3=2 DPL-4=2 DPL-5=2 DPL-6=2 DAT-3=2 DAT-4=2 DAT-6=2 OBS-3=2 OBS-4=2

# Without gh, GitHub-state criteria are scored conservatively and flagged.
for id in VCS-1 VCS-3 CI-3 DEP-2; do
  assert_eq "offline $id flagged unverified" "true" "$(printf '%s' "$ex" | jq --arg id "$id" '.[] | select(.id == $id) | .unverified')"
done
expect "$ex" offline VCS-1=1 VCS-3=0 CI-3=0 DEP-2=1

# --- partial: break specific things in a copy of the exemplary repo --------------
cp -R "$here/fixtures/exemplary" "$work/part"
( cd "$work/part"
  sed -i.bak 's#actions/checkout@[0-9a-f]*#actions/checkout@v4#' .github/workflows/ci.yml
  sed -i.bak '/^permissions:/,/contents: read/d' .github/workflows/ci.yml
  sed -i.bak 's#^FROM dhi.io/static:.*#FROM alpine:3.20#' Dockerfile
  sed -i.bak '/^migrate:/,/^$/d' justfile
  rm -f .editorconfig LICENSE renovate.json ./*.bak .github/workflows/*.bak
  printf 'node_modules/\n' > .gitignore )
git_repo "$work/part"
part="$(run_all "$work/part")"
expect "$part" partial \
  CI-5=1 CI-6=0 BLD-4=0 SEC-4=0 HYG-5=0 DOC-3=0 HYG-1=1 CFG-3=1 DAT-3=1 DEP-2=0 DEP-6=0 DEP-7=1

# --- JSONC: devcontainer.json with comments and trailing commas still parses ---
cp -R "$here/fixtures/exemplary" "$work/jsonc"
cat > "$work/jsonc/.devcontainer/devcontainer.json" <<'JSONC'
{
  // comment line
  "name": "x", // trailing comment
  "dockerComposeFile": "compose.yaml",
  "features": {
    "ghcr.io/guiyomh/features/just:0.1.0": {},
  },
  "postCreateCommand": "just setup",
}
JSONC
git_repo "$work/jsonc"
assert_eq "JSONC devcontainer: CFG-5" "2" "$(score_of "$(bash "$checks/group-4.sh" "$work/jsonc" < /dev/null)" CFG-5)"

# --- monorepo: workspace manifests are checked, not just the root ones ---
mkdir -p "$work/mono/apps/api/src/app" "$work/mono/apps/web/src"
printf '[tool.uv.workspace]\nmembers = ["apps/*"]\n' > "$work/mono/pyproject.toml"
printf '[project]\nrequires-python = ">=3.12"\ndependencies = ["fastapi>=0.110"]\n' > "$work/mono/apps/api/pyproject.toml"
printf '' > "$work/mono/apps/api/src/app/__init__.py"
printf '{"dependencies":{"react":"^18.0.0"}}\n' > "$work/mono/apps/web/package.json"
printf 'export {}\n' > "$work/mono/apps/web/src/main.ts"
printf 'export {}\n' > "$work/mono/apps/web/vite.config.ts"
printf 'export {}\n' > "$work/mono/apps/web/app.test.ts"
printf 'version = 1\n' > "$work/mono/uv.lock"
printf 'engineering_standards:\n  type: service\n  deployment_target: none\n  database: none\n' > "$work/mono/.nyx.yml"
# CI calls `just coverage`; the threshold lives in that recipe, not in the workflow.
printf 'test:\n    uv run pytest\n\ncoverage:\n    uv run coverage report --fail-under=80\n' > "$work/mono/justfile"
mkdir -p "$work/mono/.github/workflows"
printf 'on: [push, pull_request]\njobs:\n  t:\n    steps:\n      - run: just coverage\n' > "$work/mono/.github/workflows/ci.yml"
git_repo "$work/mono"
mono="$(run_all "$work/mono")"
assert_contains "DEP-4 sees workspace pyproject" "apps/api/pyproject.toml:fastapi>=0.110" "$(printf '%s' "$mono" | jq -r '.[] | select(.id == "DEP-4") | .evidence')"
assert_contains "DEP-4 sees workspace package.json" "apps/web/package.json:react@^18.0.0" "$(printf '%s' "$mono" | jq -r '.[] | select(.id == "DEP-4") | .evidence')"
assert_contains "STK-4 flags the workspace root pyproject" "pyproject.toml:requires-python" "$(printf '%s' "$mono" | jq -r '.[] | select(.id == "STK-4") | .evidence')"
expect "$mono" monorepo HYG-4=2 TST-5=2
assert_contains "DEP-1 finds root uv.lock but not a JS lockfile" "missing: package-lock.json/pnpm-lock.yaml" "$(printf '%s' "$mono" | jq -r '.[] | select(.id == "DEP-1") | .evidence')"

# --- bare --------------------------------------------------------------------------
mkdir -p "$work/bare"
printf '# bare\n' > "$work/bare/README.md"
printf 'print(1)\n' > "$work/bare/main.py"
printf 'console.log(1)\n' > "$work/bare/app.js"
printf 'engineering_standards:\n  type: service\n  deployment_target: none\n  database: none\n' > "$work/bare/.nyx.yml"
( cd "$work/bare" && git init -q -b main && git -c user.name=t -c user.email=t@example.com add -A \
  && git -c user.name=t -c user.email=t@example.com commit -qm "initial" )
bare="$(run_all "$work/bare")"
expect "$bare" bare \
  STK-2=0 DOC-3=0 HYG-1=0 HYG-4=0 HYG-5=0 AGT-1=0 AGT-2=0 VCS-2=0 VCS-4=0 VCS-5=0 CI-1=0 CI-2=0 \
  CI-5=0 CI-6=0 QUA-1=0 QUA-2=0 QUA-3=0 QUA-4=0 QUA-5=0 TST-2=0 TST-3=0 TST-5=0 BLD-1=0 \
  BLD-4=N/A SEC-2=0 SEC-3=0 SEC-4=N/A CFG-3=0 CFG-4=0 CFG-5=0 DPL-2=0 DEP-1=N/A DEP-4=N/A DEP-7=N/A

finish
