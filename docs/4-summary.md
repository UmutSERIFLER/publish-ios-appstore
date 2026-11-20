# #4: Fix the action for current runners and prepare the v2 Marketplace release

## What was built

- `action.yml` is now a thin composite action. Each step runs a script in `scripts/` and gets
  its inputs through `env:`, so there is no `${{ }}` inside shell code.
- `scripts/lib.sh` holds the pure helpers: container/scheme/build-number resolution,
  simulator selection, API key and profile decoding, and ExportOptions generation.
- Steps: setup → signing → run-tests → archive → export → upload → tag (opt-in) → cleanup
  (`if: always()`).
- New outputs: `ipaPath`, `archivePath`, `buildNumber` and `gitTag`.
- Tagging, in two places:
  - **Action:** `gitTag: true` pushes an annotated tag (default `ios-v{version}-{build}`) for
    the uploaded commit. It reads the values from the archive and never moves an existing tag.
  - **This repo:** `.github/workflows/release.yml` runs CI on every stable release, then
    moves the floating major tag (`v2`) forward. Drafts, prereleases and older hotfixes never
    move it.
- README rewritten as the Marketplace page, with Mermaid diagrams for the pipeline, signing
  modes, version/build/tag mapping and the release flow.
- Tests (`make test`): bash tests that stub `xcodebuild`, `xcrun`, `gh` and use local git
  remotes, plus one keychain integration test that runs only on CI. CI
  (`.github/workflows/ci.yml`) runs shellcheck and actionlint on Ubuntu and the tests on macOS.

## v1 bugs fixed

| v1 behaviour | Fix |
| --- | --- |
| Simulator `iPhone 14 Pro, OS=16.2` is gone from the runner images | Picks the newest available iPhone simulator, or uses `testDestination` |
| ExportOptions written into the archive's `Info.plist`, profiles keyed by team ID | Separate `ExportOptions.plist` keyed by bundle ID, read from each profile |
| Build "+1" changed only the archive metadata, never the app's `CFBundleVersion` | `CURRENT_PROJECT_VERSION=<buildNumber>`, plus a warning if the archive disagrees |
| IPA path hardcoded to `/Users/runner/work/_temp/export/<projectName>.ipa` | Finds the `.ipa` in the export directory |
| Inputs interpolated into shell (injection, quoting bugs) | Inputs passed only through `env:`; a metadata test enforces this |
| No partition list, so codesign could hang on a keychain prompt | `security set-key-partition-list` |
| Profiles not installed where Xcode 16+ looks for them | Installed in both directories, named by UUID |
| Keychain and `.p8` left on self-hosted runners | Cleanup step always runs and deletes the run's keychain and key |
| No workspace/scheme support, duplicate clean/build steps | `workspace`/`project`/`scheme` inputs, one `clean archive` |

## Decisions and trade-offs

- **Bash scripts instead of a JavaScript action:** no `node_modules`/`dist` to commit or
  audit, and the commands are the same ones people run locally. Scripts stay bash 3.2
  compatible for self-hosted Macs.
- **`altool --upload-app`** rather than `--upload-package`: it is the only form accepted by
  both Xcode 16 and Xcode 27. altool runs from the work directory because every version
  searches `./private_keys`. `--p8-file-path` exists only in newer releases.
- **`buildNumber` defaults to `github.run_number`.** It is predictable and monotonic. Teams
  that already have higher build numbers set `buildNumber` themselves.
  `manageAppVersionAndBuildNumber` is off, so Xcode does not rewrite the number.
- **Profile parsing:** profiles split on commas or newlines first, and the whole input is
  decoded as one profile only as a fallback. Two unpadded base64 profiles joined together
  still decode, and the second profile would then be silently dropped. A test covers this
  case.
- **Profiles are decoded with `/usr/bin/openssl smime`, not `security cms -D`.** The latter
  needs a default keychain, which service accounts on self-hosted runners often lack. CI's
  keychain integration test caught this. The new path was checked against 10 real
  Apple-signed profiles.
- **Provisioning profiles are kept after a run** (from PR review). They hold no secrets, and
  deleting them raced with parallel runs under the same macOS user. They are installed
  atomically (temp file + rename) and only by UUID. Ref-counting with locks was rejected as
  too much machinery for removing non-secret files.
- **`teamID` is forwarded as `DEVELOPMENT_TEAM`** (from PR review), only when set, so
  automatic signing works for projects without a saved team.
- **The test runner fails on test files it cannot load** (from PR review). Discovery runs in a
  separate bash process: `set -e` is ignored inside functions called from `if`, and `source`
  returns only the last command's status.
- **Release promotion is driven by what was tested and released** (second PR review). A
  manual run must start from the tag, and the script refuses a tag whose commit is not the
  one CI tested. Draft/prerelease flags come from the Releases API, because a manual run has
  no release payload. `v2` is compared only with the release it points at, so stray tags
  cannot block a hotfix; the `gh` CLI preinstalled on runners does the API call.
- **Third PR review:**
  - Cleanup fails the job when it cannot delete the keychain or the API key; it still tries
    everything first.
  - `extraXcodebuildArgs` may span lines (YAML block) and also reaches simulator discovery.
    Checked on Xcode 27.2: only test-only flags (`-testPlan`, `-enableCodeCoverage`) break
    discovery, and archive already rejects those.
  - A bad profile line after a valid one is rejected instead of swallowed by the
    wrapped-profile fallback.
  - `gitTag` tags the repository that contains the project, also for a nested checkout. The
    metadata test now checks that every `${VAR:?}` a step script needs is in its `env`.
  - The major tag counts only stable published releases on its commit, and moves with
    `git push --force-with-lease` plus re-check instead of a concurrency group, which
    GitHub would use to drop pending runs.
- **Fourth PR review:** releases are read in one paginated `gh api` listing instead of one
  `gh release view` per tag. Both commands exit 1 for "not found" and for an outage, so only a
  complete listing can tell a missing release apart from an error; any API error now stops the
  run. Each attempt fetches tags and lists releases after reading `v2`, so the release `v2` is
  on is known even if it was published after the checkout.
- **`buildNumber` output is read back from the archive** (second PR review), so it never
  reports a number that the project ignored.
- **`gitTag` checks `origin`** (second PR review): the default checkout has no tags, so re-runs
  used to fail on push. Same commit is now a no-op, another commit fails clearly.
- **Not done (PR review):** isolating signing identities that Xcode creates during automatic
  signing on self-hosted runners. Changing the default keychain would race across parallel
  jobs; the README documents it and recommends manual signing on shared Macs.
- **Every v1 input still works.** `mobileProvision` is ignored with a warning, because the
  profile itself has a reliable name.

## Assumptions

- The main Info.plist uses `$(CURRENT_PROJECT_VERSION)` for `CFBundleVersion` (Xcode 13+
  default).
- Runners have Xcode 15.3 or later for the `app-store-connect` export method. On older
  Xcode, set `exportMethod: app-store`.
- Under current docs, workflow files no longer block a Marketplace listing, so a CI workflow
  was added.

## Next steps

- Release (maintainer, in the GitHub UI): after merging, draft a release with tag `v2.0.0`,
  tick **Publish this Action to the GitHub Marketplace**, choose the *Deployment* and
  *Mobile* categories and publish. The Release workflow then creates or moves `v2`. The
  Marketplace checkbox exists only in the UI, so this step cannot be automated.
- The keychain search list is shared per macOS user, and two runners under one user can race
  when they update it. A lock around that update would remove the race; for now the README
  recommends one macOS user per runner.
- The Mermaid diagrams were not rendered locally; check them in the PR's README view.
- Run an end-to-end smoke test against a sample app with real signing secrets
  (`uploadApp: false`).
- Optional: an `--upload-package --wait` mode once Xcode 16 runners are retired.
