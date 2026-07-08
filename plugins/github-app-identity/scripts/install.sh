#!/usr/bin/env bash
# Machine-once install: put the GitHub App identity scripts on PATH.
# Override the target dir with GH_APP_BIN (default ~/.local/bin).
set -euo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="${GH_APP_BIN:-$HOME/.local/bin}"
mkdir -p "$bin"

for f in gh github-app-token.sh git-credential-github-app.sh setup-github-app-git.sh; do
  install -m 0755 "$src/$f" "$bin/$f"
done
echo "Installed gh-app scripts to $bin"

# Warn (non-fatal) if $bin is absent from PATH or doesn't precede the real gh.
case ":$PATH:" in
  *":$bin:"*) : ;;
  *) echo "WARNING: $bin is not on PATH — add it (ahead of your real gh)." >&2 ;;
esac

first_gh_dir=""
IFS=: read -ra parts <<< "$PATH"
for p in "${parts[@]}"; do
  [[ -x "$p/gh" ]] && { first_gh_dir="$(cd "$p" 2>/dev/null && pwd || true)"; break; }
done
if [[ -n "$first_gh_dir" && "$first_gh_dir" != "$bin" ]]; then
  echo "WARNING: a gh at $first_gh_dir precedes the shim — put $bin earlier on PATH." >&2
fi
