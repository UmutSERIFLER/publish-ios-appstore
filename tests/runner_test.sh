# shellcheck shell=bash
# The runner must never report success for a test file it could not load.

run_suite() {
  /bin/bash "$TESTS_DIR/run.sh" "$TEST_TMP/suite" >/dev/null 2>&1
}

test_runner_passes_a_healthy_suite() {
  mkdir -p "$TEST_TMP/suite"
  printf 'test_ok() { true; }\n' >"$TEST_TMP/suite/ok_test.sh"
  run_suite
}

test_runner_fails_on_syntax_error_before_the_first_test() {
  mkdir -p "$TEST_TMP/suite"
  printf 'if then\ntest_ok() { true; }\n' >"$TEST_TMP/suite/broken_test.sh"
  assert_fails run_suite
}

test_runner_fails_on_syntax_error_after_a_test() {
  mkdir -p "$TEST_TMP/suite"
  printf 'test_ok() { true; }\nif then\n' >"$TEST_TMP/suite/broken_test.sh"
  assert_fails run_suite
}

test_runner_fails_when_a_file_defines_no_tests() {
  mkdir -p "$TEST_TMP/suite"
  printf 'helper() { true; }\n' >"$TEST_TMP/suite/empty_test.sh"
  assert_fails run_suite
}

test_runner_fails_when_a_file_cannot_be_sourced() {
  mkdir -p "$TEST_TMP/suite"
  printf 'source /nonexistent/file.sh\ntest_ok() { true; }\n' >"$TEST_TMP/suite/missing_test.sh"
  assert_fails run_suite
}
