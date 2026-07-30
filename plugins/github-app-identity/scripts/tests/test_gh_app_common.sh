#!/usr/bin/env bash
# Offline tests for the shared helper library: name validation, profile
# loading, and working-directory -> profile resolution.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lib="$here/../gh-app-common.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

profiles="$work/profiles"; mkdir -p "$profiles"
cat > "$profiles/builder.env" <<'EOF'
GITHUB_APP_ID=111
GITHUB_APP_INSTALLATION_ID=222
GITHUB_APP_PRIVATE_KEY_PATH=/dev/null
GITHUB_APP_SLUG=my-builder
GITHUB_APP_BOT_USER_ID=333
EOF
touch "$profiles/pr-reviewer.env"

# Run a snippet against the library in a clean subshell. Prints its stdout;
# returns its exit status.
run() { ( set +e; cd "${2:-$work}"; GH_APP_PROFILE_DIR="$profiles" bash -c "
  set -euo pipefail
  . '$lib'
  $1" ) ; }

# --- name validation: accepts sane names ---
for name in builder pr-reviewer a A0 x.y z-1.2; do
  run "gh_app_validate_profile '$name'" >/dev/null 2>&1 \
    || { echo "FAIL: rejected valid name '$name'" >&2; exit 1; }
done

# --- name validation: rejects anything that must not become a path ---
for bad in "" "../evil" ".hidden" "a b" "a/b" "-lead" "a\$b"; do
  if run "gh_app_validate_profile '$bad'" >/dev/null 2>&1; then
    echo "FAIL: accepted invalid name '$bad'" >&2; exit 1
  fi
done

# --- load_profile: sources the file and exports its values ---
out="$(run 'gh_app_load_profile builder; echo "$GITHUB_APP_SLUG/$GITHUB_APP_ID"')"
[[ "$out" == "my-builder/111" ]] \
  || { echo "FAIL: load_profile did not export values, got '$out'" >&2; exit 1; }

# --- load_profile: a missing profile dies and names the ones that exist ---
if err="$(run 'gh_app_load_profile nope' 2>&1)"; then
  echo "FAIL: load_profile accepted a missing profile" >&2; exit 1
fi
echo "$err" | grep -q 'nope' || { echo "FAIL: error omits the bad name: $err" >&2; exit 1; }
echo "$err" | grep -q 'builder' \
  || { echo "FAIL: error does not list available profiles: $err" >&2; exit 1; }

# --- resolve: outside a git repo -> empty, exit 0 (pass-through) ---
outside="$work/outside"; mkdir -p "$outside"
out="$(run 'gh_app_resolve_profile' "$outside")" \
  || { echo "FAIL: resolve errored outside a repo" >&2; exit 1; }
[[ -z "$out" ]] || { echo "FAIL: resolve returned '$out' outside a repo" >&2; exit 1; }

# --- resolve: repo with no markers -> empty, exit 0 (pass-through) ---
plain="$work/plain"; mkdir -p "$plain"; ( cd "$plain" && git init -q . )
out="$(run 'gh_app_resolve_profile' "$plain")" \
  || { echo "FAIL: resolve errored in an unconfigured repo" >&2; exit 1; }
[[ -z "$out" ]] || { echo "FAIL: resolve returned '$out' in an unconfigured repo" >&2; exit 1; }

# --- resolve: repo with gh-app.profile -> that name ---
conf="$work/conf"; mkdir -p "$conf"
( cd "$conf" && git init -q . && git config --local gh-app.profile pr-reviewer )
out="$(run 'gh_app_resolve_profile' "$conf")"
[[ "$out" == "pr-reviewer" ]] \
  || { echo "FAIL: resolve gave '$out', expected 'pr-reviewer'" >&2; exit 1; }

# --- resolve: legacy gh-app.enabled with no profile -> abort, not pass-through ---
legacy="$work/legacy"; mkdir -p "$legacy"
( cd "$legacy" && git init -q . && git config --local gh-app.enabled true )
if err="$(run 'gh_app_resolve_profile' "$legacy" 2>&1)"; then
  echo "FAIL: legacy repo passed through instead of aborting" >&2; exit 1
fi
echo "$err" | grep -q 'setup-github-app-git.sh' \
  || { echo "FAIL: legacy abort does not say how to fix it: $err" >&2; exit 1; }

# --- resolve: a --global profile must NOT enable an unconfigured repo ---
globalcfg="$work/global.gitconfig"
printf '[gh-app]\n\tprofile = builder\n' > "$globalcfg"
out="$( GIT_CONFIG_GLOBAL="$globalcfg" run 'gh_app_resolve_profile' "$plain" )"
[[ -z "$out" ]] \
  || { echo "FAIL: a global gh-app.profile leaked into an unconfigured repo" >&2; exit 1; }

echo "PASS: gh-app-common validation, profile loading, and cwd resolution"
