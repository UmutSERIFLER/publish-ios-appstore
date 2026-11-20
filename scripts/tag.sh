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

refuse_to_move() {
  fail "Tag $name already exists on $1; it is never moved. Use a different buildNumber or gitTagName."
}

# actions/checkout fetches no tags by default, so ask origin first. The peeled
# (^{}) line is the commit of an annotated tag; a lightweight tag has none.
ref="refs/tags/$name"
remote_refs="$(git -C "$repo" ls-remote --tags origin "$ref" "$ref^{}")" ||
  fail "Cannot list tags on origin; keep the actions/checkout credentials."
remote_commit="$(printf '%s\n' "$remote_refs" | awk -v ref="$ref" '
  $2 == ref "^{}" { peeled = $1 }
  $2 == ref { plain = $1 }
  END { print (peeled != "" ? peeled : plain) }')"
if [[ -n "$remote_commit" ]]; then
  [[ "$remote_commit" == "$commit" ]] || refuse_to_move "$remote_commit"
  set_output gitTag "$name"
  echo "Tag $name already points at $commit on origin."
  exit 0
fi

existing="$(git -C "$repo" rev-parse -q --verify "$ref^{commit}" || true)"
if [[ -n "$existing" && "$existing" != "$commit" ]]; then
  refuse_to_move "$existing"
fi

if [[ -z "$existing" ]]; then
  git_cmd=(git -C "$repo")
  if ! git -C "$repo" config user.email >/dev/null; then
    git_cmd+=(-c "user.name=github-actions[bot]" -c "user.email=41898282+github-actions[bot]@users.noreply.github.com")
  fi
  "${git_cmd[@]}" tag -a "$name" -m "Uploaded to App Store Connect: version $version, build $build" "$commit"
fi

git -C "$repo" push origin "$ref" ||
  fail "Could not push tag $name. Give the job 'permissions: contents: write' and keep actions/checkout credentials."

set_output gitTag "$name"
echo "Tagged $commit as $name."
