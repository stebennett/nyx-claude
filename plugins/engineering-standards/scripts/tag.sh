#!/usr/bin/env bash
# tag.sh — read, write and gate the engineering_standards section of .nyx.yml.
#
#   tag.sh read  <repo>              print the section as JSON ("null" if absent)
#   tag.sh write <repo> <json-file>  validate, stamp versions, and write the section
#   tag.sh gate  <repo>              assess precondition; prints the tag JSON or fails
#
# Exit: 0 ok, 2 usage/dependency, 3 missing/invalid tag, 4 archived, 5 version mismatch.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
es_require_deps

cmd="${1:-}"; repo="${2:-}"
[ -n "$cmd" ] && [ -n "$repo" ] && [ -d "$repo" ] || es_die 2 "usage: tag.sh read|write|gate <repo> [json-file]"

case "$cmd" in
  read) es_tag_json "$repo" ;;
  gate) es_tag_gate "$repo" ;;
  write)
    src="${3:-}"
    [ -f "$src" ] || es_die 2 "usage: tag.sh write <repo> <json-file>"
    stamped="$(mktemp)"; trap 'rm -f "$stamped"' EXIT
    jq --arg fw "$(es_framework_version)" --argjson schema "$(es_schema_version)" \
      '{schema_version: $schema, framework_version: $fw} + (. | del(.schema_version, .framework_version))
       | .optional_categories //= [] | .exemptions //= []' "$src" > "$stamped" \
      || es_die 2 "$src is not valid JSON"
    problems="$(es_tag_problems "$(cat "$stamped")")"
    [ -z "$problems" ] || es_die 3 "refusing to write an invalid tag:
$problems"
    es_tag_write "$repo" "$stamped"
    es_tag_json "$repo"
    ;;
  *) es_die 2 "unknown command: $cmd" ;;
esac
