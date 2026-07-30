#!/usr/bin/env bash
# Offline tests for gh-app-status.sh. The network probe is stubbed via
# GH_APP_CURL; the token command is stubbed via GITHUB_APP_TOKEN_CMD.
#
# This whole file's git-config assertions depend on deterministic
# credential/insteadOf resolution, so isolate every case here from the real
# machine's ~/.gitconfig and system gitconfig up front, the same way
# test_setup_github_app_git.sh does. A personal insteadOf rule or credential
# helper on the machine running this test must never change whether it
# passes. Needs git >= 2.32 for GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM; fail
# loudly rather than passing vacuously if that's silently unsupported.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
status="$here/../gh-app-status.sh"

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
key="$work/app.pem"; echo "not-a-real-key" > "$key"; chmod 600 "$key"
cat > "$profiles/pr-reviewer.env" <<EOF
GITHUB_APP_ID=1
GITHUB_APP_INSTALLATION_ID=2
GITHUB_APP_PRIVATE_KEY_PATH=$key
GITHUB_APP_SLUG=my-reviewer
GITHUB_APP_BOT_USER_ID=4242
EOF

tok="$work/tok"; printf '#!/usr/bin/env bash\necho ghs_FAKE\n' > "$tok"; chmod +x "$tok"
ok="$work/curl-ok";  printf '#!/usr/bin/env bash\necho 200\n' > "$ok";  chmod +x "$ok"
no="$work/curl-404"; printf '#!/usr/bin/env bash\necho 404\n' > "$no"; chmod +x "$no"

# The real credential-helper value written by setup-github-app-git.sh carries
# a leading "!" and double-quotes the path, e.g.:
#   !"/opt/gh-app/git-credential-github-app.sh" --profile pr-reviewer
# The "!" forces git to run the value through a shell, which is what makes it
# survive a space in the plugin path (verified empirically against git
# 2.50.1: the unquoted and plain double-quoted forms both fail). Fixtures
# below use this exact shape rather than the plain unquoted form.
helper_value='!"/opt/gh-app/git-credential-github-app.sh" --profile pr-reviewer'

# run <dir> [VAR=value ...] — `env` is required: a VAR=value coming from "$@"
# expansion is a command name, not an assignment.
run() {
  local d="$1"; shift
  ( cd "$d" && GH_APP_PROFILE_DIR="$profiles" GITHUB_APP_TOKEN_CMD="$tok" env "$@" bash "$status" )
}

# --- outside a repo: pass-through is a valid state, exit 0 ---
outside="$work/outside"; mkdir -p "$outside"
out="$(run "$outside")" || { echo "FAIL: non-zero exit outside a repo" >&2; exit 1; }
echo "$out" | grep -qi 'pass' || { echo "FAIL: no pass-through note outside a repo: $out" >&2; exit 1; }

# --- repo with no profile: pass-through, exit 0 ---
plain="$work/plain"; mkdir -p "$plain"; ( cd "$plain" && git init -q . )
out="$(run "$plain")" || { echo "FAIL: non-zero exit in an unconfigured repo" >&2; exit 1; }
echo "$out" | grep -qi 'pass' || { echo "FAIL: no pass-through note: $out" >&2; exit 1; }

# --- a fully configured repo reports the identity and exits 0 ---
repo="$work/repo"; mkdir -p "$repo"
( cd "$repo" && git init -q . \
  && git remote add origin https://github.com/acme/widget.git \
  && git config --local gh-app.profile pr-reviewer \
  && git config --local user.name  "my-reviewer[bot]" \
  && git config --local user.email "4242+my-reviewer[bot]@users.noreply.github.com" \
  && git config --local --add credential.https://github.com.helper "" \
  && git config --local --add credential.https://github.com.helper "$helper_value" )
out="$(run "$repo" GH_APP_CURL="$ok")" || { echo "FAIL: non-zero exit on a healthy repo: $out" >&2; exit 1; }
echo "$out" | grep -q 'pr-reviewer'  || { echo "FAIL: profile not reported: $out" >&2; exit 1; }
echo "$out" | grep -q 'my-reviewer'  || { echo "FAIL: App slug not reported: $out" >&2; exit 1; }
echo "$out" | grep -q 'acme/widget'  || { echo "FAIL: repo not reported: $out" >&2; exit 1; }

# --- commit identity that disagrees with the profile is an inconsistency ---
( cd "$repo" && git config --local user.email "someone@example.com" )
if run "$repo" GH_APP_CURL="$ok" >/dev/null 2>&1; then
  echo "FAIL: mismatched commit identity reported healthy" >&2; exit 1
fi
( cd "$repo" && git config --local user.email "4242+my-reviewer[bot]@users.noreply.github.com" )

# --- repo outside the App installation (404) is an inconsistency ---
if run "$repo" GH_APP_CURL="$no" >/dev/null 2>&1; then
  echo "FAIL: a repo outside the installation reported healthy" >&2; exit 1
fi

# --- an unreadable private key is an inconsistency ---
mv "$key" "$key.moved"
if run "$repo" GH_APP_CURL="$ok" >/dev/null 2>&1; then
  echo "FAIL: a missing private key reported healthy" >&2; exit 1
fi
mv "$key.moved" "$key"

# --- an insteadOf rewrite of a configured HTTPS origin is its own distinct
# problem, not the same as "origin isn't HTTPS at all": a url.*.insteadOf
# rule can silently turn our HTTPS origin back into SSH, so the credential
# helper is never consulted and pushes go out under the personal identity.
# Simulate it with an isolated global config carrying that rule, applied only
# to this one run so the rest of the suite stays hermetic.
instead="$work/insteadof-repo"; mkdir -p "$instead"
( cd "$instead" && git init -q . \
  && git remote add origin https://github.com/acme/widget.git \
  && git config --local gh-app.profile pr-reviewer \
  && git config --local user.name  "my-reviewer[bot]" \
  && git config --local user.email "4242+my-reviewer[bot]@users.noreply.github.com" \
  && git config --local --add credential.https://github.com.helper "" \
  && git config --local --add credential.https://github.com.helper "$helper_value" )
insteadof_global="$work/insteadof-global.gitconfig"
printf '[url "git@github.com:"]\n\tinsteadOf = https://github.com/\n' > "$insteadof_global"
if out="$(run "$instead" GH_APP_CURL="$ok" GIT_CONFIG_GLOBAL="$insteadof_global" GIT_CONFIG_SYSTEM="$empty_system" 2>&1)"; then
  echo "FAIL: insteadOf rewrite of the origin reported healthy: $out" >&2; exit 1
fi
echo "$out" | grep -qi 'insteadof' \
  || { echo "FAIL: insteadOf rewrite not named as the problem: $out" >&2; exit 1; }
echo "$out" | grep -q 'git@github.com:acme/widget.git' \
  || { echo "FAIL: rewritten effective URL not reported: $out" >&2; exit 1; }

# --- a pushInsteadOf rewrite of a configured HTTPS origin is caught too,
# even though it is invisible to `ls-remote --get-url` / plain `remote
# get-url` (verified against git 2.50.1: both still report the clean HTTPS
# URL under this rule; only `remote get-url --push`, which status now also
# probes, shows the rewrite). This is the commoner "fetch over HTTPS, push
# over SSH" dotfile idiom.
pushinstead="$work/pushinsteadof-repo"; mkdir -p "$pushinstead"
( cd "$pushinstead" && git init -q . \
  && git remote add origin https://github.com/acme/widget.git \
  && git config --local gh-app.profile pr-reviewer \
  && git config --local user.name  "my-reviewer[bot]" \
  && git config --local user.email "4242+my-reviewer[bot]@users.noreply.github.com" \
  && git config --local --add credential.https://github.com.helper "" \
  && git config --local --add credential.https://github.com.helper "$helper_value" )
pushinsteadof_global="$work/pushinsteadof-global.gitconfig"
printf '[url "git@github.com:"]\n\tpushInsteadOf = https://github.com/\n' > "$pushinsteadof_global"
if out="$(run "$pushinstead" GH_APP_CURL="$ok" GIT_CONFIG_GLOBAL="$pushinsteadof_global" GIT_CONFIG_SYSTEM="$empty_system" 2>&1)"; then
  echo "FAIL: pushInsteadOf rewrite of the origin reported healthy: $out" >&2; exit 1
fi
echo "$out" | grep -qi 'pushinsteadof\|push.*rewrit\|pushInsteadOf' \
  || { echo "FAIL: pushInsteadOf rewrite not named as the problem: $out" >&2; exit 1; }
echo "$out" | grep -q 'git@github.com:acme/widget.git' \
  || { echo "FAIL: rewritten push URL not reported: $out" >&2; exit 1; }

# --- a personal credential helper configured ahead of ours, with no reset
# in front of it, must be reported: git tries helpers in order and uses the
# first one that answers, so checking only the LAST configured helper line
# (as this used to) misses a clone where the empty-reset entry was deleted
# or a migration only partially applied — exactly the state this guards.
noreset="$work/noreset-repo"; mkdir -p "$noreset"
( cd "$noreset" && git init -q . \
  && git remote add origin https://github.com/acme/widget.git \
  && git config --local gh-app.profile pr-reviewer \
  && git config --local user.name  "my-reviewer[bot]" \
  && git config --local user.email "4242+my-reviewer[bot]@users.noreply.github.com" \
  && git config --local --add credential.https://github.com.helper "personal-helper --some-flag" \
  && git config --local --add credential.https://github.com.helper "$helper_value" )
if out="$(run "$noreset" GH_APP_CURL="$ok" 2>&1)"; then
  echo "FAIL: a personal helper ahead of ours with no reset reported healthy: $out" >&2; exit 1
fi
echo "$out" | grep -qi 'credential helper' \
  || { echo "FAIL: missing-reset credential helper problem not named: $out" >&2; exit 1; }

# --- a generic credential.helper (the key stock macOS ships as
# `[credential] helper = osxkeychain` in
# /Library/Developer/CommandLineTools/usr/share/git-core/gitconfig) that
# answers ahead of ours must be caught even when the URL-scoped key alone
# looks perfectly healthy. Git merges BOTH key names — the generic
# credential.helper and the URL-scoped credential.https://github.com.helper
# — into one ordered list and tries whichever it finds first while reading
# system -> global -> local; here the generic one lives in an isolated
# system config, so it is tried before our URL-scoped entry ever gets a
# turn. Checking only the URL-scoped key (as this used to) sees a single,
# correctly-shaped entry with nothing to reset and reports OK, even though
# `git credential fill` would answer with the generic helper's identity
# instead — a clone that authenticates as whoever the generic helper serves,
# reported healthy. This is the same failure the "no reset" case above
# covers for the URL-scoped key alone, but for the generic key it takes no
# hand-deleted reset to trigger: the generic key was simply never checked.
genericsys="$work/genericsys-repo"; mkdir -p "$genericsys"
( cd "$genericsys" && git init -q . \
  && git remote add origin https://github.com/acme/widget.git \
  && git config --local gh-app.profile pr-reviewer \
  && git config --local user.name  "my-reviewer[bot]" \
  && git config --local user.email "4242+my-reviewer[bot]@users.noreply.github.com" \
  && git config --local --add credential.https://github.com.helper "$helper_value" )
genericsys_system="$work/genericsys-system.gitconfig"
printf '[credential]\n\thelper = personal-generic-helper\n' > "$genericsys_system"
if out="$(run "$genericsys" GH_APP_CURL="$ok" GIT_CONFIG_SYSTEM="$genericsys_system" GIT_CONFIG_GLOBAL="$empty_global" 2>&1)"; then
  echo "FAIL: a generic credential.helper ahead of ours reported healthy: $out" >&2; exit 1
fi
echo "$out" | grep -qi 'credential helper' \
  || { echo "FAIL: generic credential.helper problem not named: $out" >&2; exit 1; }

# --- legacy config aborts ---
legacy="$work/legacy"; mkdir -p "$legacy"
( cd "$legacy" && git init -q . && git config --local gh-app.enabled true )
if run "$legacy" GH_APP_CURL="$ok" >/dev/null 2>&1; then
  echo "FAIL: legacy repo reported healthy" >&2; exit 1
fi

echo "PASS: gh-app-status reports the active identity and fails on inconsistency"
