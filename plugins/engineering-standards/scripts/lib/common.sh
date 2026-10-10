# common.sh — shared helpers for the engineering-standards scripts. Sourced, not run.
# bash 3.2 compatible; no GNU-only constructs.
# shellcheck shell=bash

ES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ES_PLUGIN_ROOT="$(cd "$ES_LIB_DIR/../.." && pwd)"
ES_REFS="$ES_PLUGIN_ROOT/skills/engineering-standards-assess/references"
ES_RUBRIC="$ES_REFS/rubric.json"
ES_TAG_FILE=".nyx.yml"
ES_TAG_KEY="engineering_standards"

es_die() { # <exit-code> <message>
  echo "engineering-standards: $2" >&2
  exit "$1"
}

# jq and mikefarah yq v4 are both required. The Python "yq" wrapper shares the
# name but not the syntax, so check for mikefarah's version banner explicitly.
es_require_deps() {
  command -v jq >/dev/null 2>&1 \
    || es_die 2 "jq is required (brew install jq / apt-get install jq)"
  command -v yq >/dev/null 2>&1 \
    || es_die 2 "yq v4 (mikefarah) is required (brew install yq / https://github.com/mikefarah/yq)"
  case "$(yq --version 2>&1)" in
    *mikefarah*" version v4."* | *mikefarah*" version 4."*) ;;
    *) es_die 2 "yq must be mikefarah yq v4, found: $(yq --version 2>&1 | head -1)" ;;
  esac
}

es_framework_version() { jq -r .framework_version "$ES_RUBRIC"; }
es_schema_version() { jq -r .schema_version "$ES_RUBRIC"; }

# Print the tag section of <repo>/.nyx.yml as JSON, or "null" if absent.
es_tag_json() { # <repo>
  local f="$1/$ES_TAG_FILE"
  if [ ! -f "$f" ]; then echo null; return 0; fi
  yq -o=json ".$ES_TAG_KEY // null" "$f"
}

# Replace only the tag section of <repo>/.nyx.yml with <json-file>. Every other
# top-level key, and comments outside the section, are preserved.
es_tag_write() { # <repo> <json-file>
  local f="$1/$ES_TAG_FILE"
  [ -f "$f" ] || : > "$f"
  ES_TAG_SRC="$2" yq -i ".$ES_TAG_KEY = load(strenv(ES_TAG_SRC))" "$f"
}

# Print a list of problems with a tag (one per line); empty means valid.
es_tag_problems() { # <tag-json>
  printf '%s' "$1" | jq -r --slurpfile rubric "$ES_RUBRIC" '
    def enum(f; vals): if (.[f] as $v | vals | index($v)) then empty
      else "\(f) must be one of \(vals | join(", ")), got \(.[f] // "nothing")" end;
    ($rubric[0].categories | map(.id)) as $cats |
    ($rubric[0].criteria | map(.id)) as $ids |
    if type != "object" then "the section is not a mapping" else
        enum("type"; ["service","library","cli","infrastructure"]),
        enum("status"; ["active","maintained","archived"]),
        enum("deployment_target"; ["fly","cloudflare","kubernetes","none"]),
        enum("database"; ["postgresql","sqlite","d1","none"]),
        (if (.lightweight | type) != "boolean" then "lightweight must be true or false" else empty end),
        (if (.optional_categories | type) != "array" then "optional_categories must be a list"
         else .optional_categories[] | select(. as $c | $cats | index($c) | not)
              | "unknown category in optional_categories: \(.)" end),
        (if (.exemptions | type) != "array" then "exemptions must be a list"
         else (.exemptions[] | select((.id | type) != "string" or (.reason | type) != "string" or .reason == "")
              | "every exemption needs an id and a non-empty reason"),
           (.exemptions[] | .id | select(type == "string") | select(. as $i | $ids | index($i) | not)
              | "unknown criterion in exemptions: \(.)") end)
    end'
}

# Gate used by assess: exit non-zero with a re-classify instruction unless the
# repo has a valid, current, non-archived tag. Prints the tag JSON on success.
es_tag_gate() { # <repo>
  local tag schema fw problems
  tag="$(es_tag_json "$1")"
  [ "$tag" != "null" ] \
    || es_die 3 "no '$ES_TAG_KEY' section in $1/$ES_TAG_FILE — run /engineering-standards-classify first"
  schema="$(printf '%s' "$tag" | jq -r '.schema_version // "missing"')"
  fw="$(printf '%s' "$tag" | jq -r '.framework_version // "missing"')"
  [ "$schema" = "$(es_schema_version)" ] \
    || es_die 5 "tag schema_version is $schema but this plugin uses $(es_schema_version) — re-run /engineering-standards-classify"
  [ "$fw" = "$(es_framework_version)" ] \
    || es_die 5 "tag framework_version is $fw but the bundled standards are $(es_framework_version) — re-run /engineering-standards-classify"
  problems="$(es_tag_problems "$tag")"
  [ -z "$problems" ] \
    || es_die 3 "invalid tag in $1/$ES_TAG_FILE — re-run /engineering-standards-classify:
$problems"
  [ "$(printf '%s' "$tag" | jq -r .status)" != "archived" ] \
    || es_die 4 "the repository is tagged archived; archived repositories are not assessed"
  printf '%s\n' "$tag"
}

# Emit one criterion record as a single JSON line.
es_rec() { # <id> <score: 0|1|2|N/A> <evidence> [unverified: true|false]
  jq -cn --arg id "$1" --arg s "$2" --arg e "$3" --arg u "${4:-false}" \
    '{id: $id, score: (if $s == "N/A" then "N/A" else ($s | tonumber) end),
      evidence: $e, source: "script", unverified: ($u == "true")}'
}

# True when gh is installed, authenticated, and the repo has a GitHub remote.
es_gh_ok() { # <repo>
  command -v gh >/dev/null 2>&1 || return 1
  gh auth status >/dev/null 2>&1 || return 1
  (cd "$1" && gh repo view --json name >/dev/null 2>&1)
}
