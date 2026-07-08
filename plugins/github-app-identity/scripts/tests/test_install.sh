#!/usr/bin/env bash
# Offline test: install.sh places the four executables into GH_APP_BIN.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install="$here/../install.sh"
bin="$(mktemp -d)"; trap 'rm -rf "$bin"' EXIT

GH_APP_BIN="$bin" bash "$install" >/dev/null

for f in gh github-app-token.sh git-credential-github-app.sh setup-github-app-git.sh; do
  [[ -x "$bin/$f" ]] || { echo "FAIL: $f not installed/executable" >&2; exit 1; }
done
echo "PASS: install placed all four executables in GH_APP_BIN"
