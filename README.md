# Publish iOS Application to Appstore

[![CI](https://github.com/UmutSERIFLER/publish-ios-appstore/actions/workflows/ci.yml/badge.svg)](https://github.com/UmutSERIFLER/publish-ios-appstore/actions/workflows/ci.yml)

GitHub Action that tests, archives, signs and uploads an iOS app to App Store Connect, where
it shows up in TestFlight and can be submitted to the App Store.

1. Runs the scheme's tests on the newest available iPhone simulator.
2. Installs your distribution certificate and provisioning profiles in a temporary keychain,
   or lets Xcode sign automatically with your App Store Connect API key.
3. Archives with a unique build number (`github.run_number` by default).
4. Exports an App Store signed `.ipa`, validates it and uploads it with `altool`.
5. Always removes the keychain, profiles and API key afterwards, even when a step fails.

## Usage

```yaml
name: TestFlight

on:
  push:
    tags: ['v*']

jobs:
  publish:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v5

      - uses: UmutSERIFLER/publish-ios-appstore@v2
        id: publish
        with:
          projectName: MyApp                      # MyApp.xcodeproj, scheme MyApp
          appstoreAPIKey: ${{ secrets.APPSTORE_API_KEY }}
          appstoreAPIKeyID: ${{ secrets.APPSTORE_API_KEY_ID }}
          appstoreAPIIssuer: ${{ secrets.APPSTORE_API_ISSUER }}
          certificateBase64: ${{ secrets.DISTRIBUTION_CERTIFICATE_BASE64 }}
          p12FilePassword: ${{ secrets.DISTRIBUTION_CERTIFICATE_PASSWORD }}
          provisionProfileBase64: ${{ secrets.APPSTORE_PROFILE_BASE64 }}

      - uses: actions/upload-artifact@v4
        with:
          name: MyApp-${{ steps.publish.outputs.buildNumber }}
          path: ${{ steps.publish.outputs.ipaPath }}
```

### CocoaPods workspace, custom scheme, app extensions

```yaml
      - uses: UmutSERIFLER/publish-ios-appstore@v2
        with:
          workspace: ios/MyApp.xcworkspace
          scheme: MyApp Production
          version: '2.1.0'                         # -> MARKETING_VERSION
          appstoreAPIKey: ${{ secrets.APPSTORE_API_KEY }}
          appstoreAPIKeyID: ${{ secrets.APPSTORE_API_KEY_ID }}
          appstoreAPIIssuer: ${{ secrets.APPSTORE_API_ISSUER }}
          certificateBase64: ${{ secrets.DISTRIBUTION_CERTIFICATE_BASE64 }}
          p12FilePassword: ${{ secrets.DISTRIBUTION_CERTIFICATE_PASSWORD }}
          # One profile per signed target, separated by commas or newlines.
          provisionProfileBase64: |
            ${{ secrets.APP_PROFILE_BASE64 }}
            ${{ secrets.WIDGET_PROFILE_BASE64 }}
```

### Automatic signing

Leave out `certificateBase64` and `provisionProfileBase64`. Xcode then creates or downloads
the certificates and profiles it needs with the API key, which needs the **Admin** role. The
project's targets must use *Automatically manage signing*.

```yaml
      - uses: UmutSERIFLER/publish-ios-appstore@v2
        with:
          projectName: MyApp
          teamID: ABCDE12345
          appstoreAPIKey: ${{ secrets.APPSTORE_API_KEY }}
          appstoreAPIKeyID: ${{ secrets.APPSTORE_API_KEY_ID }}
          appstoreAPIIssuer: ${{ secrets.APPSTORE_API_ISSUER }}
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `appstoreAPIKey` | **required** | App Store Connect API private key: contents of `AuthKey_<id>.p8` or its base64 encoding. |
| `appstoreAPIKeyID` | **required** | App Store Connect API key ID. |
| `appstoreAPIIssuer` | **required** | App Store Connect API issuer ID. |
| `projectName` | | Project name without extension; default for `project` and `scheme`. |
| `workspace` | | Path to an `.xcworkspace`. Takes precedence over `project`. |
| `project` | `<projectName>.xcodeproj` | Path to the `.xcodeproj`. |
| `scheme` | `projectName` | Scheme to test and archive. |
| `configuration` | `Release` | Build configuration for the archive. |
| `certificateBase64` | | Base64 of the Apple Distribution `.p12`. Omit for automatic signing. |
| `p12FilePassword` | | Password of the `.p12`. |
| `provisionProfileBase64` | | Base64 App Store profile(s), separated by commas or newlines. |
| `keychainPassword` | random | Password of the temporary keychain. |
| `teamID` | from profile / archive | Apple Developer team ID. |
| `buildNumber` | `github.run_number` | `CFBundleVersion` to stamp (`CURRENT_PROJECT_VERSION`). |
| `version` | project value | `CFBundleShortVersionString` to stamp (`MARKETING_VERSION`). |
| `runTests` | `true` | Run tests before archiving. Set `false` if the scheme has no test action. |
| `testDestination` | newest iPhone simulator | `xcodebuild -destination` for tests. |
| `exportMethod` | `app-store-connect` | Export method. Use `app-store` with Xcode older than 15.3. |
| `validateApp` | `true` | Validate the `.ipa` before uploading. |
| `uploadApp` | `true` | Upload to App Store Connect. `false` only builds the `.ipa`. |
| `extraXcodebuildArgs` | | Extra space-separated `xcodebuild` arguments, e.g. `-skipMacroValidation`. |
| `mobileProvision` | | Deprecated, ignored. Profile names are read from the profiles. |

## Outputs

| Output | Description |
| --- | --- |
| `ipaPath` | Absolute path of the exported `.ipa`. |
| `archivePath` | Absolute path of the `.xcarchive` (contains the dSYMs). |
| `buildNumber` | Build number stamped on the build. |

## Preparing the secrets

| Secret | How to get it |
| --- | --- |
| `APPSTORE_API_KEY`, `APPSTORE_API_KEY_ID`, `APPSTORE_API_ISSUER` | App Store Connect → Users and Access → Integrations → Team Keys. Generate a key (App Manager role for manual signing, Admin for automatic signing), download `AuthKey_<id>.p8` and paste its contents as the secret. |
| `DISTRIBUTION_CERTIFICATE_BASE64` | Export the *Apple Distribution* certificate with its private key from Keychain Access as `.p12`, then `base64 -i Certificates.p12 \| pbcopy`. |
| `DISTRIBUTION_CERTIFICATE_PASSWORD` | Password chosen during the `.p12` export. |
| `APPSTORE_PROFILE_BASE64` | Download the *App Store Connect* distribution profile, then `base64 -i MyApp.mobileprovision \| pbcopy`. |

With manual signing, the project's targets must select the same profiles that you pass to the
action.

## Requirements and notes

- Runs on macOS runners (`macos-14`, `macos-15`, ...). To pick an Xcode version, add
  `sudo xcode-select -s /Applications/Xcode_16.4.app` before the action.
- **Build numbers:** App Store Connect rejects a build number it has already seen for the same
  version. The action passes `CURRENT_PROJECT_VERSION=<buildNumber>` to `xcodebuild`, so
  `CFBundleVersion` in your Info.plist must be `$(CURRENT_PROJECT_VERSION)`. This is the
  default for projects created with Xcode 13 or later. The action warns when the archived
  value does not match.
- All inputs reach the scripts through environment variables, never through `${{ }}` inside
  shell code. A secret that contains quotes or `$` cannot break or inject into the build.

## Migrating from v1

- Every v1 input is still accepted. `mobileProvision` is now ignored (a warning is printed),
  and `teamID`, `certificateBase64`, `p12FilePassword`, `provisionProfileBase64` and
  `keychainPassword` are optional.
- v1 increased the build number only in the archive's metadata, so the uploaded app kept its
  old `CFBundleVersion`. v2 stamps `github.run_number`. Set `buildNumber` if you need a
  higher number than your existing builds.
- Tests now run on the newest installed iPhone simulator instead of the removed
  `iPhone 14 Pro (iOS 16.2)`.
- The archive and `.ipa` live in `$RUNNER_TEMP`. Use the `archivePath` and `ipaPath` outputs.

## Development

```sh
make test   # bash test suite, runs with macOS /bin/bash 3.2
make lint   # shellcheck + actionlint (brew install shellcheck actionlint)
```

Step logic lives in [`scripts/`](scripts). [`action.yml`](action.yml) only wires inputs into
those scripts through environment variables. The tests stub `xcodebuild` and `xcrun`
([`tests/stubs`](tests/stubs)). The keychain integration test runs only when `CI=true`.

## License

[MIT](LICENSE)
