#!/usr/bin/env bash
# Tests for scaffold-verify.sh: it reports only applicable script criteria,
# split into met and gaps, and works on a staged repo with no commits yet.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/helpers.bash"
verify="$here/../scaffold-verify.sh"
tag="$here/../tag.sh"
export ES_NO_GH=1
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
stage() { ( cd "$1" && git init -q -b main && git add -A ); } # no commit, as scaffold leaves it
has() { printf '%s' "$1" | jq --arg id "$3" "[.$2[] | (.id? // .)] | index(\$id) != null"; } # <json> <met|gaps> <id>

# --- no tag ---------------------------------------------------------------------
mkdir -p "$work/notag"
assert_exit "no tag refused" 3 bash "$verify" "$work/notag"

# --- exemplary fixture, staged, no commit ------------------------------------------
cp -R "$here/fixtures/exemplary" "$work/ex"; stage "$work/ex"
out="$(bash "$verify" "$work/ex" < /dev/null)"
for id in STK-1 CI-2 BLD-4 DPL-2; do
  assert_eq "exemplary $id met" "true" "$(has "$out" met "$id")"
done
assert_eq "judgment criterion DOC-1 excluded" "false" "$(has "$out" met DOC-1)"
assert_eq "judgment criterion DOC-1 not a gap" "false" "$(has "$out" gaps DOC-1)"
assert_eq "N/A STK-2 not met" "false" "$(has "$out" met STK-2)"
assert_eq "N/A STK-2 not a gap" "false" "$(has "$out" gaps STK-2)"

# --- exemption removes the criterion ---------------------------------------------
yq -o=json '.engineering_standards | .exemptions = [{"id":"BLD-4","reason":"x"}]' "$work/ex/.nyx.yml" > "$work/tag.json"
bash "$tag" write "$work/ex" "$work/tag.json" >/dev/null
git -C "$work/ex" add -A
out="$(bash "$verify" "$work/ex" < /dev/null)"
assert_eq "exempt BLD-4 not met" "false" "$(has "$out" met BLD-4)"
assert_eq "exempt BLD-4 not a gap" "false" "$(has "$out" gaps BLD-4)"

# --- a crashing check group fails verify instead of reporting no gaps -------------------
cp -R "$here/fixtures/exemplary" "$work/broken"
printf 'on: [push\n  bad: : yaml\n' > "$work/broken/.github/workflows/ci.yml"
stage "$work/broken"
assert_exit "crashing check group fails verify" 6 bash "$verify" "$work/broken"
msg="$(bash "$verify" "$work/broken" 2>&1 < /dev/null || true)"
assert_contains "failure names the group" "group-2" "$msg"

# --- bare repo with only a tag --------------------------------------------------------
mkdir -p "$work/bare"
printf '{"type":"service","status":"active","deployment_target":"kubernetes","database":"postgresql","lightweight":false}' > "$work/bare.json"
bash "$tag" write "$work/bare" "$work/bare.json" >/dev/null
stage "$work/bare"
out="$(bash "$verify" "$work/bare" < /dev/null)"
assert_eq "bare CFG-3 gap level" '"L1"' "$(printf '%s' "$out" | jq -c '.gaps[] | select(.id == "CFG-3") | .level')"
assert_eq "bare CFG-3 not met" "false" "$(has "$out" met CFG-3)"

finish
