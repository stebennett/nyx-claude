#!/usr/bin/env bash
# Offline test: `get` emits x-access-token username and the token as password.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper="$here/../git-credential-github-app.sh"

stub="$(mktemp)"; chmod +x "$stub"
printf '#!/usr/bin/env bash\necho faketoken\n' > "$stub"
trap 'rm -f "$stub"' EXIT

out="$(printf 'protocol=https\nhost=github.com\n\n' | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" get)"

echo "$out" | grep -qx 'username=x-access-token' || { echo "FAIL: missing username line: $out" >&2; exit 1; }
echo "$out" | grep -qx 'password=faketoken'      || { echo "FAIL: missing password line: $out" >&2; exit 1; }
echo "PASS: credential helper emits x-access-token + token"
