#!/usr/bin/env bash
# Report which GitHub App identity governs the current directory, and whether
# that identity is actually usable here. Takes no arguments: it resolves the
# profile exactly as the gh shim does, so it reports what gh and git push will
# really do. Exit 0 when consistent, non-zero when something is wrong.
set -uo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gh-app-common.sh
. "$dir/gh-app-common.sh"

problems=0
note() { printf '  %-22s %s\n' "$1" "$2"; }
bad()  { printf '  %-22s %s\n' "$1" "PROBLEM: $2"; problems=$((problems + 1)); }

profile="$(gh_app_resolve_profile)" || exit 1

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "gh-app: not a git repository — gh and git pass through as your personal identity."
  exit 0
fi
repo_root="$(git rev-parse --show-toplevel)"

if [ -z "$profile" ]; then
  echo "gh-app: no profile for $repo_root — gh and git pass through as your personal identity."
  echo "        enable with: setup-github-app-git.sh <profile>"
  exit 0
fi

echo "gh-app: identity for $repo_root"
gh_app_load_profile "$profile"
note "profile" "$profile"
note "profile file" "$GH_APP_PROFILE_FILE"
note "app" "${GITHUB_APP_SLUG:-<unset>} (app id ${GITHUB_APP_ID:-<unset>}, installation ${GITHUB_APP_INSTALLATION_ID:-<unset>})"

# --- private key ---
if [ -r "${GITHUB_APP_PRIVATE_KEY_PATH:-/nonexistent}" ]; then
  note "private key" "$GITHUB_APP_PRIVATE_KEY_PATH"
else
  bad "private key" "not readable at '${GITHUB_APP_PRIVATE_KEY_PATH:-<unset>}'"
fi

# --- commit identity must match the profile, or commits carry the wrong author ---
want_name="${GITHUB_APP_SLUG:-}[bot]"
want_email="${GITHUB_APP_BOT_USER_ID:-}+${GITHUB_APP_SLUG:-}[bot]@users.noreply.github.com"
got_name="$(git -C "$repo_root" config --local --get user.name 2>/dev/null || true)"
got_email="$(git -C "$repo_root" config --local --get user.email 2>/dev/null || true)"
if [ "$got_name" = "$want_name" ] && [ "$got_email" = "$want_email" ]; then
  note "commit identity" "$got_name <$got_email>"
else
  bad "commit identity" "is '$got_name <$got_email>', profile expects '$want_name <$want_email>' — re-run setup-github-app-git.sh $profile"
fi

# --- origin must be HTTPS, and must not be silently rewritten away from it.
# A url.<base>.insteadOf rule (e.g. from a personal dotfile) rewrites URLs
# before git uses them, so the *configured* origin and the *effective* origin
# can disagree: `git remote get-url` / `git push` apply the rewrite, but the
# repo's own config still says HTTPS. That is a distinct, live failure mode
# from "origin isn't HTTPS at all" — if the rewrite turns our HTTPS origin
# back into SSH, the credential helper is never consulted and pushes go out
# under the personal identity, even though everything else here looks fine.
# `git ls-remote --get-url` applies insteadOf resolution and needs no network.
# `ls-remote --get-url` only resolves `insteadOf`, which applies to every
# operation. `pushInsteadOf` rewrites pushes only and is invisible to it:
# verified against git 2.50.1, a global `pushInsteadOf` rule leaves
# `ls-remote --get-url` (and plain `remote get-url`) reporting the clean
# HTTPS origin while `remote get-url --push` (what a real push actually
# uses) is rewritten to SSH. Probe that directly, as a distinct condition
# nested under the insteadOf check so the two rewrite kinds aren't double
# counted when both happen to apply.
configured_origin="$(git -C "$repo_root" config --get remote.origin.url 2>/dev/null || true)"
effective_origin="$(git -C "$repo_root" ls-remote --get-url origin 2>/dev/null || true)"
case "$configured_origin" in
  https://github.com/*)
    if [ "$effective_origin" != "$configured_origin" ]; then
      bad "origin" "configured as '$configured_origin' but a url.*.insteadOf rule rewrites it to '$effective_origin' — pushes would bypass the App credential helper and go out as your personal identity"
    else
      push_origin="$(git -C "$repo_root" remote get-url --push origin 2>/dev/null || true)"
      if [ "$push_origin" != "$configured_origin" ]; then
        bad "origin" "configured as '$configured_origin' but a url.*.pushInsteadOf rule rewrites pushes to '$push_origin' — pushes would bypass the App credential helper and go out as your personal identity"
      else
        note "origin" "$configured_origin"
      fi
    fi
    ;;
  "") bad "origin" "no origin remote" ;;
  *)  bad "origin" "'$configured_origin' is not HTTPS — pushes bypass the App credential helper" ;;
esac

# --- the effective helper list, as git will actually apply it. Git tries
# helpers in configured order (system -> global -> local) and uses the FIRST
# one that answers — an empty value resets the accumulated list, which is
# what setup-github-app-git.sh relies on to make ours win over an inherited
# personal helper. Checking only the LAST configured line (as this used to)
# proves a helper was appended, but not that the reset in front of it is
# still there: a clone where someone deleted the empty-reset line, or a
# partially-applied migration, would still show our helper last while a
# personal helper (earlier in the list, never reset) answers first — and
# this check would report OK. Reproduce git's own reduction instead: drop
# everything up to and including the LAST empty entry, then require the
# FIRST survivor — the one git will actually try first — to be ours.
#
# The value setup-github-app-git.sh writes carries a leading "!" and
# double-quotes the path (e.g. !"/path/git-credential-github-app.sh"
# --profile <name>): the "!" forces git to run it through a shell, which is
# what makes it survive a space in the plugin path. Require that exact
# shape, not just a substring match, so a helper that would silently fail to
# run is still flagged here.
helpers="$(git -C "$repo_root" config --get-all credential.https://github.com.helper 2>/dev/null || true)"
if [ -z "$helpers" ]; then
  first_survivor=""
else
  last_empty_line=0
  line_no=0
  while IFS= read -r helper_line; do
    line_no=$((line_no + 1))
    [ -z "$helper_line" ] && last_empty_line=$line_no
  done <<EOF
$helpers
EOF
  first_survivor="$(printf '%s\n' "$helpers" | sed -n "$((last_empty_line + 1))p")"
fi
case "$first_survivor" in
  '!"'*'git-credential-github-app.sh" --profile '"$profile")
    note "credential helper" "$first_survivor" ;;
  *)
    bad "credential helper" "the first helper git will try is '$first_survivor', not this profile's App credential helper (expected the '!\"...\"' quoted form) — a personal helper may run first, or the reset that should precede ours is missing. re-run setup-github-app-git.sh $profile" ;;
esac

# --- live check: can this App actually see this repository? ---
owner_repo=""
case "$configured_origin" in
  https://github.com/*) owner_repo="${configured_origin#https://github.com/}"; owner_repo="${owner_repo%.git}" ;;
esac

token="$("${GITHUB_APP_TOKEN_CMD:-$dir/github-app-token.sh}" --profile "$profile" 2>/dev/null || true)"
if [ -z "$token" ]; then
  bad "token" "could not mint a token for profile '$profile'. $GH_APP_DOCTRINE"
elif [ -z "$owner_repo" ]; then
  bad "repo access" "cannot derive owner/repo from origin, skipping the access check"
else
  # One unpaginated call: 200 only if this installation can see this repo.
  code="$( "${GH_APP_CURL:-curl}" -sS -o /dev/null -w '%{http_code}' --max-time 30 \
      -H "Authorization: token $token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/${owner_repo}" 2>/dev/null || echo 000 )"
  case "$code" in
    200) note "repo access" "$owner_repo (App installation confirmed)" ;;
    404) bad "repo access" "$owner_repo is not visible to this App — install '${GITHUB_APP_SLUG:-<unset>}' on it" ;;
    401) bad "repo access" "token rejected (401) — check the App id and private key in $GH_APP_PROFILE_FILE" ;;
    *)   bad "repo access" "unexpected HTTP $code checking $owner_repo" ;;
  esac
fi

if [ "$problems" -ne 0 ]; then
  echo "gh-app: $problems problem(s) found."
  echo "gh-app: $GH_APP_DOCTRINE"
  exit 1
fi
echo "gh-app: OK — this clone acts as ${GITHUB_APP_SLUG:-<unset>}[bot] via profile '$profile'."
