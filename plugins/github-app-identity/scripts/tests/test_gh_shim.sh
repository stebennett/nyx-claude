#!/usr/bin/env bash
# Offline tests for the directory-aware gh shim. No real gh, repo, or network.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shim="$here/../gh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# A stub "real gh" that records argv and whether GH_TOKEN was set.
stub="$work/realgh"
cat > "$stub" <<EOF
#!/usr/bin/env bash
echo "GH_TOKEN=\${GH_TOKEN:-<unset>}" > "$work/ran"
printf '%s\n' "\$@" >> "$work/ran"
EOF
chmod +x "$stub"

# Case a: NOT enabled -> pass-through to real gh, no token minted.
rm -f "$work/ran"
( cd "$work" && GH_APP_REAL_GH="$stub" bash "$shim" api /rate_limit )
grep -q 'GH_TOKEN=<unset>' "$work/ran" || { echo "FAIL(a): token set on pass-through" >&2; exit 1; }
grep -q 'api' "$work/ran" || { echo "FAIL(a): args not forwarded" >&2; exit 1; }

# Case b: enabled + empty token -> abort, real gh NOT run.
rm -f "$work/ran"
empty="$work/empty"; printf '#!/usr/bin/env bash\nexit 0\n' > "$empty"; chmod +x "$empty"
if GH_APP_ENABLED_OVERRIDE=true GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$empty" bash "$shim" api /x >/dev/null 2>&1; then
  echo "FAIL(b): shim ran with empty token" >&2; exit 1
fi
if [[ -f "$work/ran" ]]; then echo "FAIL(b): real gh was invoked despite empty token" >&2; exit 1; fi

# Case c: enabled + token -> real gh invoked with GH_TOKEN set.
rm -f "$work/ran"
tok="$work/tok"; printf '#!/usr/bin/env bash\necho ghs_REAL\n' > "$tok"; chmod +x "$tok"
GH_APP_ENABLED_OVERRIDE=true GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$tok" bash "$shim" pr view 1
grep -q 'GH_TOKEN=ghs_REAL' "$work/ran" || { echo "FAIL(c): GH_TOKEN not passed to real gh" >&2; exit 1; }

# Case d: no recursion — shim resolves a real gh that is not itself, via PATH.
rm -f "$work/ran"
bindir="$work/bin"; realdir="$work/real"; mkdir -p "$bindir" "$realdir"
cp "$shim" "$bindir/gh"; chmod +x "$bindir/gh"
cp "$stub" "$realdir/gh"; chmod +x "$realdir/gh"
GH_APP_ENABLED_OVERRIDE=true GITHUB_APP_TOKEN_CMD="$tok" PATH="$bindir:$realdir:$PATH" "$bindir/gh" issue list
grep -q 'GH_TOKEN=ghs_REAL' "$work/ran" || { echo "FAIL(d): shim did not resolve/exec the real gh" >&2; exit 1; }

echo "PASS: gh shim pass-through / abort / App-auth / no-recursion"
