# shellcheck shell=bash
# Exercises the real `security` keychain flow with the runner's real HOME,
# exactly as the action runs. It mutates the user's keychain search list and
# provisioning profile folders, so it only runs on throwaway CI runners.

test_signing_installs_certificate_and_profiles_then_cleanup_removes_them() {
  [[ "${CI:-}" == "true" ]] || skip "needs a disposable macOS runner (set CI=true)"

  local team="ABCDE12345" work_dir="$TEST_TMP/work" app_uuid widget_uuid keychains_before
  app_uuid="$(uuidgen)"
  widget_uuid="$(uuidgen)"
  local legacy_app="$HOME/Library/MobileDevice/Provisioning Profiles/$app_uuid.mobileprovision"
  local xcode16_widget="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$widget_uuid.mobileprovision"
  export WORK_DIR="$work_dir" GITHUB_OUTPUT="$TEST_TMP/github_output"
  mkdir -p "$work_dir"
  : >"$GITHUB_OUTPUT"
  keychains_before="$(security list-keychains -d user)"

  make_p12 "$TEST_TMP/cert.p12" "p12-secret"
  make_profile "$TEST_TMP/app.mobileprovision" "App Store App" "$app_uuid" "$team" "$team.com.example.app"
  make_profile "$TEST_TMP/widget.mobileprovision" "App Store Widget" "$widget_uuid" "$team" "$team.com.example.app.widget"
  export INPUT_CERTIFICATE INPUT_PROVISION_PROFILE INPUT_P12_PASSWORD="p12-secret" INPUT_KEYCHAIN_PASSWORD=""
  INPUT_CERTIFICATE="$(b64 "$TEST_TMP/cert.p12")"
  INPUT_PROVISION_PROFILE="$(b64 "$TEST_TMP/app.mobileprovision"),$(b64 "$TEST_TMP/widget.mobileprovision")"

  bash "$ROOT_DIR/scripts/signing.sh"

  local keychain="$work_dir/signing.keychain-db" keychains_during line
  keychains_during="$(security list-keychains -d user)"
  assert_contains "$keychains_during" "$keychain"
  while IFS= read -r line; do
    assert_contains "$keychains_during" "$(printf '%s' "$line" | tr -d ' "')"
  done <<<"$keychains_before"
  security find-certificate -c "Test Distribution" "$keychain" >/dev/null
  assert_file_exists "$legacy_app"
  assert_file_exists "$xcode16_widget"
  assert_eq "2" "$(wc -l <"$work_dir/profiles.tsv" | tr -d ' ')"
  assert_eq "teamId=$team" "$(grep '^teamId=' "$GITHUB_OUTPUT")"
  [[ ! -e "$work_dir/certificate.p12" ]]

  bash "$ROOT_DIR/scripts/cleanup.sh"

  assert_eq "$keychains_before" "$(security list-keychains -d user)"
  [[ ! -e "$keychain" ]]
  [[ ! -e "$legacy_app" ]]
  [[ ! -e "$xcode16_widget" ]]
}
