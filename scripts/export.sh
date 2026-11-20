#!/usr/bin/env bash
# Exports the archive to an App Store signed .ipa.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

: "${WORK_DIR:?}" "${ARCHIVE_PATH:?}"
export_options="$WORK_DIR/ExportOptions.plist"
export_path="$WORK_DIR/export"
profiles_tsv="$WORK_DIR/profiles.tsv"

archive_property() {
  /usr/libexec/PlistBuddy -c "Print :ApplicationProperties:$1" "$ARCHIVE_PATH/Info.plist" 2>/dev/null || true
}

team_id="${INPUT_TEAM_ID:-${PROFILE_TEAM_ID:-}}"
[[ -n "$team_id" ]] || team_id="$(archive_property Team)"

bundle_id="$(archive_property CFBundleIdentifier)"
if [[ -s "$profiles_tsv" && -n "$bundle_id" ]] && ! cut -f1 "$profiles_tsv" | grep -qxF "$bundle_id"; then
  warn "No provisioning profile in provisionProfileBase64 matches the app bundle id '$bundle_id'."
fi

write_export_options "$export_options" "${INPUT_EXPORT_METHOD:-app-store-connect}" "$team_id" "$profiles_tsv"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${API_KEY_PATH:?}" \
  -authenticationKeyID "${INPUT_API_KEY_ID:?}" \
  -authenticationKeyIssuerID "${INPUT_API_ISSUER:?}"

# The .ipa is named after the product, which can differ from the project name.
ipa_path="$(find "$export_path" -maxdepth 1 -name '*.ipa' -print 2>/dev/null | head -n 1)"
[[ -n "$ipa_path" ]] || fail "xcodebuild -exportArchive did not produce an .ipa in $export_path."

set_output ipaPath "$ipa_path"
echo "Exported $ipa_path"
