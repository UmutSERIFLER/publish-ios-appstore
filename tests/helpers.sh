# shellcheck shell=bash
# Minimal assertion helpers; bash 3.2 compatible (macOS /bin/bash).

SKIP_STATUS=200

skip() {
  printf '    skipped: %s\n' "$1" >&2
  exit "$SKIP_STATUS"
}

assert_eq() {
  local expected="$1" actual="$2" message="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    printf '    expected: %s\n    actual:   %s\n' "$expected" "$actual" >&2
    [[ -n "$message" ]] && printf '    %s\n' "$message" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf '    expected to contain: %s\n    actual: %s\n' "$needle" "$haystack" >&2
    return 1
  fi
}

assert_fails() {
  if ( "$@" ) >/dev/null 2>&1; then
    printf '    expected failure: %s\n' "$*" >&2
    return 1
  fi
}

assert_file_exists() {
  if [[ ! -f "$1" ]]; then
    printf '    expected file to exist: %s\n' "$1" >&2
    return 1
  fi
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

# Builds a CMS-signed plist that decodes like a real
# .mobileprovision. /usr/bin/openssl (LibreSSL) is used on purpose: its PKCS#12
# output stays importable by `security import`, unlike OpenSSL 3 defaults.
make_profile() {
  local out="$1" name="$2" uuid="$3" team="$4" app_id="$5" work
  work="$(mktemp -d)"
  cat >"$work/profile.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Name</key><string>$name</string>
  <key>UUID</key><string>$uuid</string>
  <key>TeamIdentifier</key><array><string>$team</string></array>
  <key>Entitlements</key><dict>
    <key>application-identifier</key><string>$app_id</string>
  </dict>
</dict></plist>
EOF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=Test Profile Signer" \
    -keyout "$work/key.pem" -out "$work/cert.pem" >/dev/null 2>&1
  /usr/bin/openssl smime -sign -binary -nodetach -outform der \
    -in "$work/profile.plist" -signer "$work/cert.pem" -inkey "$work/key.pem" -out "$out"
  rm -rf "$work"
}

make_p12() {
  local out="$1" password="$2" work
  work="$(mktemp -d)"
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=Test Distribution" \
    -keyout "$work/key.pem" -out "$work/cert.pem" >/dev/null 2>&1
  /usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
    -passout "pass:$password" -out "$out"
  rm -rf "$work"
}

b64() {
  base64 <"$1" | tr -d '\n'
}

# Creates $TEST_TMP/repo (main branch) cloned from bare $TEST_TMP/origin.git.
# The developer's git config is ignored, so signing hooks cannot interfere.
make_git_repo() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@example.com"
  git init -q --bare -b main "$TEST_TMP/origin.git"
  git init -q -b main "$TEST_TMP/repo"
  git -C "$TEST_TMP/repo" remote add origin "$TEST_TMP/origin.git"
}

# Commits on $TEST_TMP/repo, pushes main and prints the new commit id.
git_commit() {
  git -C "$TEST_TMP/repo" commit -q --allow-empty -m "$1"
  git -C "$TEST_TMP/repo" push -q origin main
  git -C "$TEST_TMP/repo" rev-parse HEAD
}

remote_tag_commit() {
  git --git-dir "$TEST_TMP/origin.git" rev-parse -q --verify "refs/tags/$1^{commit}" || true
}
