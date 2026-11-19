#!/usr/bin/env bash
# Usage: tests/run.sh [suite_dir]   (default: tests/)
# Runs every *_test.sh in suite_dir. Each test_* function runs in its own
# subshell with a fresh $TEST_TMP so tests cannot leak state into each other.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$TESTS_DIR")"
SUITE_DIR="${1:-$TESTS_DIR}"
export TESTS_DIR ROOT_DIR

passed=0
failed=0
skipped=0
failures=""

record_failure() {
  failed=$((failed + 1))
  failures="$failures $1"
  printf 'FAIL %s\n' "$1"
}

# Prints the test_* functions a file defines; fails if the file does not parse,
# cannot be sourced, or defines no tests. Runs in a separate bash process
# because `set -e` is ignored inside functions called from an `if` condition,
# and `source` returns only the status of the file's last command.
discover_tests() {
  "$BASH" -n "$1" || return 1
  # shellcheck disable=SC2016 # expanded by the child bash, not here
  "$BASH" -c '
    set -euo pipefail
    source "$1"
    source "$2" >/dev/null
    declare -F | awk "{ print \$3 }" | grep "^test_"
  ' discover "$TESTS_DIR/helpers.sh" "$1"
}

for test_file in "$SUITE_DIR"/*_test.sh; do
  if ! test_names="$(discover_tests "$test_file")"; then
    record_failure "$(basename "$test_file"):could-not-load-tests"
    continue
  fi
  for test_name in $test_names; do
    TEST_TMP="$(mktemp -d)"
    export TEST_TMP
    # No EXIT trap inside the subshell: bash 3.2 lets the trap's status mask a
    # failed `source`, which would report a broken test as passing.
    (
      set -euo pipefail
      # shellcheck source=tests/helpers.sh
      source "$TESTS_DIR/helpers.sh"
      # shellcheck source=/dev/null
      source "$test_file"
      "$test_name"
    )
    status=$?
    rm -rf "$TEST_TMP"
    if [[ $status -eq 0 ]]; then
      passed=$((passed + 1))
      printf 'ok   %s\n' "$test_name"
    elif [[ $status -eq 200 ]]; then
      skipped=$((skipped + 1))
      printf 'skip %s\n' "$test_name"
    else
      record_failure "$test_name"
    fi
  done
done

printf '\n%d passed, %d failed, %d skipped\n' "$passed" "$failed" "$skipped"
if [[ $failed -gt 0 ]]; then
  printf 'failed:%s\n' "$failures"
  exit 1
fi
