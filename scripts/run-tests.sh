#!/usr/bin/env bash
# Runs the scheme's tests on a simulator before anything is signed or uploaded.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

if ! is_true "${INPUT_RUN_TESTS:-true}"; then
  echo "runTests is false; skipping tests."
  exit 0
fi

# Discovery resolves Swift packages too, so it gets the extra arguments (e.g.
# -scmProvider system). Test-only flags would also break archive, so they are
# never valid here anyway.
project=("${CONTAINER_FLAG:?}" "${CONTAINER_PATH:?}" -scheme "${SCHEME:?}")
split_extra_args "${INPUT_EXTRA_ARGS:-}"
destination="${INPUT_TEST_DESTINATION:-}"

if [[ -z "$destination" ]]; then
  discover=(-showdestinations "${project[@]}")
  if ((${#EXTRA_ARGS[@]})); then discover+=("${EXTRA_ARGS[@]}"); fi
  destinations="$(xcodebuild "${discover[@]}" 2>&1)" ||
    fail "xcodebuild -showdestinations failed: $destinations"
  simulator_id="$(printf '%s\n' "$destinations" | pick_simulator_id)"
  [[ -n "$simulator_id" ]] ||
    fail "No iPhone simulator is available for scheme '$SCHEME'. Set the testDestination input."
  destination="id=$simulator_id"
fi

args=(test "${project[@]}" -destination "$destination")
if ((${#EXTRA_ARGS[@]})); then args+=("${EXTRA_ARGS[@]}"); fi

echo "Running tests on destination '$destination'."
xcodebuild "${args[@]}"
