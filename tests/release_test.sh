# shellcheck shell=bash
# Release pipeline of this action: publishing v2.x.y must move the floating
# major tag (v2) that `uses: UmutSERIFLER/publish-ios-appstore@v2` resolves.

release() {
  (cd "$TEST_TMP/repo" && RELEASE_TAG="$1" PRERELEASE="${2:-false}" \
    bash "$ROOT_DIR/.github/scripts/update-major-tag.sh")
}

tag_release() {
  git -C "$TEST_TMP/repo" tag "$1" "$2"
  git -C "$TEST_TMP/repo" push -q origin "refs/tags/$1"
}

test_release_points_major_tag_at_newest_release() {
  make_git_repo
  local first second
  first="$(git_commit "first")"
  tag_release v2.0.0 "$first"
  release v2.0.0 >/dev/null
  second="$(git_commit "second")"
  tag_release v2.1.0 "$second"
  release v2.1.0 >/dev/null
  assert_eq "$second" "$(remote_tag_commit v2)"
}

test_release_never_moves_major_tag_backwards() {
  make_git_repo
  local first second hotfix
  first="$(git_commit "first")"
  tag_release v2.0.0 "$first"
  second="$(git_commit "second")"
  tag_release v2.1.0 "$second"
  release v2.1.0 >/dev/null
  hotfix="$(git_commit "hotfix for 2.0")"
  tag_release v2.0.1 "$hotfix"
  release v2.0.1 >/dev/null
  assert_eq "$second" "$(remote_tag_commit v2)"
}

test_release_of_new_major_keeps_previous_major_tag() {
  make_git_repo
  local first second
  first="$(git_commit "first")"
  tag_release v2.0.0 "$first"
  release v2.0.0 >/dev/null
  second="$(git_commit "breaking")"
  tag_release v3.0.0 "$second"
  release v3.0.0 >/dev/null
  assert_eq "$first" "$(remote_tag_commit v2)"
  assert_eq "$second" "$(remote_tag_commit v3)"
}

test_release_skips_prereleases() {
  make_git_repo
  local first
  first="$(git_commit "first")"
  tag_release v2.0.0-rc.1 "$first"
  release v2.0.0-rc.1 true >/dev/null
  assert_eq "" "$(remote_tag_commit v2)"
}

test_release_rejects_non_semver_tags() {
  make_git_repo
  local first
  first="$(git_commit "first")"
  tag_release release-2 "$first"
  assert_fails release release-2
}

test_release_rejects_unknown_tag() {
  make_git_repo
  git_commit "first" >/dev/null
  assert_fails release v9.9.9
}
