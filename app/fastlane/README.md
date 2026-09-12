# fastlane

Release automation for both stores. This directory is a **skeleton**: the
lanes are complete enough to run, but nothing here can work until the accounts
and credentials below exist, and none of it creates them.

```
app/
├── Gemfile              fastlane, installed with `bundle install` from app/
└── fastlane/
    ├── Appfile          bundle ids and the identities, all overridable by env
    ├── Fastfile         the lanes
    └── metadata/        store listing copy — DRAFT, see "Metadata" below
```

Run everything from `app/`:

```sh
cd app
bundle install
bundle exec fastlane android internal   # Linux, macOS or CI
bundle exec fastlane ios beta           # macOS with Xcode only
```

## Lanes

| Lane | What it does |
|---|---|
| `android internal` | Gradle `bundleRelease` (the Flutter Gradle plugin builds the Dart side), then `supply` to the Play **internal testing** track. |
| `android promote_closed` | Promotes the newest internal build to the closed test track without rebuilding. |
| `ios beta` | `match(readonly)` → `gym` → `pilot` to TestFlight. |
| `ios release` | `match(readonly)` → `gym` → `deliver` to App Store Connect, **without** submitting for review. Promotion stays a human decision. |

## Environment

| Variable | Used by | What it is |
|---|---|---|
| `PLAY_SERVICE_ACCOUNT_JSON_PATH` | `android internal` | path to the Play service account JSON key |
| `VELORKI_ENV_FILE` | `android internal` | dart-define file, default `app/env/prod.json` |
| `BUILD_NUMBER` | `android internal` | version code; Play refuses a repeat |
| `MATCH_PASSWORD`, `MATCH_GIT_URL` | `ios *` | the match repository and its passphrase |
| `APP_STORE_CONNECT_API_KEY_PATH` | `ios *` | the App Store Connect API key (`.json` as `app_store_connect_api_key`) |
| `FASTLANE_APPLE_ID`, `APPLE_TEAM_ID`, `ITC_TEAM_ID` | `ios *` | the Apple identities, placeholders in `Appfile` |

`app/android/key.properties` and `app/android/app/upload.jks` (the upload
keystore) must exist for a signed Android build; CI writes both from secrets,
see `.github/workflows/release.yml`.

## What has to be created by hand first

### On the Mac (once)

1. **Apple Developer Program membership** for Orkitec, and the app record in
   App Store Connect with bundle id `com.orkitec.velorki`.
2. **App Store Connect API key** (Users and Access → Integrations → App Store
   Connect API, role *App Manager*). Download the `.p8` once, keep it in the
   password manager, and point `APP_STORE_CONNECT_API_KEY_PATH` at the JSON
   wrapper fastlane expects.
3. **A private `match` repository** (for example `orkitec/velorki-certs`) and
   `bundle exec fastlane match appstore` run **once** from the Mac to create
   the distribution certificate and the provisioning profile. Everything after
   that runs `readonly`.
4. **Xcode project work that cannot be done from this repository**:
   - add `ios/Runner/PrivacyInfo.xcprivacy` to the Runner target
     (*Target → Build Phases → Copy Bundle Resources*) — the file exists, but
     it is not in the bundle until Xcode knows about it;
   - the **Share Extension** target for `receive_sharing_intent`, with its own
     bundle id, an App Group shared with the app, and profiles for both
     (see `lib/features/import_export/README.md`);
   - the In-App Purchase capability and the subscription products.
5. **Subscriptions** in App Store Connect (monthly and yearly, one group,
   seven-day introductory free trial) and the same product ids in RevenueCat.

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
subscription prices. Both upload lanes therefore run with
`skip_upload_metadata` / `skip_metadata` set, so a release cannot silently
overwrite what is in the consoles. Remove those flags once the copy is agreed
and the screenshots are in `metadata/*/en-US/images`.

Character limits, which `title.txt`, `short_description.txt`, `name.txt`,
`subtitle.txt` and `keywords.txt` are already inside: Play 30 / 80 / 4000,
App Store 30 / 30 / 4000 and 100 for the comma-separated keywords. The word
"Strava" must not appear in the app name, the Play title or the keywords —
their brand guidelines forbid it.

What is **not** in these files and has to be answered in the consoles by hand:
the Play Data safety form, the Play app content declarations, the App Store
App Privacy answers, the age rating questionnaires and the export compliance
question. `docs/STORE_CHECKLIST.md` lists them with their exact locations.
