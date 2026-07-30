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
# shellcheck source=gh-app-common.sh
. "$dir/gh-app-common.sh"

[ $# -eq 1 ] || gh_app_die "usage: setup-github-app-git.sh <profile>"
profile="$1"
gh_app_load_profile "$profile"

: "${GITHUB_APP_SLUG:?GITHUB_APP_SLUG not set in $GH_APP_PROFILE_FILE}"
: "${GITHUB_APP_BOT_USER_ID:?GITHUB_APP_BOT_USER_ID not set in $GH_APP_PROFILE_FILE}"

repo_root="$(git rev-parse --show-toplevel)"
origin_url="$(git -C "$repo_root" remote get-url origin)"
owner_repo="$(parse_owner_repo "$origin_url")" \
  || gh_app_die "cannot derive owner/repo from origin: $origin_url"

bot_name="${GITHUB_APP_SLUG}[bot]"
bot_email="${GITHUB_APP_BOT_USER_ID}+${GITHUB_APP_SLUG}[bot]@users.noreply.github.com"
helper="$dir/git-credential-github-app.sh"

git -C "$repo_root" config --local user.name  "$bot_name"
git -C "$repo_root" config --local user.email "$bot_email"
git -C "$repo_root" remote set-url origin "https://github.com/${owner_repo}.git"

# git collects credential helpers system -> global -> local and uses the FIRST
# that answers. `gh auth login` writes a github.com helper into ~/.gitconfig and
# macOS ships osxkeychain in the system config, so simply appending ours would
# leave it unreachable and push as the personal account. An empty value resets
# the accumulated list, making ours the only helper for this host.
git -C "$repo_root" config --local --unset-all credential.https://github.com.helper 2>/dev/null || true
git -C "$repo_root" config --local --add credential.https://github.com.helper ""
git -C "$repo_root" config --local --add credential.https://github.com.helper "$helper --profile $profile"
git -C "$repo_root" config --local credential.https://github.com.useHttpPath false

git -C "$repo_root" config --local gh-app.profile "$profile"
git -C "$repo_root" config --local --unset-all gh-app.enabled 2>/dev/null || true

echo "Enabled GitHub App identity '$profile' for ${owner_repo}:"
echo "  commit identity: $bot_name <$bot_email>"
echo "  origin over HTTPS, credential helper reset to: $helper --profile $profile"
echo "  gh-app.profile = $profile (gh and git push act as this App here)"
echo "  verify with: gh-app-status.sh"
