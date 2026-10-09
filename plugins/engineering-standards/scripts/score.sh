#!/usr/bin/env bash
# score.sh — apply the rubric to a set of criterion records.
#
#   score.sh <repo> <records.json>
#
# <records.json> is one JSON array holding a record for every applicable
# criterion (scripts and assessors combined). Prints the scored assessment as
# JSON: per-criterion scores with N/A resolved, category percentages, overall
# score, score level, gate level, maturity level and blocking gate criteria.
#
# Applicability (section 3 matrix, optional_categories, applies_when, and tag
# exemptions) is decided here, so a record for an inapplicable criterion is
# ignored. Every applicable criterion must have exactly one record.
#
# Exit: 0 ok, 2 usage, 3-5 tag gate (see tag.sh), 6 missing/duplicate/invalid records.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
es_require_deps

repo="${1:-}"; records="${2:-}"
[ -n "$repo" ] && [ -d "$repo" ] && [ -f "$records" ] || es_die 2 "usage: score.sh <repo> <records.json>"
tag="$(es_tag_gate "$repo")"
name="$(git -C "$repo" remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#.*[/:]##' || true)"
[ -n "$name" ] || name="$(basename "$(cd "$repo" && pwd)")"

result="$(jq -n -L "$ES_LIB_DIR" \
  --slurpfile rubric "$ES_RUBRIC" \
  --slurpfile recs "$records" \
  --argjson tag "$tag" \
  --arg name "$name" \
  --arg date "${ES_DATE:-$(date +%Y-%m-%d)}" '
  include "applicability";
  def lvl: ltrimstr("L") | tonumber;
  $rubric[0] as $r | $recs[0] as $records |
  categories($r; $tag) as $cats |
  (criteria($r; $tag) | map(
    if .applicable then . as $c | ([$records[] | select(.id == $c.id)]) as $m |
      $c + {matches: ($m | length)} + ($m[0] // {} | {score, evidence, source, unverified: (.unverified // false)})
    else . end)) as $crit |

  # Validation: every applicable criterion has exactly one well-formed record.
  ([$crit[] | select(.applicable and .matches == 0) | .id]) as $missing |
  ([$crit[] | select(.applicable and .matches > 1) | .id]) as $dupes |
  ([$crit[] | select(.applicable and .matches == 1)
     | select((.score | IN(0, 1, 2, "N/A") | not) or ((.evidence // "") | length) == 0) | .id]) as $bad |
  ([$records[].id] - [$r.criteria[].id]) as $unknown |
  if ($missing + $dupes + $bad + $unknown | length) > 0 then
    {error: {missing: $missing, duplicate: $dupes, invalid: $bad, unknown: $unknown}}
  else
    ($crit | map(del(.matches))) as $crit |
    ($cats | map(. as $c |
      [$crit[] | select(.category == $c.id and .applicable and .score != "N/A")] as $scored |
      $c + {scored: ($scored | length),
            points: ($scored | map(.score) | add // 0),
            percent: (if ($c.applicable and ($scored | length) > 0)
                      then (($scored | map(.score) | add) / (2 * ($scored | length)) * 100) else null end)})) as $cats |
    ([$cats[] | select(.percent != null) | .percent]) as $pcts |
    (if ($pcts | length) > 0 then ($pcts | add / length) else 0 end) as $overall |
    ([$r.levels[] | select(.min_score <= $overall) | .level] | last) as $score_level |
    # Gate level: highest level whose criteria and every lower level are met or N/A.
    ([$crit[] | select(.applicable and .score != "N/A" and .score != 2) | (.level | lvl)] | min // 4) as $lowest_unmet |
    ("L\([$lowest_unmet - 1, 3] | min)") as $gate_level |
    ("L\([($score_level | lvl), ($gate_level | lvl)] | min)") as $maturity |
    (($maturity | lvl) + 1) as $next |
    {
      repository: $name,
      framework_version: $r.framework_version,
      assessed: $date,
      tag: $tag,
      criteria: $crit,
      categories: $cats,
      overall: (($overall * 10 | round) / 10),
      score_level: $score_level,
      gate_level: $gate_level,
      maturity: $maturity,
      next_level: (if $next > 3 then null else "L\($next)" end),
      next_level_min_score: (if $next > 3 then null else ($r.levels[$next].min_score) end),
      blocking: (if $next > 3 then [] else
        [$crit[] | select(.applicable and .score != "N/A" and .score != 2 and (.level | lvl) <= $next) | .id] end),
      unverified: [$crit[] | select(.applicable and .unverified) | .id]
    }
  end')"

err="$(printf '%s' "$result" | jq -c '.error // empty')"
if [ -n "$err" ]; then
  es_die 6 "records do not cover the applicable criteria exactly once: $err"
fi
printf '%s\n' "$result"
