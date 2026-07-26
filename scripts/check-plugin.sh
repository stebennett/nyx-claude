#!/usr/bin/env bash
# check-plugin.sh — structural validation for a Claude Code plugin directory.
#
# Checks:
#   1. .claude-plugin/plugin.json exists, parses, and carries name/version/description/author
#   2. every *.json under the plugin parses
#   3. every agents/*.md has frontmatter whose `name:` equals the filename stem
#   4. every skills/*/SKILL.md has frontmatter whose `name:` equals its directory name
#   5. every `references/...md` path named in a SKILL.md exists, resolved either
#      relative to that skill's directory or relative to the plugin root
#      (a ${CLAUDE_PLUGIN_ROOT}-style path). Both forms are in use in this repo.
#   6. every agents/*.md stem is referenced by at least one SKILL.md in the plugin
#
# Exit: 0 pass, 1 structural failure, 2 usage error.
#
# bash 3.2 compatible. No GNU-only constructs.

set -u

plugin="${1:-}"
if [ -z "$plugin" ] || [ ! -d "$plugin" ]; then
  echo "usage: check-plugin.sh <plugin-dir>" >&2
  exit 2
fi
plugin="${plugin%/}"

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# Read one frontmatter key from a markdown file. Empty output means absent
# or the file has no frontmatter block starting on line 1.
fm_get() {
  awk -v k="$2" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, k ":") == 1 {
      sub("^" k ":[ \t]*", "")
      sub("[ \t]+$", "")
      print
      exit
    }
  ' "$1"
}

# 1. manifest
manifest="$plugin/.claude-plugin/plugin.json"
if [ ! -f "$manifest" ]; then
  err "missing $manifest"
elif ! jq -e . "$manifest" >/dev/null 2>&1; then
  err "$manifest is not valid JSON"
else
  for key in name version description author; do
    jq -e "has(\"$key\")" "$manifest" >/dev/null 2>&1 \
      || err "$manifest missing required key: $key"
  done
fi

# 2. every JSON parses
while IFS= read -r f; do
  jq -e . "$f" >/dev/null 2>&1 || err "$f is not valid JSON"
done < <(find "$plugin" -type f -name '*.json')

# 3. agents
while IFS= read -r f; do
  stem=$(basename "$f" .md)
  name=$(fm_get "$f" name)
  desc=$(fm_get "$f" description)
  [ -n "$name" ] || err "$f has no frontmatter 'name:'"
  [ -n "$desc" ] || err "$f has no frontmatter 'description:'"
  if [ -n "$name" ] && [ "$name" != "$stem" ]; then
    err "$f frontmatter name '$name' does not match filename stem '$stem'"
  fi
done < <(find "$plugin/agents" -type f -name '*.md' 2>/dev/null)

# 4 & 5. skills
while IFS= read -r f; do
  skilldir=$(dirname "$f")
  dirname_=$(basename "$skilldir")
  name=$(fm_get "$f" name)
  desc=$(fm_get "$f" description)
  [ -n "$name" ] || err "$f has no frontmatter 'name:'"
  [ -n "$desc" ] || err "$f has no frontmatter 'description:'"
  if [ -n "$name" ] && [ "$name" != "$dirname_" ]; then
    err "$f frontmatter name '$name' does not match directory '$dirname_'"
  fi
  # The regex must capture any leading path segments — a reference may be
  # ../sibling-skill/references/x.md or skills/foo/references/x.md, and
  # matching from "references/" onward would silently drop the prefix.
  while IFS= read -r rel; do
    if [ ! -f "$skilldir/$rel" ] && [ ! -f "$plugin/$rel" ]; then
      err "$f references missing file: $rel"
    fi
  done < <(grep -oE '(\.\./)*([A-Za-z0-9_.-]+/)*references/[A-Za-z0-9_./-]+\.md' "$f" \
             | sort -u)
done < <(find "$plugin/skills" -type f -name 'SKILL.md' 2>/dev/null)

# 6. orphan agents — also catches a dispatch-name typo in a SKILL.md,
#    because the correct stem then appears nowhere.
while IFS= read -r f; do
  stem=$(basename "$f" .md)
  if ! grep -rqF -- "$stem" "$plugin/skills" 2>/dev/null; then
    err "agent '$stem' is never referenced by any SKILL.md in $plugin"
  fi
done < <(find "$plugin/agents" -type f -name '*.md' 2>/dev/null)

if [ "$fail" -ne 0 ]; then
  echo "check-plugin: FAILED ($plugin)" >&2
  exit 1
fi
echo "check-plugin: OK ($plugin)"
exit 0
