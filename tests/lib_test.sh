# shellcheck shell=bash
# shellcheck source=scripts/lib.sh
source "$ROOT_DIR/scripts/lib.sh"

TEAM="ABCDE12345"
PEM_KEY="-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgFAKEKEYFAKEKEYFAKE
-----END PRIVATE KEY-----"

# --- is_true ---------------------------------------------------------------

test_is_true_accepts_common_truthy_spellings() {
  is_true true && is_true TRUE && is_true yes && is_true 1
}

test_is_true_rejects_everything_else() {
  ! is_true false && ! is_true "" && ! is_true no && ! is_true 0
}

# --- resolve_container -----------------------------------------------------

test_resolve_container_prefers_workspace() {
  resolve_container "ios/App.xcworkspace" "ios/App.xcodeproj" "App"
  assert_eq "-workspace ios/App.xcworkspace" "${XCODE_CONTAINER_ARGS[*]}"
}

test_resolve_container_uses_project_path() {
  resolve_container "" "ios/App.xcodeproj" "App"
  assert_eq "-project ios/App.xcodeproj" "${XCODE_CONTAINER_ARGS[*]}"
}

test_resolve_container_falls_back_to_project_name() {
  resolve_container "" "" "App"
  assert_eq "-project App.xcodeproj" "${XCODE_CONTAINER_ARGS[*]}"
}

test_resolve_container_fails_without_any_input() {
  assert_fails resolve_container "" "" ""
}

# --- resolve_scheme --------------------------------------------------------

test_resolve_scheme_prefers_explicit_scheme() {
  assert_eq "App Release" "$(resolve_scheme "App Release" "App")"
}

test_resolve_scheme_falls_back_to_project_name() {
  assert_eq "App" "$(resolve_scheme "" "App")"
}

test_resolve_scheme_fails_without_any_input() {
  assert_fails resolve_scheme "" ""
}

# --- resolve_build_number --------------------------------------------------

test_resolve_build_number_uses_explicit_value() {
  assert_eq "1.2.3" "$(resolve_build_number "1.2.3" "42")"
}

test_resolve_build_number_defaults_to_run_number() {
  assert_eq "42" "$(resolve_build_number "" "42")"
}

test_resolve_build_number_rejects_invalid_cfbundleversion() {
  assert_fails resolve_build_number "1.0-beta" "42"
  assert_fails resolve_build_number "1.2.3.4" "42"
  assert_fails resolve_build_number "" ""
}

# --- pick_simulator_id -----------------------------------------------------

test_pick_simulator_id_picks_newest_available_iphone() {
  local id
  id="$(pick_simulator_id <"$TESTS_DIR/fixtures/showdestinations.txt")"
  assert_eq "9A0D1E7C-5B7A-4E7B-8C1A-2B3C4D5E6F70" "$id"
}

test_pick_simulator_id_prints_nothing_without_iphone_simulators() {
  assert_eq "" "$(printf '{ platform:iOS, id:123, name:My iPhone }\n' | pick_simulator_id)"
}

# --- write_api_key ---------------------------------------------------------

test_write_api_key_accepts_raw_p8_contents() {
  local path
  path="$(write_api_key "$PEM_KEY" "KEY123" "$TEST_TMP/keys")"
  assert_eq "$TEST_TMP/keys/AuthKey_KEY123.p8" "$path"
  assert_eq "$PEM_KEY" "$(cat "$path")"
}

test_write_api_key_accepts_base64_encoded_p8() {
  local encoded path
  encoded="$(printf '%s\n' "$PEM_KEY" | base64 | tr -d '\n')"
  path="$(write_api_key "$encoded" "KEY123" "$TEST_TMP/keys")"
  assert_eq "$PEM_KEY" "$(cat "$path")"
}

test_write_api_key_restricts_permissions() {
  local path
  path="$(write_api_key "$PEM_KEY" "KEY123" "$TEST_TMP/keys")"
  assert_eq "600" "$(stat -f '%Lp' "$path")"
}

test_write_api_key_rejects_garbage() {
  assert_fails write_api_key "not-a-key" "KEY123" "$TEST_TMP/keys"
}

# --- decode_profiles / read_profile ----------------------------------------

test_decode_profiles_accepts_line_wrapped_base64() {
  make_profile "$TEST_TMP/app.mobileprovision" "App Store App" "UUID-APP" "$TEAM" "$TEAM.com.example.app"
  # GNU base64 wraps at 76 columns; v1 users may have stored the secret that way.
  local wrapped
  wrapped="$(b64 "$TEST_TMP/app.mobileprovision" | fold -w 76)"
  decode_profiles "$wrapped" "$TEST_TMP/out"
  assert_eq "1" "$(find "$TEST_TMP/out" -name '*.mobileprovision' | wc -l | tr -d ' ')"
}

test_decode_profiles_splits_multiple_profiles() {
  make_profile "$TEST_TMP/app.mobileprovision" "App Store App" "UUID-APP" "$TEAM" "$TEAM.com.example.app"
  make_profile "$TEST_TMP/widget.mobileprovision" "App Store Widget" "UUID-WIDGET" "$TEAM" "$TEAM.com.example.app.widget"
  local input
  input="$(b64 "$TEST_TMP/app.mobileprovision"),
$(b64 "$TEST_TMP/widget.mobileprovision")"
  decode_profiles "$input" "$TEST_TMP/out"
  assert_eq "2" "$(find "$TEST_TMP/out" -name '*.mobileprovision' | wc -l | tr -d ' ')"
}

test_decode_profiles_splits_newline_separated_profiles() {
  # Size the first profile to a multiple of 3 bytes so its base64 has no "="
  # padding: then both lines joined also decode, which must not win.
  local name="App Store App"
  while :; do
    make_profile "$TEST_TMP/app.mobileprovision" "$name" "UUID-APP" "$TEAM" "$TEAM.com.example.app"
    [[ $(($(wc -c <"$TEST_TMP/app.mobileprovision") % 3)) -ne 0 ]] || break
    name="${name}X"
  done
  make_profile "$TEST_TMP/widget.mobileprovision" "App Store Widget" "UUID-WIDGET" "$TEAM" "$TEAM.com.example.app.widget"
  local input
  input="$(b64 "$TEST_TMP/app.mobileprovision")
$(b64 "$TEST_TMP/widget.mobileprovision")
"
  decode_profiles "$input" "$TEST_TMP/out"
  assert_eq "2" "$(find "$TEST_TMP/out" -name '*.mobileprovision' | wc -l | tr -d ' ')"
  assert_eq "UUID-WIDGET" "$(read_profile "$TEST_TMP/out/profile-1.mobileprovision" | cut -f4)"
}

test_decode_profiles_rejects_invalid_profile() {
  assert_fails decode_profiles "$(printf 'garbage' | base64)" "$TEST_TMP/out"
}

test_read_profile_extracts_bundle_name_team_and_uuid() {
  make_profile "$TEST_TMP/app.mobileprovision" "App Store App" "UUID-APP" "$TEAM" "$TEAM.com.example.app"
  assert_eq "com.example.app	App Store App	$TEAM	UUID-APP" "$(read_profile "$TEST_TMP/app.mobileprovision")"
}

# --- write_export_options --------------------------------------------------

test_write_export_options_manual_signing_maps_bundle_ids_to_profiles() {
  printf 'com.example.app\tApp Store App\t%s\tUUID-APP\ncom.example.app.widget\tApp Store Widget\t%s\tUUID-W\n' \
    "$TEAM" "$TEAM" >"$TEST_TMP/profiles.tsv"
  local plist="$TEST_TMP/ExportOptions.plist"
  write_export_options "$plist" "app-store-connect" "$TEAM" "$TEST_TMP/profiles.tsv"
  assert_eq "app-store-connect" "$(plist_value "$plist" method)"
  assert_eq "$TEAM" "$(plist_value "$plist" teamID)"
  assert_eq "manual" "$(plist_value "$plist" signingStyle)"
  assert_eq "false" "$(plist_value "$plist" manageAppVersionAndBuildNumber)"
  assert_eq "App Store App" "$(plist_value "$plist" provisioningProfiles:com.example.app)"
  assert_eq "App Store Widget" "$(plist_value "$plist" provisioningProfiles:com.example.app.widget)"
}

test_write_export_options_without_profiles_uses_automatic_signing() {
  local plist="$TEST_TMP/ExportOptions.plist"
  write_export_options "$plist" "app-store-connect" "$TEAM" "$TEST_TMP/missing.tsv"
  assert_eq "automatic" "$(plist_value "$plist" signingStyle)"
  assert_fails plist_value "$plist" provisioningProfiles
}

test_write_export_options_skips_wildcard_profiles() {
  printf '*\tWildcard\t%s\tUUID-STAR\n' "$TEAM" >"$TEST_TMP/profiles.tsv"
  local plist="$TEST_TMP/ExportOptions.plist"
  write_export_options "$plist" "app-store-connect" "$TEAM" "$TEST_TMP/profiles.tsv" 2>/dev/null
  assert_fails plist_value "$plist" "provisioningProfiles:*"
}
