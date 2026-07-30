#!/usr/bin/env bash
# Offline tests for the directory-aware gh shim. Real git repos, stub gh,
# stub token command. No network.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shim="$here/../gh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# Stub "real gh": records GH_TOKEN and argv.
stub="$work/realgh"
cat > "$stub" <<EOF
#!/usr/bin/env bash
echo "GH_TOKEN=\${GH_TOKEN:-<unset>}" > "$work/ran"
printf '%s\n' "\$@" >> "$work/ran"
EOF
chmod +x "$stub"

# Stub token command: echoes a token derived from the --profile it was given,
# so the test can prove the right profile reached it.
tok="$work/tok"
cat > "$tok" <<'EOF'
#!/usr/bin/env bash
p=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   p="${2:-}"; shift 2 ;;
    --profile=*) p="${1#--profile=}"; shift ;;
    *) shift ;;
  esac
done
[ -n "$p" ] || { echo "token stub: no --profile" >&2; exit 1; }
echo "ghs_TOKEN_FOR_$p"
EOF
chmod +x "$tok"

# Case a: not a repo -> pass-through, no token.
rm -f "$work/ran"; outside="$work/outside"; mkdir -p "$outside"
( cd "$outside" && GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$tok" bash "$shim" api /rate_limit )
grep -q 'GH_TOKEN=<unset>' "$work/ran" || { echo "FAIL(a): token set on pass-through" >&2; exit 1; }
grep -q 'api' "$work/ran" || { echo "FAIL(a): args not forwarded" >&2; exit 1; }

# Case b: repo with no marker -> pass-through.
rm -f "$work/ran"; plain="$work/plain"; mkdir -p "$plain"; ( cd "$plain" && git init -q . )
( cd "$plain" && GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$tok" bash "$shim" pr list )
grep -q 'GH_TOKEN=<unset>' "$work/ran" || { echo "FAIL(b): token set in unconfigured repo" >&2; exit 1; }

# Case c/d: two clones, two identities -> each gets its own profile's token.
for pair in "build:builder" "review:pr-reviewer"; do
  d="$work/${pair%%:*}"; p="${pair##*:}"
  mkdir -p "$d"; ( cd "$d" && git init -q . && git config --local gh-app.profile "$p" )
  rm -f "$work/ran"
  ( cd "$d" && GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$tok" bash "$shim" pr view 1 )
  grep -q "GH_TOKEN=ghs_TOKEN_FOR_$p" "$work/ran" \
    || { echo "FAIL(c/d): clone $d did not authenticate as '$p': $(cat "$work/ran")" >&2; exit 1; }
done

# Case e: enabled repo + empty token -> abort, real gh NOT run.
rm -f "$work/ran"
empty="$work/empty"; printf '#!/usr/bin/env bash\nexit 0\n' > "$empty"; chmod +x "$empty"
if ( cd "$work/build" && GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$empty" bash "$shim" api /x ) >/dev/null 2>&1; then
  echo "FAIL(e): shim ran with an empty token" >&2; exit 1
fi
if [[ -f "$work/ran" ]]; then echo "FAIL(e): real gh was invoked despite empty token" >&2; exit 1; fi

# Case f: enabled repo + failing token command -> abort, real gh NOT run.
rm -f "$work/ran"
boom="$work/boom"; printf '#!/usr/bin/env bash\nexit 3\n' > "$boom"; chmod +x "$boom"
if ( cd "$work/build" && GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$boom" bash "$shim" api /x ) >/dev/null 2>&1; then
  echo "FAIL(f): shim ran despite a failing token command" >&2; exit 1
fi
if [[ -f "$work/ran" ]]; then echo "FAIL(f): real gh was invoked despite token failure" >&2; exit 1; fi

# Case g: legacy marker with no profile -> abort, never pass-through to personal auth.
rm -f "$work/ran"; legacy="$work/legacy"; mkdir -p "$legacy"
( cd "$legacy" && git init -q . && git config --local gh-app.enabled true )
if ( cd "$legacy" && GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$tok" bash "$shim" api /x ) >/dev/null 2>&1; then
  echo "FAIL(g): legacy repo passed through to personal auth" >&2; exit 1
fi
if [[ -f "$work/ran" ]]; then echo "FAIL(g): real gh ran in a legacy repo" >&2; exit 1; fi

# Case h: no recursion — the shim resolves a real gh that is not itself, via PATH.
rm -f "$work/ran"
bindir="$work/bin"; realdir="$work/real"; mkdir -p "$bindir" "$realdir"
cp "$shim" "$bindir/gh"; cp "$here/../gh-app-common.sh" "$bindir/"; chmod +x "$bindir/gh"
cp "$stub" "$realdir/gh"; chmod +x "$realdir/gh"
( cd "$work/build" && GITHUB_APP_TOKEN_CMD="$tok" PATH="$bindir:$realdir:$PATH" "$bindir/gh" issue list )
grep -q 'GH_TOKEN=ghs_TOKEN_FOR_builder' "$work/ran" \
  || { echo "FAIL(h): shim did not resolve/exec the real gh" >&2; exit 1; }

echo "PASS: gh shim pass-through / per-clone identity / abort / legacy trap / no-recursion"
