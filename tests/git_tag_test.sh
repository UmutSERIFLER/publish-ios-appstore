# shellcheck shell=bash
# Optional `gitTag` step: after a successful upload, tag the shipped commit.

write_archive_info() {
  mkdir -p "$1"
  cat >"$1/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>ApplicationProperties</key><dict>
    <key>CFBundleShortVersionString</key><string>$2</string>
    <key>CFBundleVersion</key><string>$3</string>
  </dict>
</dict></plist>
EOF
}

tag_env() {
  make_git_repo
  export GITHUB_OUTPUT="$TEST_TMP/github_output" GITHUB_WORKSPACE="$TEST_TMP/repo"
  export ARCHIVE_PATH="$TEST_TMP/App.xcarchive" INPUT_GIT_TAG="true" INPUT_GIT_TAG_NAME="" INPUT_UPLOAD_APP="true"
  : >"$GITHUB_OUTPUT"
  write_archive_info "$ARCHIVE_PATH" "2.1.0" "57"
}

run_tag_step() {
  bash "$ROOT_DIR/scripts/tag.sh"
}

test_git_tag_is_off_by_default() {
  tag_env
  git_commit "release" >/dev/null
  INPUT_GIT_TAG="" run_tag_step
  assert_eq "" "$(remote_tag_commit ios-v2.1.0-57)"
}

test_git_tag_pushes_annotated_tag_for_shipped_commit() {
  tag_env
  local commit
  commit="$(git_commit "release")"
  run_tag_step >/dev/null
  assert_eq "$commit" "$(remote_tag_commit ios-v2.1.0-57)"
  assert_eq "tag" "$(git --git-dir "$TEST_TMP/origin.git" cat-file -t ios-v2.1.0-57)"
  assert_eq "ios-v2.1.0-57" "$(grep '^gitTag=' "$GITHUB_OUTPUT" | cut -d= -f2-)"
}

test_git_tag_uses_custom_name_template() {
  tag_env
  local commit
  commit="$(git_commit "release")"
  INPUT_GIT_TAG_NAME="testflight/{version}/{build}" run_tag_step >/dev/null
  assert_eq "$commit" "$(remote_tag_commit testflight/2.1.0/57)"
}

test_git_tag_is_skipped_when_nothing_was_uploaded() {
  tag_env
  git_commit "release" >/dev/null
  INPUT_UPLOAD_APP="false" run_tag_step >/dev/null
  assert_eq "" "$(remote_tag_commit ios-v2.1.0-57)"
}

test_git_tag_is_idempotent_for_the_same_commit() {
  tag_env
  git_commit "release" >/dev/null
  run_tag_step >/dev/null
  run_tag_step >/dev/null
}

test_git_tag_refuses_to_move_an_existing_tag() {
  tag_env
  git_commit "first" >/dev/null
  run_tag_step >/dev/null
  git_commit "second" >/dev/null
  assert_fails run_tag_step
}

test_git_tag_rejects_invalid_tag_names() {
  tag_env
  git_commit "release" >/dev/null
  INPUT_GIT_TAG_NAME="bad name {build}"
  assert_fails run_tag_step
}
