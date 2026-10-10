#!/usr/bin/env bash
# Tests for plan.sh: group selection follows applicability, judgment criteria
# exclude N/A and exempt ones, and tag/evidence contradictions become warnings.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/helpers.bash"
plan="$here/../plan.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

cp -R "$here/fixtures/exemplary" "$work/ex"
( cd "$work/ex" && git init -q -b main && git -c user.name=t -c user.email=t@example.com add -A \
  && git -c user.name=t -c user.email=t@example.com commit -qm "feat: x" )
p="$(bash "$plan" "$work/ex" < /dev/null)"
assert_eq "service runs all five groups" "1,2,3,4,5" "$(printf '%s' "$p" | jq -r '[.groups[].group] | join(",")')"
assert_eq "no warnings when the tag matches" "0" "$(printf '%s' "$p" | jq '.warnings | length')"
assert_eq "judgment criteria only" "true" "$(printf '%s' "$p" | jq --slurpfile r "$here/../../skills/engineering-standards-assess/references/rubric.json" \
  '[.groups[].judgment[].id] as $j | ($r[0].criteria | map(select(.method == "judgment")) | map(.id)) as $all | ($j - $all) == []')"
assert_eq "SQLite-only DAT-10 excluded for postgresql" "false" "$(printf '%s' "$p" | jq '[.groups[].judgment[].id] | index("DAT-10") != null')"

yq -i '.engineering_standards.type = "library" | .engineering_standards.exemptions = [{"id": "DOC-5", "reason": "single component"}]' "$work/ex/.nyx.yml"
p="$(bash "$plan" "$work/ex" < /dev/null)"
assert_eq "library skips group 5" "1,2,3,4" "$(printf '%s' "$p" | jq -r '[.groups[].group] | join(",")')"
assert_eq "exempt criterion not assigned" "false" "$(printf '%s' "$p" | jq '[.groups[].judgment[].id] | index("DOC-5") != null')"
assert_contains "contradiction warned" "Tag says type is library" "$(printf '%s' "$p" | jq -r '.warnings[]')"

yq -i '.engineering_standards.status = "archived"' "$work/ex/.nyx.yml"
assert_exit "archived repo refused" 4 bash "$plan" "$work/ex"

finish
