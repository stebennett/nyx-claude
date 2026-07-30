#!/usr/bin/env bash
# Offline tests for per-repo setup, including the regression that matters:
# an inherited global credential helper must not beat ours. Requires git >= 2.32
# for GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup="$here/../setup-github-app-git.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

profiles="$work/profiles"; mkdir -p "$profiles"
cat > "$profiles/pr-reviewer.env" <<'EOF'
GITHUB_APP_ID=1
GITHUB_APP_INSTALLATION_ID=2
GITHUB_APP_PRIVATE_KEY_PATH=/dev/null
GITHUB_APP_SLUG=my-reviewer
GITHUB_APP_BOT_USER_ID=4242
EOF

repo="$work/repo"; mkdir -p "$repo"
( cd "$repo" && git init -q . && git remote add origin git@github.com:acme/widget.git )

run_setup() { ( cd "$repo" && GH_APP_PROFILE_DIR="$profiles" bash "$setup" "$@" ); }

# --- a profile argument is required ---
if run_setup >/dev/null 2>&1; then echo "FAIL: ran with no profile" >&2; exit 1; fi
if run_setup ghost >/dev/null 2>&1; then echo "FAIL: accepted an unknown profile" >&2; exit 1; fi

run_setup pr-reviewer >/dev/null

cfg() { git -C "$repo" config --local --get "$1"; }

# --- identity, marker, and remote ---
[[ "$(cfg user.name)"  == "my-reviewer[bot]" ]] || { echo "FAIL: user.name = $(cfg user.name)" >&2; exit 1; }
[[ "$(cfg user.email)" == "4242+my-reviewer[bot]@users.noreply.github.com" ]] \
  || { echo "FAIL: user.email = $(cfg user.email)" >&2; exit 1; }
[[ "$(cfg gh-app.profile)" == "pr-reviewer" ]] || { echo "FAIL: gh-app.profile not set" >&2; exit 1; }
[[ "$(git -C "$repo" remote get-url origin)" == "https://github.com/acme/widget.git" ]] \
  || { echo "FAIL: origin not switched to HTTPS" >&2; exit 1; }

# --- helper list: exactly one empty reset then one helper carrying the profile ---
helpers="$(git -C "$repo" config --local --get-all credential.https://github.com.helper)"
[[ "$(printf '%s\n' "$helpers" | wc -l | tr -d ' ')" == "2" ]] \
  || { echo "FAIL: expected 2 helper values, got: $helpers" >&2; exit 1; }
[[ -z "$(printf '%s\n' "$helpers" | sed -n '1p')" ]] \
  || { echo "FAIL: first helper value is not the empty reset: $helpers" >&2; exit 1; }
printf '%s\n' "$helpers" | sed -n '2p' | grep -q -- '--profile pr-reviewer' \
  || { echo "FAIL: helper line lacks --profile pr-reviewer: $helpers" >&2; exit 1; }

# --- idempotence: running twice must not duplicate the helper values ---
run_setup pr-reviewer >/dev/null
helpers="$(git -C "$repo" config --local --get-all credential.https://github.com.helper)"
[[ "$(printf '%s\n' "$helpers" | wc -l | tr -d ' ')" == "2" ]] \
  || { echo "FAIL: helper values duplicated on re-run: $helpers" >&2; exit 1; }

# --- a legacy gh-app.enabled marker is cleared ---
git -C "$repo" config --local gh-app.enabled true
run_setup pr-reviewer >/dev/null
if git -C "$repo" config --local --get gh-app.enabled >/dev/null 2>&1; then
  echo "FAIL: legacy gh-app.enabled survived setup" >&2; exit 1
fi

# --- REGRESSION: an inherited global helper must not answer before ours ---
# Reproduces the real machine: `gh auth login` writes a github.com helper into
# ~/.gitconfig, and the system gitconfig adds osxkeychain.
personal="$work/helper-personal"
cat > "$personal" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = get ] && { echo username=personal-user; echo password=PERSONAL_TOKEN; }
EOF
chmod +x "$personal"

ours="$work/helper-app"
cat > "$ours" <<'EOF'
#!/usr/bin/env bash
op=""
while [ $# -gt 0 ]; do case "$1" in --profile) shift 2 ;; --profile=*) shift ;; *) op="$1"; shift ;; esac; done
[ "$op" = get ] && { echo username=x-access-token; echo password=APP_TOKEN; }
EOF
chmod +x "$ours"

printf '[credential]\n\thelper = osxkeychain-stub\n' > "$work/system.gitconfig"
printf '[credential "https://github.com"]\n\thelper =\n\thelper = %s\n' "$personal" > "$work/global.gitconfig"

# Point the repo's local helper at our stub, exactly as setup wrote it (path + --profile).
git -C "$repo" config --local --unset-all credential.https://github.com.helper
git -C "$repo" config --local --add credential.https://github.com.helper ""
git -C "$repo" config --local --add credential.https://github.com.helper "$ours --profile pr-reviewer"

creds="$( printf 'protocol=https\nhost=github.com\n\n' \
  | GIT_CONFIG_SYSTEM="$work/system.gitconfig" GIT_CONFIG_GLOBAL="$work/global.gitconfig" \
    GIT_TERMINAL_PROMPT=0 git -C "$repo" credential fill 2>/dev/null )"

echo "$creds" | grep -qx 'username=x-access-token' \
  || { echo "FAIL: REGRESSION — an inherited helper won the credential race: $creds" >&2; exit 1; }
if echo "$creds" | grep -q 'PERSONAL_TOKEN'; then
  echo "FAIL: REGRESSION — personal credentials were returned: $creds" >&2; exit 1
fi

echo "PASS: per-repo setup writes the profile, is idempotent, and beats inherited helpers"
