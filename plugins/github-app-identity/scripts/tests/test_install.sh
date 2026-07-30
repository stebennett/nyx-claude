#!/usr/bin/env bash
# Offline test: install.sh places every executable plus the sourced library
# into GH_APP_BIN, and the installed shim can find its library.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install="$here/../install.sh"
bin="$(mktemp -d)"; trap 'rm -rf "$bin"' EXIT

GH_APP_BIN="$bin" bash "$install" >/dev/null

for f in gh github-app-token.sh git-credential-github-app.sh setup-github-app-git.sh gh-app-status.sh; do
  [[ -x "$bin/$f" ]] || { echo "FAIL: $f not installed/executable" >&2; exit 1; }
done

# The library is sourced, not executed: present, readable, not executable.
[[ -f "$bin/gh-app-common.sh" ]] || { echo "FAIL: gh-app-common.sh not installed" >&2; exit 1; }
if [[ -x "$bin/gh-app-common.sh" ]]; then
  echo "FAIL: gh-app-common.sh should not be executable" >&2; exit 1
fi

# An installed script must be able to source the library from its own directory.
out="$( cd / && bash -c ". '$bin/gh-app-common.sh'; gh_app_validate_profile builder && echo sourced" )"
[[ "$out" == "sourced" ]] || { echo "FAIL: installed library did not source cleanly: $out" >&2; exit 1; }

echo "PASS: install placed all five executables plus the sourced library in GH_APP_BIN"
