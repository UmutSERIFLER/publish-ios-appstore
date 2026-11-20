#!/usr/bin/env bash
# Runs even when earlier steps fail: removes this run's keychain (certificate
# and private key) and the API key, so no secret lingers on self-hosted runners.
# Every removal is attempted; any failure fails the step, so a runner that
# still holds secrets never looks clean.
# Provisioning profiles stay installed: they hold no secrets and a concurrent
# run may still need them (see signing.sh). The archive and .ipa are kept for
# later steps (e.g. actions/upload-artifact).
set -uo pipefail

[[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]] || exit 0

failed=0
error() {
  echo "::error::$1" >&2
  failed=1
}

keychain="$WORK_DIR/signing.keychain-db"
if [[ -f "$keychain" ]]; then
  security delete-keychain "$keychain" ||
    error "Could not delete keychain $keychain; it still holds the signing certificate. Delete it by hand."
fi

for path in private_keys profiles certificate.p12; do
  rm -rf "${WORK_DIR:?}/$path" || error "Could not remove $WORK_DIR/$path. Delete it by hand."
done

if ((failed)); then
  exit 1
fi
echo "Removed signing assets and API key."
