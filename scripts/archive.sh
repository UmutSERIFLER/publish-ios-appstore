#!/usr/bin/env bash
# Archives the app for App Store distribution and stamps the build number.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

archive_path="${WORK_DIR:?}/${SCHEME:?}.xcarchive"

args=(
  clean archive "${CONTAINER_FLAG:?}" "${CONTAINER_PATH:?}"
  -scheme "$SCHEME"
  -configuration "${INPUT_CONFIGURATION:-Release}"
  -destination generic/platform=iOS
  -archivePath "$archive_path"
  # Lets automatic signing fetch certificates/profiles with the API key; a
  # no-op for manually signed targets.
  -allowProvisioningUpdates
  -authenticationKeyPath "${API_KEY_PATH:?}"
  -authenticationKeyID "${INPUT_API_KEY_ID:?}"
  -authenticationKeyIssuerID "${INPUT_API_ISSUER:?}"
  # Applies to the app and its extensions, which must share CFBundleVersion.
  "CURRENT_PROJECT_VERSION=${BUILD_NUMBER:?}"
)
# Without it, automatically signed projects that never saved a team fail to
# archive; when empty the project's own DEVELOPMENT_TEAM is kept.
if [[ -n "${INPUT_TEAM_ID:-}" ]]; then
  args+=("DEVELOPMENT_TEAM=$INPUT_TEAM_ID")
fi
if [[ -n "${INPUT_VERSION:-}" ]]; then
  args+=("MARKETING_VERSION=$INPUT_VERSION")
fi
if [[ -n "${INPUT_EXTRA_ARGS:-}" ]]; then
  read -r -a extra_args <<<"$INPUT_EXTRA_ARGS"
  args+=("${extra_args[@]}")
fi

xcodebuild "${args[@]}"

archived_build_number="$(
  /usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$archive_path/Info.plist" 2>/dev/null || true
)"
if [[ "$archived_build_number" != "$BUILD_NUMBER" ]]; then
  warn "Archived CFBundleVersion is '$archived_build_number', not '$BUILD_NUMBER'. Set CFBundleVersion to \$(CURRENT_PROJECT_VERSION) in Info.plist (default for Xcode 13+ projects), otherwise App Store Connect rejects re-uploads of the same build number."
fi

set_output archivePath "$archive_path"
