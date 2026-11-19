# #4: Fix the action for current runners and prepare the v2 Marketplace release

## What was built

- `action.yml` is now a thin composite action. Each step runs a script in `scripts/` and gets
  its inputs through `env:`, so there is no `${{ }}` inside shell code.
- `scripts/lib.sh` holds the pure helpers: container/scheme/build-number resolution,
  simulator selection, API key and profile decoding, and ExportOptions generation.
- Steps: setup → signing → run-tests → archive → export → upload → cleanup (`if: always()`).
- New outputs: `ipaPath`, `archivePath` and `buildNumber`.
- Tests (`make test`): 51 bash tests that stub `xcodebuild` and `xcrun`, plus one keychain
  integration test that runs only on CI. CI (`.github/workflows/ci.yml`) runs shellcheck and
  actionlint on Ubuntu and the tests on macOS.

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
| Keychain, profiles and `.p8` left on self-hosted runners | Cleanup step always runs; it removes only files it created |
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
  still decode, and `security cms` would then silently drop the second profile. A test
  covers this case.
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
  *Mobile* categories and publish. Then point the major tag at it:
  `git tag -f v2 v2.0.0 && git push -f origin v2`.
- Run an end-to-end smoke test against a sample app with real signing secrets
  (`uploadApp: false`).
- Optional: an `--upload-package --wait` mode once Xcode 16 runners are retired.
