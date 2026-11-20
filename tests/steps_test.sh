# shellcheck shell=bash
# Step scripts run against stubbed xcodebuild/xcrun (tests/stubs) so the exact
# flags handed to Apple's tools are asserted without a real project.

PEM_KEY="-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgFAKEKEYFAKEKEYFAKE
-----END PRIVATE KEY-----"

use_stubs() {
  PATH="$TESTS_DIR/stubs:$PATH"
  GITHUB_OUTPUT="$TEST_TMP/github_output"
  RUNNER_TEMP="$TEST_TMP/runner_temp"
  mkdir -p "$RUNNER_TEMP"
  : >"$GITHUB_OUTPUT"
  export PATH GITHUB_OUTPUT RUNNER_TEMP
}

run_step() {
  bash "$ROOT_DIR/scripts/$1"
}

step_output() {
  grep "^$1=" "$GITHUB_OUTPUT" | tail -n 1 | cut -d= -f2-
}

setup_env() {
  export INPUT_PROJECT_NAME="App" INPUT_WORKSPACE="" INPUT_PROJECT="" INPUT_SCHEME=""
  export INPUT_BUILD_NUMBER="" INPUT_VERSION="" INPUT_MOBILE_PROVISION="" INPUT_TEAM_ID=""
  export INPUT_API_KEY="$PEM_KEY" INPUT_API_KEY_ID="KEY123" INPUT_API_ISSUER="issuer-uuid"
  export GITHUB_RUN_NUMBER="57"
}

xcode_env() {
  export WORK_DIR="$TEST_TMP/work" CONTAINER_FLAG="-workspace" CONTAINER_PATH="ios/App.xcworkspace"
  export SCHEME="App" INPUT_EXTRA_ARGS="" INPUT_API_KEY_ID="KEY123" INPUT_API_ISSUER="issuer-uuid"
  export API_KEY_PATH="$TEST_TMP/work/private_keys/AuthKey_KEY123.p8"
  mkdir -p "$WORK_DIR"
}

# --- setup.sh --------------------------------------------------------------

test_setup_writes_api_key_and_outputs() {
  use_stubs
  setup_env
  run_step setup.sh
  local work_dir
  work_dir="$(step_output workDir)"
  assert_contains "$work_dir" "$RUNNER_TEMP/publish-ios-appstore."
  assert_eq "$work_dir/private_keys/AuthKey_KEY123.p8" "$(step_output apiKeyPath)"
  assert_file_exists "$work_dir/private_keys/AuthKey_KEY123.p8"
  assert_eq "-project" "$(step_output containerFlag)"
  assert_eq "App.xcodeproj" "$(step_output containerPath)"
  assert_eq "App" "$(step_output scheme)"
  assert_eq "57" "$(step_output buildNumber)"
}

test_setup_fails_without_api_key() {
  use_stubs
  setup_env
  INPUT_API_KEY=""
  assert_fails run_step setup.sh
}

test_setup_fails_on_invalid_version() {
  use_stubs
  setup_env
  INPUT_VERSION="1.0-beta"
  assert_fails run_step setup.sh
}

test_setup_fails_on_malformed_team_id() {
  use_stubs
  setup_env
  export INPUT_TEAM_ID="my team"
  assert_fails run_step setup.sh
}

test_setup_warns_that_mobile_provision_is_deprecated() {
  use_stubs
  setup_env
  INPUT_MOBILE_PROVISION="My Profile"
  assert_contains "$(run_step setup.sh 2>&1)" "::warning::"
}

# --- signing.sh ------------------------------------------------------------

install_profile_for_run() {
  WORK_DIR="$TEST_TMP/$1" INPUT_CERTIFICATE="" INPUT_PROVISION_PROFILE="$2" run_step signing.sh >/dev/null
}

test_signing_installs_profiles_by_uuid_in_both_xcode_folders() {
  use_stubs
  export HOME="$TEST_TMP/home"
  mkdir -p "$TEST_TMP/run-a"
  make_profile "$TEST_TMP/app.mobileprovision" "App Store App" "UUID-APP" "ABCDE12345" "ABCDE12345.com.example.app"
  install_profile_for_run run-a "$(b64 "$TEST_TMP/app.mobileprovision")"
  assert_file_exists "$HOME/Library/MobileDevice/Provisioning Profiles/UUID-APP.mobileprovision"
  assert_file_exists "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/UUID-APP.mobileprovision"
  assert_eq "com.example.app	App Store App	ABCDE12345	UUID-APP" "$(cat "$TEST_TMP/run-a/profiles.tsv")"
  assert_eq "teamId=ABCDE12345" "$(grep '^teamId=' "$GITHUB_OUTPUT")"
}

test_cleanup_keeps_profiles_a_concurrent_run_still_needs() {
  use_stubs
  export HOME="$TEST_TMP/home"
  mkdir -p "$TEST_TMP/run-a" "$TEST_TMP/run-b"
  make_profile "$TEST_TMP/app.mobileprovision" "App Store App" "UUID-APP" "ABCDE12345" "ABCDE12345.com.example.app"
  install_profile_for_run run-a "$(b64 "$TEST_TMP/app.mobileprovision")"
  install_profile_for_run run-b "$(b64 "$TEST_TMP/app.mobileprovision")"
  WORK_DIR="$TEST_TMP/run-a" run_step cleanup.sh >/dev/null
  assert_file_exists "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/UUID-APP.mobileprovision"
}

test_signing_is_skipped_without_certificate_or_profile() {
  use_stubs
  xcode_env
  export INPUT_CERTIFICATE="" INPUT_PROVISION_PROFILE="" INPUT_P12_PASSWORD="" INPUT_KEYCHAIN_PASSWORD=""
  run_step signing.sh
  [[ ! -e "$WORK_DIR/signing.keychain-db" ]]
  assert_eq "" "$(step_output teamId)"
}

# --- run-tests.sh ----------------------------------------------------------

test_run_tests_is_skipped_when_disabled() {
  use_stubs
  xcode_env
  export INPUT_RUN_TESTS="false" INPUT_TEST_DESTINATION=""
  run_step run-tests.sh
  [[ ! -e "$TEST_TMP/xcodebuild.log" ]]
}

test_run_tests_uses_newest_iphone_simulator() {
  use_stubs
  xcode_env
  export INPUT_RUN_TESTS="true" INPUT_TEST_DESTINATION=""
  run_step run-tests.sh
  assert_contains "$(tail -n 1 "$TEST_TMP/xcodebuild.log")" \
    "test -workspace ios/App.xcworkspace -scheme App -destination id=9A0D1E7C-5B7A-4E7B-8C1A-2B3C4D5E6F70"
}

# Discovery resolves packages too, so it needs options like -scmProvider.
test_run_tests_passes_extra_args_to_destination_discovery() {
  use_stubs
  xcode_env
  export INPUT_RUN_TESTS="true" INPUT_TEST_DESTINATION=""
  INPUT_EXTRA_ARGS="-scmProvider system"
  run_step run-tests.sh
  assert_contains "$(head -n 1 "$TEST_TMP/xcodebuild.log")" "-showdestinations -workspace ios/App.xcworkspace -scheme App -scmProvider system"
}

test_run_tests_uses_explicit_destination_and_extra_args() {
  use_stubs
  xcode_env
  export INPUT_RUN_TESTS="true" INPUT_TEST_DESTINATION="platform=iOS Simulator,name=iPhone 16"
  INPUT_EXTRA_ARGS="-skipMacroValidation -skipPackagePluginValidation"
  run_step run-tests.sh
  assert_eq "1" "$(wc -l <"$TEST_TMP/xcodebuild.log" | tr -d ' ')"
  assert_contains "$(cat "$TEST_TMP/xcodebuild.log")" \
    "-destination platform=iOS\\ Simulator\\,name=iPhone\\ 16 -skipMacroValidation -skipPackagePluginValidation"
}

test_run_tests_passes_every_line_of_extra_args() {
  use_stubs
  xcode_env
  export INPUT_RUN_TESTS="true" INPUT_TEST_DESTINATION="platform=iOS Simulator,name=iPhone 16"
  INPUT_EXTRA_ARGS=$'-skipMacroValidation\n-scmProvider system'
  run_step run-tests.sh
  assert_contains "$(cat "$TEST_TMP/xcodebuild.log")" "16 -skipMacroValidation -scmProvider system"
}

test_run_tests_fails_without_iphone_simulator() {
  use_stubs
  xcode_env
  export INPUT_RUN_TESTS="true" INPUT_TEST_DESTINATION=""
  printf '{ platform:iOS, id:123, name:My iPhone }\n' >"$TEST_TMP/destinations.txt"
  export STUB_DESTINATIONS="$TEST_TMP/destinations.txt"
  assert_fails run_step run-tests.sh
}

# --- archive.sh ------------------------------------------------------------

test_archive_stamps_versions_and_authenticates_with_api_key() {
  use_stubs
  xcode_env
  export INPUT_CONFIGURATION="Release" BUILD_NUMBER="57" INPUT_VERSION="2.1.0"
  INPUT_EXTRA_ARGS="-skipMacroValidation"
  run_step archive.sh
  local log
  log="$(cat "$TEST_TMP/xcodebuild.log")"
  assert_contains "$log" "clean archive -workspace ios/App.xcworkspace -scheme App -configuration Release"
  assert_contains "$log" "-destination generic/platform=iOS -archivePath $WORK_DIR/App.xcarchive"
  assert_contains "$log" "-allowProvisioningUpdates -authenticationKeyPath $API_KEY_PATH -authenticationKeyID KEY123 -authenticationKeyIssuerID issuer-uuid"
  assert_contains "$log" "CURRENT_PROJECT_VERSION=57 MARKETING_VERSION=2.1.0 -skipMacroValidation"
  assert_eq "$WORK_DIR/App.xcarchive" "$(step_output archivePath)"
  assert_eq "57" "$(step_output buildNumber)"
}

test_archive_omits_marketing_version_and_team_when_not_set() {
  use_stubs
  xcode_env
  export INPUT_CONFIGURATION="Release" BUILD_NUMBER="57" INPUT_VERSION="" INPUT_TEAM_ID=""
  run_step archive.sh
  if grep -q -e MARKETING_VERSION -e DEVELOPMENT_TEAM "$TEST_TMP/xcodebuild.log"; then return 1; fi
}

test_archive_passes_team_id_for_automatic_signing() {
  use_stubs
  xcode_env
  export INPUT_CONFIGURATION="Release" BUILD_NUMBER="57" INPUT_VERSION="" INPUT_TEAM_ID="ABCDE12345"
  run_step archive.sh
  assert_contains "$(cat "$TEST_TMP/xcodebuild.log")" "CURRENT_PROJECT_VERSION=57 DEVELOPMENT_TEAM=ABCDE12345"
}

test_archive_passes_every_line_of_extra_args() {
  use_stubs
  xcode_env
  export INPUT_CONFIGURATION="Release" BUILD_NUMBER="57" INPUT_VERSION=""
  INPUT_EXTRA_ARGS=$'-skipMacroValidation\n-scmProvider system\n'
  run_step archive.sh
  assert_contains "$(cat "$TEST_TMP/xcodebuild.log")" "CURRENT_PROJECT_VERSION=57 -skipMacroValidation -scmProvider system"
}

test_archive_warns_when_build_number_is_not_applied() {
  use_stubs
  xcode_env
  export INPUT_CONFIGURATION="Release" BUILD_NUMBER="57" INPUT_VERSION=""
  export STUB_ARCHIVED_BUILD_NUMBER="1"
  assert_contains "$(run_step archive.sh 2>&1)" "::warning::"
}

test_archive_outputs_the_build_number_it_actually_archived() {
  use_stubs
  xcode_env
  export INPUT_CONFIGURATION="Release" BUILD_NUMBER="57" INPUT_VERSION=""
  export STUB_ARCHIVED_BUILD_NUMBER="1"
  run_step archive.sh 2>/dev/null
  assert_eq "1" "$(step_output buildNumber)"
}

# --- export.sh -------------------------------------------------------------

test_export_uses_installed_profiles_and_outputs_ipa() {
  use_stubs
  xcode_env
  export BUILD_NUMBER="57" INPUT_CONFIGURATION="Release" INPUT_VERSION=""
  run_step archive.sh
  printf 'com.example.app\tApp Store App\tPROFILETEAM\tUUID-APP\n' >"$WORK_DIR/profiles.tsv"
  export ARCHIVE_PATH="$WORK_DIR/App.xcarchive" INPUT_EXPORT_METHOD="app-store-connect"
  export INPUT_TEAM_ID="" PROFILE_TEAM_ID="PROFILETEAM"
  run_step export.sh
  local options="$WORK_DIR/ExportOptions.plist"
  assert_eq "manual" "$(plist_value "$options" signingStyle)"
  assert_eq "PROFILETEAM" "$(plist_value "$options" teamID)"
  assert_eq "App Store App" "$(plist_value "$options" provisioningProfiles:com.example.app)"
  assert_contains "$(tail -n 1 "$TEST_TMP/xcodebuild.log")" \
    "-exportArchive -archivePath $ARCHIVE_PATH -exportPath $WORK_DIR/export -exportOptionsPlist $options -allowProvisioningUpdates"
  assert_eq "$WORK_DIR/export/My App.ipa" "$(step_output ipaPath)"
}

test_export_falls_back_to_archive_team_for_automatic_signing() {
  use_stubs
  xcode_env
  export BUILD_NUMBER="57" INPUT_CONFIGURATION="Release" INPUT_VERSION=""
  run_step archive.sh
  export ARCHIVE_PATH="$WORK_DIR/App.xcarchive" INPUT_EXPORT_METHOD="app-store-connect"
  export INPUT_TEAM_ID="" PROFILE_TEAM_ID=""
  run_step export.sh
  assert_eq "automatic" "$(plist_value "$WORK_DIR/ExportOptions.plist" signingStyle)"
  assert_eq "ARCHIVETEAM" "$(plist_value "$WORK_DIR/ExportOptions.plist" teamID)"
}

test_export_warns_when_app_bundle_has_no_profile() {
  use_stubs
  xcode_env
  export BUILD_NUMBER="57" INPUT_CONFIGURATION="Release" INPUT_VERSION=""
  run_step archive.sh
  printf 'com.other.app\tOther\tTEAM\tUUID\n' >"$WORK_DIR/profiles.tsv"
  export ARCHIVE_PATH="$WORK_DIR/App.xcarchive" INPUT_EXPORT_METHOD="app-store-connect"
  export INPUT_TEAM_ID="TEAM" PROFILE_TEAM_ID=""
  assert_contains "$(run_step export.sh 2>&1)" "::warning::"
}

test_export_fails_when_no_ipa_is_produced() {
  use_stubs
  xcode_env
  export ARCHIVE_PATH="$WORK_DIR/App.xcarchive" INPUT_EXPORT_METHOD="app-store-connect"
  export INPUT_TEAM_ID="TEAM" PROFILE_TEAM_ID="" STUB_SKIP_IPA="1"
  mkdir -p "$ARCHIVE_PATH"
  assert_fails run_step export.sh
}

test_export_fails_when_xcodebuild_fails() {
  use_stubs
  xcode_env
  export ARCHIVE_PATH="$WORK_DIR/App.xcarchive" INPUT_EXPORT_METHOD="app-store-connect"
  export INPUT_TEAM_ID="TEAM" PROFILE_TEAM_ID="" STUB_XCODEBUILD_EXIT="70"
  mkdir -p "$ARCHIVE_PATH"
  assert_fails run_step export.sh
}

# --- upload.sh -------------------------------------------------------------

test_upload_validates_then_uploads_from_work_dir() {
  use_stubs
  xcode_env
  export IPA_PATH="$WORK_DIR/export/My App.ipa" INPUT_VALIDATE_APP="true" INPUT_UPLOAD_APP="true"
  run_step upload.sh
  local log
  log="$(cat "$TEST_TMP/xcrun.log")"
  assert_eq "2" "$(wc -l <"$TEST_TMP/xcrun.log" | tr -d ' ')"
  assert_contains "$(sed -n 1p "$TEST_TMP/xcrun.log")" \
    "$WORK_DIR|altool --validate-app -f $WORK_DIR/export/My\\ App.ipa -t ios --apiKey KEY123 --apiIssuer issuer-uuid"
  assert_contains "$(sed -n 2p "$TEST_TMP/xcrun.log")" \
    "$WORK_DIR|altool --upload-app -f $WORK_DIR/export/My\\ App.ipa -t ios --apiKey KEY123 --apiIssuer issuer-uuid"
}

test_upload_can_skip_validation_and_upload() {
  use_stubs
  xcode_env
  export IPA_PATH="$WORK_DIR/export/My App.ipa" INPUT_VALIDATE_APP="false" INPUT_UPLOAD_APP="false"
  run_step upload.sh
  [[ ! -e "$TEST_TMP/xcrun.log" ]]
}

test_upload_fails_when_altool_fails() {
  use_stubs
  xcode_env
  export IPA_PATH="$WORK_DIR/export/My App.ipa" INPUT_VALIDATE_APP="true" INPUT_UPLOAD_APP="true"
  export STUB_XCRUN_EXIT="1"
  assert_fails run_step upload.sh
}

# --- cleanup.sh ------------------------------------------------------------

test_cleanup_removes_secrets_but_keeps_build_products() {
  use_stubs
  xcode_env
  mkdir -p "$WORK_DIR/private_keys" "$WORK_DIR/export"
  : >"$API_KEY_PATH"
  : >"$WORK_DIR/export/My App.ipa"
  : >"$WORK_DIR/certificate.p12"
  run_step cleanup.sh
  [[ ! -e "$WORK_DIR/private_keys" ]]
  [[ ! -e "$WORK_DIR/certificate.p12" ]]
  assert_file_exists "$WORK_DIR/export/My App.ipa"
}

# A self-hosted runner must not look clean while it still holds secrets.
test_cleanup_fails_when_keychain_cannot_be_deleted_but_still_removes_api_key() {
  use_stubs
  xcode_env
  mkdir -p "$WORK_DIR/private_keys" "$TEST_TMP/bin"
  : >"$API_KEY_PATH"
  : >"$WORK_DIR/signing.keychain-db"
  printf '#!/bin/sh\nexit 1\n' >"$TEST_TMP/bin/security"
  chmod +x "$TEST_TMP/bin/security"
  local output
  output="$(PATH="$TEST_TMP/bin:$PATH" run_step cleanup.sh 2>&1)" && return 1
  assert_contains "$output" "::error::Could not delete keychain"
  [[ ! -e "$WORK_DIR/private_keys" ]]
}

test_cleanup_fails_when_api_key_cannot_be_removed() {
  use_stubs
  xcode_env
  mkdir -p "$WORK_DIR/private_keys"
  : >"$API_KEY_PATH"
  chmod a-w "$WORK_DIR/private_keys"
  local status=0
  run_step cleanup.sh >/dev/null 2>&1 || status=$?
  chmod u+w "$WORK_DIR/private_keys"
  [[ $status -ne 0 ]]
}

test_cleanup_is_a_no_op_without_work_dir() {
  WORK_DIR="" run_step cleanup.sh
}
