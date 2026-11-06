#!/usr/bin/env bash
# scaffold-preflight.sh — decide whether <repo> is new enough to scaffold.
#
#   scaffold-preflight.sh <repo>
#
# Prints JSON: {git, commits, worktree, nested, files, non_doc_files, verdict}.
#   files          tracked plus untracked, non-ignored files (everything outside
#                  .git when <repo> is not a git repo)
#   non_doc_files  the files that are not documentation (DOC_PATTERN below)
#   worktree       "none" outside git, "secondary" in a linked worktree, else "main"
#   nested         true when <repo> is a subdirectory of an enclosing git repo
#   verdict        "empty" | "docs-only" | "populated"
#
# Exit: 0 ok (the verdict is data, not an exit code), 2 usage/dependency.
set -eu
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
es_require_deps

repo="${1:-}"
[ -n "$repo" ] && [ -d "$repo" ] || es_die 2 "usage: scaffold-preflight.sh <repo>"
cd "$repo"

# What counts as specification and design documentation (plus OS and editor
# cruft, which never blocks). Keep this the only copy.
DOC_PATTERN='(^|/)\.DS_Store$|(^|/)Thumbs\.db$|^\.vscode/|^\.idea/|^docs/|\.(md|markdown|txt|rst|adoc|pdf)$|^LICENSE|^\.gitignore$|^\.gitattributes$|^\.nyx\.yml$|^\.claude/|^\.github/ISSUE_TEMPLATE/'

list="$(mktemp)"; trap 'rm -f "$list"' EXIT
git=false commits=false worktree=none nested=false
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git=true
  git rev-parse --verify -q HEAD >/dev/null 2>&1 && commits=true
  [ -z "$(git rev-parse --show-prefix)" ] || nested=true
  gd="$(cd "$(git rev-parse --git-dir)" && pwd -P)"
  gcd="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
  if [ "$gd" = "$gcd" ]; then worktree=main; else worktree=secondary; fi
  git ls-files --cached --others --exclude-standard -z > "$list"
else
  find . -type f -not -path './.git/*' -print0 > "$list"
fi

jq -R -s --arg pat "$DOC_PATTERN" --argjson git "$git" --argjson commits "$commits" --arg wt "$worktree" --argjson nested "$nested" '
  split("\u0000") | map(select(length > 0) | ltrimstr("./")) as $files |
  ($files | map(select(test($pat) | not))) as $other |
  {git: $git, commits: $commits, worktree: $wt, nested: $nested, files: $files, non_doc_files: $other,
   verdict: (if ($files | length) == 0 then "empty"
             elif ($other | length) == 0 then "docs-only"
             else "populated" end)}' "$list"
