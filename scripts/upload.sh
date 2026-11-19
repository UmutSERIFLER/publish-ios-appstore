#!/usr/bin/env bash
# Validates and uploads the .ipa to App Store Connect (TestFlight).
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

: "${IPA_PATH:?}" "${WORK_DIR:?}"
auth=(--apiKey "${INPUT_API_KEY_ID:?}" --apiIssuer "${INPUT_API_ISSUER:?}")

# Every altool version searches ./private_keys for AuthKey_<id>.p8, whereas
# --p8-file-path and API_PRIVATE_KEYS_DIR only exist in newer Xcode releases.
cd "$WORK_DIR"
export API_PRIVATE_KEYS_DIR="$WORK_DIR/private_keys"

if is_true "${INPUT_VALIDATE_APP:-true}"; then
  echo "Validating $IPA_PATH"
  xcrun altool --validate-app -f "$IPA_PATH" -t ios "${auth[@]}"
fi

if is_true "${INPUT_UPLOAD_APP:-true}"; then
  echo "Uploading $IPA_PATH"
  xcrun altool --upload-app -f "$IPA_PATH" -t ios "${auth[@]}" --show-progress
else
  echo "uploadApp is false; the .ipa was not uploaded: $IPA_PATH"
fi
