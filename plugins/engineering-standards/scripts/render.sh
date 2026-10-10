#!/usr/bin/env bash
# render.sh — render a scored assessment as docs/assessment.md (section 7 template).
#
#   render.sh <scored.json> [actions.json] [warnings.json]
#
# <scored.json> is score.sh output. [actions.json] is an array of
# {id, action, target_level}. [warnings.json] is an array of strings (e.g. the
# tag contradicting detected evidence). Prints Markdown on stdout.
#
# The only additions to the section 7 template are the "## Needs manual
# confirmation" section, "(unverified)" score markers, and a Warnings line
# when there are warnings.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
es_require_deps

scored="${1:-}"; actions="${2:-}"; warnings="${3:-}"
[ -f "$scored" ] || es_die 2 "usage: render.sh <scored.json> [actions.json] [warnings.json]"
[ -n "$actions" ] && [ -f "$actions" ] || actions=/dev/null
[ -n "$warnings" ] && [ -f "$warnings" ] || warnings=/dev/null

jq -r \
  --slurpfile actions "$actions" \
  --slurpfile warnings "$warnings" '
  def cell: tostring | gsub("[\r\n]+"; " ") | gsub("\\|"; "\\|");
  def score_cell: (.score | tostring) + (if .unverified then " (unverified)" else "" end);
  def levelname: {"L0": "L0 — Ad hoc", "L1": "L1 — Baseline", "L2": "L2 — Managed", "L3": "L3 — Exemplary"}[.];
  def target: {"fly": "Fly.io", "cloudflare": "Cloudflare", "kubernetes": "Kubernetes", "none": "none"}[.];
  def titlecase: (.[:1] | ascii_upcase) + .[1:];
  def pct: if . == null then "N/A" else (. * 10 | round / 10 | tostring) end;
  . as $s |
  ($actions[0] // []) as $acts |
  ($warnings[0] // []) as $warns |
  [
    "# Engineering Standards Assessment",
    "",
    "- **Repository:** \($s.repository)",
    "- **Type:** \(if $s.tag.type == "cli" then "CLI" else ($s.tag.type | titlecase) end)",
    "- **Deployment target:** \($s.tag.deployment_target | target)",
    "- **Status:** \($s.tag.status | titlecase)",
    "- **Assessed:** \($s.assessed)",
    "- **Framework version:** \($s.framework_version)",
    (if ($warns | length) > 0 then "- **Warnings:** \($warns | map(cell) | join("; "))" else empty end),
    "",
    "## Summary",
    "",
    "| Category | Score (%) | Notes |",
    "|---|---|---|",
    ($s.categories[] | . as $c |
      ([$s.criteria[] | select(.category == $c.id and .applicable and .score != "N/A" and .score != 2) | .id]) as $unmet |
      "| \($c.id) | \($c.percent | pct) | \(
        if ($c.applicable | not) then $c.why
        elif $c.scored == 0 then "Every criterion N/A"
        elif ($unmet | length) == 0 then "All \($c.scored) applicable criteria met"
        else "Not fully met: \($unmet | join(", "))" end | cell) |"),
    "",
    "- **Overall score:** \($s.overall)",
    "- **Maturity level:** \($s.maturity | levelname)",
    "- **Blocking gate criteria:** \(
      if $s.next_level == null then "None — highest level reached"
      else (if ($s.blocking | length) > 0 then $s.blocking | join(", ") else "None" end)
        + (if $s.overall < $s.next_level_min_score then " (\($s.next_level) also needs an overall score ≥ \($s.next_level_min_score))" else "" end)
      end)",
    "",
    "## Criterion scores",
    "",
    "| ID | Score | Evidence / justification |",
    "|---|---|---|",
    ($s.criteria[] | "| \(.id) | \(score_cell) | \(.evidence | cell) |"),
    "",
    "## Actions",
    "",
    "| ID | Action | Target level |",
    "|---|---|---|",
    (if ($acts | length) == 0 then "| — | No actions | — |"
     else ($acts[] | "| \(.id | cell) | \(.action | cell) | \(.target_level | cell) |") end),
    "",
    "## Needs manual confirmation",
    "",
    ([$s.criteria[] | select(.applicable and .unverified)] as $u |
     if ($u | length) == 0 then "Every applicable criterion was verified."
     else ("These criteria were scored on the evidence available to the assessment and could not be fully verified. A human check may raise the score.", "",
       "| ID | Scored | What was not verified |", "|---|---|---|",
       ($u[] | "| \(.id) | \(.score) | \(.evidence | cell) |")) end)
  ] | .[]' "$scored"
