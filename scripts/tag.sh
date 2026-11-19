#!/usr/bin/env bash
# Optional: tags the commit that was just uploaded, so every TestFlight build
# can be traced back to its source. Needs `permissions: contents: write`.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

is_true "${INPUT_GIT_TAG:-false}" || exit 0
if ! is_true "${INPUT_UPLOAD_APP:-true}"; then
  echo "uploadApp is false; nothing was shipped, so no git tag is created."
  exit 0
fi

archive_property() {
  /usr/libexec/PlistBuddy -c "Print :ApplicationProperties:$1" "${ARCHIVE_PATH:?}/Info.plist" 2>/dev/null || true
}

# Tag what actually shipped: the values stamped into the archive.
version="$(archive_property CFBundleShortVersionString)"
build="$(archive_property CFBundleVersion)"
[[ -n "$version" && -n "$build" ]] || fail "Cannot read the version and build number from $ARCHIVE_PATH."

template="${INPUT_GIT_TAG_NAME:-}"
[[ -n "$template" ]] || template='ios-v{version}-{build}'
name="${template//\{version\}/$version}"
name="${name//\{build\}/$build}"
git check-ref-format "refs/tags/$name" || fail "gitTagName produced an invalid tag name: '$name'."

repo="${GITHUB_WORKSPACE:-$PWD}"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 ||
  fail "gitTag needs the repository checked out with actions/checkout in $repo."
commit="$(git -C "$repo" rev-parse HEAD)"

existing="$(git -C "$repo" rev-parse -q --verify "refs/tags/$name^{commit}" || true)"
if [[ -n "$existing" && "$existing" != "$commit" ]]; then
  fail "Tag $name already exists on $existing; it is never moved. Use a different buildNumber or gitTagName."
fi

if [[ -z "$existing" ]]; then
  git_cmd=(git -C "$repo")
  if ! git -C "$repo" config user.email >/dev/null; then
    git_cmd+=(-c "user.name=github-actions[bot]" -c "user.email=41898282+github-actions[bot]@users.noreply.github.com")
  fi
  "${git_cmd[@]}" tag -a "$name" -m "Uploaded to App Store Connect: version $version, build $build" "$commit"
fi

git -C "$repo" push origin "refs/tags/$name" ||
  fail "Could not push tag $name. Give the job 'permissions: contents: write' and keep actions/checkout credentials."

set_output gitTag "$name"
echo "Tagged $commit as $name."
