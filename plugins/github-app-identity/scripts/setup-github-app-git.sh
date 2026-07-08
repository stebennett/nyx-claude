#!/usr/bin/env bash
# Per-repo enable: idempotent git config so this repo's commits/pushes act as the
# GitHub App, plus the `gh-app.enabled` marker the gh shim keys on. Run inside the
# target repo AFTER machine install + populating the shared env. See the runbook.
set -euo pipefail

# Parse "owner/repo" from a git remote URL (SSH or HTTPS). Prints it, or returns 1.
parse_owner_repo() {
  local url="${1%.git}" or
  case "$url" in
    git@*:*/*)     or="${url#*:}" ;;
    ssh://*/*/*)   or="${url#ssh://*/}" ;;
    https://*/*/*) or="${url#https://*/}" ;;
    http://*/*/*)  or="${url#http://*/}" ;;
    *) return 1 ;;
  esac
  [[ "$or" == */* && "$or" != */*/* ]] || return 1
  printf '%s\n' "$or"
}

if [[ "${1:-}" == "--parse" ]]; then
  parse_owner_repo "${2:-}" || { echo "cannot parse owner/repo from: ${2:-}" >&2; exit 1; }
  exit 0
fi

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="${GITHUB_APP_ENV:-$HOME/.config/gh-app/github-app.env}"
if [[ -f "$env_file" ]]; then
  set -a; # shellcheck disable=SC1090
  source "$env_file"; set +a
fi

: "${GITHUB_APP_SLUG:?GITHUB_APP_SLUG not set (see the github-app-identity setup runbook)}"
: "${GITHUB_APP_BOT_USER_ID:?GITHUB_APP_BOT_USER_ID not set}"

repo_root="$(git rev-parse --show-toplevel)"
origin_url="$(git -C "$repo_root" remote get-url origin)"
owner_repo="$(parse_owner_repo "$origin_url")" \
  || { echo "cannot derive owner/repo from origin: $origin_url" >&2; exit 1; }

bot_name="${GITHUB_APP_SLUG}[bot]"
bot_email="${GITHUB_APP_BOT_USER_ID}+${GITHUB_APP_SLUG}[bot]@users.noreply.github.com"
helper="$dir/git-credential-github-app.sh"

git -C "$repo_root" config user.name  "$bot_name"
git -C "$repo_root" config user.email "$bot_email"
git -C "$repo_root" remote set-url origin "https://github.com/${owner_repo}.git"
git -C "$repo_root" config credential.https://github.com.helper "$helper"
git -C "$repo_root" config credential.https://github.com.useHttpPath false
git -C "$repo_root" config gh-app.enabled true

echo "Enabled GitHub App identity for ${owner_repo}:"
echo "  commit identity: $bot_name <$bot_email>"
echo "  origin over HTTPS + credential helper: $helper"
echo "  gh-app.enabled = true (the gh shim will act as the App here)"
