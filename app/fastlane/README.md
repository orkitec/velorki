# fastlane

Release automation for Google Play, and the App Store screenshots and texts.
The iOS app itself is built, signed and uploaded by `xcodebuild` with
automatic signing, see [`docs/RELEASE_IOS.md`](../../docs/RELEASE_IOS.md). Nothing here creates the
accounts or credentials below.

```
app/
├── Gemfile              fastlane, installed with `bundle install` from app/
└── fastlane/
    ├── Appfile          package name and Play key, overridable by env
    ├── Fastfile         the lanes
    └── metadata/        store listing copy — DRAFT, see "Metadata" below
```

Run everything from `app/`:

```sh
cd app
bundle install
bundle exec fastlane android internal
```

## Lanes

| Lane | What it does |
|---|---|
| `android internal` | Gradle `bundleRelease` (the Flutter Gradle plugin builds the Dart side), then `supply` to the Play **internal testing** track. |
| `android promote_closed` | Promotes the newest internal build to the closed test track without rebuilding. |
| `android latest_version_code` | Writes the highest version code on the internal, alpha, beta and production tracks to `LATEST_VERSION_CODE_FILE`. Run by `.github/workflows/release.yml` before it builds. |
| `ios latest_build_number` | Writes the newest App Store Connect build number (any version, 0 for none) to `LATEST_BUILD_NUMBER_FILE`, with `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_PATH`. Run by `.github/workflows/release.yml` before it archives. |
| `ios store_assets` | `deliver`: the screenshots in `SCREENSHOTS_PATH` (laid out by `tool/store_stage_deliver.sh`) onto App Store version `APP_VERSION`, replacing those of each language uploaded, and with `UPLOAD_METADATA=true` `metadata/ios`. Run by `.github/workflows/store-assets.yml` with `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_PATH`; see `docs/STORE_ASSETS.md`. |

## Environment

| Variable | Used by | What it is |
|---|---|---|
| `PLAY_SERVICE_ACCOUNT_JSON_PATH` | `android internal`, `android latest_version_code` | path to the Play service account JSON key |
| `VELORKI_ENV_FILE` | `android internal` | dart-define file, default `app/env/prod.json` |
| `BUILD_NUMBER` | `android internal` | version code; Play refuses a repeat |

`app/android/key.properties` and `app/android/app/upload.jks` (the upload
keystore) must exist for a signed Android build; CI writes both from secrets,
see `.github/workflows/release.yml`.

## What has to be created by hand first

The App Store side (developer membership, app record, API key, subscriptions)
is in [`docs/RELEASE_IOS.md`](../../docs/RELEASE_IOS.md) and
[`docs/STORE_CHECKLIST.md`](../../docs/STORE_CHECKLIST.md).

### In the Play Console (once)

1. The app entry for `com.orkitec.velorki`, with **Play App Signing** enabled
   and the upload key generated locally.
2. A **service account** in the Google Cloud project linked to the Play
   Console, with the *Release manager* permission granted in the Play Console
   and a JSON key downloaded; that file is
   `PLAY_SERVICE_ACCOUNT_JSON_PATH`, and its contents are the
   `PLAY_SERVICE_ACCOUNT_JSON` secret in GitHub Actions.
3. The **internal testing** track with at least one tester, so the first
   upload has somewhere to land. If the developer account is personal rather
   than an organisation, a closed test with twelve testers running for
   fourteen days is required before production access — check this early, it
   sets the release date.
4. Subscriptions (monthly and yearly, seven-day free trial) matching the
   RevenueCat product ids.

## Metadata

`metadata/android/en-US` and `metadata/ios/en-US` hold the store copy. It is
a **draft**: written from `README.md` and `docs/ARCHITECTURE.md`, not yet read
by anyone else, and not yet checked against the final feature set or the
subscription prices. `android internal` therefore runs with
`skip_upload_metadata` set, so a release cannot silently overwrite the Play
listing; `metadata/ios` is uploaded only when the store-assets workflow is run with
`metadata`. Remove the flags once the copy is agreed and the
screenshots are in `metadata/android/en-US/images`.

Character limits, which `title.txt`, `short_description.txt`, `name.txt`,
`subtitle.txt` and `keywords.txt` are already inside: Play 30 / 80 / 4000,
App Store 30 / 30 / 4000 and 100 for the comma-separated keywords. The word
"Strava" must not appear in the app name, the Play title or the keywords —
their brand guidelines forbid it.

What is **not** in these files and has to be answered in the consoles by hand:
the Play Data safety form, the Play app content declarations, the App Store
App Privacy answers, the age rating questionnaires and the export compliance
question. `docs/STORE_CHECKLIST.md` lists them with their exact locations.
