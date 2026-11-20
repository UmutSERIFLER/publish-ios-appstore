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
  export CONTAINER_PATH="App.xcodeproj"
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

# actions/checkout fetches no tags by default, so a tag pushed by an earlier
# run exists only on origin.
push_tag_then_forget_it_locally() {
  git -C "$TEST_TMP/repo" tag -a "$1" -m "earlier run"
  git -C "$TEST_TMP/repo" push -q origin "refs/tags/$1"
  git -C "$TEST_TMP/repo" tag -d "$1" >/dev/null
}

test_git_tag_keeps_remote_tag_that_already_targets_the_commit() {
  tag_env
  git_commit "release" >/dev/null
  push_tag_then_forget_it_locally ios-v2.1.0-57
  local before
  before="$(git --git-dir "$TEST_TMP/origin.git" rev-parse refs/tags/ios-v2.1.0-57)"
  run_tag_step >/dev/null
  assert_eq "$before" "$(git --git-dir "$TEST_TMP/origin.git" rev-parse refs/tags/ios-v2.1.0-57)"
  assert_eq "ios-v2.1.0-57" "$(grep '^gitTag=' "$GITHUB_OUTPUT" | cut -d= -f2-)"
}

test_git_tag_refuses_remote_tag_on_another_commit() {
  tag_env
  local first
  first="$(git_commit "first")"
  push_tag_then_forget_it_locally ios-v2.1.0-57
  git_commit "second" >/dev/null
  local output
  output="$(run_tag_step 2>&1)" && return 1
  assert_contains "$output" "Tag ios-v2.1.0-57 already exists on $first"
}

# The app can be a second checkout below the workspace (actions/checkout with
# `path:`); the tag belongs to that repository, not the root one.
test_git_tag_tags_the_repository_that_holds_the_project() {
  tag_env
  local commit
  commit="$(git_commit "release")"
  git init -q --bare -b main "$TEST_TMP/root-origin.git"
  git init -q -b main "$TEST_TMP/ws"
  git -C "$TEST_TMP/ws" remote add origin "$TEST_TMP/root-origin.git"
  git -C "$TEST_TMP/ws" commit -q --allow-empty -m "orchestration"
  git clone -q "$TEST_TMP/origin.git" "$TEST_TMP/ws/ios-app"
  GITHUB_WORKSPACE="$TEST_TMP/ws" CONTAINER_PATH="ios-app/App.xcworkspace" run_tag_step >/dev/null
  assert_eq "$commit" "$(remote_tag_commit ios-v2.1.0-57)"
  assert_eq "" "$(git --git-dir "$TEST_TMP/root-origin.git" tag --list)"
}

test_git_tag_fails_when_the_project_is_not_in_a_git_checkout() {
  tag_env
  git_commit "release" >/dev/null
  mkdir -p "$TEST_TMP/plain/ios"
  GITHUB_WORKSPACE="$TEST_TMP/plain" CONTAINER_PATH="ios/App.xcodeproj"
  export GIT_CEILING_DIRECTORIES="$TEST_TMP"
  assert_fails run_tag_step
}
