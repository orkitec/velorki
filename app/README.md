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

All user-facing text lives in `lib/l10n/app_en.arb`. Other languages come
from Crowdin (`docs/LOCALISATION.md`); do not edit them by hand. Run
`flutter gen-l10n` after changing the ARB (build_runner does not do it).

## Tests

`flutter test` for the app and `dart test` inside each `packages/*` directory —
that is what the `check` job of `.github/workflows/app.yml` runs on every push,
together with `flutter test --coverage`, `dart format`, both analyzers and the
`brouter_dart` parity suites against the committed oracle tiles. The debug APK
is built by the `apk` job beside it, not after it.

`test/perf/gazetteer_perf_test.dart` is the exception: it skips itself unless
`GAZETTEER_PERF_FILE` points at a `<TILE>.gaz`, read from
`--dart-define=GAZETTEER_PERF_FILE=...` first and from the environment second.
It links the file into a temp directory, opens it with `GazetteerStore` and
times a prefix query, a kind search and the spelling pass against ceilings
loose enough to survive a CI runner. `.github/workflows/gazetteer-perf.yml`
runs it nightly against New York (`W75_N40.gaz`, 89 MB, pulled from the tag
the mirror's `latest.json` names) and puts the numbers in the run summary;
locally the Madeira fixture is a fast smoke test:

```sh
flutter test test/perf/gazetteer_perf_test.dart \
  --dart-define=GAZETTEER_PERF_FILE=$PWD/../tools/gazetteer/fixtures/W20_N30.gaz
```

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
VELORKI_ITEST_SHARD=1/3 tool/itest.sh   # one third of the files
VELORKI_ITEST_COMBINED=1 tool/itest.sh  # every file in one run (iOS CI)
```

`VELORKI_ITEST_SHARD=N/M` spreads the files over `M` shards by the weights in
`itest_weight` (heaviest first into the lightest shard so far), which keeps
`close_loop`, `navigate_route` and `record_ride` — the three slow flows — in
three different shards; the split is a function of the file names only, so
shards never disagree about it. `VELORKI_ITEST_DRY_RUN=1` prints the selection
and stops.

`VELORKI_ITEST_COMBINED=1` runs `integration_test/all_tests.dart` instead — it
imports every file and runs each one's tests inside its own group — so one
build, one install and one attach cover the whole suite. It takes no filter and
no shard, and it needs a longer watchdog than a single file does
(`VELORKI_ITEST_TIMEOUT=2400`). Because it exists, every test here has to hold
in a shared process as well as in a fresh one: set up the preferences it reads,
timestamp or diff whatever it writes to the database, and leave no recording
running behind it.

The runner passes `--dart-define=VELORKI_BROUTER_URL=` (nothing to route
against but the device), `--dart-define=VELORKI_API_URL=` and
`--dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000`, and stops at the
first failure. Without `VELORKI_ITEST_COMBINED` each file is its own `flutter
test` run, because the `integration_test` binding installs one test build per
invocation; budget one to two minutes per file, or three to four minutes for a
combined run on a device that already has the region's tile — the first run on
a cold one downloads it before anything routes.

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
`.github/workflows/integration.yml` runs the suite on an emulator with the
Madeira tile on every push to main that touches `app/`, the committed tiles or
the `.gaz` fixtures, again nightly, and by hand from the Actions tab; a newer
push cancels the older run, the nightly is never cancelled. Its matrix is API
level (31, 35, 36) by shard (1/3, 2/3, 3/3), so a job is named `emulator (31,
1/3)`, and it caches the Gradle directories and a booted AVD snapshot per API
level. `.github/workflows/integration-ios.yml` is the same suite on an iOS
simulator, but in a single job with `VELORKI_ITEST_COMBINED=1`: there the Xcode
build and the simulator boot dwarf the tests, and sharding made every shard pay
them again for each of its files. The pods and the Xcode derived data are
cached.

`integration_test/plan_route_test.dart` is the exception: it wants a BRouter
*server*, so `tool/itest.sh` skips it unless `VELORKI_BROUTER_URL` is set
(`tools/brouter-oracle/serve.sh` starts one on port 17777).

## Platform notes

Android `minSdk` is 26. Both platforms register the `velorki://` URL scheme for
OAuth callbacks and shared links (`AndroidManifest.xml` intent filter,
`CFBundleURLTypes` in `ios/Runner/Info.plist`).
