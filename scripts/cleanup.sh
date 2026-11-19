#!/usr/bin/env bash
# Runs even when earlier steps fail: removes the keychain, the API key and the
# profiles this action installed, so nothing lingers on self-hosted runners.
# The archive and .ipa are kept for later steps (e.g. actions/upload-artifact).
set -uo pipefail

[[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]] || exit 0

keychain="$WORK_DIR/signing.keychain-db"
if [[ -f "$keychain" ]]; then
  security delete-keychain "$keychain" || echo "::warning::Could not delete keychain $keychain"
fi

installed_profiles="$WORK_DIR/installed-profiles.txt"
if [[ -f "$installed_profiles" ]]; then
  while IFS= read -r profile; do
    [[ -n "$profile" ]] && rm -f "$profile"
  done <"$installed_profiles"
  rm -f "$installed_profiles"
fi

rm -rf "$WORK_DIR/private_keys" "$WORK_DIR/profiles" "$WORK_DIR/certificate.p12"
echo "Removed signing assets and API key."
