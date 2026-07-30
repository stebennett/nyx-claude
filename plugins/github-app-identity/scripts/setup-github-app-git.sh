#!/usr/bin/env bash
# Per-repo enable: idempotent git config so this repo's commits/pushes act as a
# named GitHub App profile. Writes gh-app.profile, which the gh shim and the
# credential helper key on. Run inside the target repo with a profile name
# (see GH_APP_PROFILE_DIR / the profiles created by machine install). See the runbook.
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

https_url="https://github.com/${owner_repo}.git"

# A url.<base>.insteadOf rule (e.g. from a personal dotfile) can silently
# rewrite our HTTPS origin back to SSH, which would defeat the credential
# helper we are about to install: pushes would go out over SSH under the
# user's personal key and never reach the App. Detect and refuse before any
# config is written, rather than leaving the repo half-configured or working
# around it with a token-in-URL trick. `ls-remote --get-url` applies
# insteadOf resolution and needs no network and no configured remote.
effective_url="$(git ls-remote --get-url "$https_url")"
if [ "$effective_url" != "$https_url" ]; then
  gh_app_die "this repo's HTTPS URL is rewritten to '$effective_url' by a url.*.insteadOf rule in your git config.
Pushes would go out over SSH as your personal identity and never reach the App credential helper.
Remove or narrow that rule (e.g. git config --global --unset-all url.<base>.insteadof), then re-run."
fi

# `ls-remote --get-url` (above) only resolves `insteadOf`, which applies to
# every operation. `pushInsteadOf` rewrites pushes only and is invisible to
# it: verified against git 2.50.1, a global `pushInsteadOf` rule leaves
# `ls-remote --get-url` reporting the clean HTTPS URL while `git remote
# get-url --push` (what a real push actually uses) is rewritten to SSH. Scan
# the config directly for both rewrite keys and check whether any rule's
# value is a prefix of our target HTTPS URL — belt and braces alongside the
# ls-remote check above, not a replacement for it.
rewrite_rules="$(git config --get-regexp '^url\..*\.(push)?insteadof$' 2>/dev/null || true)"
if [ -n "$rewrite_rules" ]; then
  offending=""
  while IFS= read -r rule_line; do
    [ -n "$rule_line" ] || continue
    rule_key="${rule_line%% *}"
    rule_value="${rule_line#* }"
    case "$https_url" in
      "$rule_value"*) offending="${offending}${rule_key} = ${rule_value}
" ;;
    esac
  done <<EOF
$rewrite_rules
EOF
  if [ -n "$offending" ]; then
    gh_app_die "this repo's HTTPS URL would be rewritten by url.*.insteadOf/pushInsteadOf rule(s) in your git config:
${offending}Pushes (pushInsteadOf) or all operations (insteadOf) would go out under the rewritten base and never reach the App credential helper.
Remove or narrow the rule(s) (e.g. git config --global --unset-all url.<base>.insteadof, or ...pushinsteadof), then re-run."
  fi
fi

bot_name="${GITHUB_APP_SLUG}[bot]"
bot_email="${GITHUB_APP_BOT_USER_ID}+${GITHUB_APP_SLUG}[bot]@users.noreply.github.com"
helper="$dir/git-credential-github-app.sh"
# A plain (non-"!") credential.helper value is split on whitespace with no
# quoting at all, so a plugin path containing a space would break in two. The
# "!"-prefixed form is instead run through $SHELL -c, where our double quotes
# are honored, so it survives a space in the path.
helper_value="!\"$helper\" --profile $profile"

git -C "$repo_root" config --local user.name  "$bot_name"
git -C "$repo_root" config --local user.email "$bot_email"
git -C "$repo_root" remote set-url origin "$https_url"

# git collects credential helpers system -> global -> local and uses the FIRST
# that answers. `gh auth login` writes a github.com helper into ~/.gitconfig and
# macOS ships osxkeychain in the system config, so simply appending ours would
# leave it unreachable and push as the personal account. An empty value resets
# the accumulated list, making ours the only helper for this host.
git -C "$repo_root" config --local --unset-all credential.https://github.com.helper || true
git -C "$repo_root" config --local --add credential.https://github.com.helper ""
git -C "$repo_root" config --local --add credential.https://github.com.helper "$helper_value"
git -C "$repo_root" config --local credential.https://github.com.useHttpPath false

git -C "$repo_root" config --local gh-app.profile "$profile"
git -C "$repo_root" config --local --unset-all gh-app.enabled || true

echo "Enabled GitHub App identity '$profile' for ${owner_repo}:"
echo "  commit identity: $bot_name <$bot_email>"
echo "  origin over HTTPS, credential helper reset to: $helper_value"
echo "  gh-app.profile = $profile (gh and git push act as this App here)"
echo "  verify with: gh-app-status.sh"
