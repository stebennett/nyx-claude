#!/usr/bin/env bash
# rubric.json must mirror the criteria tables in standards.md exactly: same IDs,
# same levels, same framework version. Editing one without the other fails here.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/helpers.bash"
refs="$here/../../skills/engineering-standards-assess/references"
standards="$refs/standards.md"
rubric="$refs/rubric.json"

# ID<TAB>level for every criterion row in section 5 (the section 7 template
# also has criterion-shaped rows, so stop at section 6).
from_md="$(awk -F'|' '/^## 6\./ { exit }
  /^\| [A-Z]+-[0-9]+ \|/ { id = $2; lvl = $(NF - 1); gsub(/ /, "", id); gsub(/ /, "", lvl); print id "\t" lvl }' \
  "$standards" | sort)"
from_json="$(jq -r '.criteria[] | "\(.id)\t\(.level)"' "$rubric" | sort)"
assert_eq "criterion IDs and levels match" "$from_md" "$from_json"

md_version="$(sed -nE 's/^Version ([0-9]+\.[0-9]+).*/\1/p' "$standards" | head -1)"
assert_eq "framework version matches" "$md_version" "$(jq -r .framework_version "$rubric")"

# The version is also stated in the section 7 template; keep it in step.
template_version="$(sed -nE 's/^- \*\*Framework version:\*\* ([0-9.]+)$/\1/p' "$standards")"
assert_eq "template framework version matches" "$md_version" "$template_version"

# Every criterion belongs to a declared category, and every category to a group 1-5.
orphans="$(jq -r '(.categories | map(.id)) as $c | .criteria[] | select(.category as $x | $c | index($x) | not) | .id' "$rubric")"
assert_eq "no criteria without a category" "" "$orphans"
bad_groups="$(jq -r '.categories[] | select(.group < 1 or .group > 5) | .id' "$rubric")"
assert_eq "every category in group 1-5" "" "$bad_groups"
bad_methods="$(jq -r '.criteria[] | select(.method != "script" and .method != "judgment") | .id' "$rubric")"
assert_eq "every criterion has a valid method" "" "$bad_methods"

finish
