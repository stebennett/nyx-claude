#!/usr/bin/env bash
# Offline tests: --profile is required, caches are keyed per profile, and a
# missing profile errors rather than serving another profile's cached token.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../github-app-token.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

profiles="$work/profiles"; cache="$work/cache"; mkdir -p "$profiles" "$cache"
for p in builder pr-reviewer; do
  cat > "$profiles/$p.env" <<EOF
GITHUB_APP_ID=1
GITHUB_APP_INSTALLATION_ID=2
GITHUB_APP_PRIVATE_KEY_PATH=/dev/null
GITHUB_APP_SLUG=$p
GITHUB_APP_BOT_USER_ID=3
EOF
done

future=$(( $(date +%s) + 3600 ))
printf '{"token":"ghs_BUILDER","expires_at_epoch":%s}\n'  "$future" > "$cache/token-builder.json"
printf '{"token":"ghs_REVIEWER","expires_at_epoch":%s}\n' "$future" > "$cache/token-pr-reviewer.json"

run() { GH_APP_PROFILE_DIR="$profiles" GH_APP_CACHE_DIR="$cache" bash "$script" "$@"; }

# --- each profile gets its own cached token: no bleed between identities ---
out="$(run --profile builder)"
[[ "$out" == "ghs_BUILDER" ]] || { echo "FAIL: builder got '$out'" >&2; exit 1; }
out="$(run --profile pr-reviewer)"
[[ "$out" == "ghs_REVIEWER" ]] || { echo "FAIL: pr-reviewer got '$out'" >&2; exit 1; }

# --- --profile=<name> form works too ---
out="$(run --profile=builder)"
[[ "$out" == "ghs_BUILDER" ]] || { echo "FAIL: --profile= form got '$out'" >&2; exit 1; }

# --- no --profile: refuse (an implicit default is how the wrong token gets minted) ---
if run >/dev/null 2>&1; then echo "FAIL: ran without --profile" >&2; exit 1; fi

# --- unknown profile: error, and do NOT fall back to any cached token ---
if out="$(run --profile ghost 2>/dev/null)"; then
  echo "FAIL: unknown profile succeeded with '$out'" >&2; exit 1
fi

# --- a profile whose env file was deleted must error, not serve a stale cache ---
rm -f "$profiles/builder.env"
if out="$(run --profile builder 2>/dev/null)"; then
  echo "FAIL: deleted profile served a stale cached token '$out'" >&2; exit 1
fi

# --- an expired cache entry is not reused (no network here, so it must fail loudly) ---
past=$(( $(date +%s) - 60 ))
printf '{"token":"ghs_STALE","expires_at_epoch":%s}\n' "$past" > "$cache/token-pr-reviewer.json"
out="$(run --profile pr-reviewer 2>/dev/null || true)"
[[ "$out" != "ghs_STALE" ]] || { echo "FAIL: reused an expired token" >&2; exit 1; }

echo "PASS: token minter requires --profile and isolates caches per profile"
