#!/usr/bin/env bash
# Points the floating major tag (e.g. v2) at a newly published release, so
# workflows using `UmutSERIFLER/publish-ios-appstore@v2` pick it up.
# Env: RELEASE_TAG (e.g. v2.1.0), TESTED_COMMIT (the commit CI just passed),
# GH_TOKEN for `gh`. Run inside a full clone (fetch-depth: 0).
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../../scripts/lib.sh"

tag="${RELEASE_TAG:?RELEASE_TAG is not set}"
tested="${TESTED_COMMIT:?TESTED_COMMIT is not set}"

# A manual dispatch carries no release payload, so always ask the API.
flags="$(gh release view "$tag" --json isDraft,isPrerelease --jq '"\(.isDraft) \(.isPrerelease)"')" ||
  fail "No GitHub release found for $tag. Publish the release first."
read -r draft prerelease <<<"$flags"
if is_true "$draft" || is_true "$prerelease"; then
  echo "$tag is a draft or prerelease; the major tag is left unchanged."
  exit 0
fi

semver='^v([0-9]+)\.([0-9]+)\.([0-9]+)$'
[[ "$tag" =~ $semver ]] ||
  fail "Release tag '$tag' must look like v2.1.0. Run this workflow from the release tag, not a branch."
major="v${BASH_REMATCH[1]}"

commit="$(git rev-parse -q --verify "refs/tags/$tag^{commit}")" ||
  fail "Tag $tag does not exist in this checkout (use actions/checkout with fetch-depth: 0)."
[[ "$commit" == "$tested" ]] ||
  fail "CI tested $tested, but $tag is $commit. Run this workflow from the $tag tag (Use workflow from > Tags)."

# Succeeds if version $1 is newer than $2 (both vX.Y.Z).
is_newer() {
  local a b i
  IFS=. read -r -a a <<<"${1#v}"
  IFS=. read -r -a b <<<"${2#v}"
  for i in 0 1 2; do
    if ((a[i] > b[i])); then return 0; fi
    if ((a[i] < b[i])); then return 1; fi
  done
  return 1
}

# Compare with the release the major tag is on now, not with every tag: a
# pushed tag or prerelease that never reached v2 must not block a hotfix.
current_commit="$(git rev-parse -q --verify "refs/tags/$major^{commit}" || true)"
if [[ -n "$current_commit" ]]; then
  current="$(
    git tag --points-at "$current_commit" --list "$major.*" | grep -E "$semver" |
      sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1
  )" || true
  [[ -n "$current" ]] ||
    fail "$major points at $current_commit, which has no $major.x.y tag. Move $major by hand."
  current="v$current"
  if [[ "$current" == "$tag" ]]; then
    echo "$major already points at $tag."
    exit 0
  fi
  if ! is_newer "$tag" "$current"; then
    echo "::notice::$major stays on $current because $tag is older."
    exit 0
  fi
fi

git tag -f "$major" "$commit"
git push --force origin "refs/tags/$major"
echo "$major now points at $tag ($commit)."
