#!/usr/bin/env bash
# Offline test: a fresh cached token is reused verbatim without config or network.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../github-app-token.sh"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

future=$(( $(date +%s) + 3600 ))
printf '{"token":"ghs_CACHEDTOKEN123","expires_at_epoch":%s}\n' "$future" > "$tmp"

out="$(GITHUB_APP_ENV=/dev/null GITHUB_APP_TOKEN_CACHE="$tmp" bash "$script")"

if [[ "$out" != "ghs_CACHEDTOKEN123" ]]; then
  echo "FAIL: expected cached token, got: '$out'" >&2
  exit 1
fi
echo "PASS: cache-reuse path returns cached token"
