# applicability.jq — which categories and criteria apply to a tag. Shared by
# score.sh and plan.sh so the rules live in one place.
#
#   include "applicability"; (with jq -L <this directory>)

# All conditions hold for the tag ({field, in} or {field, not_in}).
def holds($tag; $conds):
  all($conds[]; . as $c | ($tag[$c.field] | tostring) as $v |
    if $c.in then ($c.in | index($v)) != null else ($c.not_in | index($v)) == null end);

# Rubric categories annotated with {matrix, applicable, why}.
def categories($r; $tag):
  $r.categories | map(
    .applicability[$tag.type] as $a | .id as $id |
    . + {matrix: $a} +
    (if $a == "-" then {applicable: false, why: "Not applicable to \($tag.type) projects (section 3 matrix)"}
     elif $a == "O" and (($tag.optional_categories | index($id)) == null)
       then {applicable: false, why: "Optional for \($tag.type) projects and not adopted"}
     elif (holds($tag; .applies_when // []) | not)
       then {applicable: false, why: "Not applicable: \(.applies_when | map("\(.field) \(if .in then "in" else "not in" end) \(.in // .not_in | join("/"))") | join(", "))"}
     else {applicable: true, why: null} end));

# Rubric criteria annotated with {applicable}; inapplicable ones carry a
# resolved N/A {score, evidence, source}.
def criteria($r; $tag):
  (categories($r; $tag) | map({key: .id, value: .}) | from_entries) as $catmap |
  ($tag.exemptions | map({key: .id, value: .reason}) | from_entries) as $exempt |
  $r.criteria | map(
    $catmap[.category] as $cat |
    if ($cat.applicable | not) then . + {applicable: false, score: "N/A", evidence: $cat.why, source: "rubric", unverified: false}
    elif (holds($tag; .applies_when) | not) then . + {applicable: false, score: "N/A", source: "rubric", unverified: false,
      evidence: "Not applicable: \(.applies_when | map("\(.field) is \($tag[.field])") | join(", "))"}
    elif $exempt[.id] then . + {applicable: false, score: "N/A", evidence: "Exempt: \($exempt[.id])", source: "tag", unverified: false}
    else . + {applicable: true} end);
