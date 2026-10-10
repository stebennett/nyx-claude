#!/usr/bin/env bash
# plan.sh — work out what an assessment of <repo> has to do.
#
#   plan.sh <repo>
#
# Gates on the tag (same exits as tag.sh gate), then prints JSON:
#   tag       — the validated tag
#   groups    — each group with any applicable category: its number, categories,
#               and the applicable judgment criteria ({id, level, text}) an
#               assessor must score. Script criteria come from checks/group-N.sh.
#   warnings  — where detect.sh's evidence contradicts the tag
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/common.sh"
es_require_deps

repo="${1:-}"
[ -n "$repo" ] && [ -d "$repo" ] || es_die 2 "usage: plan.sh <repo>"
tag="$(es_tag_gate "$repo")"
detected="$(bash "$here/detect.sh" "$repo" < /dev/null)"

jq -n -L "$ES_LIB_DIR" --slurpfile rubric "$ES_RUBRIC" --argjson tag "$tag" --argjson det "$detected" '
  include "applicability";
  $rubric[0] as $r |
  categories($r; $tag) as $cats |
  criteria($r; $tag) as $crit |
  {
    tag: $tag,
    groups: [range(1; 6) as $g |
      [$cats[] | select(.group == $g and .applicable) | .id] as $ids |
      select($ids | length > 0) |
      {group: $g, categories: $ids,
       judgment: [$crit[] | select(.applicable and .method == "judgment" and (.category as $c | $ids | index($c)))
                  | {id, level, text}]}],
    warnings: [("type", "deployment_target", "database") as $f |
      select($det.proposed[$f] != $tag[$f]) |
      "Tag says \($f) is \($tag[$f]), but the repository suggests \($det.proposed[$f]) (\($det.reasons[$f]))"]
  }'
