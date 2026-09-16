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
| `VELORKI_SEGMENTS_URL` | Mirror of the rd5 routing tiles for on-device routing downloads, and of the `<TILE>.gaz` search indexes beside them: a directory with `manifest.json`, or a pointer such as the mirror's `latest.json` that names the current snapshot. |
| `VELORKI_PHOTON_URL` | Photon geocoder, for "Search online for …" and for a device with no routing tiles. Places are otherwise searched in the `.gaz` files downloaded next to the tiles. |
| `VELORKI_MAP_STYLE_URL` | MapLibre style JSON. Default OpenFreeMap Liberty. |
| `VELORKI_MAP_STYLE_URL_DARK` | MapLibre style JSON for dark mode. Default OpenFreeMap Fiord. |
| `VELORKI_CYCLOSM_TILE_URL` | CyclOSM raster tiles for the optional cycling overlay. |
| `VELORKI_REVENUECAT_KEY_*` | RevenueCat public SDK keys per platform. Empty: subscription UI hidden. |
| `VELORKI_STRAVA_CLIENT_ID`, `VELORKI_RWGPS_CLIENT_ID` | Public OAuth client ids. The secrets live in the relay. |
| `VELORKI_OAUTH_SCHEME` | Custom URL scheme for OAuth callbacks and share links. |
| `VELORKI_STORE_URL_ANDROID`, `VELORKI_STORE_URL_IOS` | The app's store page per platform, opened when a routing tile needs a newer app. Empty: the rider is only told. |

## Analysis

`flutter analyze --fatal-infos lib test integration_test` for the app package. Riverpod's own
lints ship as an `analysis_server_plugin` declared under `plugins:` in
`analysis_options.yaml`; the `flutter analyze` front end does not load analyzer
plugins, so run `dart analyze --fatal-infos lib test integration_test` as well to see them
(`custom_lint` is no longer involved and is incompatible with riverpod_lint 3.1).

## Database

Drift, schema version 3, timestamps stored as ISO text
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

`flutter test` for the app and `dart test` inside each `packages/*` directory —
that is what `.github/workflows/app.yml` runs on every push, together with
`flutter test --coverage`, `dart format`, both analyzers and the `brouter_dart`
parity suites against the committed oracle tiles.

### Emulator integration tests

`integration_test/` holds the feature flows that only mean something on a real
device: planning against the on-device routing engine, the Loop sheet, saving
into the library, recording a ride, the map style reload and a GPX import.
They drive the real `VelorkiApp` with the real map, the real database and the
real BRouter port — only the things a test runner cannot have are faked (the
GPS, the location and notification permissions, the Android foreground
service, and the Photon geocoder).

```
tool/itest.sh                 # the whole suite on emulator-5554
tool/itest.sh close_loop      # only the files whose path matches
```

The runner passes `--dart-define=VELORKI_BROUTER_URL=` (nothing to route
against but the device), `--dart-define=VELORKI_API_URL=` and
`--dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000`, and stops at the
first failure. Each file is its own `flutter test` run, because the
`integration_test` binding installs one test build per invocation; budget one
to two minutes per file.

What the emulator needs before the first run:

- an rd5 tile mirror on the host at port 8000: `tool/itest_mirror.sh` builds
  one out of the committed oracle tile and its `.gaz` search fixture, writes
  the `manifest.json` and serves it in the background (`ITEST_MIRROR_PORT`
  moves the port). `10.0.2.2` is the host as the emulator sees it. The suite
  downloads the tile it needs on the first run and reuses it afterwards.
- a virtual position in the region under test, e.g.
  `adb -s emulator-5554 emu geo fix -73.9645 40.8153` for New York.

`VELORKI_ITEST_REGION` picks the coordinates: `nyc` (default, tile `W75_N40`)
or `madeira` (tile `W20_N30`, the tile the frozen BRouter oracle release
serves). `integration_test/support/region.dart` holds both sets.
`.github/workflows/integration.yml` runs the suite nightly on an emulator with
the Madeira tile, and can be started by hand from the Actions tab.

`integration_test/plan_route_test.dart` is the exception: it wants a BRouter
*server*, so `tool/itest.sh` skips it unless `VELORKI_BROUTER_URL` is set
(`tools/brouter-oracle/serve.sh` starts one on port 17777).

## Platform notes

Android `minSdk` is 26. Both platforms register the `velorki://` URL scheme for
OAuth callbacks and shared links (`AndroidManifest.xml` intent filter,
`CFBundleURLTypes` in `ios/Runner/Info.plist`).
