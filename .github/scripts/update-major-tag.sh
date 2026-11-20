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

# Prints "<tag> <isDraft> <isPrerelease>" for every GitHub release, read in
# one listing: a tag missing from it has no release. Any API error fails the
# call, so an outage can never look like a missing release.
list_releases() {
  gh api --paginate "repos/{owner}/{repo}/releases?per_page=100" \
    --jq '.[] | "\(.tag_name) \(.draft) \(.prerelease)"'
}

# Prints "<isDraft> <isPrerelease>" for tag $1 from $releases; empty if none.
release_flags() {
  awk -v tag="$1" '$1 == tag { print $2, $3; exit }' <<<"$releases"
}

# A manual dispatch carries no release payload, so always ask the API.
releases="$(list_releases)" || fail "Cannot list GitHub releases; nothing changed. Re-run later."
flags="$(release_flags "$tag")"
[[ -n "$flags" ]] || fail "No GitHub release found for $tag. Publish the release first."
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

# Newest stable, published vN.x.y release on commit $1; empty if none. Plain
# tags and prereleases on the same commit never count as promoted.
promoted_release() {
  local version
  for version in $(
    git tag --points-at "$1" --list "$major.*" | grep -E "$semver" |
      sed 's/^v//' | sort -t. -k1,1nr -k2,2nr -k3,3nr
  ); do
    if [[ "$(release_flags "v$version")" == "false false" ]]; then
      echo "v$version"
      return
    fi
  done
}

# Prints "<ref value> <commit>" of the major tag on origin, or nothing.
remote_major() {
  local ref="refs/tags/$major"
  git ls-remote --tags origin "$ref" "$ref^{}" | awk -v ref="$ref" '
    $2 == ref { raw = $1 }
    $2 == ref "^{}" { peeled = $1 }
    END { if (raw != "") print raw, (peeled != "" ? peeled : raw) }'
}

# Runs are not serialized: a concurrency group keeps only one pending run and
# drops the others. So the move is a compare-and-swap: push only if the major
# tag is still what was checked, otherwise fetch and decide again.
for attempt in 1 2 3 4 5; do
  state="$(remote_major)" || fail "Cannot read tags from origin."
  # Read after the major tag, so the list holds whatever release it is on.
  releases="$(list_releases)" || fail "Cannot list GitHub releases; $major was not moved. Re-run later."
  lease=""
  if [[ -n "$state" ]]; then
    read -r lease current_commit <<<"$state"
    # Compare with the release the major tag is on now, not with every tag: a
    # pushed tag or prerelease that never reached v2 must not block a hotfix.
    current="$(promoted_release "$current_commit")"
    [[ -n "$current" ]] ||
      fail "$major points at $current_commit, which has no published $major.x.y release. Move $major by hand."
    if [[ "$current" == "$tag" ]]; then
      echo "$major already points at $tag."
      exit 0
    fi
    if ! is_newer "$tag" "$current"; then
      echo "::notice::$major stays on $current because $tag is older."
      exit 0
    fi
  fi
  # An empty lease means "must not exist yet".
  if git push --force-with-lease="refs/tags/$major:$lease" origin "$commit:refs/tags/$major"; then
    echo "$major now points at $tag ($commit)."
    exit 0
  fi
  echo "$major changed during attempt $attempt; checking again."
  git fetch -q --tags --force origin
done
fail "Could not move $major: it kept changing. Re-run this workflow from the $tag tag."
