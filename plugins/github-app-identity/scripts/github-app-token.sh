#!/usr/bin/env bash
# Mint (and cache) a GitHub App installation access token, printed to stdout.
#   github-app-token.sh --profile <name>
# Profile config comes from $GH_APP_PROFILE_DIR/<name>.env; tokens are cached
# per profile so two identities can never reuse each other's token.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gh-app-common.sh
. "$dir/gh-app-common.sh"

profile=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   [ $# -ge 2 ] || gh_app_die "--profile requires a value (usage: github-app-token.sh --profile <name>)"
                 profile="$2"; shift 2 ;;
    --profile=*) profile="${1#--profile=}"; shift ;;
    *) gh_app_die "unknown argument '$1' (usage: github-app-token.sh --profile <name>)" ;;
  esac
done
[ -n "$profile" ] || gh_app_die "--profile <name> is required (usage: github-app-token.sh --profile <name>)"

# Load before touching the cache: a deleted or mistyped profile must error
# rather than quietly serve a token minted under some other identity.
gh_app_load_profile "$profile"

cache_file="$(gh_app_cache_dir)/token-$profile.json"

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
: "${GITHUB_APP_ID:?GITHUB_APP_ID not set in $GH_APP_PROFILE_FILE}"
: "${GITHUB_APP_INSTALLATION_ID:?GITHUB_APP_INSTALLATION_ID not set in $GH_APP_PROFILE_FILE}"
: "${GITHUB_APP_PRIVATE_KEY_PATH:?GITHUB_APP_PRIVATE_KEY_PATH not set in $GH_APP_PROFILE_FILE}"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

now="$(date +%s)"
header_b64="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)"
payload_b64="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$GITHUB_APP_ID" | b64url)"
signing_input="${header_b64}.${payload_b64}"
signature="$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$GITHUB_APP_PRIVATE_KEY_PATH" | b64url)"
jwt="${signing_input}.${signature}"

response="$(curl -sS --max-time 30 -X POST \
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
) || { echo "gh-app: failed to mint an installation token for profile '$profile'. Response: $response" >&2
       echo "gh-app: $GH_APP_DOCTRINE" >&2
       exit 1; }

umask 077
mkdir -p "$(dirname "$cache_file")"
tmp_cache="$(mktemp "${cache_file}.XXXXXX")"
printf '{"token":"%s","expires_at_epoch":%s}\n' "$token" "$exp_epoch" > "$tmp_cache"
chmod 600 "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"

printf '%s\n' "$token"
