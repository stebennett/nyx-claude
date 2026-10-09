# Shared assertions for the engineering-standards script tests. Sourced, not run.
# bash 3.2 compatible.
# shellcheck shell=bash

tests_run=0
tests_failed=0

pass() { tests_run=$((tests_run + 1)); }
fail() { tests_run=$((tests_run + 1)); tests_failed=$((tests_failed + 1)); echo "FAIL: $*" >&2; }

assert_eq() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then pass; else fail "$1: expected [$2], got [$3]"; fi
}

assert_contains() { # <name> <needle> <haystack>
  case "$3" in *"$2"*) pass ;; *) fail "$1: [$2] not found in output: $3" ;; esac
}

assert_exit() { # <name> <expected-code> <cmd...>
  local name="$1" want="$2" got=0
  shift 2
  "$@" >/dev/null 2>&1 || got=$?
  assert_eq "$name (exit code)" "$want" "$got"
}

# score_of <records-json> <criterion-id>
score_of() { printf '%s' "$1" | jq -r --arg id "$2" '.[] | select(.id == $id) | .score | tostring'; }

finish() {
  if [ "$tests_failed" -ne 0 ]; then
    echo "$(basename "$0"): $tests_failed of $tests_run assertions failed" >&2
    exit 1
  fi
  echo "$(basename "$0"): all $tests_run assertions passed"
}
