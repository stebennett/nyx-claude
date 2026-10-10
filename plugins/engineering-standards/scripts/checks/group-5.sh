#!/usr/bin/env bash
# group-5.sh — mechanical checks for DPL, DAT, OBS and OPS.
#
#   group-5.sh <repo>
#
# Prints a JSON array of criterion records.
# No pipefail: many checks pipe into `grep -q`, which exits on the first match
# and SIGPIPEs the producer; pipefail would turn that race into a false "no".
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/common.sh"
. "$here/../lib/repo.sh"
es_require_deps
repo="${1:-}"; [ -n "$repo" ] && [ -d "$repo" ] || es_die 2 "usage: group-5.sh <repo>"
cd "$repo"

target="$(tag_field deployment_target)"
database="$(tag_field database)"
type="$(tag_field type)"
charts="$(files_matching '^charts/[^/]+/Chart\.yaml$' | sed 's#/Chart\.yaml$##')"
wrangler="$(first_of wrangler.toml wrangler.jsonc wrangler.json || true)"
chart_templates() { for c in $charts; do [ ! -d "$c/templates" ] || find "$c/templates" -type f -exec cat {} +; done; return 0; }
chart_values() { for c in $charts; do [ ! -f "$c/values.yaml" ] || cat "$c/values.yaml"; done; return 0; }
app_source() { source_files '\.(go|py|ts|tsx)$' | grep -Ev '(^|/)(tests?|__tests__|e2e)/|_test\.go$|test_[^/]*\.py$|\.test\.tsx?$|\.spec\.tsx?$' || true; }

out="$(mktemp)"; trap 'rm -f "$out"' EXIT
{
# DPL-2 — target configuration committed.
case "$target" in
  fly) [ -f fly.toml ] && es_rec DPL-2 2 "fly.toml committed" || es_rec DPL-2 0 "Target is Fly.io but there is no fly.toml" ;;
  cloudflare) [ -n "$wrangler" ] && es_rec DPL-2 2 "$wrangler committed" || es_rec DPL-2 0 "Target is Cloudflare but there is no wrangler.toml/jsonc" ;;
  kubernetes) [ -n "$charts" ] && es_rec DPL-2 2 "Helm chart(s): $(printf '%s\n' "$charts" | summarise 3)" || es_rec DPL-2 0 "Target is Kubernetes but there is no chart in charts/<app>/" ;;
  *) es_rec DPL-2 0 "No deployment target in the tag" ;;
esac

# DPL-3 — CI lints, renders and validates the chart.
lint="$(wf_grep 'helm lint')"; tmpl="$(wf_grep 'helm template')"; kc="$(wf_grep 'kubeconform')"
n=0; [ -n "$lint" ] && n=$((n + 1)); [ -n "$tmpl" ] && n=$((n + 1)); [ -n "$kc" ] && n=$((n + 1))
case "$n" in
  3) es_rec DPL-3 2 "CI runs helm lint, helm template and kubeconform" ;;
  0) es_rec DPL-3 0 "CI does not lint or validate the chart" ;;
  *) es_rec DPL-3 1 "CI runs helm lint: $( [ -n "$lint" ] && echo yes || echo no), helm template: $( [ -n "$tmpl" ] && echo yes || echo no), kubeconform: $( [ -n "$kc" ] && echo yes || echo no)" ;;
esac

# DPL-4 — chart semver, appVersion, image tag defaults to appVersion, version bumped per change.
if [ -z "$charts" ]; then es_rec DPL-4 0 "No Helm chart"
else
  issues=""
  for c in $charts; do
    v="$(yq -r '.version // ""' "$c/Chart.yaml")"
    printf '%s' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+' || issues="$issues
$c: version '$v' is not semver"
    [ -n "$(yq -r '.appVersion // ""' "$c/Chart.yaml")" ] || issues="$issues
$c: no appVersion"
    grep -rqs 'Chart.AppVersion' "$c/templates" || issues="$issues
$c: image tag does not default to .Chart.AppVersion"
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      unbumped=0; changes=0
      for sha in $(git log -n 20 --format=%H -- "$c" 2>/dev/null); do
        changes=$((changes + 1))
        git show "$sha" -- "$c/Chart.yaml" | grep -Eq '^\+version:' || unbumped=$((unbumped + 1))
      done
      [ "$unbumped" -eq 0 ] || issues="$issues
$c: $unbumped of the last $changes chart changes did not bump version"
    fi
  done
  n_issues="$(printf '%s\n' "$issues" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$n_issues" -eq 0 ]; then es_rec DPL-4 2 "Chart versions semver, bumped on every change; image tag defaults to appVersion"
  elif [ "$n_issues" -le 2 ]; then es_rec DPL-4 1 "$(printf '%s\n' "$issues" | summarise 4)"
  else es_rec DPL-4 0 "$(printf '%s\n' "$issues" | summarise 4)"
  fi
fi

# DPL-5 — resources, securityContext and probes, configurable through values.yaml.
if [ -z "$charts" ]; then es_rec DPL-5 0 "No Helm chart"
else
  t="$(chart_templates)"; v="$(chart_values)"
  have=""; lack=""
  for k in resources securityContext livenessProbe readinessProbe; do
    if printf '%s' "$t" | grep -Eq "\.Values\.[A-Za-z0-9_.]*$k|$k:" && printf '%s' "$v" | grep -Eq "^[[:space:]]*$k:"; then have="$have $k"
    else lack="$lack $k"; fi
  done
  if [ -z "$lack" ]; then es_rec DPL-5 2 "Templates set$have from values.yaml"
  elif [ -n "$have" ]; then es_rec DPL-5 1 "Configurable:$have; missing or not in values.yaml:$lack"
  else es_rec DPL-5 0 "No resources, securityContext or probes configurable through values.yaml"
  fi
fi

# DPL-6 — an ArgoCD Application deploys the chart.
argo="$(files_matching '\.ya?ml$' | while IFS= read -r f; do grep -Eq 'argoproj\.io/' "$f" && grep -Eq '^kind:[[:space:]]*(Application|ApplicationSet)' "$f" && echo "$f"; done || true)"
manual="$(wf_grep 'helm (install|upgrade)')"
if [ -n "$manual" ]; then es_rec DPL-6 0 "Workflows run helm install/upgrade directly: $(printf '%s\n' "$manual" | summarise 3)"
elif [ -n "$argo" ]; then es_rec DPL-6 2 "ArgoCD Application in: $(printf '%s\n' "$argo" | summarise 3)"
else es_rec DPL-6 0 "No ArgoCD Application in this repo (it may live in a GitOps repo)" true
fi

# DPL-8 — preview deployments for pull requests.
prev=""
for f in $(workflows); do
  wf_on "$f" pull_request || continue
  grep -Eq 'wrangler(-action)?|pages deploy|pages-action|fly-pr-review-apps|flyctl deploy|fly deploy' "$f" && prev="$prev $f"
done
if [ -n "$prev" ]; then es_rec DPL-8 2 "Pull-request workflows deploy previews:$prev"
elif [ "$target" = cloudflare ]; then es_rec DPL-8 0 "No preview deploy in a pull_request workflow (Cloudflare's Git integration may create them)" true
else es_rec DPL-8 0 "No preview deploy in a pull_request workflow"
fi

# DAT-3 — versioned migrations applied by just migrate.
mig="$(files_matching '(^|/)(migrations|alembic/versions|migrate)/[^/]+\.(sql|py|go)$' | head -50)"
n_mig="$(printf '%s\n' "$mig" | sed '/^$/d' | wc -l | tr -d ' ')"
if [ "$n_mig" -gt 0 ] && just_has migrate; then es_rec DAT-3 2 "$n_mig migration files; just migrate defined"
elif [ "$n_mig" -gt 0 ]; then es_rec DAT-3 1 "$n_mig migration files, but no just migrate recipe"
elif just_has migrate; then es_rec DAT-3 1 "just migrate defined, but no committed migration files found"
else es_rec DAT-3 0 "No versioned migrations"
fi

# DAT-4 — migrations run automatically before the new version serves traffic.
case "$target" in
  kubernetes)
    if chart_templates | grep -Eq 'helm\.sh/hook:.*pre-(upgrade|install)'; then es_rec DAT-4 2 "Helm pre-upgrade hook in the chart"
    else es_rec DAT-4 0 "No Helm pre-upgrade/pre-install hook Job"; fi ;;
  fly)
    if [ -f fly.toml ] && grep -Eq '^[[:space:]]*release_command' fly.toml; then es_rec DAT-4 2 "fly.toml release_command: $(sed -nE 's/^[[:space:]]*release_command[[:space:]]*=[[:space:]]*//p' fly.toml)"
    elif [ -f fly.toml ] && grep -Eq '^[^#]*(alembic[^#]*upgrade|goose[^#]* up|migrate)' fly.toml; then
      es_rec DAT-4 1 "Migrations run in a fly.toml process command before the server starts, not via release_command — check the standard's intent is met (e.g. volumes unavailable to release machines)" true
    else es_rec DAT-4 0 "No release_command in fly.toml"; fi ;;
  cloudflare)
    if [ -n "$(wf_grep 'd1 migrations apply')" ]; then es_rec DAT-4 2 "Workflow applies D1 migrations"
    else es_rec DAT-4 0 "No workflow step applies migrations"; fi ;;
  *) es_rec DAT-4 0 "No deployment target, so no automated migration step" ;;
esac

# DAT-6 — PostgreSQL major pinned and equal across Dev Container, CI and production.
majors() { # <file...>; /dev/null keeps grep off stdin when the list is empty
  { grep -Eoh 'postgres(ql)?:[0-9]+|postgres(ql)?-[0-9]+|imageName:.*postgresql:[0-9]+' /dev/null "$@" 2>/dev/null || true; } \
    | { grep -Eo '[0-9]+$' || true; } | sort -u
}
dev_m="$(majors $(files_matching '^\.devcontainer/') $(files_matching '(^|/)(docker-)?compose[^/]*\.ya?ml$'))"
ci_m="$(majors $(workflows))"
prod_m="$(majors $(for c in $charts; do find "$c" -type f; done) $(files_matching '^(deploy|k8s|manifests)/') $(first_of fly.toml || true))"
all_m="$(printf '%s\n%s\n%s\n' "$dev_m" "$ci_m" "$prod_m" | sed '/^$/d' | sort -u)"
n_all="$(printf '%s\n' "$all_m" | sed '/^$/d' | wc -l | tr -d ' ')"
summary="devcontainer=${dev_m:-?} ci=${ci_m:-?} production=${prod_m:-?}"
if [ "$n_all" -gt 1 ]; then es_rec DAT-6 0 "PostgreSQL majors differ: $(printf '%s' "$summary" | tr '\n' ',')"
elif [ "$n_all" -eq 0 ]; then es_rec DAT-6 0 "No pinned PostgreSQL major found"
elif [ -n "$dev_m" ] && [ -n "$ci_m" ] && [ -n "$prod_m" ]; then es_rec DAT-6 2 "PostgreSQL $all_m in the Dev Container, CI and production"
else es_rec DAT-6 1 "PostgreSQL $all_m where pinned; not found in: $( [ -z "$dev_m" ] && printf 'devcontainer ')$( [ -z "$ci_m" ] && printf 'ci ')$( [ -z "$prod_m" ] && printf 'production')" "$( [ -z "$prod_m" ] && echo true || echo false)"
fi

# DAT-9 — SQLite on persistent storage with a single instance.
case "$target" in
  kubernetes)
    t="$(chart_templates)"; v="$(chart_values)"
    pvc=false; one=false; rec=false
    printf '%s\n%s' "$t" "$v" | grep -Eq 'longhorn' && printf '%s' "$t" | grep -Eq 'PersistentVolumeClaim|persistentVolumeClaim' && pvc=true
    printf '%s\n%s' "$t" "$v" | grep -Eq '^[[:space:]]*replicas:[[:space:]]*1[[:space:]]*$|replicaCount:[[:space:]]*1[[:space:]]*$' && one=true
    printf '%s\n%s' "$t" "$v" | grep -Eq 'type:[[:space:]]*Recreate' && rec=true
    if $pvc && $one && $rec; then es_rec DAT-9 2 "Longhorn PVC, one replica, Recreate strategy"
    elif $pvc || $one || $rec; then es_rec DAT-9 1 "Longhorn PVC: $pvc, replicas 1: $one, Recreate: $rec"
    else es_rec DAT-9 0 "No Longhorn PVC, single replica or Recreate strategy in the chart"; fi ;;
  fly)
    if [ -f fly.toml ] && grep -Eq '^\[\[?mounts\]\]?' fly.toml; then es_rec DAT-9 1 "Fly volume mounted; scaling to a single Machine is not visible in config" true
    else es_rec DAT-9 0 "No Fly volume in fly.toml"; fi ;;
  *) es_rec DAT-9 0 "SQLite persistence and single-instance rule not verifiable for target '${target:-none}'" true ;;
esac

# OBS-3 — health and readiness endpoints.
if [ "$type" = cli ] || [ "$type" = library ]; then
  es_rec OBS-3 N/A "Not a long-running service"
else
  src="$(app_source)"
  live=false; ready=false
  if [ -n "$src" ]; then
    grep -Eqs '"/?(healthz|livez|health|alive)"|/healthz|/livez' $src && live=true
    grep -Eqs '"/?(readyz|ready|readiness)"|/readyz' $src && ready=true
  fi
  if $live && $ready; then es_rec OBS-3 2 "Liveness and readiness endpoints in the source"
  elif $live || $ready; then es_rec OBS-3 1 "liveness endpoint: $live; readiness endpoint: $ready"
  else es_rec OBS-3 0 "No health or readiness endpoints found"; fi
fi

# OBS-4 — Prometheus metrics.
metrics="$(grep -Elis 'prometheus/client_golang|prometheus[-_]client|prom-client|prometheus-fastapi-instrumentator|starlette[-_]exporter|opentelemetry-exporter-prometheus' /dev/null $(manifests go.mod pyproject.toml package.json requirements.txt) || true)"
if [ -n "$metrics" ]; then es_rec OBS-4 2 "Prometheus client library in: $(printf '%s\n' "$metrics" | summarise 3)"
elif [ -n "$(app_source)" ] && grep -Eqs '"/metrics"' $(app_source); then es_rec OBS-4 1 "A /metrics route exists, but no Prometheus client library was found"
else es_rec OBS-4 0 "No Prometheus metrics"
fi
} > "$out"
jq -s . "$out"
