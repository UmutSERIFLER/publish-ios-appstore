# shellcheck shell=bash
# Release pipeline of this action: publishing v2.x.y must move the floating
# major tag (v2) that `uses: UmutSERIFLER/publish-ios-appstore@v2` resolves.

# Runs the promotion for $1. CI tested $2 (default: the tag's own commit, as
# for a `release` event or a dispatch from the tag).
release() {
  local tested="${2:-}"
  [[ -n "$tested" ]] || tested="$(git -C "$TEST_TMP/repo" rev-parse "$1^{commit}" 2>/dev/null || echo unknown)"
  rm -f "$TEST_TMP/gh-calls"
  (cd "$TEST_TMP/repo" && PATH="$TESTS_DIR/stubs:$PATH" RELEASE_TAG="$1" TESTED_COMMIT="$tested" \
    bash "$ROOT_DIR/.github/scripts/update-major-tag.sh")
}

push_tag() {
  git -C "$TEST_TMP/repo" tag "$1" "$2"
  git -C "$TEST_TMP/repo" push -q origin "refs/tags/$1"
}

# Tags $2 as $1 and records a GitHub release; $3 is "stable", "draft" or "prerelease".
publish_release() {
  push_tag "$1" "$2"
  case "${3:-stable}" in
    stable) echo "$1 false false" ;;
    draft) echo "$1 true false" ;;
    prerelease) echo "$1 false true" ;;
  esac >>"$TEST_TMP/releases"
}

test_release_points_major_tag_at_newest_release() {
  make_git_repo
  local first second
  first="$(git_commit "first")"
  publish_release v2.0.0 "$first"
  release v2.0.0 >/dev/null
  second="$(git_commit "second")"
  publish_release v2.1.0 "$second"
  release v2.1.0 >/dev/null
  assert_eq "$second" "$(remote_tag_commit v2)"
}

test_release_is_idempotent() {
  make_git_repo
  local first
  first="$(git_commit "first")"
  publish_release v2.0.0 "$first"
  release v2.0.0 >/dev/null
  release v2.0.0 >/dev/null
  assert_eq "$first" "$(remote_tag_commit v2)"
}

test_release_never_moves_major_tag_backwards() {
  make_git_repo
  local first second hotfix
  first="$(git_commit "first")"
  publish_release v2.0.0 "$first"
  second="$(git_commit "second")"
  publish_release v2.1.0 "$second"
  release v2.1.0 >/dev/null
  hotfix="$(git_commit "hotfix for 2.0")"
  publish_release v2.0.1 "$hotfix"
  release v2.0.1 >/dev/null
  assert_eq "$second" "$(remote_tag_commit v2)"
}

# Only the version v2 points at matters: a pushed tag or a prerelease that
# never reached v2 must not block a stable hotfix.
test_release_is_not_blocked_by_newer_tags_that_were_never_promoted() {
  make_git_repo
  local first unreleased candidate hotfix
  first="$(git_commit "first")"
  publish_release v2.1.0 "$first"
  release v2.1.0 >/dev/null
  unreleased="$(git_commit "work in progress")"
  push_tag v2.3.0 "$unreleased"
  candidate="$(git_commit "candidate")"
  publish_release v2.2.0 "$candidate" prerelease
  hotfix="$(git_commit "hotfix")"
  publish_release v2.1.1 "$hotfix"
  release v2.1.1 >/dev/null
  assert_eq "$hotfix" "$(remote_tag_commit v2)"
}

# Same idea when the stray tags sit on the commit v2 already points at.
test_release_ignores_unreleased_tags_on_the_promoted_commit() {
  make_git_repo
  local first hotfix
  first="$(git_commit "first")"
  publish_release v2.1.0 "$first"
  release v2.1.0 >/dev/null
  push_tag v2.3.0 "$first"
  publish_release v2.2.0 "$first" prerelease
  hotfix="$(git_commit "hotfix")"
  publish_release v2.1.1 "$hotfix"
  release v2.1.1 >/dev/null
  assert_eq "$hotfix" "$(remote_tag_commit v2)"
}

# Runs are not serialized (a concurrency group drops pending runs), so a run
# that checked v2 before another run moved it must re-check, not overwrite.
test_release_does_not_overwrite_a_concurrent_promotion() {
  make_git_repo
  local first newer older
  first="$(git_commit "first")"
  publish_release v2.0.0 "$first"
  release v2.0.0 >/dev/null
  newer="$(git_commit "2.2.0")"
  publish_release v2.2.0 "$newer"
  older="$(git_commit "2.1.0 from a maintenance branch")"
  publish_release v2.1.0 "$older"
  # Call 1 checks v2.1.0 itself; call 2 runs after this run has read v2.
  printf 'git --git-dir "%s" update-ref refs/tags/v2 %s\n' "$TEST_TMP/origin.git" "$newer" \
    >"$TEST_TMP/on-gh-call-2"
  local output
  output="$(release v2.1.0 2>&1)"
  assert_contains "$output" "v2 changed during attempt 1; checking again."
  assert_contains "$output" "v2 stays on v2.2.0"
  assert_eq "$newer" "$(remote_tag_commit v2)"
}

# An API error must stop the run, not read as "no release": v2's commit carries
# v2.0.0 and v2.2.0, and losing v2.2.0 would let v2.1.0 move v2 backward.
test_release_aborts_when_github_releases_cannot_be_read() {
  make_git_repo
  local first maintenance
  first="$(git_commit "first")"
  publish_release v2.0.0 "$first"
  publish_release v2.2.0 "$first"
  release v2.2.0 >/dev/null
  maintenance="$(git_commit "2.1.0 from a maintenance branch")"
  publish_release v2.1.0 "$maintenance"
  touch "$TEST_TMP/gh-fail-call-2"
  assert_fails release v2.1.0
  assert_eq "$first" "$(remote_tag_commit v2)"
}

test_release_of_new_major_keeps_previous_major_tag() {
  make_git_repo
  local first second
  first="$(git_commit "first")"
  publish_release v2.0.0 "$first"
  release v2.0.0 >/dev/null
  second="$(git_commit "breaking")"
  publish_release v3.0.0 "$second"
  release v3.0.0 >/dev/null
  assert_eq "$first" "$(remote_tag_commit v2)"
  assert_eq "$second" "$(remote_tag_commit v3)"
}

# A manual dispatch has no release payload, so the flags come from the API.
test_release_skips_releases_marked_as_prerelease() {
  make_git_repo
  local first
  first="$(git_commit "first")"
  publish_release v2.1.0 "$first" prerelease
  release v2.1.0 >/dev/null
  assert_eq "" "$(remote_tag_commit v2)"
}

test_release_skips_draft_releases() {
  make_git_repo
  local first
  first="$(git_commit "first")"
  publish_release v2.1.0 "$first" draft
  release v2.1.0 >/dev/null
  assert_eq "" "$(remote_tag_commit v2)"
}

test_release_requires_a_github_release_for_the_tag() {
  make_git_repo
  local first
  first="$(git_commit "first")"
  push_tag v2.1.0 "$first"
  assert_fails release v2.1.0
  assert_eq "" "$(remote_tag_commit v2)"
}

# A dispatch from master tests master, not the release tag.
test_release_rejects_tag_that_ci_did_not_test() {
  make_git_repo
  local first tested
  first="$(git_commit "first")"
  publish_release v2.1.0 "$first"
  tested="$(git_commit "untagged work on master")"
  local output
  output="$(release v2.1.0 "$tested" 2>&1)" && return 1
  assert_contains "$output" "CI tested $tested"
  assert_eq "" "$(remote_tag_commit v2)"
}

test_release_refuses_major_tag_on_an_unreleased_commit() {
  make_git_repo
  local first manual second
  first="$(git_commit "first")"
  publish_release v2.0.0 "$first"
  manual="$(git_commit "moved by hand")"
  push_tag v2 "$manual"
  second="$(git_commit "second")"
  publish_release v2.1.0 "$second"
  assert_fails release v2.1.0
  assert_eq "$manual" "$(remote_tag_commit v2)"
}

test_release_rejects_non_semver_tags() {
  make_git_repo
  local first
  first="$(git_commit "first")"
  publish_release release-2 "$first"
  assert_fails release release-2
}

test_release_rejects_unknown_tag() {
  make_git_repo
  git_commit "first" >/dev/null
  echo "v9.9.9 false false" >>"$TEST_TMP/releases"
  assert_fails release v9.9.9
}

# Wiring the script relies on: CI and promotion see the same commit, and
# prereleases never start the workflow.
test_release_workflow_promotes_only_the_commit_ci_tested() {
  # shellcheck disable=SC2016 # Ruby source, not shell
  ruby -ryaml -e '
    wf = YAML.safe_load(File.read(ARGV[0]))
    on = wf.key?(true) ? wf[true] : wf["on"] # YAML 1.1 reads a bare `on` as true
    errors = []
    errors << "trigger on release types [released]" unless on.dig("release", "types") == ["released"]
    errors << "no concurrency group: GitHub drops pending runs; the script uses a lease" if wf["concurrency"]
    errors << "workflow_dispatch must not take a tag input; run it from the tag" if on["workflow_dispatch"].is_a?(Hash) && on["workflow_dispatch"]["inputs"]
    job = wf.dig("jobs", "update-major-tag")
    errors << "update-major-tag must need ci" unless Array(job["needs"]).include?("ci")
    env = job["steps"].map { |s| s["env"] }.compact.first || {}
    errors << "TESTED_COMMIT must be github.sha" unless env["TESTED_COMMIT"] == "${{ github.sha }}"
    errors << "RELEASE_TAG must fall back to github.ref_name" unless env["RELEASE_TAG"].to_s.include?("github.ref_name")
    errors << "GH_TOKEN missing" if env["GH_TOKEN"].to_s.empty?
    abort errors.join("\n") unless errors.empty?
  ' "$ROOT_DIR/.github/workflows/release.yml"
}
