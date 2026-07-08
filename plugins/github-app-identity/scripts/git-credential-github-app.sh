#!/usr/bin/env bash
# git credential helper: supplies a GitHub App installation token for HTTPS git ops.
# Configured via: git config credential.https://github.com.helper <abs path to this file>
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  get)
    token="$("${GITHUB_APP_TOKEN_CMD:-$dir/github-app-token.sh}")"
    echo "username=x-access-token"
    echo "password=$token"
    ;;
  *)
    # store/erase: nothing to persist — tokens are minted fresh each time.
    : ;;
esac
