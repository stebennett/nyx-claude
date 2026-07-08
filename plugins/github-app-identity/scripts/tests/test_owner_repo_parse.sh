#!/usr/bin/env bash
# Offline test: owner/repo is parsed from SSH & HTTPS remotes; garbage errors out.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup="$here/../setup-github-app-git.sh"

check() { # url expected
  local got; got="$(bash "$setup" --parse "$1")" || { echo "FAIL: parse errored on '$1'" >&2; exit 1; }
  [[ "$got" == "$2" ]] || { echo "FAIL: '$1' -> '$got', expected '$2'" >&2; exit 1; }
}

check "git@github.com:acme/widget.git"          "acme/widget"
check "git@github.com:acme/widget"              "acme/widget"
check "https://github.com/acme/widget.git"      "acme/widget"
check "https://github.com/acme/widget"          "acme/widget"
check "ssh://git@github.com/acme/widget.git"    "acme/widget"

if bash "$setup" --parse "not-a-remote-url" >/dev/null 2>&1; then
  echo "FAIL: garbage remote should error" >&2; exit 1
fi
echo "PASS: owner/repo parsed from SSH/HTTPS, garbage rejected"
