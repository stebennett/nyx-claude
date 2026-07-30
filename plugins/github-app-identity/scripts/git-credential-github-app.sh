#!/usr/bin/env bash
# git credential helper: supplies a GitHub App installation token for HTTPS git ops.
# Configured by setup-github-app-git.sh as:
#   credential.https://github.com.helper = <abs path> --profile <name>
# git appends the operation (get/store/erase) as the LAST argument, so the
# profile has to be scanned for rather than read from $1.
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gh-app-common.sh
. "$dir/gh-app-common.sh"

profile=""
op=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   profile="${2:-}"; shift 2 ;;
    --profile=*) profile="${1#--profile=}"; shift ;;
    *) op="$1"; shift ;;
  esac
done

case "$op" in
  get)
    if [ -z "$profile" ]; then
      echo "gh-app credential helper: no --profile in the git config helper line." >&2
      echo "gh-app: re-run: setup-github-app-git.sh <profile>" >&2
      exit 1
    fi
    token="$("${GITHUB_APP_TOKEN_CMD:-$dir/github-app-token.sh}" --profile "$profile")" \
      || gh_app_die "credential helper could not mint a token for profile '$profile'. $GH_APP_DOCTRINE"
    [ -n "$token" ] \
      || gh_app_die "credential helper got an empty token for profile '$profile'. $GH_APP_DOCTRINE"
    echo "username=x-access-token"
    echo "password=$token"
    ;;
  *)
    # store/erase: nothing to persist — tokens are minted fresh each time.
    : ;;
esac
