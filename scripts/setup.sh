#!/usr/bin/env bash
# Validates inputs, creates the per-run work directory and writes the App Store
# Connect API key. GitHub does not enforce `required: true` on composite action
# inputs, so required values are checked here.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

[[ -n "${INPUT_API_KEY:-}" ]] || fail "appstoreAPIKey is required."
[[ -n "${INPUT_API_KEY_ID:-}" ]] || fail "appstoreAPIKeyID is required."
[[ -n "${INPUT_API_ISSUER:-}" ]] || fail "appstoreAPIIssuer is required."

resolve_container "${INPUT_WORKSPACE:-}" "${INPUT_PROJECT:-}" "${INPUT_PROJECT_NAME:-}"
scheme="$(resolve_scheme "${INPUT_SCHEME:-}" "${INPUT_PROJECT_NAME:-}")"
build_number="$(resolve_build_number "${INPUT_BUILD_NUMBER:-}" "${GITHUB_RUN_NUMBER:-}")"

if [[ -n "${INPUT_VERSION:-}" ]] && ! is_bundle_version "$INPUT_VERSION"; then
  fail "version '$INPUT_VERSION' must be one to three period-separated integers, e.g. 2.1.0."
fi
team_pattern='^[A-Z0-9]{10}$'
if [[ -n "${INPUT_TEAM_ID:-}" && ! "$INPUT_TEAM_ID" =~ $team_pattern ]]; then
  fail "teamID '$INPUT_TEAM_ID' must be the 10-character Apple Developer team ID, e.g. ABCDE12345."
fi
if [[ -n "${INPUT_MOBILE_PROVISION:-}" ]]; then
  warn "mobileProvision is deprecated and ignored: profile names are read from provisionProfileBase64."
fi

work_dir="$(mktemp -d "${RUNNER_TEMP:?RUNNER_TEMP is not set}/publish-ios-appstore.XXXXXX")"
# Emitted first so the cleanup step can find secrets even if a later line fails.
set_output workDir "$work_dir"

api_key_path="$(write_api_key "$INPUT_API_KEY" "$INPUT_API_KEY_ID" "$work_dir/private_keys")"

set_output apiKeyPath "$api_key_path"
set_output containerFlag "${XCODE_CONTAINER_ARGS[0]}"
set_output containerPath "${XCODE_CONTAINER_ARGS[1]}"
set_output scheme "$scheme"
set_output buildNumber "$build_number"
echo "Using ${XCODE_CONTAINER_ARGS[*]}, scheme '$scheme', build number $build_number."
