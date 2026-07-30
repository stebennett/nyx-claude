#!/usr/bin/env bash
# Shared helpers for the github-app-identity scripts. Sourced, never executed.
# bash 3.2 compatible; no GNU-only constructs.

# Appended to every auth-failure message. This is the plugin's standing rule,
# placed where an agent actually reads it: in the abort it just hit.
GH_APP_DOCTRINE="Do NOT retry with personal credentials or 'gh auth login' — this means setup is incomplete. Run gh-app-status.sh."

gh_app_die() { echo "gh-app: $*" >&2; exit 1; }

gh_app_profile_dir() { printf '%s\n' "${GH_APP_PROFILE_DIR:-$HOME/.config/gh-app/profiles}"; }
gh_app_cache_dir()   { printf '%s\n' "${GH_APP_CACHE_DIR:-$HOME/.cache/gh-app}"; }

# A profile name becomes a path component twice (profile file, cache file), so
# it is validated before it is ever concatenated into a path.
# Must be called from the current shell — it exits, which a $( ) subshell eats.
gh_app_validate_profile() {
  local name="${1:-}"
  local rule="must match ^[A-Za-z0-9][A-Za-z0-9._-]*\$ (letters, digits, dot, dash)"
  [ -n "$name" ] || gh_app_die "empty profile name — $rule"
  case "$name" in
    [A-Za-z0-9]*) : ;;
    *) gh_app_die "invalid profile name '$name' — $rule" ;;
  esac
  case "$name" in
    *[!A-Za-z0-9._-]*) gh_app_die "invalid profile name '$name' — $rule" ;;
  esac
  return 0
}

gh_app_list_profiles() {
  local d f n found=0
  d="$(gh_app_profile_dir)"
  for f in "$d"/*.env; do
    [ -f "$f" ] || continue
    n="${f##*/}"; n="${n%.env}"
    printf '  %s\n' "$n"
    found=1
  done
  [ "$found" -eq 1 ] || printf '  (none found in %s)\n' "$d"
}

# Validate, require, and source a profile. Exports its values and sets
# GH_APP_PROFILE_FILE. Dies if the profile does not exist.
gh_app_load_profile() {
  local name="${1:-}" f
  gh_app_validate_profile "$name"
  f="$(gh_app_profile_dir)/$name.env"
  if [ ! -f "$f" ]; then
    echo "gh-app: no such profile '$name' (expected $f)" >&2
    echo "gh-app: available profiles:" >&2
    gh_app_list_profiles >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  . "$f"
  set +a
  GH_APP_PROFILE_FILE="$f"
  return 0
}

# Print the profile governing the current directory, or nothing when gh should
# pass through unchanged. Exits 1 on legacy config.
# Callers MUST write: profile="$(gh_app_resolve_profile)" || exit 1
gh_app_resolve_profile() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local p
  p="$(git config --local --get gh-app.profile 2>/dev/null || true)"
  if [ -n "$p" ]; then
    printf '%s\n' "$p"
    return 0
  fi

  # --local, never a plain --get: a stray --global setting must not enable every
  # repo on the machine. In a linked worktree --local resolves to the clone's
  # shared config, which is what makes worktrees inherit the clone's identity.
  if git config --local --get gh-app.enabled >/dev/null 2>&1; then
    echo "gh-app: legacy config — this repo sets gh-app.enabled but no gh-app.profile." >&2
    echo "gh-app: re-run: setup-github-app-git.sh <profile>" >&2
    exit 1
  fi
  return 0
}
