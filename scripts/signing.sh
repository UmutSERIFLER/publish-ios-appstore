#!/usr/bin/env bash
# Manual signing: imports the distribution certificate into a temporary keychain
# and installs every provisioning profile. Skipped entirely for automatic
# signing, where xcodebuild fetches signing assets with the API key.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

: "${WORK_DIR:?WORK_DIR is not set}"
KEYCHAIN_PATH="$WORK_DIR/signing.keychain-db"
PROFILES_TSV="$WORK_DIR/profiles.tsv"
INSTALLED_PROFILES="$WORK_DIR/installed-profiles.txt"

create_keychain() {
  local password="$1"
  security create-keychain -p "$password" "$KEYCHAIN_PATH"
  # 6h timeout so the keychain does not lock in the middle of a long archive.
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
  security unlock-keychain -p "$password" "$KEYCHAIN_PATH"
}

# Prepends the keychain to the user search list but keeps the existing entries,
# so self-hosted runners still see their login keychain.
add_keychain_to_search_list() {
  local keychains=("$KEYCHAIN_PATH") line
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')"
    [[ -n "$line" && "$line" != "$KEYCHAIN_PATH" ]] && keychains+=("$line")
  done < <(security list-keychains -d user)
  security list-keychains -d user -s "${keychains[@]}"
}

install_certificate() {
  local password="${INPUT_KEYCHAIN_PASSWORD:-}" certificate="$WORK_DIR/certificate.p12"
  if [[ -z "$password" ]]; then
    password="$(openssl rand -hex 24)"
    echo "::add-mask::$password"
  fi

  create_keychain "$password"
  (umask 077 && printf '%s' "$INPUT_CERTIFICATE" | decode_base64 >"$certificate") ||
    fail "certificateBase64 is not valid base64."
  security import "$certificate" -k "$KEYCHAIN_PATH" -f pkcs12 -P "${INPUT_P12_PASSWORD:-}" -A ||
    fail "Could not import certificateBase64; check p12FilePassword."
  rm -f "$certificate"
  # Without a partition list codesign prompts for keychain access and hangs CI.
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$KEYCHAIN_PATH" >/dev/null
  add_keychain_to_search_list
  echo "Imported signing certificate into $KEYCHAIN_PATH."
}

install_profiles() {
  local decoded_dir="$WORK_DIR/profiles" profile metadata uuid dir destination
  decode_profiles "$INPUT_PROVISION_PROFILE" "$decoded_dir"
  : >"$PROFILES_TSV"

  for profile in "$decoded_dir"/*.mobileprovision; do
    metadata="$(read_profile "$profile")"
    printf '%s\n' "$metadata" >>"$PROFILES_TSV"
    uuid="$(printf '%s' "$metadata" | cut -f4)"
    for dir in "${PROFILE_DIRS[@]}"; do
      mkdir -p "$dir"
      destination="$dir/$uuid.mobileprovision"
      # Only files we create are removed by cleanup; pre-installed ones stay.
      if [[ ! -e "$destination" ]]; then
        cp "$profile" "$destination"
        printf '%s\n' "$destination" >>"$INSTALLED_PROFILES"
      fi
    done
    echo "Installed profile '$(printf '%s' "$metadata" | cut -f2)' for $(printf '%s' "$metadata" | cut -f1)."
  done
  rm -rf "$decoded_dir"

  set_output teamId "$(head -n 1 "$PROFILES_TSV" | cut -f3)"
}

if [[ -z "${INPUT_CERTIFICATE:-}" && -z "${INPUT_PROVISION_PROFILE:-}" ]]; then
  echo "No certificate or provisioning profile given; using automatic signing with the API key."
  exit 0
fi
[[ -z "${INPUT_CERTIFICATE:-}" ]] || install_certificate
[[ -z "${INPUT_PROVISION_PROFILE:-}" ]] || install_profiles
