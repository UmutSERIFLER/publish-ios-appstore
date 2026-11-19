#!/usr/bin/env bash
# Points the floating major tag (e.g. v2) at a newly published release, so
# workflows using `UmutSERIFLER/publish-ios-appstore@v2` pick it up.
# Env: RELEASE_TAG (e.g. v2.1.0), PRERELEASE (true/false). Run inside the repo.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../../scripts/lib.sh"

tag="${RELEASE_TAG:?RELEASE_TAG is not set}"

if is_true "${PRERELEASE:-false}"; then
  echo "$tag is a prerelease; the major tag is left unchanged."
  exit 0
fi

semver='^v([0-9]+)\.[0-9]+\.[0-9]+$'
[[ "$tag" =~ $semver ]] ||
  fail "Release tag '$tag' must look like v2.1.0. Mark release candidates as prereleases."
major="v${BASH_REMATCH[1]}"

git rev-parse -q --verify "refs/tags/$tag" >/dev/null ||
  fail "Tag $tag does not exist in this checkout (use actions/checkout with fetch-depth: 0)."

# A hotfix for an older minor (v2.0.1 after v2.1.0) must not drag v2 backwards.
newest="v$(
  git tag --list "$major.*" | grep -E "$semver" | sed 's/^v//' |
    sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1
)"
if [[ "$newest" != "$tag" ]]; then
  echo "::notice::$major stays on $newest because $tag is not the newest $major release."
  exit 0
fi

commit="$(git rev-parse "$tag^{commit}")"
git tag -f "$major" "$commit"
git push --force origin "refs/tags/$major"
echo "$major now points at $tag ($commit)."
