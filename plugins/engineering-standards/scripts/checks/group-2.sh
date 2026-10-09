#!/usr/bin/env bash
# group-2.sh — mechanical checks for VCS, CI and DEP.
#
#   group-2.sh <repo>
#
# Prints a JSON array of criterion records. Criteria needing GitHub state use gh
# when it is installed and authenticated, and are marked unverified otherwise.
# ES_NO_GH=1 forces the offline path (used by the tests).
# No pipefail: many checks pipe into `grep -q`, which exits on the first match
# and SIGPIPEs the producer; pipefail would turn that race into a false "no".
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/common.sh"
. "$here/../lib/repo.sh"
es_require_deps
repo="${1:-}"; [ -n "$repo" ] && [ -d "$repo" ] || es_die 2 "usage: group-2.sh <repo>"
cd "$repo"

gh_ok=false
if [ -z "${ES_NO_GH:-}" ] && es_gh_ok .; then gh_ok=true; fi
nwo=""
if $gh_ok; then nwo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"; fi
is_git=false
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && is_git=true

out="$(mktemp)"; trap 'rm -f "$out"' EXIT
{
# VCS-1 — default branch is main and releasable.
if $gh_ok; then
  default="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
elif $is_git; then
  default="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  [ -n "$default" ] || default="$(git symbolic-ref -q --short HEAD 2>/dev/null || true)"
else
  default=""
fi
if [ "$default" != "main" ]; then
  es_rec VCS-1 0 "Default branch is '${default:-unknown}', not main"
elif $gh_ok; then
  last="$(gh run list --branch main --limit 1 --json conclusion -q '.[0].conclusion // empty' 2>/dev/null || true)"
  case "$last" in
    success) es_rec VCS-1 2 "Default branch is main; latest CI run on main succeeded" ;;
    "") es_rec VCS-1 1 "Default branch is main; no CI runs on main to show it is releasable" ;;
    *) es_rec VCS-1 1 "Default branch is main; latest CI run on main concluded '$last'" ;;
  esac
else
  es_rec VCS-1 1 "Default branch appears to be main (from local git); CI status on main not checked without gh" true
fi

# VCS-2 — Conventional Commits.
if $is_git && git rev-parse -q --verify HEAD >/dev/null; then
  subjects="$(git log --no-merges -n 50 --format=%s)"
  total="$(printf '%s\n' "$subjects" | sed '/^$/d' | wc -l | tr -d ' ')"
  conv="$(printf '%s\n' "$subjects" | grep -Ec '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]*\))?!?: .+' || true)"
  pct=$((conv * 100 / (total > 0 ? total : 1)))
  if [ "$pct" -ge 90 ]; then es_rec VCS-2 2 "$conv of the last $total non-merge commits follow Conventional Commits ($pct%)"
  elif [ "$pct" -ge 50 ]; then es_rec VCS-2 1 "$conv of the last $total non-merge commits follow Conventional Commits ($pct%)"
  else es_rec VCS-2 0 "$conv of the last $total non-merge commits follow Conventional Commits ($pct%)"
  fi
else
  es_rec VCS-2 0 "No git history"
fi

# VCS-3 — main protected by a ruleset blocking force-push and requiring checks.
if ! $gh_ok; then
  es_rec VCS-3 0 "Branch rulesets not checked: gh unavailable or unauthenticated" true
else
  rules="$(gh api "repos/$nwo/rules/branches/main" 2>/dev/null | jq -r '.[].type' || true)"
  nff=false; checks=false
  printf '%s\n' "$rules" | grep -qx non_fast_forward && nff=true
  printf '%s\n' "$rules" | grep -qx required_status_checks && checks=true
  if $nff && $checks; then es_rec VCS-3 2 "Ruleset on main blocks force-push and requires status checks"
  elif $nff || $checks; then es_rec VCS-3 1 "Ruleset on main: force-push blocked=$nff, status checks required=$checks"
  elif gh api "repos/$nwo/branches/main/protection" >/dev/null 2>&1; then
    es_rec VCS-3 1 "main uses classic branch protection rather than a ruleset"
  elif disabled="$(gh api "repos/$nwo/rulesets" 2>/dev/null | jq -r '[.[] | select(.target == "branch" and .enforcement != "active") | "\(.name) (\(.enforcement))"] | join(", ")')" && [ -n "$disabled" ]; then
    es_rec VCS-3 0 "Branch ruleset(s) exist but are not enforced: $disabled"
  else
    es_rec VCS-3 0 "No ruleset or branch protection on main"
  fi
fi

# VCS-4 — semver release tags.
if $is_git; then
  tags="$(git tag -l)"
  n_tags="$(printf '%s\n' "$tags" | sed '/^$/d' | wc -l | tr -d ' ')"
  n_semver="$(printf '%s\n' "$tags" | grep -Ec '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || true)"
  if [ "$n_tags" -eq 0 ]; then es_rec VCS-4 0 "No tags"
  elif [ "$n_semver" -eq "$n_tags" ]; then es_rec VCS-4 2 "All $n_tags tags are vX.Y.Z"
  elif [ "$n_semver" -gt 0 ]; then es_rec VCS-4 1 "$n_semver of $n_tags tags are vX.Y.Z"
  else es_rec VCS-4 0 "$n_tags tags, none of the form vX.Y.Z"
  fi
else
  es_rec VCS-4 0 "No git history"
fi

# VCS-5 — commit format enforced by a hook or CI check.
enforcers="$(files_matching '(^|/)(commitlint\.config\.[a-z]+|\.commitlintrc[^/]*)$')"
hook="$( [ -f .pre-commit-config.yaml ] && grep -El 'conventional-pre-commit|commitlint|commitizen' .pre-commit-config.yaml || true)"
ci="$(wf_grep 'commitlint|semantic-pull-request|conventional-commit|commitizen|cz check')"
if [ -n "$hook$ci" ]; then
  es_rec VCS-5 2 "Commit format enforced by: $(printf '%s\n' $hook $ci | summarise 3)"
elif [ -n "$enforcers" ]; then
  es_rec VCS-5 1 "commitlint config present ($enforcers) but not wired into a hook or CI"
else
  es_rec VCS-5 0 "No commit message enforcement"
fi

# CI-1 — workflows committed.
wfs="$(workflows)"
if [ -n "$wfs" ]; then es_rec CI-1 2 "Workflows: $(printf '%s\n' "$wfs" | summarise 5)"
else es_rec CI-1 0 "No .github/workflows/*.yml"
fi

# CI-2 — CI runs just check and just build on push and PR.
check_runs="$(wf_runs_on_push_and_pr 'just +check')"
build_needed=false; required_recipes | grep -qx build && build_needed=true
build_runs=both
$build_needed && build_runs="$(wf_runs_on_push_and_pr 'just +build')"
if [ "$check_runs" = both ] && [ "$build_runs" = both ]; then
  es_rec CI-2 2 "CI runs just check$($build_needed && echo ' and just build') on push and pull_request"
elif [ "$check_runs" != none ] || { $build_needed && [ "$build_runs" != none ]; } \
     || { [ "$(wf_runs_on_push_and_pr 'just +lint')" != none ] && [ "$(wf_runs_on_push_and_pr 'just +test')" != none ]; }; then
  es_rec CI-2 1 "just check: $check_runs; just build: $($build_needed && echo "$build_runs" || echo not-required) (both = on push and pull_request)$( [ "$check_runs" = none ] && echo '; CI calls just lint/just test separately instead of just check')"
else
  es_rec CI-2 0 "No workflow runs just check"
fi

# CI-3 — pipeline under 10 minutes (median of recent successful runs on main).
if ! $gh_ok; then
  es_rec CI-3 0 "Run durations not checked: gh unavailable or unauthenticated" true
else
  median="$(gh run list --branch main --status success --limit 20 --json createdAt,updatedAt 2>/dev/null \
    | jq '[.[] | (.updatedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)] | sort
          | if length == 0 then empty else .[length / 2 | floor] end' || true)"
  if [ -z "$median" ]; then es_rec CI-3 0 "No successful runs on main to time" true
  elif [ "$median" -lt 600 ]; then es_rec CI-3 2 "Median of recent successful runs on main: $((median / 60))m$((median % 60))s"
  elif [ "$median" -lt 900 ]; then es_rec CI-3 1 "Median of recent successful runs on main: $((median / 60))m$((median % 60))s"
  else es_rec CI-3 0 "Median of recent successful runs on main: $((median / 60))m$((median % 60))s"
  fi
fi

# CI-5 — third-party actions pinned to a full commit SHA.
if [ -z "$wfs" ]; then
  es_rec CI-5 0 "No workflows"
else
  uses="$(for f in $wfs; do sed -nE 's/^[[:space:]-]*uses:[[:space:]]*["'\'']?([^"'\''[:space:]#]+).*/\1/p' "$f"; done \
    | grep -Ev '^(\./|docker://)' || true)"
  total="$(printf '%s\n' "$uses" | sed '/^$/d' | wc -l | tr -d ' ')"
  unpinned="$(printf '%s\n' "$uses" | sed '/^$/d' | grep -Ev '@[0-9a-f]{40}$' | sort -u || true)"
  n_unpinned="$(printf '%s\n' "$unpinned" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$total" -eq 0 ]; then es_rec CI-5 2 "Workflows use no third-party actions"
  elif [ -z "$unpinned" ]; then es_rec CI-5 2 "All $total action references pinned to a commit SHA"
  elif [ "$n_unpinned" -lt "$total" ]; then es_rec CI-5 1 "Not SHA-pinned: $(printf '%s\n' "$unpinned" | summarise 5)"
  else es_rec CI-5 0 "No actions are SHA-pinned: $(printf '%s\n' "$unpinned" | summarise 5)"
  fi
fi

# CI-6 — explicit, least-privilege permissions in every workflow.
if [ -z "$wfs" ]; then
  es_rec CI-6 0 "No workflows"
else
  explicit=""; implicit=""; broad=""
  for f in $wfs; do
    top="$(yq '.permissions // ""' "$f")"
    jobs_all="$(yq '[.jobs[] | has("permissions")] | all' "$f" 2>/dev/null || echo false)"
    if [ -n "$top" ] || [ "$jobs_all" = true ]; then explicit="$explicit $f"; else implicit="$implicit $f"; fi
    grep -Eq 'permissions:[[:space:]]*write-all' "$f" && broad="$broad $f"
  done
  if [ -z "$implicit" ] && [ -z "$broad" ]; then es_rec CI-6 2 "Every workflow sets permissions explicitly"
  elif [ -n "$explicit" ]; then es_rec CI-6 1 "Implicit permissions:${implicit:- none}; write-all:${broad:- none}"
  else es_rec CI-6 0 "No workflow sets permissions"
  fi
fi

# DEP-1 — lockfile per ecosystem.
have=""; lack=""
for f in $(manifests go.mod); do
  grep -q '^require' "$f" || continue
  [ -f "$(dirname "$f")/go.sum" ] && have="$have $(dirname "$f")/go.sum" || lack="$lack $(dirname "$f")/go.sum"
done
if [ -n "$(manifests pyproject.toml)" ]; then
  lock="$(manifests uv.lock poetry.lock | head -1)"
  [ -n "$lock" ] && have="$have $lock" || lack="$lack uv.lock/poetry.lock"
fi
if [ -n "$(manifests package.json)" ]; then
  lock="$(manifests package-lock.json pnpm-lock.yaml | head -1)"
  [ -n "$lock" ] && have="$have $lock" || lack="$lack package-lock.json/pnpm-lock.yaml"
fi
if [ -z "$have$lack" ]; then es_rec DEP-1 N/A "No package manifests with dependencies"
elif [ -z "$lack" ]; then es_rec DEP-1 2 "Lockfiles:$have"
elif [ -n "$have" ]; then es_rec DEP-1 1 "Lockfiles:$have; missing:$lack"
else es_rec DEP-1 0 "Missing lockfiles:$lack"
fi

# DEP-2 — Renovate configured and opening PRs; Dependabot version updates not used.
renovate="$(renovate_config || true)"
dependabot="$( [ -f .github/dependabot.yml ] && grep -q 'package-ecosystem' .github/dependabot.yml && echo .github/dependabot.yml || true)"
if [ -z "$renovate" ]; then
  es_rec DEP-2 0 "No Renovate config"
elif [ -n "$dependabot" ]; then
  es_rec DEP-2 1 "Renovate configured ($renovate) but Dependabot version updates are also configured"
elif ! $gh_ok; then
  es_rec DEP-2 1 "Renovate configured ($renovate); PR activity not checked without gh" true
else
  # The hosted app's PRs, or a self-hosted Renovate's (identified by branch prefix).
  recent="$(gh pr list --state all --author 'app/renovate' --limit 1 --json createdAt -q '.[0].createdAt // empty' 2>/dev/null || true)"
  [ -n "$recent" ] || recent="$(gh pr list --state all --limit 200 --json headRefName,createdAt \
    -q '[.[] | select(.headRefName | startswith("renovate/"))][0].createdAt // empty' 2>/dev/null || true)"
  if [ -n "$recent" ]; then es_rec DEP-2 2 "Renovate configured ($renovate); latest Renovate PR $recent"
  else es_rec DEP-2 1 "Renovate configured ($renovate) but no Renovate PRs found"
  fi
fi

# DEP-4 — exact pins everywhere (libraries may range their published metadata).
type="$(tag_field type)"
pinned=0; loose=""
note_loose() { loose="$loose
$1"; }
exact_semver='^v?[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$'
# Python: PEP 508 strings. Exact means a single == pin (or a direct URL).
for pyproject in $(manifests pyproject.toml); do
  py="$(yq -p toml -o json '.' "$pyproject" 2>/dev/null || echo '{}')"
  while IFS='	' read -r where spec; do
    spec="${spec%%;*}"; spec="$(printf '%s' "$spec" | sed -E 's/[[:space:]]+$//')"
    [ -n "$spec" ] || continue
    if printf '%s' "$spec" | grep -Eq '(===?[^=,<>~!*]+$|@ )' && ! printf '%s' "$spec" | grep -q '\*'; then pinned=$((pinned + 1))
    elif [ "$type" = library ] && [ "$where" = published ] && printf '%s' "$spec" | grep -q '<'; then pinned=$((pinned + 1))
    else note_loose "$pyproject:$spec"; fi
  done <<EOF_PY
$(printf '%s' "$py" | jq -r '
  ((.project.dependencies // [])[] | "published\t\(.)"),
  ((.project["optional-dependencies"] // {}) | .[][] | "published\t\(.)"),
  ((.["dependency-groups"] // {}) | .[][] | select(type == "string") | "dev\t\(.)"),
  ((.tool.uv["dev-dependencies"] // [])[] | "dev\t\(.)")')
EOF_PY
done
# Node: exact versions; library dependencies/peerDependencies may use bounded ranges.
for pkg in $(manifests package.json); do
  while IFS='	' read -r section name ver; do
    [ -n "$name" ] || continue
    if printf '%s' "$ver" | grep -Eq "$exact_semver|^(workspace|file|link|portal):"; then pinned=$((pinned + 1))
    elif [ "$type" = library ] && { [ "$section" = dependencies ] || [ "$section" = peerDependencies ]; } \
         && printf '%s' "$ver" | grep -Eq '^[\^~][0-9]|<'; then pinned=$((pinned + 1))
    else note_loose "$pkg:$name@$ver"; fi
  done <<EOF_NODE
$(jq -r '["dependencies","devDependencies","peerDependencies","optionalDependencies"][] as $s
         | (.[$s] // {}) | to_entries[] | "\($s)\t\(.key)\t\(.value)"' "$pkg" 2>/dev/null)
EOF_NODE
done
if [ -n "$(manifests package.json)" ]; then
  if [ -f .npmrc ] && grep -Eq '^save-exact[[:space:]]*=[[:space:]]*true' .npmrc; then pinned=$((pinned + 1))
  else note_loose ".npmrc:save-exact=true missing"; fi
fi
# Container images: a tag that is a full version (or a digest); not latest, not bare major.
image_ok() {
  case "$1" in
    *@sha256:*) return 0 ;;
    *:*) t="${1##*:}"; printf '%s' "$t" | grep -Eq '^v?[0-9]+\.[0-9]+' ;;
    *) return 1 ;;
  esac
}
for d in $(dockerfiles); do
  for img in $(docker_images "$d"); do
    if image_ok "$img"; then pinned=$((pinned + 1)); else note_loose "$d:$img"; fi
  done
done
for dc in $(files_matching '^\.devcontainer/.*devcontainer\.json$'); do
  dcj="$(jsonc "$dc")"
  for img in $(printf '%s' "$dcj" | jq -r '.image // empty' 2>/dev/null); do
    if image_ok "$img"; then pinned=$((pinned + 1)); else note_loose "$dc:$img"; fi
  done
  for feat in $(printf '%s' "$dcj" | jq -r '(.features // {}) | keys[]' 2>/dev/null); do
    if printf '%s' "$feat" | grep -Eq '(:[0-9]+\.[0-9]+(\.[0-9]+)?|@sha256:[0-9a-f]+)$'; then pinned=$((pinned + 1))
    else note_loose "$dc:feature $feat"; fi
  done
  for opt in $(printf '%s' "$dcj" | jq -r '(.features // {}) | to_entries[] | select((.value | type) == "object" and (.value.version // "") == "latest") | .key' 2>/dev/null); do
    note_loose "$dc:feature $opt version=latest"
  done
done
for c in $(files_matching '(^|/)(docker-)?compose[^/]*\.ya?ml$'); do
  for img in $(yq -r '.services[].image // ""' "$c" 2>/dev/null); do
    [ -n "$img" ] || continue
    if image_ok "$img"; then pinned=$((pinned + 1)); else note_loose "$c:$img"; fi
  done
done
for chart in $(files_matching '^charts/[^/]+/Chart\.yaml$'); do
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    if printf '%s' "$v" | grep -Eq "$exact_semver"; then pinned=$((pinned + 1)); else note_loose "$chart:dependency $v"; fi
  done <<EOF_CHART
$(yq -r '.dependencies[]? | .name + "@" + (.version // "")' "$chart" | sed 's/.*@//')
EOF_CHART
done
if [ -n "$renovate" ]; then
  if grep -Eq '"?rangeStrategy"?[[:space:]]*:[[:space:]]*"pin"' "$renovate"; then pinned=$((pinned + 1))
  else note_loose "$renovate:rangeStrategy pin missing"; fi
fi
n_loose="$(printf '%s\n' "$loose" | sed '/^$/d' | wc -l | tr -d ' ')"
if [ "$pinned" -eq 0 ] && [ "$n_loose" -eq 0 ]; then
  es_rec DEP-4 N/A "No dependency manifests, images, charts or Renovate config to pin"
elif [ "$n_loose" -eq 0 ]; then
  es_rec DEP-4 2 "All $pinned dependency references are exact"
elif [ "$pinned" -gt 0 ]; then
  es_rec DEP-4 1 "$n_loose not exact (of $((pinned + n_loose))): $(printf '%s\n' "$loose" | summarise 8)"
else
  es_rec DEP-4 0 "No exact pins; $n_loose loose: $(printf '%s\n' "$loose" | summarise 8)"
fi

# DEP-6 — Renovate automerges patch and minor once CI passes.
if [ -z "$renovate" ]; then
  es_rec DEP-6 0 "No Renovate config"
elif grep -Eq '"?automerge"?[[:space:]]*:[[:space:]]*true' "$renovate"; then
  if grep -Eq 'minor|patch' "$renovate" || ! grep -q 'matchUpdateTypes' "$renovate"; then
    es_rec DEP-6 2 "Renovate automerge enabled in $renovate"
  else
    es_rec DEP-6 1 "Renovate automerge enabled in $renovate, but not obviously for patch/minor"
  fi
else
  es_rec DEP-6 0 "Renovate automerge not enabled"
fi

# DEP-7 — base images pinned by digest, maintained by Renovate.
all=0; digests=0
for d in $(dockerfiles); do
  for img in $(docker_images "$d"); do
    all=$((all + 1))
    case "$img" in *@sha256:*) digests=$((digests + 1)) ;; esac
  done
done
if [ "$all" -eq 0 ]; then es_rec DEP-7 N/A "No Dockerfile base images"
elif [ "$digests" -eq "$all" ] && [ -n "$renovate" ]; then es_rec DEP-7 2 "All $all base images digest-pinned; Renovate maintains them"
elif [ "$digests" -eq "$all" ]; then es_rec DEP-7 1 "All $all base images digest-pinned, but no Renovate config to maintain them"
elif [ "$digests" -gt 0 ]; then es_rec DEP-7 1 "$digests of $all base images digest-pinned"
else es_rec DEP-7 0 "No base images digest-pinned ($all images)"
fi
} > "$out"
jq -s . "$out"
