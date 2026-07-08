#!/usr/bin/env bash
# Mint (and cache) a GitHub App installation access token, printed to stdout.
# Config is read from $GITHUB_APP_ENV (default ~/.config/gh-app/github-app.env)
# or the process environment. See the github-app-identity setup runbook.
set -euo pipefail

env_file="${GITHUB_APP_ENV:-$HOME/.config/gh-app/github-app.env}"
if [[ -f "$env_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
fi

cache_file="${GITHUB_APP_TOKEN_CACHE:-$HOME/.cache/gh-app/github-app-token.json}"

# --- Reuse a cached token while > 5 min of life remains (no config/network needed). ---
if [[ -f "$cache_file" ]]; then
  read -r cached_token cached_exp < <(
    python3 - "$cache_file" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get("token", ""), int(d.get("expires_at_epoch", 0)))
except Exception:
    print("", 0)
PY
  )
  if [[ -n "$cached_token" && $((cached_exp - $(date +%s))) -gt 300 ]]; then
    printf '%s\n' "$cached_token"
    exit 0
  fi
fi

# --- Mint a fresh token. ---
: "${GITHUB_APP_ID:?GITHUB_APP_ID not set (see the github-app-identity setup runbook)}"
: "${GITHUB_APP_INSTALLATION_ID:?GITHUB_APP_INSTALLATION_ID not set}"
: "${GITHUB_APP_PRIVATE_KEY_PATH:?GITHUB_APP_PRIVATE_KEY_PATH not set}"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

now="$(date +%s)"
header_b64="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)"
payload_b64="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$GITHUB_APP_ID" | b64url)"
signing_input="${header_b64}.${payload_b64}"
signature="$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$GITHUB_APP_PRIVATE_KEY_PATH" | b64url)"
jwt="${signing_input}.${signature}"

response="$(curl -sS -X POST \
  -H "Authorization: Bearer $jwt" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens")"

read -r token exp_epoch < <(
  printf '%s' "$response" | python3 -c '
import json, sys, calendar, time
d = json.load(sys.stdin)
if "token" not in d:
    sys.stderr.write("no token in response: %s\n" % d); sys.exit(1)
exp = calendar.timegm(time.strptime(d["expires_at"], "%Y-%m-%dT%H:%M:%SZ"))
print(d["token"], exp)
'
) || { echo "Failed to mint installation token. Response: $response" >&2; exit 1; }

umask 077
mkdir -p "$(dirname "$cache_file")"
printf '{"token":"%s","expires_at_epoch":%s}\n' "$token" "$exp_epoch" > "$cache_file"
chmod 600 "$cache_file"

printf '%s\n' "$token"
