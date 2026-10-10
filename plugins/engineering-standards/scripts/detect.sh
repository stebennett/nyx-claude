#!/usr/bin/env bash
# detect.sh — gather classification signals for a repository and propose a tag.
#
#   detect.sh <repo>
#
# Prints JSON: {signals, proposed, reasons, existing}. "proposed" is a best guess
# for every tag field; the classify skill confirms each one with the user, so
# these heuristics only need to be a good starting point, not authoritative.
# No pipefail: `... | grep -q` SIGPIPEs its producer on an early match.
set -eu
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
es_require_deps

repo="${1:-}"
[ -n "$repo" ] && [ -d "$repo" ] || es_die 2 "usage: detect.sh <repo>"
cd "$repo"

. "$ES_LIB_DIR/repo.sh"
files="$(repo_files)"

count_ext() { # <extended-regex on path>
  printf '%s\n' "$files" | grep -Ec "$1" || true
}

# Manifests and config anywhere in the tree: monorepos keep one per workspace.
mf="$(manifests go.mod pyproject.toml package.json requirements.txt requirements-dev.txt)"
compose_files="$(files_matching '(^|/)(docker-)?compose[^/]*\.ya?ml$')"
devcontainer_files="$(files_matching '^\.devcontainer/')"
wrangler="$(files_matching '^wrangler\.(toml|jsonc?)$' | head -1)"
charts="$(files_matching '(^|/)Chart\.yaml$' | grep -v node_modules | sed 's#/Chart\.yaml$##' || true)"
dockerfiles="$(files_matching '(^|/)Dockerfile[^/]*$')"
migration_dirs="$(printf '%s\n' "$files" | sed -nE 's#^(.*(migrations|alembic|migrate)[^/]*)/.*#\1#p' | sort -u | head -5)"
k8s_manifests="$(printf '%s\n' "$files" | grep -E '\.ya?ml$' | while IFS= read -r f; do
  grep -Eq '^kind: *(Deployment|StatefulSet|Application|Kustomization|HelmRelease|Service)( |$)' "$f" 2>/dev/null && echo "$f"
done | head -20 || true)"

# Database evidence: driver dependencies, connection strings in config, and
# direct driver use in source. Tests are excluded so fixtures don't count.
config_globs="*.toml *.ini *.example *.env.example *.yaml *.yml *.json"
# shellcheck disable=SC2086 # word-splitting the glob list is intended
pg_hits="$( { printf '%s\n' $mf | while IFS= read -r f; do [ -f "$f" ] && grep -Eqi 'psycopg|asyncpg|jackc/pgx|lib/pq|"pg"|postgres' "$f" && echo "$f"; done
  search_files 'postgres(ql)?(\+[a-z0-9]+)?://|image:[[:space:]]*postgres' $config_globs; } \
  | grep -Ev '(^|/)(tests?|docs?)/' | sort -u | head -5 || true)"
# shellcheck disable=SC2086
sqlite_hits="$( { printf '%s\n' $mf | while IFS= read -r f; do [ -f "$f" ] && grep -Eqi 'sqlite' "$f" && echo "$f"; done
  search_files 'sqlite(\+[a-z0-9]+)?:///|import sqlite3|mattn/go-sqlite3|modernc\.org/sqlite|better-sqlite3' $config_globs '*.py' '*.go' '*.ts'; } \
  | grep -Ev '(^|/)(tests?|docs?)/|(^|/)test_[^/]*$|_test\.go$' | sort -u | head -5 || true)"
d1_hits=""
if [ -n "$wrangler" ]; then d1_hits="$(grep -El 'd1_databases' "$wrangler" || true)"; fi
web_hits="$(printf '%s\n' $mf | while IFS= read -r f; do
  [ -f "$f" ] && grep -Eqi 'fastapi|flask|django|starlette|aiohttp|gin-gonic|labstack/echo|go-chi|gorilla/mux|"express"|"hono"|"next"|"react"|"vite"|"astro"' "$f" && echo "$f"
done || true)"
go_server="$(search_files 'ListenAndServe' '*.go' | head -3)"
py_scripts="$(printf '%s\n' $mf | grep 'pyproject\.toml$' | while IFS= read -r f; do grep -q '^\[project\.scripts\]' "$f" && echo "$f"; done || true)"
pkg_bin="$(printf '%s\n' $mf | grep 'package\.json$' | while IFS= read -r f; do jq -e '.bin' "$f" >/dev/null 2>&1 && echo "$f"; done || true)"
tf_count="$(count_ext '\.tf$')"
readme="$(files_matching '^[Rr][Ee][Aa][Dd][Mm][Ee](\.md)?$' | head -1)"
status_line=""
if [ -n "$readme" ]; then
  status_line="$(grep -Eio '(status)[^a-z]{0,10}(active|maintained|archived)' "$readme" | head -1 || true)"
fi

lines() { printf '%s\n' "$1" | sed '/^$/d' | jq -R . | jq -sc .; }

signals="$(jq -n \
  --argjson go "$(count_ext '\.go$')" \
  --argjson py "$(count_ext '\.py$')" \
  --argjson ts "$(count_ext '\.(ts|tsx|mts|cts)$')" \
  --argjson js "$(count_ext '\.(js|jsx|mjs|cjs)$')" \
  --argjson other "$(count_ext '\.(java|kt|rb|rs|php|cs|scala|ex|exs)$')" \
  --argjson tf "$tf_count" \
  --argjson fly "$( [ -f fly.toml ] && echo true || echo false)" \
  --arg wrangler "$wrangler" \
  --argjson charts "$(lines "$charts")" \
  --argjson k8s "$(lines "$k8s_manifests")" \
  --argjson dockerfiles "$(lines "$dockerfiles")" \
  --argjson migrations "$(lines "$migration_dirs")" \
  --argjson pg "$(lines "$pg_hits")" \
  --argjson sqlite "$(lines "$sqlite_hits")" \
  --argjson d1 "$(lines "$d1_hits")" \
  --argjson web "$(lines "$web_hits")" \
  --argjson goserver "$(lines "$go_server")" \
  --argjson cmd "$(printf '%s\n' "$files" | grep -q '^cmd/' && echo true || echo false)" \
  --argjson pyscripts "$( [ -n "$py_scripts" ] && echo true || echo false)" \
  --argjson pkgbin "$( [ -n "$pkg_bin" ] && echo true || echo false)" \
  --arg status_line "$status_line" \
  '{languages: {go: $go, python: $py, typescript: $ts, javascript: $js, other: $other, terraform: $tf},
    deployment: {fly_toml: $fly, wrangler: $wrangler, charts: $charts, k8s_manifests: $k8s, dockerfiles: $dockerfiles},
    database: {postgresql: $pg, sqlite: $sqlite, d1: $d1, migration_dirs: $migrations},
    shape: {web_frameworks: $web, go_servers: $goserver, cmd_dir: $cmd, python_scripts: $pyscripts, package_bin: $pkgbin},
    readme_status: $status_line}')"

existing="$(es_tag_json .)"

# Heuristic proposal. Each field carries a reason so the user can judge it.
printf '%s' "$signals" | jq --argjson existing "$existing" '
  . as $s |
  ($s.languages | .go + .python + .typescript + .javascript + .other) as $code |
  ([(if $s.deployment.fly_toml then "fly.toml" else empty end),
    (if $s.deployment.wrangler != "" then $s.deployment.wrangler else empty end),
    (if ($s.deployment.charts | length) > 0 then "Helm chart(s) at \($s.deployment.charts | join(", "))"
     elif ($s.deployment.k8s_manifests | length) > 0 then "Kubernetes manifests" else empty end)]) as $found |
  (if ($found | length) > 1 then " — several targets found (\($found | join("; "))); the tag records the production one" else "" end) as $also |
  (if $s.deployment.fly_toml then ["fly", "fly.toml present\($also)"]
   elif $s.deployment.wrangler != "" then ["cloudflare", "\($s.deployment.wrangler) present\($also)"]
   elif ($s.deployment.charts | length) > 0 then ["kubernetes", "Helm chart(s) at \($s.deployment.charts | join(", "))\($also)"]
   elif ($s.deployment.k8s_manifests | length) > 0 then ["kubernetes", "Kubernetes manifests present\($also)"]
   else ["none", "no fly.toml, Wrangler config, Helm chart or Kubernetes manifests"] end) as $target |
  (if ($s.database.d1 | length) > 0 then ["d1", "d1_databases in Wrangler config"]
   elif ($s.database.postgresql | length) > 0 then ["postgresql", "PostgreSQL references in \($s.database.postgresql | join(", "))\(if ($s.database.sqlite | length) > 0 then " (SQLite also referenced in \($s.database.sqlite | join(", ")))" else "" end)"]
   elif ($s.database.sqlite | length) > 0 then ["sqlite", "SQLite references in \($s.database.sqlite | join(", "))"]
   else ["none", "no PostgreSQL, SQLite or D1 references in manifests, config or source"] end) as $db |
  (if $code == 0 and ($s.languages.terraform > 0 or ($s.deployment.k8s_manifests | length) > 0 or ($s.deployment.charts | length) > 0)
     then ["infrastructure", "no application source; manifests, charts or Terraform only"]
   elif $target[0] != "none" or ($s.shape.web_frameworks | length) > 0 or ($s.shape.go_servers | length) > 0
     then ["service", "deployment config or server framework present"]
   elif $s.shape.cmd_dir or $s.shape.python_scripts or $s.shape.package_bin
     then ["cli", "cmd/, [project.scripts] or package.json bin present, no server signals"]
   else ["library", "source code with no deployment, server or entry-point signals"] end) as $type |
  ($s.readme_status | ascii_downcase | capture("(?<v>active|maintained|archived)").v // null) as $st |
  {
    signals: $s,
    proposed: {
      type: $type[0],
      status: ($st // "active"),
      deployment_target: $target[0],
      database: $db[0],
      lightweight: ($db[0] == "sqlite" or $db[0] == "d1"),
      optional_categories: [],
      exemptions: []
    },
    reasons: {
      type: $type[1],
      status: (if $st then "README states status \($st)" else "README does not declare a status; defaulting to active" end),
      deployment_target: $target[1],
      database: $db[1],
      lightweight: (if ($db[0] == "sqlite" or $db[0] == "d1") then "SQLite/D1 is only allowed for lightweight deployments (DAT-2) — confirm single writer, no shared data, backup-loss acceptable" else "not SQLite/D1" end),
      optional_categories: "matrix O categories are scored only when adopted — decide per category",
      exemptions: "none inferred"
    },
    existing: $existing
  }'
