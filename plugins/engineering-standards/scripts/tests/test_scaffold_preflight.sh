#!/usr/bin/env bash
# Tests for scaffold-preflight.sh: the empty / docs-only / populated verdict,
# untracked and gitignored files, awkward filenames, and worktree detection.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/helpers.bash"
pre="$here/../scaffold-preflight.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
g() { git -c user.name=t -c user.email=t@example.com "$@"; }
field() { printf '%s' "$1" | jq -c ".$2"; } # <json> <field>
run() { bash "$pre" "$1" < /dev/null; }

# --- empty, not a git repo ------------------------------------------------------
d="$work/plain"; mkdir -p "$d"
out="$(run "$d")"
assert_eq "plain dir verdict" '"empty"' "$(field "$out" verdict)"
assert_eq "plain dir git" "false" "$(field "$out" git)"
assert_eq "plain dir worktree" '"none"' "$(field "$out" worktree)"

# --- empty git repo -------------------------------------------------------------
d="$work/emptygit"; mkdir -p "$d"; git -C "$d" init -q -b main
out="$(run "$d")"
assert_eq "empty git verdict" '"empty"' "$(field "$out" verdict)"
assert_eq "empty git git" "true" "$(field "$out" git)"
assert_eq "empty git commits" "false" "$(field "$out" commits)"

# --- untracked docs, no commit --------------------------------------------------
d="$work/untracked"; mkdir -p "$d/docs"; git -C "$d" init -q -b main
echo spec > "$d/docs/spec.md"; echo readme > "$d/README.md"
out="$(run "$d")"
assert_eq "untracked docs verdict" '"docs-only"' "$(field "$out" verdict)"
assert_eq "untracked docs counted" "2" "$(field "$out" 'files | length')"

# --- filename with a space ------------------------------------------------------
d="$work/space"; mkdir -p "$d/docs"; git -C "$d" init -q -b main
echo spec > "$d/docs/My Spec.md"
out="$(run "$d")"
assert_eq "spaced name verdict" '"docs-only"' "$(field "$out" verdict)"
assert_eq "spaced name kept whole" '["docs/My Spec.md"]' "$(field "$out" files)"

# --- gitignored clutter ---------------------------------------------------------
d="$work/ignored"; mkdir -p "$d/docs" "$d/node_modules"; git -C "$d" init -q -b main
printf 'node_modules/\n' > "$d/.gitignore"; echo x > "$d/node_modules/x.js"; echo s > "$d/docs/spec.md"
out="$(run "$d")"
assert_eq "gitignored clutter verdict" '"docs-only"' "$(field "$out" verdict)"

# --- non-Markdown docs at the root ----------------------------------------------
d="$work/pdf"; mkdir -p "$d"; git -C "$d" init -q -b main
echo p > "$d/spec.pdf"; echo n > "$d/notes.txt"
out="$(run "$d")"
assert_eq "root pdf/txt verdict" '"docs-only"' "$(field "$out" verdict)"

# --- populated --------------------------------------------------------------------
d="$work/populated"; mkdir -p "$d/docs"; git -C "$d" init -q -b main
echo 'module x' > "$d/go.mod"; echo s > "$d/docs/spec.md"
out="$(run "$d")"
assert_eq "populated verdict" '"populated"' "$(field "$out" verdict)"
assert_eq "populated non-doc files" '["go.mod"]' "$(field "$out" non_doc_files)"

# --- worktrees ---------------------------------------------------------------------
d="$work/main"; mkdir -p "$d/docs"; git -C "$d" init -q -b main
echo s > "$d/docs/spec.md"; g -C "$d" add -A; g -C "$d" commit -qm "docs: spec"
git -C "$d" worktree add -q "$work/wt" -b other
out="$(run "$work/wt")"
assert_eq "secondary worktree detected" '"secondary"' "$(field "$out" worktree)"
out="$(run "$d")"
assert_eq "main worktree" '"main"' "$(field "$out" worktree)"
assert_eq "main has commits" "true" "$(field "$out" commits)"

# --- OS and editor cruft does not block -----------------------------------------------
d="$work/cruft"; mkdir -p "$d/docs" "$d/.vscode"; git -C "$d" init -q -b main
echo s > "$d/docs/spec.md"; echo x > "$d/.DS_Store"; echo '{}' > "$d/.vscode/settings.json"
out="$(run "$d")"
assert_eq "OS/editor cruft verdict" '"docs-only"' "$(field "$out" verdict)"

# --- new project nested inside an existing repo ---------------------------------------
mkdir -p "$d/newproj/docs"; echo s > "$d/newproj/docs/spec.md"
out="$(run "$d/newproj")"
assert_eq "nested project flagged" "true" "$(field "$out" nested)"
out="$(run "$d")"
assert_eq "repo root not nested" "false" "$(field "$out" nested)"
out="$(run "$work/plain")"
assert_eq "non-git dir not nested" "false" "$(field "$out" nested)"

# --- usage --------------------------------------------------------------------------
assert_exit "missing argument" 2 bash "$pre"

finish
