#!/usr/bin/env bash
# Tests for tag.sh: writing preserves the rest of .nyx.yml, and the assess gate
# refuses missing, invalid, archived and version-mismatched tags.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/helpers.bash"
tag="$here/../tag.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

valid='{"type":"service","status":"active","deployment_target":"kubernetes","database":"postgresql",
  "lightweight":false,"optional_categories":[],"exemptions":[{"id":"SEC-4","reason":"no containers"}]}'

# --- missing file / section -------------------------------------------------
repo="$work/missing"; mkdir -p "$repo"
assert_eq "read with no .nyx.yml" "null" "$(bash "$tag" read "$repo")"
assert_exit "gate with no .nyx.yml" 3 bash "$tag" gate "$repo"
printf 'other: 1\n' > "$repo/.nyx.yml"
assert_exit "gate with no section" 3 bash "$tag" gate "$repo"
msg="$(bash "$tag" gate "$repo" 2>&1 || true)"
assert_contains "gate tells the user to classify" "/engineering-standards-classify" "$msg"

# --- write preserves other keys and comments ----------------------------------
repo="$work/preserve"; mkdir -p "$repo"
cat > "$repo/.nyx.yml" <<'YAML'
# top comment kept
other_tool:
  setting: keep-me # inline comment kept
YAML
printf '%s' "$valid" > "$work/tag.json"
bash "$tag" write "$repo" "$work/tag.json" >/dev/null
assert_eq "other key preserved" "keep-me" "$(yq '.other_tool.setting' "$repo/.nyx.yml")"
assert_contains "top comment preserved" "# top comment kept" "$(cat "$repo/.nyx.yml")"
assert_contains "inline comment preserved" "# inline comment kept" "$(cat "$repo/.nyx.yml")"
assert_eq "type written" "service" "$(yq '.engineering_standards.type' "$repo/.nyx.yml")"
assert_contains "section written as block YAML" "  type: service" "$(cat "$repo/.nyx.yml")"
assert_eq "framework version stamped" "1.4" "$(yq '.engineering_standards.framework_version' "$repo/.nyx.yml")"
assert_eq "schema version stamped" "1" "$(yq '.engineering_standards.schema_version' "$repo/.nyx.yml")"
assert_exit "gate passes on a fresh tag" 0 bash "$tag" gate "$repo"

# Rewriting replaces the section wholesale (no stale keys) and still keeps other keys.
printf '%s' "$valid" | jq '.type = "cli" | .exemptions = []' > "$work/tag2.json"
bash "$tag" write "$repo" "$work/tag2.json" >/dev/null
assert_eq "section rewritten" "cli" "$(yq '.engineering_standards.type' "$repo/.nyx.yml")"
assert_eq "exemptions replaced" "0" "$(yq '.engineering_standards.exemptions | length' "$repo/.nyx.yml")"
assert_eq "other key still preserved" "keep-me" "$(yq '.other_tool.setting' "$repo/.nyx.yml")"

# --- write refuses invalid tags ------------------------------------------------
for bad in '.type = "website"' '.lightweight = "no"' '.exemptions = [{"id":"SEC-4"}]' \
           '.exemptions = [{"id":"XYZ-9","reason":"r"}]' '.optional_categories = ["NOPE"]'; do
  printf '%s' "$valid" | jq "$bad" > "$work/bad.json"
  assert_exit "write refuses: $bad" 3 bash "$tag" write "$repo" "$work/bad.json"
done
assert_eq "refused write left the file alone" "cli" "$(yq '.engineering_standards.type' "$repo/.nyx.yml")"

# --- gate: archived and version mismatches --------------------------------------
yq -i '.engineering_standards.status = "archived"' "$repo/.nyx.yml"
assert_exit "gate refuses archived" 4 bash "$tag" gate "$repo"
yq -i '.engineering_standards.status = "active"' "$repo/.nyx.yml"

for v in 1.3 1.5 2.0; do
  yq -i ".engineering_standards.framework_version = \"$v\"" "$repo/.nyx.yml"
  assert_exit "gate refuses framework $v" 5 bash "$tag" gate "$repo"
done
yq -i '.engineering_standards.framework_version = "1.4" | .engineering_standards.schema_version = 2' "$repo/.nyx.yml"
assert_exit "gate refuses schema 2" 5 bash "$tag" gate "$repo"
msg="$(bash "$tag" gate "$repo" 2>&1 || true)"
assert_contains "mismatch tells the user to classify" "/engineering-standards-classify" "$msg"

yq -i '.engineering_standards.schema_version = 1 | .engineering_standards.type = "website"' "$repo/.nyx.yml"
assert_exit "gate refuses a hand-edited invalid tag" 3 bash "$tag" gate "$repo"

finish
