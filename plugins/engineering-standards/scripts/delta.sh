#!/usr/bin/env bash
# delta.sh — compare a new scored assessment with the previous docs/assessment.md.
#
#   delta.sh <previous-assessment.md> <scored.json>
#
# Prints JSON: {previous: {overall, maturity, assessed, framework_version} | null,
# current: {...}, changed: [{id, from, to}]}. A missing previous file gives
# previous: null and no changes. Reads the tables render.sh writes.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
es_require_deps

old="${1:-}"; scored="${2:-}"
[ -n "$old" ] && [ -f "$scored" ] || es_die 2 "usage: delta.sh <previous-assessment.md> <scored.json>"

if [ -f "$old" ]; then
  prev="$(awk '
    /^- \*\*Overall score:\*\*/ { sub(/^- \*\*Overall score:\*\* */, ""); overall = $0 }
    /^- \*\*Maturity level:\*\*/ { sub(/^- \*\*Maturity level:\*\* */, ""); maturity = substr($0, 1, 2) }
    /^- \*\*Assessed:\*\*/ { sub(/^- \*\*Assessed:\*\* */, ""); assessed = $0 }
    /^- \*\*Framework version:\*\*/ { sub(/^- \*\*Framework version:\*\* */, ""); fw = $0 }
    /^## Criterion scores/ { in_c = 1; next }
    /^## / { in_c = 0 }
    in_c && /^\| [A-Z]+-[0-9]+ \|/ { split($0, f, "|"); id = f[2]; s = f[3]; gsub(/ /, "", id); sub(/^ */, "", s); sub(/ .*/, "", s); print "C\t" id "\t" s }
    END { print "M\t" overall "\t" maturity "\t" assessed "\t" fw }
  ' "$old" | jq -R -s '
    split("\n") | map(select(length > 0) | split("\t")) as $rows |
    ($rows[] | select(.[0] == "M")) as $m |
    {overall: ($m[1] | tonumber? // null), maturity: $m[2], assessed: $m[3], framework_version: $m[4],
     criteria: ([$rows[] | select(.[0] == "C") | {key: .[1], value: .[2]}] | from_entries)}')"
else
  prev=null
fi

jq --argjson prev "$prev" '
  {overall, maturity, assessed, framework_version,
   criteria: (.criteria | map({key: .id, value: (.score | tostring)}) | from_entries)} as $cur |
  {previous: (if $prev == null then null else $prev | del(.criteria) end),
   current: ($cur | del(.criteria)),
   changed: (if $prev == null then [] else
     [$cur.criteria | to_entries[] | select($prev.criteria[.key] != null and $prev.criteria[.key] != .value)
      | {id: .key, from: $prev.criteria[.key], to: .value}] end)}' "$scored"
