# shellcheck shell=bash
# Shared helpers for the action's step scripts.
# Must stay bash 3.2 compatible: self-hosted Macs may only have /bin/bash, so no
# associative arrays, mapfile, ${var,,}, or expanding empty arrays under `set -u`.

# shellcheck disable=SC2034 # used by the scripts that source this file
PROFILE_DIRS=(
  "$HOME/Library/MobileDevice/Provisioning Profiles"
  # Xcode 16+ reads profiles from here instead of the legacy directory above.
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
)

fail() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}

warn() {
  printf '::warning::%s\n' "$*" >&2
}

is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    true | yes | 1) return 0 ;;
    *) return 1 ;;
  esac
}

set_output() {
  local name="$1" value="$2"
  [[ "$value" != *$'\n'* ]] || fail "Output '$name' must be a single line."
  printf '%s=%s\n' "$name" "$value" >>"${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
}

# Sets XCODE_CONTAINER_ARGS to the -workspace/-project flag xcodebuild needs.
# shellcheck disable=SC2034 # XCODE_CONTAINER_ARGS is read by the caller
resolve_container() {
  local workspace="$1" project="$2" project_name="$3"
  if [[ -n "$workspace" ]]; then
    XCODE_CONTAINER_ARGS=(-workspace "$workspace")
  elif [[ -n "$project" ]]; then
    XCODE_CONTAINER_ARGS=(-project "$project")
  elif [[ -n "$project_name" ]]; then
    XCODE_CONTAINER_ARGS=(-project "$project_name.xcodeproj")
  else
    fail "Set one of the inputs: workspace, project or projectName."
  fi
}

resolve_scheme() {
  local scheme="${1:-$2}"
  [[ -n "$scheme" ]] || fail "Set the scheme input (or projectName, which is used as the scheme)."
  printf '%s\n' "$scheme"
}

# App Store Connect accepts one to three period-separated integers.
is_bundle_version() {
  local pattern='^[0-9]+(\.[0-9]+){0,2}$'
  [[ "$1" =~ $pattern ]]
}

resolve_build_number() {
  local build_number="${1:-$2}"
  [[ -n "$build_number" ]] || fail "buildNumber is empty and GITHUB_RUN_NUMBER is not set."
  is_bundle_version "$build_number" ||
    fail "buildNumber '$build_number' must be one to three period-separated integers, e.g. 42 or 1.0.42."
  printf '%s\n' "$build_number"
}

# Reads `xcodebuild -showdestinations` output on stdin and prints the id of the
# iPhone simulator with the newest OS, so tests never pin a device name that a
# future runner image drops (v1 hardcoded "iPhone 14 Pro, OS=16.2").
pick_simulator_id() {
  awk '
    /platform:iOS Simulator/ && /name:iPhone/ && !/placeholder/ && !/error:/ {
      id = ""; os = "0";
      if (match($0, /id:[^,}]+/)) id = substr($0, RSTART + 3, RLENGTH - 3);
      if (match($0, /OS:[0-9.]+/)) os = substr($0, RSTART + 3, RLENGTH - 3);
      gsub(/ /, "", id);
      if (id != "") print os, id;
    }
  ' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1 | awk '{ print $2 }'
}

decode_base64() {
  tr -d '[:space:]' | base64 --decode
}

# Accepts the raw .p8 contents or its base64 encoding; prints the written path.
write_api_key() {
  local content="$1" key_id="$2" dir="$3" path
  local id_pattern='^[A-Za-z0-9]+$'
  [[ "$key_id" =~ $id_pattern ]] || fail "appstoreAPIKeyID must be alphanumeric."
  path="$dir/AuthKey_$key_id.p8"
  mkdir -p "$dir"
  chmod 700 "$dir"
  (
    umask 077
    if [[ "$content" == *"-----BEGIN"* ]]; then
      printf '%s\n' "$content" >"$path"
    else
      printf '%s' "$content" | decode_base64 >"$path" 2>/dev/null || true
    fi
  )
  if ! grep -q -- '-----BEGIN PRIVATE KEY-----' "$path"; then
    rm -f "$path"
    fail "appstoreAPIKey must be the contents of the AuthKey_<id>.p8 file or its base64 encoding."
  fi
  chmod 600 "$path"
  printf '%s\n' "$path"
}

# Prints the plist embedded in a signed .mobileprovision. Not `security cms -D`:
# it needs a default keychain, which service accounts on self-hosted runners
# often lack. The system LibreSSL ships with every macOS; the signature chain
# is not verified because Xcode validates the profile when it signs.
profile_plist() {
  /usr/bin/openssl smime -verify -noverify -inform der -in "$1" 2>/dev/null
}

decode_profile_to() {
  local encoded="$1" out="$2"
  printf '%s' "$encoded" | decode_base64 >"$out" 2>/dev/null &&
    profile_plist "$out" >/dev/null
}

# Decodes each non-empty line into <out_dir>/profile-N.mobileprovision; fails
# if any line is not a profile.
decode_profile_lines() {
  local lines="$1" out_dir="$2" chunk index=0
  while IFS= read -r chunk; do
    chunk="$(printf '%s' "$chunk" | tr -d '[:space:]')"
    [[ -n "$chunk" ]] || continue
    decode_profile_to "$chunk" "$out_dir/profile-$index.mobileprovision" || return 1
    index=$((index + 1))
  done < <(printf '%s\n' "$lines")
  [[ $index -gt 0 ]]
}

# Decodes one or more base64 profiles (separated by commas or newlines) into
# <out_dir>/profile-N.mobileprovision.
decode_profiles() {
  local input="$1" out_dir="$2"
  local invalid="provisionProfileBase64 must hold base64-encoded .mobileprovision files separated by commas or newlines."
  mkdir -p "$out_dir"

  if [[ "$input" == *,* ]]; then
    decode_profile_lines "$(printf '%s' "$input" | tr -d '[:space:]' | tr ',' '\n')" "$out_dir" || fail "$invalid"
    return 0
  fi
  # Splitting must win over joining: two unpadded profiles joined together
  # may still decode, silently dropping the second one.
  decode_profile_lines "$input" "$out_dir" && return 0
  rm -f "$out_dir"/profile-*.mobileprovision
  # A single profile stored line-wrapped (GNU base64 default) only decodes whole.
  decode_profile_to "$input" "$out_dir/profile-0.mobileprovision" || fail "$invalid"
}

# Prints "<bundle id>\t<profile name>\t<team id>\t<uuid>".
read_profile() {
  local file="$1" plist app_id name team uuid
  plist="$(mktemp)"
  profile_plist "$file" >"$plist" || {
    rm -f "$plist"
    fail "Cannot decode provisioning profile $file."
  }
  app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$plist")"
  name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$plist")"
  team="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$plist")"
  uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$plist")"
  rm -f "$plist"
  # application-identifier is "<App ID prefix>.<bundle id>".
  printf '%s\t%s\t%s\t%s\n' "${app_id#*.}" "$name" "$team" "$uuid"
}

xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

plist_string() {
  printf '  <key>%s</key><string>%s</string>\n' "$(xml_escape "$1")" "$(xml_escape "$2")"
}

plist_bool() {
  printf '  <key>%s</key><%s/>\n' "$1" "$2"
}

# Writes the -exportOptionsPlist file. Manual signing when profiles were
# installed (bundle id -> profile name), automatic signing otherwise.
write_export_options() {
  local out="$1" method="$2" team="$3" profiles_tsv="$4"
  local style="automatic" mappings="" seen=" " bundle name _team _uuid

  if [[ -s "$profiles_tsv" ]]; then
    style="manual"
    while IFS=$'\t' read -r bundle name _team _uuid; do
      [[ -n "$bundle" ]] || continue
      if [[ "$bundle" == *"*"* ]]; then
        warn "Skipping wildcard profile '$name': App Store exports need an explicit App ID profile."
        continue
      fi
      [[ "$seen" != *" $bundle "* ]] || continue
      seen="$seen$bundle "
      mappings="$mappings$(printf '    <key>%s</key><string>%s</string>' "$(xml_escape "$bundle")" "$(xml_escape "$name")")"$'\n'
    done <"$profiles_tsv"
  fi

  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    printf '<plist version="1.0">\n<dict>\n'
    plist_string method "$method"
    plist_string destination export
    plist_string signingStyle "$style"
    [[ -z "$team" ]] || plist_string teamID "$team"
    plist_bool uploadSymbols true
    # The action stamps the build number itself; stop Xcode from rewriting it.
    plist_bool manageAppVersionAndBuildNumber false
    if [[ -n "$mappings" ]]; then
      printf '  <key>provisioningProfiles</key>\n  <dict>\n%s  </dict>\n' "$mappings"
    fi
    printf '</dict>\n</plist>\n'
  } >"$out"

  plutil -lint -s "$out" || fail "Generated export options plist is invalid: $out"
}
