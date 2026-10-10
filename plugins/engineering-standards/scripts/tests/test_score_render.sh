#!/usr/bin/env bash
# Golden tests for score.sh (category %, overall mean, score vs gate level,
# blocking criteria, N/A handling, exemptions, record validation), render.sh
# and delta.sh. Records are synthetic so every expected number is hand-checkable.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/helpers.bash"
s="$here/.."
rubric="$here/../../skills/engineering-standards-assess/references/rubric.json"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
export ES_DATE=2026-01-02

repo="$work/lib"; mkdir -p "$repo"
tag_json() { # <jq edits to a library tag>
  jq -n "{type: \"library\", status: \"active\", deployment_target: \"none\", database: \"none\",
          lightweight: false, optional_categories: [], exemptions: [{id: \"SEC-4\", reason: \"no containers\"}]} | $1"
}
set_tag() { tag_json "$1" > "$work/tag.json"; bash "$s/tag.sh" write "$repo" "$work/tag.json" >/dev/null; }
set_tag '.'

# Records scoring every criterion <default>, then jq edits applied.
recs() { # <default-score> [jq edits]
  jq --argjson d "$1" '[.criteria[] | {id, score: $d, evidence: "e", source: "script", unverified: false}] | '"${2:-.}" "$rubric" > "$work/recs.json"
}
score() { bash "$s/score.sh" "$repo" "$work/recs.json"; }
field() { printf '%s' "$1" | jq -r "$2"; }
set_score() { echo "map(if .id == \"$1\" then .score = $2 else . end)"; }

# --- all met -------------------------------------------------------------------
recs 2; out="$(score)"
assert_eq "all met: overall" "100" "$(field "$out" .overall)"
assert_eq "all met: maturity" "L3" "$(field "$out" .maturity)"
assert_eq "all met: no blocking" "0" "$(field "$out" '.blocking | length')"
assert_eq "all met: no next level" "null" "$(field "$out" .next_level)"
assert_eq "library: DPL not applicable" "null" "$(field "$out" '.categories[] | select(.id == "DPL") | .percent')"
assert_eq "library: DAT optional, not adopted" "false" "$(field "$out" '.categories[] | select(.id == "DAT") | .applicable')"
assert_eq "library: 12 categories scored" "12" "$(field "$out" '[.categories[] | select(.percent != null)] | length')"
assert_eq "exemption becomes N/A" "Exempt: no containers" "$(field "$out" '.criteria[] | select(.id == "SEC-4") | .evidence')"
assert_eq "exempt criterion not scored" "5" "$(field "$out" '.categories[] | select(.id == "SEC") | .scored')"
assert_eq "record for inapplicable criterion ignored" "N/A" "$(field "$out" '.criteria[] | select(.id == "DPL-1") | .score')"
assert_eq "repository name falls back to directory" "lib" "$(field "$out" .repository)"

# --- one L1 criterion unmet: high score, gated to L0 -----------------------------
recs 2 "$(set_score DOC-1 0)"; out="$(score)"
assert_eq "DOC-1 unmet: DOC %" "83.3" "$(field "$out" '.categories[] | select(.id == "DOC") | .percent * 10 | round / 10')"
assert_eq "DOC-1 unmet: overall (11×100 + 83.33)/12" "98.6" "$(field "$out" .overall)"
assert_eq "DOC-1 unmet: score level" "L3" "$(field "$out" .score_level)"
assert_eq "DOC-1 unmet: gate level" "L0" "$(field "$out" .gate_level)"
assert_eq "DOC-1 unmet: maturity is the lower" "L0" "$(field "$out" .maturity)"
assert_eq "DOC-1 unmet: blocking" "DOC-1" "$(field "$out" '.blocking | join(",")')"

# --- one L3 criterion partial --------------------------------------------------------
recs 2 "$(set_score HYG-5 1)"; out="$(score)"
assert_eq "HYG-5 partial: maturity" "L2" "$(field "$out" .maturity)"
assert_eq "HYG-5 partial: next level" "L3" "$(field "$out" .next_level)"
assert_eq "HYG-5 partial: blocking" "HYG-5" "$(field "$out" '.blocking | join(",")')"

# --- everything partial: score 50 → L1 by score, L0 by gate ---------------------------
recs 1; out="$(score)"
assert_eq "all partial: overall" "50" "$(field "$out" .overall)"
assert_eq "all partial: score level" "L1" "$(field "$out" .score_level)"
assert_eq "all partial: maturity" "L0" "$(field "$out" .maturity)"
assert_eq "all partial: blocking = applicable L1 criteria" \
  "$(jq -c '[.criteria[] | select(.applicable and .score != "N/A" and .level == "L1") | .id]' <<<"$out")" \
  "$(field "$out" '.blocking | tojson')"

# --- gate met at L1 but score too low ---------------------------------------------------
jq '[.criteria[] | {id, score: (if .level == "L1" then 2 else 0 end), evidence: "e", source: "script", unverified: false}]' "$rubric" > "$work/recs.json"
out="$(score)"
assert_eq "L1 gate met" "L1" "$(field "$out" .gate_level)"
assert_eq "maturity = min(score level, gate level)" \
  "$(field "$out" '[.score_level, .gate_level] | min')" "$(field "$out" .maturity)"

# --- N/A records leave the denominator ----------------------------------------------------
recs 2 "$(set_score STK-1 0) | map(if .id == \"STK-3\" then .score = \"N/A\" | .evidence = \"no TypeScript\" else . end)"
out="$(score)"
assert_eq "STK with one N/A: 4/6" "66.7" "$(field "$out" '.categories[] | select(.id == "STK") | .percent * 10 | round / 10')"

# --- optional category adopted, SQLite-only criteria ------------------------------------
set_tag '.database = "sqlite" | .lightweight = true | .optional_categories = ["DAT"]'
recs 2; out="$(score)"
assert_eq "adopted DAT is scored" "true" "$(field "$out" '.categories[] | select(.id == "DAT") | .applicable')"
assert_eq "PostgreSQL-only DAT-7 is N/A under sqlite" "N/A" "$(field "$out" '.criteria[] | select(.id == "DAT-7") | .score')"
assert_eq "DAT scores 8 criteria under sqlite" "8" "$(field "$out" '.categories[] | select(.id == "DAT") | .scored')"
set_tag '.'

# --- record validation -----------------------------------------------------------------------
recs 2 'map(select(.id != "DOC-2"))'
assert_exit "missing record" 6 score
msg="$(score 2>&1 || true)"; assert_contains "missing record named" "DOC-2" "$msg"
recs 2 '. + [{id: "DOC-2", score: 1, evidence: "dup", source: "script"}]'
assert_exit "duplicate record" 6 score
recs 2 '. + [{id: "ZZZ-1", score: 1, evidence: "x", source: "script"}]'
assert_exit "unknown criterion" 6 score
recs 2 "$(set_score DOC-2 3)"
assert_exit "score out of range" 6 score
recs 2 'map(if .id == "DOC-2" then .evidence = "" else . end)'
assert_exit "empty evidence" 6 score
recs 2; yq -i '.engineering_standards.framework_version = "1.3"' "$repo/.nyx.yml"
assert_exit "stale tag refused" 5 score
set_tag '.'

# --- render ------------------------------------------------------------------------------------
recs 2 "$(set_score DOC-4 1) | $(set_score VCS-3 0) | map(if .id == \"VCS-3\" then .unverified = true | .evidence = \"rulesets not checked | no gh\" else . end)"
score > "$work/scored.json"
printf '%s' '[{"id":"DOC-4","action":"Record ADRs in docs/adr/","target_level":"L2"}]' > "$work/actions.json"
printf '%s' '["fly.toml present but tagged none"]' > "$work/warnings.json"
md="$(bash "$s/render.sh" "$work/scored.json" "$work/actions.json" "$work/warnings.json")"
assert_contains "title" "# Engineering Standards Assessment" "$md"
assert_contains "type" "- **Type:** Library" "$md"
assert_contains "framework" "- **Framework version:** 1.4" "$md"
assert_contains "assessed date" "- **Assessed:** 2026-01-02" "$md"
assert_contains "warning line" "- **Warnings:** fly.toml present but tagged none" "$md"
assert_contains "summary row" "| DPL | N/A | Not applicable to library projects (section 3 matrix) |" "$md"
assert_contains "maturity named" "- **Maturity level:** L1 — Baseline" "$md"
assert_contains "blocking listed" "- **Blocking gate criteria:** DOC-4, VCS-3" "$md"
assert_contains "unverified marker" "| VCS-3 | 0 (unverified) |" "$md"
assert_contains "pipes escaped" 'rulesets not checked \| no gh' "$md"
assert_contains "action row" "| DOC-4 | Record ADRs in docs/adr/ | L2 |" "$md"
assert_contains "manual confirmation section" "## Needs manual confirmation" "$md"
assert_eq "all 96 criteria listed" "96" "$(printf '%s\n' "$md" | awk '/^## Criterion scores/{c=1;next} /^## /{c=0} c && /^\| [A-Z]+-[0-9]+ \|/' | wc -l | tr -d ' ')"
assert_eq "16 category rows" "16" "$(printf '%s\n' "$md" | awk '/^## Summary/{c=1;next} /^- /{c=0} c && /^\| [A-Z]+ \|/' | wc -l | tr -d ' ')"
section_order="$(printf '%s\n' "$md" | grep '^## ' | tr '\n' '/')"
assert_eq "section order" "## Summary/## Criterion scores/## Actions/## Needs manual confirmation/" "$section_order"

# --- delta -------------------------------------------------------------------------------------
printf '%s\n' "$md" > "$work/assessment.md"
assert_eq "no previous file" "null" "$(bash "$s/delta.sh" "$work/none.md" "$work/scored.json" | jq -c .previous)"
recs 2; score > "$work/scored2.json"
d="$(bash "$s/delta.sh" "$work/assessment.md" "$work/scored2.json")"
assert_eq "previous maturity parsed" "L1" "$(field "$d" .previous.maturity)"
assert_eq "current maturity" "L3" "$(field "$d" .current.maturity)"
assert_eq "changed criteria" "DOC-4:1>2,VCS-3:0>2" "$(field "$d" '[.changed[] | "\(.id):\(.from)>\(.to)"] | join(",")')"

finish
