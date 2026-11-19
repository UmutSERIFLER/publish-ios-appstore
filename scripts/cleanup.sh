#!/usr/bin/env bash
# Runs even when earlier steps fail: removes this run's keychain (certificate
# and private key) and the API key, so no secret lingers on self-hosted runners.
# Provisioning profiles stay installed: they hold no secrets and a concurrent
# run may still need them (see signing.sh). The archive and .ipa are kept for
# later steps (e.g. actions/upload-artifact).
set -uo pipefail

[[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]] || exit 0

keychain="$WORK_DIR/signing.keychain-db"
if [[ -f "$keychain" ]]; then
  security delete-keychain "$keychain" || echo "::warning::Could not delete keychain $keychain"
fi

rm -rf "$WORK_DIR/private_keys" "$WORK_DIR/profiles" "$WORK_DIR/certificate.p12"
echo "Removed signing assets and API key."
