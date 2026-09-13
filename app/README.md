# Velorki app

Flutter app for iOS and Android plus the pure-Dart packages under `packages/`.

## Toolchain

- `mise install` in the repository root installs Flutter 3.47.4, Java 21 and
  Node. Or use fvm with `.fvmrc`.
- Android SDK without Android Studio: unpack the command-line tools into
  `~/Android/Sdk/cmdline-tools/latest`, then
  `sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"` and
  `flutter config --android-sdk ~/Android/Sdk`. `mise.toml` exports
  `ANDROID_HOME` for you.
- iOS builds need Xcode on a Mac. `fastlane/` holds the lanes.

## Run

```
flutter pub get
tool/gen.sh                    # build_runner + flutter gen-l10n
flutter run --dart-define-from-file=env/dev.json
```

`tool/gen.sh` must be run after a fresh clone and after touching anything with
codegen: none of `*.g.dart`, `*.freezed.dart`, `*.drift.dart` or
`lib/l10n/generated/` is committed. (`--delete-conflicting-outputs` no longer
exists in build_runner 2.16; it cleans up on its own.)

`env/dev.json` points at the official Velorki servers. Copy it to
`env/local.json` (git-ignored) to point at your own; `env/ci.json` has empty
server URLs, which hides the Strava, RideWithGPS and AI features and makes the
app fully local.

## Configuration keys

| Key | Meaning |
|-----|---------|
| `VELORKI_BROUTER_URL` | BRouter routing server. Empty: on-device routing only (needs downloaded tiles). |
| `VELORKI_API_URL` | The relay. Empty: Strava, RideWithGPS, AI assistant and link sharing are hidden. |
| `VELORKI_SEGMENTS_URL` | Mirror of the rd5 routing tiles for on-device routing downloads. |
| `VELORKI_PHOTON_URL` | Photon geocoder for search. |
| `VELORKI_MAP_STYLE_URL` | MapLibre style JSON. Default OpenFreeMap Liberty. |
| `VELORKI_MAP_STYLE_URL_DARK` | MapLibre style JSON for dark mode. Default OpenFreeMap Fiord. |
| `VELORKI_CYCLOSM_TILE_URL` | CyclOSM raster tiles for the optional cycling overlay. |
| `VELORKI_REVENUECAT_KEY_*` | RevenueCat public SDK keys per platform. Empty: subscription UI hidden. |
| `VELORKI_STRAVA_CLIENT_ID`, `VELORKI_RWGPS_CLIENT_ID` | Public OAuth client ids. The secrets live in the relay. |
| `VELORKI_OAUTH_SCHEME` | Custom URL scheme for OAuth callbacks and share links. |

## Analysis

`flutter analyze --fatal-infos lib test` for the app package. Riverpod's own
lints ship as an `analysis_server_plugin` declared under `plugins:` in
`analysis_options.yaml`; the `flutter analyze` front end does not load analyzer
plugins, so run `dart analyze --fatal-infos lib test` as well to see them
(`custom_lint` is no longer involved and is incompatible with riverpod_lint 3.1).

## Database

Drift, schema version 1, timestamps stored as ISO text
(`build.yaml → store_date_time_values_as_text`). Before changing the schema,
bump `schemaVersion` and dump the new version so migrations stay testable:

```
dart run drift_dev schema dump lib/core/db/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/core/db/generated/
```

## Strings

All user-facing text lives in `lib/l10n/app_en.arb`. Other languages are
produced by the GL Strings integration; do not edit them by hand. Run
`flutter gen-l10n` after changing the ARB (build_runner does not do it).

## Tests

`flutter test` for the app, `dart test` inside each `packages/*` directory.

## Platform notes

Android `minSdk` is 26. Both platforms register the `velorki://` URL scheme for
OAuth callbacks and shared links (`AndroidManifest.xml` intent filter,
`CFBundleURLTypes` in `ios/Runner/Info.plist`).
