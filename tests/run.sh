#!/usr/bin/env bash
# Runs every tests/*_test.sh. Each test_* function runs in its own subshell with
# a fresh $TEST_TMP so tests cannot leak state into each other.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$TESTS_DIR")"
export TESTS_DIR ROOT_DIR

passed=0
failed=0
skipped=0
failures=""

for test_file in "$TESTS_DIR"/*_test.sh; do
  test_names="$(
    # shellcheck source=/dev/null
    source "$test_file"
    declare -F | awk '{print $3}' | grep '^test_' || true
  )"
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
      failed=$((failed + 1))
      failures="$failures $test_name"
      printf 'FAIL %s\n' "$test_name"
    fi
  done
done

printf '\n%d passed, %d failed, %d skipped\n' "$passed" "$failed" "$skipped"
if [[ $failed -gt 0 ]]; then
  printf 'failed:%s\n' "$failures"
  exit 1
fi
