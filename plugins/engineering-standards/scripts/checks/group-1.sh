#!/usr/bin/env bash
# group-1.sh — mechanical checks for STK, HYG, DOC and AGT.
#
#   group-1.sh <repo>
#
# Prints a JSON array of criterion records (see lib/common.sh es_rec). Only the
# criteria with method "script" in rubric.json are scored here.
# No pipefail: many checks pipe into `grep -q`, which exits on the first match
# and SIGPIPEs the producer; pipefail would turn that race into a false "no".
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/common.sh"
. "$here/../lib/repo.sh"
es_require_deps
repo="${1:-}"; [ -n "$repo" ] && [ -d "$repo" ] || es_die 2 "usage: group-1.sh <repo>"
cd "$repo"

out="$(mktemp)"; trap 'rm -f "$out"' EXIT
{
# STK-1 — backend code is Python or Go.
other="$(source_files '\.(java|kt|kts|rb|rs|php|cs|scala|ex|exs|clj|swift)$')"
if [ -z "$other" ]; then
  es_rec STK-1 2 "No backend source in languages other than Python or Go"
else
  n_other="$(printf '%s\n' "$other" | wc -l | tr -d ' ')"
  n_ok="$(source_files '\.(go|py)$' | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$n_ok" -gt $((n_other * 9)) ]; then
    es_rec STK-1 1 "Mostly Python/Go, but $n_other other-language file(s): $(printf '%s\n' "$other" | summarise 5)"
  else
    es_rec STK-1 0 "$n_other non-Python/Go backend file(s): $(printf '%s\n' "$other" | summarise 5)"
  fi
fi

# STK-2 — frontend is TypeScript; generated/config JS is exempt.
js="$(source_files '\.(js|jsx|mjs|cjs)$' | grep -Ev '(^|/)[^/]*config[^/]*\.[mc]?js$|(^|/)\.(eslintrc|prettierrc)\.c?js$|^docs?/' || true)"
if [ -n "$js" ]; then
  es_rec STK-2 0 "Hand-written JavaScript source: $(printf '%s\n' "$js" | summarise 5)"
elif lang_ts; then
  es_rec STK-2 2 "Frontend source is TypeScript; no .js/.jsx source outside config files"
else
  es_rec STK-2 N/A "No frontend code (no TypeScript or JavaScript source)"
fi

# STK-3 — tsconfig strict.
if ! lang_ts; then
  es_rec STK-3 N/A "No TypeScript in the repository"
else
  tsconfigs="$(files_matching '(^|/)tsconfig[^/]*\.json$' | grep -v node_modules || true)"
  if [ -z "$tsconfigs" ]; then
    es_rec STK-3 0 "TypeScript present but no tsconfig.json"
  elif grep -Eq '"strict"[[:space:]]*:[[:space:]]*true|"extends"[^,]*strict' $tsconfigs; then
    es_rec STK-3 2 "\"strict\": true in $(grep -El '"strict"[[:space:]]*:[[:space:]]*true|"extends"[^,]*strict' $tsconfigs | summarise 3)"
  else
    es_rec STK-3 0 "No \"strict\": true in $(printf '%s\n' "$tsconfigs" | summarise 3)"
  fi
fi

# STK-4 — toolchain versions pinned for each language in use.
ok=""; missing=""
# Monorepos: every go.mod / pyproject.toml needs its pin; package.json needs
# engines.node in at least the workspace root (or the only package.json).
for f in $(manifests go.mod); do
  grep -Eq '^go [0-9]' "$f" && ok="$ok $f:go" || missing="$missing $f:go"
  grep -Eq '^toolchain ' "$f" && ok="$ok $f:toolchain" || missing="$missing $f:toolchain"
done
pyprojects="$(manifests pyproject.toml)"
if [ -n "$pyprojects" ]; then
  for f in $pyprojects; do
    grep -Eq '^requires-python' "$f" && ok="$ok $f:requires-python" || missing="$missing $f:requires-python"
  done
  [ -n "$(files_matching '(^|/)\.python-version$')" ] && ok="$ok .python-version" || missing="$missing .python-version"
fi
pkgs="$(manifests package.json)"
if [ -n "$pkgs" ]; then
  root_pkg="$(first_of package.json || printf '%s\n' "$pkgs" | head -1)"
  [ -n "$(jq -r '.engines.node // empty' "$root_pkg" 2>/dev/null)" ] && ok="$ok $root_pkg:engines.node" || missing="$missing $root_pkg:engines.node"
  [ -n "$(files_matching '(^|/)\.(nvmrc|node-version)$')" ] && ok="$ok node-version-file" || missing="$missing .nvmrc/.node-version"
fi
if [ -z "$ok$missing" ]; then
  es_rec STK-4 N/A "No go.mod, pyproject.toml or package.json"
elif [ -z "$missing" ]; then
  es_rec STK-4 2 "Pinned:$ok"
elif [ -n "$ok" ]; then
  es_rec STK-4 1 "Pinned:$ok; missing:$missing"
else
  es_rec STK-4 0 "Missing:$missing"
fi

# DOC-3 — licence, or README states private and unlicensed.
licence="$(files_matching '^(LICEN[CS]E|COPYING)([.-][^/]*)?$' | head -1)"
readme="$(first_of README.md README readme.md README.rst || true)"
if [ -n "$licence" ]; then
  es_rec DOC-3 2 "Licence file: $licence"
elif [ -n "$readme" ] && grep -Eiq 'private' "$readme" && grep -Eiq 'unlicen[cs]ed|not licen[cs]ed|no licen[cs]e|all rights reserved' "$readme"; then
  es_rec DOC-3 2 "$readme states the repository is private and unlicensed"
else
  es_rec DOC-3 0 "No LICENSE file and the README does not state private/unlicensed"
fi

# HYG-1 — .gitignore covers build output, local env files and editor files.
if [ ! -f .gitignore ]; then
  es_rec HYG-1 0 "No .gitignore"
else
  have=""; lack=""
  grep -Eq '(^|/)(dist|build|bin|out|target|__pycache__|node_modules|coverage|\.venv|\*\.pyc)/?' .gitignore \
    && have="$have build-output" || lack="$lack build-output"
  grep -Eq '\.env' .gitignore && have="$have env-files" || lack="$lack env-files"
  grep -Eq '\.vscode|\.idea|\.DS_Store|\*\.swp|\*~' .gitignore && have="$have editor-files" || lack="$lack editor-files"
  if [ -z "$lack" ]; then es_rec HYG-1 2 ".gitignore covers:$have"
  elif [ -n "$have" ]; then es_rec HYG-1 1 ".gitignore covers:$have; missing:$lack"
  else es_rec HYG-1 0 ".gitignore covers none of build output, env files, editor files"
  fi
fi

# HYG-2 — no committed build artefacts or binaries over 1 MB.
artefacts="$(files_matching '(^|/)(dist|build|out|target|node_modules|__pycache__|coverage)/|\.(pyc|o|so|dylib|dll|exe|class|jar|whl)$' | grep -Ev '^\.github/' || true)"
large=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  size="$(wc -c < "$f" | tr -d ' ')"
  [ "$size" -gt 1048576 ] && large="$large
$f ($((size / 1048576)) MB)"
done <<EOF_FILES
$(repo_files)
EOF_FILES
if [ -n "$artefacts" ]; then
  es_rec HYG-2 0 "Committed build output: $(printf '%s\n' "$artefacts" | summarise 5)"
elif [ -n "$large" ]; then
  es_rec HYG-2 1 "Files over 1 MB: $(printf '%s\n' "$large" | summarise 5) — confirm each is required and documented" true
else
  es_rec HYG-2 2 "No build output or files over 1 MB tracked"
fi

# HYG-4 — layout follows language conventions.
ok=""; bad=""
if lang_go; then
  if [ "$(tag_field type)" = "library" ]; then ok="$ok go(library)"
  elif has_files '^cmd/[^/]+/' && has_files '^internal/'; then ok="$ok go:cmd+internal"
  else bad="$bad go:needs-cmd/<name>/-and-internal/"; fi
fi
if lang_python; then
  if [ -n "$(manifests pyproject.toml)" ] && has_files '(^|/)src/[^/]+/__init__\.py$'; then ok="$ok python:src-layout"
  else bad="$bad python:needs-src/<package>/-with-pyproject.toml"; fi
fi
if lang_ts; then
  stray="$(source_files '\.(ts|tsx)$' | grep -Ev '(^|/)src/|(^|/)(tests?|e2e|__tests__|scripts)/|\.(config|test|spec)\.tsx?$|\.config\.[a-z]+\.ts$|\.d\.ts$|^(workers?|functions)/|(^|/)(vite|vitest|playwright|eslint|tailwind|postcss|jest)\.[^/]*\.ts$' || true)"
  if [ -z "$stray" ]; then ok="$ok typescript:src/"
  else bad="$bad typescript-outside-src/($(printf '%s\n' "$stray" | summarise 3))"; fi
fi
if [ -z "$ok$bad" ]; then es_rec HYG-4 N/A "No Go, Python or TypeScript source"
elif [ -z "$bad" ]; then es_rec HYG-4 2 "Conventional layout:$ok"
elif [ -n "$ok" ]; then es_rec HYG-4 1 "Conventional:$ok; not:$bad"
else es_rec HYG-4 0 "Not conventional:$bad"
fi

# HYG-5 — .editorconfig.
[ -f .editorconfig ] && es_rec HYG-5 2 ".editorconfig present" || es_rec HYG-5 0 "No .editorconfig"

# AGT-1 — agent file present.
agent="$(first_of CLAUDE.md AGENTS.md .claude/CLAUDE.md || true)"
if [ -n "$agent" ]; then es_rec AGT-1 2 "Agent file: $agent"; else es_rec AGT-1 0 "No CLAUDE.md or AGENTS.md"; fi

# AGT-2 — agent file directs the agent to just recipes for build/test/lint/run.
if [ -z "$agent" ]; then
  es_rec AGT-2 0 "No agent file"
else
  want="test lint"
  for r in build run; do required_recipes | grep -qx "$r" && want="$want $r"; done
  named=""; absent=""
  for r in $want; do
    if grep -Eq "just (check|$r)([^A-Za-z_-]|$)" "$agent"; then named="$named $r"; else absent="$absent $r"; fi
  done
  if [ -z "$absent" ]; then es_rec AGT-2 2 "$agent directs to just recipes for:$named"
  elif grep -q 'just ' "$agent"; then es_rec AGT-2 1 "$agent mentions just but not recipes for:$absent"
  else es_rec AGT-2 0 "$agent does not mention just recipes"
  fi
fi
} > "$out"
jq -s . "$out"
