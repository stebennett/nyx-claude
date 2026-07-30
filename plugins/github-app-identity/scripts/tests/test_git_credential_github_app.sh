#!/usr/bin/env bash
# Offline tests: the helper scans for --profile (git appends the operation
# last), emits x-access-token, and refuses to answer without a profile.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper="$here/../git-credential-github-app.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# Token stub echoing a token derived from --profile.
stub="$work/tok"
cat > "$stub" <<'EOF'
#!/usr/bin/env bash
p=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   p="${2:-}"; shift 2 ;;
    --profile=*) p="${1#--profile=}"; shift ;;
    *) shift ;;
  esac
done
[ -n "$p" ] || exit 1
echo "tok_$p"
EOF
chmod +x "$stub"

req() { printf 'protocol=https\nhost=github.com\n\n'; }

# --- get, with the operation appended last as git does it ---
out="$(req | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" --profile pr-reviewer get)"
echo "$out" | grep -qx 'username=x-access-token' \
  || { echo "FAIL: missing username line: $out" >&2; exit 1; }
echo "$out" | grep -qx 'password=tok_pr-reviewer' \
  || { echo "FAIL: wrong/missing password line: $out" >&2; exit 1; }

# --- the profile actually selects the identity ---
out="$(req | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" --profile builder get)"
echo "$out" | grep -qx 'password=tok_builder' \
  || { echo "FAIL: helper ignored the profile: $out" >&2; exit 1; }

# --- get with no --profile: no credentials, non-zero exit ---
if out="$(req | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" get 2>/dev/null)"; then
  echo "FAIL: answered without a profile" >&2; exit 1
fi

# --- --profile with no value: must say so, not die silently on `shift 2` ---
err="$(req | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" --profile 2>&1 >/dev/null || true)"
if req | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" --profile >/dev/null 2>&1; then
  echo "FAIL: accepted a valueless --profile" >&2; exit 1
fi
echo "$err" | grep -q 'requires a value' \
  || { echo "FAIL: valueless --profile gave no diagnostic, got: '$err'" >&2; exit 1; }
if echo "${out:-}" | grep -q 'password='; then
  echo "FAIL: leaked a password line without a profile" >&2; exit 1
fi

# --- get when the token command fails: no credentials, non-zero exit ---
boom="$work/boom"; printf '#!/usr/bin/env bash\nexit 3\n' > "$boom"; chmod +x "$boom"
if out="$(req | GITHUB_APP_TOKEN_CMD="$boom" bash "$helper" --profile builder get 2>/dev/null)"; then
  echo "FAIL: answered despite a failing token command" >&2; exit 1
fi

# --- store/erase are no-ops that succeed (tokens are minted fresh each time) ---
req | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" --profile builder store >/dev/null
req | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" --profile builder erase >/dev/null

echo "PASS: credential helper honours --profile and fails closed"
