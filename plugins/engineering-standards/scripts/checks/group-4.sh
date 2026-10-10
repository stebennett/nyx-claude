#!/usr/bin/env bash
# group-4.sh — mechanical checks for SEC and CFG.
#
#   group-4.sh <repo>
#
# Prints a JSON array of criterion records.
# No pipefail: many checks pipe into `grep -q`, which exits on the first match
# and SIGPIPEs the producer; pipefail would turn that race into a false "no".
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/common.sh"
. "$here/../lib/repo.sh"
es_require_deps
repo="${1:-}"; [ -n "$repo" ] && [ -d "$repo" ] || es_die 2 "usage: group-4.sh <repo>"
cd "$repo"

wfs="$(workflows)"
dfs="$(dockerfiles)"
charts="$(files_matching '^charts/[^/]+/Chart\.yaml$' | sed 's#/Chart\.yaml$##')"
chart_text() { for c in $charts; do find "$c" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.tpl' \) -exec cat {} +; done; return 0; }

out="$(mktemp)"; trap 'rm -f "$out"' EXIT
{
# SEC-2 — secret scanning in CI or pre-commit.
scanners='gitleaks|trufflehog|detect-secrets|ggshield|secretlint'
where="$( { wf_grep "$scanners"; [ -f .pre-commit-config.yaml ] && grep -Eil "$scanners" .pre-commit-config.yaml; } | summarise 3 || true)"
if [ -n "$where" ]; then es_rec SEC-2 2 "Secret scanning in: $where"
else es_rec SEC-2 0 "No secret scanning in CI or pre-commit"
fi

# SEC-3 — dependency vulnerability scan in CI.
vulns='govulncheck|pip-audit|npm audit|pnpm audit|osv-scanner|trivy (fs|repo|filesystem)|scan-type:[[:space:]]*["'\'']?(fs|repo)|grype dir:|uv-secure|safety check'
found="$(wf_grep "$vulns")"
if [ -n "$found" ]; then es_rec SEC-3 2 "Vulnerability scan in: $(printf '%s\n' "$found" | summarise 3) ($(cat $found | grep -Eo "$vulns" | sort -u | summarise 3))"
else es_rec SEC-3 0 "No dependency vulnerability scan in CI"
fi

# SEC-4 — non-root user and read-only root filesystem.
if [ -z "$dfs$charts" ]; then
  es_rec SEC-4 N/A "No containers built or deployed"
else
  nonroot=true; why=""
  for d in $dfs; do
    final="$(docker_final_image "$d")"
    user="$(awk 'toupper($1) == "FROM" { u = "" } toupper($1) == "USER" { u = $2 } END { print u }' "$d")"
    case "$user" in
      root|0|0:0) nonroot=false; why="$why $d:USER-$user" ;;
      "") case "$final" in dhi.io/*-dev*|dhi.io/*:*-dev*) nonroot=false; why="$why $d:dev-image-runs-as-root" ;;
            dhi.io/*) why="$why $d:DHI-runtime-nonroot-by-default" ;;
            *) nonroot=false; why="$why $d:no-USER" ;; esac ;;
      *) why="$why $d:USER-$user" ;;
    esac
  done
  if [ -n "$charts" ]; then
    ct="$(chart_text)"
    printf '%s' "$ct" | grep -Eq 'runAsNonRoot:[[:space:]]*true|runAsUser:[[:space:]]*[1-9]' && why="$why chart:runAsNonRoot" \
      || { [ -z "$dfs" ] && nonroot=false; why="$why chart:no-runAsNonRoot"; }
    ro=false; printf '%s' "$ct" | grep -Eq 'readOnlyRootFilesystem:[[:space:]]*true' && ro=true
    why="$why chart:readOnlyRootFilesystem=$ro"
  else
    ro=na
  fi
  if ! $nonroot; then es_rec SEC-4 0 "Container may run as root:$why"
  elif [ "$ro" = false ]; then es_rec SEC-4 1 "Non-root, but no read-only root filesystem:$why"
  else es_rec SEC-4 2 "Non-root$( [ "$ro" = true ] && echo ' with read-only root filesystem'):$why"
  fi
fi

# SEC-6 — CI scans images and fails on fixable criticals.
if [ -z "$dfs" ]; then
  es_rec SEC-6 N/A "No container images built"
else
  scan="$(wf_grep 'trivy image|image-ref:|grype |anchore/scan-action|docker scout cves')"
  if [ -z "$scan" ]; then es_rec SEC-6 0 "No container image scan in CI"
  else
    txt="$(cat $scan)"
    crit=false; unfixed=false; fails=false
    printf '%s' "$txt" | grep -Eqi 'CRITICAL|severity-cutoff:[[:space:]]*critical|--only-severity[= ]critical' && crit=true
    printf '%s' "$txt" | grep -Eqi 'ignore-unfixed|only-fixed|--ignore-unfixed|only-fixed:[[:space:]]*true' && unfixed=true
    printf '%s' "$txt" | grep -Eqi "exit-code:[[:space:]]*['\"]?1|--exit-code[= ]1|fail-build:[[:space:]]*true|--fail-on" && fails=true
    if $crit && $unfixed && $fails; then es_rec SEC-6 2 "Image scan fails on fixable criticals in: $(printf '%s\n' "$scan" | summarise 3)"
    else es_rec SEC-6 1 "Image scan present; critical severity: $crit, ignore-unfixed: $unfixed, fails build: $fails"
    fi
  fi
fi

# CFG-3 — justfile defines every recipe section 2.1 requires for this tag.
if [ -z "$(justfile_path || true)" ]; then
  es_rec CFG-3 0 "No justfile at the repo root"
else
  want="$(required_recipes)"
  n_want="$(printf '%s\n' "$want" | sed '/^$/d' | wc -l | tr -d ' ')"
  missing="$(for r in $want; do just_has "$r" || echo "$r"; done)"
  n_missing="$(printf '%s\n' "$missing" | sed '/^$/d' | wc -l | tr -d ' ')"
  default_ok=true
  just_has default && ! just_body default | grep -q -- '--list' && default_ok=false
  if [ "$n_missing" -eq 0 ] && $default_ok; then es_rec CFG-3 2 "All $n_want required recipes defined: $(printf '%s\n' "$want" | tr '\n' ' ')"
  elif [ "$n_missing" -eq 0 ]; then es_rec CFG-3 1 "All required recipes defined, but default does not run just --list"
  elif [ "$n_missing" -lt "$n_want" ] && [ $((n_missing * 2)) -le "$n_want" ]; then es_rec CFG-3 1 "Missing recipes: $(printf '%s\n' "$missing" | summarise 10)"
  else es_rec CFG-3 0 "Missing $n_missing of $n_want required recipes: $(printf '%s\n' "$missing" | summarise 10)"
  fi
fi

# CFG-4 — Dev Container present and the project builds/tests inside it.
dc="$(first_of .devcontainer/devcontainer.json .devcontainer.json || true)"
if [ -z "$dc" ]; then es_rec CFG-4 0 "No .devcontainer/devcontainer.json"
else
  ci_dc="$(wf_grep 'devcontainers/ci|devcontainer (up|exec|build)')"
  if [ -n "$ci_dc" ] && grep -Eq 'just +(check|test)' $ci_dc; then es_rec CFG-4 2 "$dc present; CI runs the tests inside it ($(printf '%s\n' "$ci_dc" | summarise 2))"
  else es_rec CFG-4 1 "$dc present; whether the project builds and its tests pass inside it is not verified" true
  fi
fi

# CFG-5 — Dev Container installs just and recipe tools at pinned versions; postCreateCommand runs just setup.
if [ -z "$dc" ]; then es_rec CFG-5 0 "No Dev Container"
else
  dcj="$(jsonc "$dc")"
  just_inst=false
  printf '%s' "$dcj" | jq -e '(.features // {}) | keys | any(test("just"))' >/dev/null 2>&1 && just_inst=true
  dc_df="$(files_matching '^\.devcontainer/.*Dockerfile' | head -1)"
  [ -n "$dc_df" ] && grep -Eq 'just' "$dc_df" && just_inst=true
  post="$(printf '%s' "$dcj" | jq -r '.postCreateCommand // "" | if type == "array" then join(" ") elif type == "object" then [.[]] | flatten | join(" ") else . end' 2>/dev/null || true)"
  setup=false; printf '%s' "$post" | grep -Eq 'just +setup' && setup=true
  unpinned="$(printf '%s' "$dcj" | jq -r '(.features // {}) | keys[] | select(test("(:[0-9]+\\.[0-9]+(\\.[0-9]+)?|@sha256:[0-9a-f]+)$") | not)' 2>/dev/null || true)"
  if $just_inst && $setup && [ -z "$unpinned" ]; then es_rec CFG-5 2 "Dev Container installs just at a pinned version and postCreateCommand runs just setup"
  elif $just_inst || $setup; then es_rec CFG-5 1 "installs just: $just_inst; postCreateCommand runs just setup: $setup; unpinned features: $(printf '%s\n' "$unpinned" | summarise 3)"
  else es_rec CFG-5 0 "Dev Container neither installs just nor runs just setup"
  fi
fi
} > "$out"
jq -s . "$out"
