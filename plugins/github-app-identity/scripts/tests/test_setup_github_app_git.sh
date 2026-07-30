#!/usr/bin/env bash
# Offline tests for per-repo setup, including the regression that matters:
# an inherited global credential helper must not beat ours, and the pre-flight
# check that refuses to proceed when a url.*.insteadOf rule would silently
# route pushes over SSH instead. Requires git >= 2.32 for
# GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup="$here/../setup-github-app-git.sh"
scripts_dir="$(cd "$here/.." && pwd)"
expected_helper="$scripts_dir/git-credential-github-app.sh"

# This whole file's git-config assertions -- not just the regression block --
# depend on deterministic credential/insteadOf resolution, so isolate every
# case here from the real machine's ~/.gitconfig and system gitconfig up
# front. A personal insteadOf rule or credential helper on the machine
# running this test must never change whether it passes (it did, before this
# export existed: this test went red on a configured dev machine and green on
# a clean CI runner). Needs git >= 2.32 for GIT_CONFIG_GLOBAL/SYSTEM; fail
# loudly rather than passing vacuously if that's silently unsupported.
git_version_words="$(git --version | sed -nE 's/^git version ([0-9]+)\.([0-9]+).*/\1 \2/p')"
git_major="${git_version_words%% *}"
git_minor="${git_version_words##* }"
if [ -z "$git_major" ] || [ "$git_major" -lt 2 ] || { [ "$git_major" -eq 2 ] && [ "$git_minor" -lt 32 ]; }; then
  echo "FAIL: this test requires git >= 2.32 for GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM (found: $(git --version))" >&2
  exit 1
fi

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

empty_global="$work/empty-global.gitconfig"; : > "$empty_global"
empty_system="$work/empty-system.gitconfig"; : > "$empty_system"
export GIT_CONFIG_GLOBAL="$empty_global"
export GIT_CONFIG_SYSTEM="$empty_system"

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

# --- helper list: exactly one empty reset then one helper carrying the exact path + profile ---
helpers="$(git -C "$repo" config --local --get-all credential.https://github.com.helper)"
[[ "$(printf '%s\n' "$helpers" | wc -l | tr -d ' ')" == "2" ]] \
  || { echo "FAIL: expected 2 helper values, got: $helpers" >&2; exit 1; }
[[ -z "$(printf '%s\n' "$helpers" | sed -n '1p')" ]] \
  || { echo "FAIL: first helper value is not the empty reset: $helpers" >&2; exit 1; }
helper_line="$(printf '%s\n' "$helpers" | sed -n '2p')"
expected_helper_line="!\"$expected_helper\" --profile pr-reviewer"
[[ "$helper_line" == "$expected_helper_line" ]] \
  || { echo "FAIL: helper line = '$helper_line', expected '$expected_helper_line'" >&2; exit 1; }
[[ "$(cfg credential.https://github.com.useHttpPath)" == "false" ]] \
  || { echo "FAIL: useHttpPath not set to false" >&2; exit 1; }

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
# ~/.gitconfig, and the system gitconfig adds osxkeychain. This swaps only the
# real (non-empty) helper line for a stub -- the empty reset that setup itself
# wrote is left in place -- so the assertion is about setup's actual output,
# not about a helper list the test hand-wrote from scratch.
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

# '.+' matches only the non-empty (real helper) line, leaving setup's empty
# reset entry untouched.
git -C "$repo" config --local --replace-all credential.https://github.com.helper \
  "$ours --profile pr-reviewer" '.+'

creds="$( printf 'protocol=https\nhost=github.com\n\n' \
  | GIT_CONFIG_SYSTEM="$work/system.gitconfig" GIT_CONFIG_GLOBAL="$work/global.gitconfig" \
    GIT_TERMINAL_PROMPT=0 git -C "$repo" credential fill 2>/dev/null )"

echo "$creds" | grep -qx 'username=x-access-token' \
  || { echo "FAIL: REGRESSION — an inherited helper won the credential race: $creds" >&2; exit 1; }
if echo "$creds" | grep -q 'PERSONAL_TOKEN'; then
  echo "FAIL: REGRESSION — personal credentials were returned: $creds" >&2; exit 1
fi

# --- NEGATIVE CONTROL: without the reset, the inherited helper wins ---
# Proves the empty-string reset -- not some quirk of this test's wiring, and
# not a silently-ignored GIT_CONFIG_* override on an old git -- is what makes
# ours win: strip the reset out, leaving the real accumulated order
# system -> global(personal) -> local(ours), and confirm the personal helper
# now answers first, exactly as the original (pre-fix) defect did.
git -C "$repo" config --local --unset-all credential.https://github.com.helper
git -C "$repo" config --local --add credential.https://github.com.helper "$ours --profile pr-reviewer"

creds_no_reset="$( printf 'protocol=https\nhost=github.com\n\n' \
  | GIT_CONFIG_SYSTEM="$work/system.gitconfig" GIT_CONFIG_GLOBAL="$work/global.gitconfig" \
    GIT_TERMINAL_PROMPT=0 git -C "$repo" credential fill 2>/dev/null )"

echo "$creds_no_reset" | grep -qx 'username=personal-user' \
  || { echo "FAIL: negative control — without the reset, the personal helper should win but got: $creds_no_reset" >&2; exit 1; }

# --- PRE-FLIGHT: an inherited insteadOf rewrite is refused, not bypassed ---
# Simulates a personal url.*.insteadOf rule that would rewrite our HTTPS
# origin back to SSH (defeating the credential helper entirely). Setup must
# fail loudly and must not have mutated the repo's config at all.
repo2="$work/repo-insteadof"; mkdir -p "$repo2"
( cd "$repo2" && git init -q . && git remote add origin git@github.com:acme/widget.git )

insteadof_global="$work/insteadof-global.gitconfig"
printf '[url "git@github.com:"]\n\tinsteadOf = https://github.com/\n' > "$insteadof_global"

if ( cd "$repo2" && GH_APP_PROFILE_DIR="$profiles" GIT_CONFIG_GLOBAL="$insteadof_global" bash "$setup" pr-reviewer ) \
    >/dev/null 2>&1; then
  echo "FAIL: setup should refuse when an insteadOf rule rewrites the HTTPS origin" >&2; exit 1
fi
if git -C "$repo2" config --local --get gh-app.profile >/dev/null 2>&1; then
  echo "FAIL: pre-flight refusal still left gh-app.profile set — repo not left unmutated" >&2; exit 1
fi
if git -C "$repo2" config --local --get user.name >/dev/null 2>&1; then
  echo "FAIL: pre-flight refusal still left user.name set — repo not left unmutated" >&2; exit 1
fi
[[ "$(git -C "$repo2" remote get-url origin)" == "git@github.com:acme/widget.git" ]] \
  || { echo "FAIL: pre-flight refusal should leave origin untouched" >&2; exit 1; }

echo "PASS: per-repo setup writes the profile, is idempotent, beats inherited helpers, and refuses an insteadOf rewrite"
