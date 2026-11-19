# shellcheck shell=bash
# Exercises the real `security` keychain flow. It mutates the user's keychain
# search list, so it only runs on throwaway CI runners (CI=true).

test_signing_installs_certificate_and_profiles_then_cleanup_removes_them() {
  [[ "${CI:-}" == "true" ]] || skip "needs a disposable macOS runner (set CI=true)"

  local team="ABCDE12345" work_dir="$TEST_TMP/work"
  export HOME="$TEST_TMP/home" WORK_DIR="$work_dir" GITHUB_OUTPUT="$TEST_TMP/github_output"
  mkdir -p "$HOME" "$work_dir"
  : >"$GITHUB_OUTPUT"

  make_p12 "$TEST_TMP/cert.p12" "p12-secret"
  make_profile "$TEST_TMP/app.mobileprovision" "App Store App" "UUID-APP" "$team" "$team.com.example.app"
  make_profile "$TEST_TMP/widget.mobileprovision" "App Store Widget" "UUID-WIDGET" "$team" "$team.com.example.app.widget"
  export INPUT_CERTIFICATE INPUT_PROVISION_PROFILE INPUT_P12_PASSWORD="p12-secret" INPUT_KEYCHAIN_PASSWORD=""
  INPUT_CERTIFICATE="$(b64 "$TEST_TMP/cert.p12")"
  INPUT_PROVISION_PROFILE="$(b64 "$TEST_TMP/app.mobileprovision"),$(b64 "$TEST_TMP/widget.mobileprovision")"

  bash "$ROOT_DIR/scripts/signing.sh"

  local keychain="$work_dir/signing.keychain-db"
  assert_contains "$(security list-keychains -d user)" "$keychain"
  security find-certificate -c "Test Distribution" "$keychain" >/dev/null
  assert_file_exists "$HOME/Library/MobileDevice/Provisioning Profiles/UUID-APP.mobileprovision"
  assert_file_exists "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/UUID-WIDGET.mobileprovision"
  assert_eq "2" "$(wc -l <"$work_dir/profiles.tsv" | tr -d ' ')"
  assert_eq "teamId=$team" "$(grep '^teamId=' "$GITHUB_OUTPUT")"
  [[ ! -e "$work_dir/certificate.p12" ]]

  bash "$ROOT_DIR/scripts/cleanup.sh"

  if security list-keychains -d user | grep -q "$keychain"; then return 1; fi
  [[ ! -e "$keychain" ]]
  [[ ! -e "$HOME/Library/MobileDevice/Provisioning Profiles/UUID-APP.mobileprovision" ]]
  [[ ! -e "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/UUID-WIDGET.mobileprovision" ]]
}
