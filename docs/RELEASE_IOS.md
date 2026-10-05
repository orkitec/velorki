# iOS release

The app is signed with Xcode's automatic signing, the distribution side with
Apple's cloud-managed certificate: no certificate repository, no manual
profiles. The `ios` job of `.github/workflows/release.yml` does it on a
runner, beside the `android` job; a Mac with Xcode signed into the team does it
by hand. Android is in [`app/fastlane/README.md`](../app/fastlane/README.md).

Signing happens twice. `xcodebuild archive` signs with an **Apple Development**
identity, and its private key has to be in a keychain (Apple keeps no copy, so
CI gets it from a secret). `xcodebuild -exportArchive` then re-signs with the
cloud-managed **Apple Distribution** certificate and the App Store profiles.
The archive cannot skip signing: the export takes each target's entitlements
(App Groups, HealthKit, push) from the archive's signature.

One upload carries four bundle ids, all under team `8Z44M8DMKK`:

| Bundle id | Xcode target |
|---|---|
| `com.orkitec.velorki` | `Runner` |
| `com.orkitec.velorki.VelorkiLiveActivity` | `VelorkiLiveActivity` |
| `com.orkitec.velorki.share` | `VelorkiShare` |
| `com.orkitec.velorki.watchkitapp` | `VelorkiWatch` |

## One-time setup

1. **App Store Connect API key.** App Store Connect → *Users and Access* →
   *Integrations* → *App Store Connect API* → *Team Keys* → **+**, role
   **Admin** (or **App Manager** with *Access to Cloud Managed Distribution
   Certificate*). The `.p8` downloads once; keep it in the password manager
   with the **Key ID** and the **Issuer ID** shown on the same page.

2. **Development identity for CI.** Any Apple Development certificate of the
   team with its private key; a dedicated one keeps it apart from a person's.
   Create it in the Developer Portal (*Certificates* → **+** → *Apple
   Development*, with a CSR from Keychain Access → *Certificate Assistant*),
   open the downloaded `.cer`, then in Keychain Access → *My Certificates*
   export the identity as a `.p12` with a password.

3. **GitHub secrets**, in the `release` environment (*Settings* →
   *Environments* → `release`, which has the required reviewer):

   | Secret | Value |
   |---|---|
   | `ASC_KEY_ID` | the API key's Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID |
   | `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_<KEYID>.p8` |
   | `IOS_DEV_CERT_P12_BASE64` | `base64 -i ci-development.p12` |
   | `IOS_DEV_CERT_PASSWORD` | the `.p12` password |
   | `APP_ENV_PROD_JSON` | `app/env/prod.json`; shared with the `android` job |

   With any of them empty except the password, the `ios` job builds unsigned, prints a notice and finishes green.

## What a tag or a dispatch does

`git tag v1.2.3 && git push origin v1.2.3`. An existing tag is released again
from *Actions* → *release* → *Run workflow* on `main`
(`gh workflow run release.yml --ref main -f tag=v1.2.3`): the workflow comes
from `main`, the code from the tag. `platforms` picks `ios` or `android` alone,
`build_number` reuses the number the other store already has (empty computes
one), and `dry_run` archives and signs but uploads nothing. A trial run uses a
tag such as `v1.0.1-rc1`. Only the logins in the repository variable
`RELEASE_ACTORS` (comma-separated) may start or re-run a release.

1. The `version` job checks that the tag's `X.Y.Z` is the pubspec's version
   at that tag and computes the build number both platforms use:
   `run_number + 10` (iOS builds 1 and 2 and Android version codes 1 to 4
   came before), unless `build_number` is given.
2. The `ios` job waits for approval in the `release` environment.
3. It writes `env/prod.json`, decodes the key into the runner's temp directory
   and imports the development identity into a throwaway keychain.
4. `fastlane ios latest_build_number` reads the newest build number on App
   Store Connect; the job fails if its own is below it, or if the API cannot
   be reached. If it is the same number, an earlier run uploaded it: the job
   skips the archive and the upload and finishes green.
5. `flutter build ios --config-only` writes the Flutter configuration with
   that version and build number.
6. `xcodebuild archive` signs for development, fetching the profiles with the
   API key; the export re-signs for the App Store and uploads to App Store
   Connect. Nothing is submitted for review.
7. The key, the keychain and `env/prod.json` are deleted, also on failure.

App Store Connect refuses a version whose train is closed: after 1.0.0 is
released, bump `version:` in `app/pubspec.yaml` before the next upload.

## What stays manual

- Check the build in TestFlight once processing is done (a few minutes).
- Pick the build on the App Store version page, fill in the release notes.
- New subscriptions or in-app purchases: create them in App Store Connect and
  add them to the same submission as the app version the first time.
- **Submit for Review**, and the release itself. The App Privacy answers, the
  age rating and the metadata are listed in
  [`STORE_CHECKLIST.md`](STORE_CHECKLIST.md).

## Building and uploading by hand

On a Mac whose Xcode is signed into the team (*Settings* → *Accounts*), from a
clean checkout of the release commit, with `app/env/prod.json` written from
the password manager (`app/env/example.json` shows the shape):

```sh
cd app
flutter build ipa --release --dart-define-from-file=env/prod.json --build-number=<N>
plutil -replace destination -string upload -o /tmp/ExportUpload.plist ios/ExportOptions.plist
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
  -exportOptionsPlist /tmp/ExportUpload.plist -exportPath /tmp/velorki-upload \
  -allowProvisioningUpdates
```

`<N>` must be higher than every build uploaded before, CI's included. Without
an Xcode account, add `-authenticationKeyPath AuthKey_<KEYID>.p8
-authenticationKeyID <KEYID> -authenticationKeyIssuerID <ISSUER>` to the
export; `flutter build ipa` still needs a development identity in the login
keychain. `ios/ExportOptions.plist` unchanged exports an `.ipa` instead of
uploading it.
