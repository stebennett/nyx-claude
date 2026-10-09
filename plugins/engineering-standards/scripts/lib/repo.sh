# repo.sh — read-only introspection of the repository in the current directory,
# shared by the checks/group-*.sh scripts. Sourced after common.sh.
# bash 3.2 compatible; no GNU-only constructs.
# shellcheck shell=bash

# --- files ------------------------------------------------------------------

# Tracked files when this is a git work tree, otherwise everything outside .git.
# Cached: every check consults it.
ES_FILES=""
repo_files() {
  if [ -z "$ES_FILES" ]; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      ES_FILES="$(git ls-files)"
    else
      ES_FILES="$(find . -type f -not -path './.git/*' | sed 's#^\./##')"
    fi
  fi
  printf '%s\n' "$ES_FILES"
}

files_matching() { repo_files | grep -E "$1" || true; } # <ERE on path>
has_files() { [ -n "$(files_matching "$1")" ]; }       # <ERE on path>

# First existing path among the arguments.
first_of() {
  local f
  for f in "$@"; do [ -e "$f" ] && { printf '%s\n' "$f"; return 0; }; done
  return 1
}

# Source files excluding vendored, generated and dependency directories.
source_files() { # <ERE on extension>
  files_matching "$1" | grep -Ev '(^|/)(node_modules|vendor|dist|build|\.venv|third_party|generated)/' || true
}

# Every tracked copy of a manifest (monorepos keep one per workspace member).
manifests() { # <filename...>
  local n pat=""
  for n in "$@"; do pat="$pat${pat:+|}$(printf '%s' "$n" | sed 's/\./\\./g')"; done
  files_matching "(^|/)($pat)\$" | grep -Ev '(^|/)(node_modules|vendor|\.venv)/' || true
}

# Tracked files under <pathspec globs> whose content matches <ERE>.
search_files() { # <ERE> <glob...>
  local pat="$1"
  shift
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git grep -lIE "$pat" -- "$@" 2>/dev/null || true
  else
    local g args=""
    for g in "$@"; do args="$args --include=$g"; done
    # shellcheck disable=SC2086 # word-splitting the --include list is intended
    grep -rlIE $args "$pat" . 2>/dev/null | sed 's#^\./##' || true
  fi
}

lang_go() { has_files '\.go$'; }
lang_python() { has_files '\.py$'; }
lang_ts() { has_files '\.(ts|tsx|mts|cts)$'; }
lang_node() { [ -f package.json ]; }

# Up to <n> lines of input joined with ", ", with "(+N more)" when truncated.
summarise() { # <n>
  awk -v n="$1" 'NF { c++; if (c <= n) out = out (c > 1 ? ", " : "") $0 }
    END { if (c > n) out = out " (+" c - n " more)"; print out }'
}

# --- tag --------------------------------------------------------------------

ES_TAG=""
tag_field() { # <field>
  [ -n "$ES_TAG" ] || ES_TAG="$(es_tag_json .)"
  printf '%s' "$ES_TAG" | jq -r --arg f "$1" '.[$f] // empty | tostring'
}

# Recipes section 2.1 requires for this repo's tag.
required_recipes() {
  [ -n "$ES_TAG" ] || ES_TAG="$(es_tag_json .)"
  jq -r --argjson tag "$ES_TAG" '
    .recipes[] | select(all(.applies_when[];
      . as $c | ($tag[$c.field] | tostring) as $v |
      if $c.in then ($c.in | index($v)) != null else ($c.not_in | index($v)) == null end)) | .name' "$ES_RUBRIC"
}

# --- GitHub Actions workflows ------------------------------------------------

workflows() { files_matching '^\.github/workflows/[^/]+\.ya?ml$'; }

# Workflows whose text matches <ERE>.
wf_grep() {
  local f
  for f in $(workflows); do grep -Eq "$1" "$f" && printf '%s\n' "$f"; done
  return 0
}

# Event names that trigger <workflow>, one per line. `on:` may be a string, a
# list, or a map; mikefarah yq reads YAML 1.2, so the key stays the string "on".
wf_triggers() {
  yq -r '.on | ((select(tag == "!!str")), (select(tag == "!!seq") | .[]), (select(tag == "!!map") | keys | .[]))' "$1" 2>/dev/null
}

wf_on() { wf_triggers "$1" | grep -qx "$2"; } # <workflow> <event>

# Does some workflow matching <ERE> run on both push and pull_request?
# Prints "both", "partial" (matches, but not on both events) or "none".
wf_runs_on_push_and_pr() {
  local f found=none
  for f in $(wf_grep "$1"); do
    found=partial
    if wf_on "$f" push && wf_on "$f" pull_request; then echo both; return 0; fi
  done
  echo "$found"
}

# --- justfile -----------------------------------------------------------------

justfile_path() { first_of justfile Justfile .justfile; }

# Recipe names defined in the justfile, one per line.
just_recipes() {
  local jf
  jf="$(justfile_path)" || return 0
  awk '
    /^[ \t]/ || /^#/ || /^$/ { next }
    /^(set|alias|export|import|mod)[ \t]/ { next }
    /:=/ { next }
    /^\[/ { next }
    /^@?[A-Za-z_][A-Za-z0-9_-]*[^:]*:/ { name = $1; sub(/^@/, "", name); sub(/:.*/, "", name); print name }
  ' "$jf"
}

just_has() { just_recipes | grep -qx "$1"; }

# The header dependencies and body of <recipe>, plus the bodies of recipes it
# depends on or calls with `just <name>` (one level), so `check: lint test` and
# a body of `just lint` both expose what lint runs.
just_body() { # <recipe> [depth]
  local jf depth="${2:-0}" text dep
  jf="$(justfile_path)" || return 0
  text="$(awk -v r="$1" '
    !in_r && /^[^ \t#]/ {
      h = $0; sub(/^@/, "", h)
      split(h, parts, /[ \t:]/)
      if (parts[1] == r && h !~ /:=/) { in_r = 1; sub(/^[^:]*:/, "", h); print "deps:" h; next }
    }
    in_r && /^[^ \t]/ && !/^$/ { exit }
    in_r { print }
  ' "$jf")"
  printf '%s\n' "$text"
  [ "$depth" -lt 2 ] || return 0
  for dep in $(printf '%s\n' "$text" | sed -nE 's/^deps:(.*)/\1/p' | tr ' ' '\n' | sed -E 's/\(.*//') \
             $(printf '%s\n' "$text" | sed -nE 's/.*just ([A-Za-z_][A-Za-z0-9_-]*).*/\1/p'); do
    [ -n "$dep" ] && [ "$dep" != "$1" ] && just_has "$dep" && just_body "$dep" $((depth + 1))
  done
  return 0
}

# --- Dockerfiles ---------------------------------------------------------------

dockerfiles() { files_matching '(^|/)Dockerfile[^/]*$' | grep -v '^\.devcontainer/' || true; }

# Images named by FROM lines in <dockerfile>, excluding earlier stage names,
# scratch and ARG-substituted images. One per line.
docker_images() {
  awk '
    toupper($1) == "FROM" {
      img = ""
      for (i = 2; i <= NF; i++) if ($i !~ /^--/) { img = $i; break }
      for (i = 2; i < NF; i++) if (toupper($i) == "AS") stages[tolower($(i + 1))] = 1
      if (img == "" || img == "scratch" || img ~ /\$/ || (tolower(img) in stages)) next
      print img
    }' "$1"
}

# The image of the final FROM line (the runtime stage).
docker_final_image() {
  awk 'toupper($1) == "FROM" { img = ""; for (i = 2; i <= NF; i++) if ($i !~ /^--/) { img = $i; break } }
       END { print img }' "$1"
}

docker_stage_count() { grep -Eic '^[[:space:]]*FROM[[:space:]]' "$1" || true; }

# --- Renovate ------------------------------------------------------------------

renovate_config() {
  first_of renovate.json renovate.json5 .github/renovate.json .github/renovate.json5 \
    .gitlab/renovate.json .renovaterc .renovaterc.json .renovaterc.json5
}

# --- JSONC ---------------------------------------------------------------------

# Strip whole-line // comments and trailing commas so jq can read JSONC
# (devcontainer.json, tsconfig.json). Good enough for config files; not a parser.
jsonc() {
  sed -E 's#^[[:space:]]*//.*$##; s#[[:space:]]+//[^"]*$##' "$1" | tr '\n' ' ' | sed -E 's/,[[:space:]]*([]}])/\1/g'
}
