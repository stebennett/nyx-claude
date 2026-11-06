#!/usr/bin/env bash
# scaffold-verify.sh — which applicable script criteria does <repo> meet yet?
#
#   scaffold-verify.sh <repo>
#
# Gates on the tag, runs checks/group-1..5.sh, and prints JSON:
#   met   — ids of applicable script criteria scored 2
#   gaps  — the rest ({id, level, text, score, evidence, unverified}), by level then id
# Judgment criteria, inapplicable and exempt criteria, and N/A records are left out.
# The checks read git ls-files, so stage new files before running this.
#
# Exit: 0 ok, 2 usage/dependency, 3-5 tag gate (see tag.sh), 6 a check group failed.
# No pipefail: the check scripts pipe into `grep -q`.
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/common.sh"
es_require_deps

repo="${1:-}"
[ -n "$repo" ] && [ -d "$repo" ] || es_die 2 "usage: scaffold-verify.sh <repo>"
tag="$(es_tag_gate "$repo")"

run="$(mktemp -d)"; trap 'rm -rf "$run"' EXIT
# Each group to its own file, so one crashing group fails the run instead of
# silently dropping its criteria (and every group after it).
for g in 1 2 3 4 5; do
  bash "$here/checks/group-$g.sh" "$repo" < /dev/null > "$run/group-$g.json" 2> "$run/group-$g.err" \
    || es_die 6 "checks/group-$g.sh failed: $(tail -3 "$run/group-$g.err")"
done
jq -s 'add' "$run"/group-*.json > "$run/records.json"

# An applicable script criterion with no record is a gap, not a pass.
jq -n -L "$ES_LIB_DIR" --slurpfile rubric "$ES_RUBRIC" --argjson tag "$tag" --slurpfile recs "$run/records.json" '
  include "applicability";
  ($recs[0] | map({key: .id, value: .}) | from_entries) as $byid |
  [criteria($rubric[0]; $tag)[] | select(.applicable and .method == "script")
   | ($byid[.id] // {score: 0, evidence: "No record from the check scripts", unverified: false}) as $rec
   | select($rec.score != "N/A")
   | {id, level, text, score: $rec.score, evidence: $rec.evidence, unverified: $rec.unverified}] as $scored |
  {met: [$scored[] | select(.score == 2) | .id],
   gaps: ($scored | map(select(.score != 2)) | sort_by(.level, .id))}'
