#!/usr/bin/env bash
# Runs the scheme's tests on a simulator before anything is signed or uploaded.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

if ! is_true "${INPUT_RUN_TESTS:-true}"; then
  echo "runTests is false; skipping tests."
  exit 0
fi

container=("${CONTAINER_FLAG:?}" "${CONTAINER_PATH:?}")
destination="${INPUT_TEST_DESTINATION:-}"

if [[ -z "$destination" ]]; then
  destinations="$(xcodebuild -showdestinations "${container[@]}" -scheme "${SCHEME:?}" 2>&1)" ||
    fail "xcodebuild -showdestinations failed: $destinations"
  simulator_id="$(printf '%s\n' "$destinations" | pick_simulator_id)"
  [[ -n "$simulator_id" ]] ||
    fail "No iPhone simulator is available for scheme '$SCHEME'. Set the testDestination input."
  destination="id=$simulator_id"
fi

args=(test "${container[@]}" -scheme "$SCHEME" -destination "$destination")
split_extra_args "${INPUT_EXTRA_ARGS:-}"
if ((${#EXTRA_ARGS[@]})); then
  args+=("${EXTRA_ARGS[@]}")
fi

echo "Running tests on destination '$destination'."
xcodebuild "${args[@]}"
