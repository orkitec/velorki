# Velorki — instructions for coding agents

Velorki is a free, open-source Flutter bike route planner and ride recorder
(iOS + Android) on OpenStreetMap data. Routing runs on the phone (a Dart port
of BRouter in `app/packages/brouter_dart`); a thin Node relay in `api/` only
holds OAuth secrets, the hosted LLM and shared links. Read `docs/ARCHITECTURE.md`
before changing structure.

## Repositories

- **`~/Work/velorki`** (this one, `orkitec/velorki`): the app, the relay, the
  BRouter profiles and deploy files, the gazetteer builder and the oracle.
- **`~/Work/velorki-data`** (`orkitec/velorki-data`): the tile mirror. Its
  `publish-tiles` workflow copies brouter.de's rd5 tiles into GitHub Releases
  monthly; `publish-gazetteer` then builds a `<TILE>.gaz` per tile from
  Geofabrik extracts with *this* repo's `tools/gazetteer/build.py` and attaches
  it beside the rd5. The app follows `main/latest.json` there and merges every
  shard's `manifest.json`. A change to the `.gaz` format or the manifest shape
  touches both repos; the file format is documented here, the mirror there.

## How to work here

- **Verify on a device before committing.** Unit tests are not enough for UI
  or map changes: build (`flutter build apk --profile --dart-define-from-file=env/local.json`),
  install on the emulator or the phone, drive the flow, look at a screenshot.
  Commit after that, push in batches, never one push per fix.
- **Commits**: plain English, say what changed and why. No AI attribution,
  no `Co-Authored-By` or session trailers.
- **Before any commit**, from `app/`, over `lib test integration_test` as
  `app.yml` does: `dart format`, `flutter analyze --fatal-infos`,
  `dart analyze --fatal-infos` (riverpod_lint only runs through `dart analyze`),
  `flutter test`, and `dart test` in any package you touched.
- **Delegation**: routine implementation goes to cheaper subagents with a
  precise brief; design decisions, verification and review stay with the
  main agent. Subagents must not commit.
- Keep docs terse and current. Delete rather than rewrite. No plan history.

## Toolchain facts

- Flutter/Dart/Java via mise (`mise.toml`); maplibre_gl needs Java 21,
  permission_handler needs compileSdk 37. Android SDK at `~/Android/Sdk`.
- Codegen: `bash tool/gen.sh` (riverpod, freezed, drift, gen-l10n). build_runner
  here has no `--delete-conflicting-outputs`.
- Strings live in `app/lib/l10n/app_en.arb` only (other locales come from GL
  Strings); run `gen.sh` after editing it.
- Config is `--dart-define-from-file=env/<name>.json`. `env/local.json` and
  `env/phone.json` are git-ignored: local points the tile mirror at
  `http://10.0.2.2:8000` (emulator only, debug builds only — profile builds
  block cleartext), phone at the GitHub Releases mirror.
- Emulator: start with `~/Work/bin/velorki-emu` (sizes the window for the
  tiled desktop). Two devices are usually attached: always pass `adb -s`.
  `app/tool/emu_ride.py` simulates a moving rider with course and speed
  (`adb emu geo fix` gives neither), for follow-mode and recording checks.
- Never `pkill -f <pattern>` from a shell whose own command line contains the
  pattern; use `pkill -x` or `[p]attern`.

## Code conventions

- Feature-first layout under `app/lib/features/<feature>/{data,domain,application,presentation}`;
  pure logic in `app/packages/*` (no Flutter imports).
- `app/packages/brouter_dart` is a transliteration of upstream BRouter: no
  behavioural changes inside ported files, upstream releases are ported as
  patches and proven by re-recording the oracle corpus. See its README,
  "Keeping up with upstream".
- The gazetteer file (`tools/gazetteer`, read by `GazetteerStore`) is on
  riders' phones once a build ships: change it additively (new tables or
  nullable columns the app treats as optional) and keep `schema_version`;
  a breaking change bumps the version, and the app skips files it cannot
  read. Before shipping, change it as freely as needed.
- Riverpod 3 codegen, freezed, Drift. Screens read the map through
  `PlannerMapHost`; nothing outside `features/map` imports maplibre.
- Maps: `MapChromeInsets` tells the map what a screen's chrome covers;
  `PlannerMapHost(embedded: true)` for maps that do not reach the bottom edge.
  Route/marker colours come from the theme via `MapPalette`.
- Theme: `app/lib/app/theme.dart` (`AccentPreset`, `VelorkiColors`). Stat
  captions render upper-case (`StatTile`, `SectionCaption`), so widget tests
  look for `DISTANCE`, not `Distance`.
- The floating navigation bar overlays content (`extendBody`): scroll views
  pad by `MediaQuery.paddingOf(context).bottom`.
- Modal sheets open on the root navigator (`useRootNavigator: true`).

## Tests

- `app/test`: widget/unit tests per feature with `support/` harnesses and fakes.
- `app/integration_test`: emulator flows; run all with `app/tool/itest.sh`,
  one `flutter test` per file. `VELORKI_ITEST_SHARD=1/3` runs a third of the
  files (Android CI splits it three ways), `VELORKI_ITEST_DRY_RUN=1` just lists
  what a shard would run, and `VELORKI_ITEST_COMBINED=1` runs
  `integration_test/all_tests.dart` — every file grouped into one process, one
  build and one attach, which is what iOS CI does. So a test may assume neither
  a fresh process nor anything a file before it left behind.
  `app/tool/itest_mirror.sh` builds and serves the tile mirror they download
  from — the oracle rd5 plus its `.gaz` fixture — on port 8000.
- BRouter parity: `tools/brouter-oracle` with the two committed tiles in
  `tools/brouter-oracle/tiles/`; the corpus is bound to those exact bytes.
- `app/test/perf`: timings against a real gazetteer, skipped unless
  `GAZETTEER_PERF_FILE` names a `.gaz` (`--dart-define` or the environment).
- CI: `app.yml` (every push; `check` is the static checks and the unit tests,
  `apk` builds the debug artifact beside it, and `gazetteer` builds the
  Liechtenstein extract and checks the `.gaz` fixtures), `integration.yml` and
  `integration-ios.yml` (every push to main that touches app/tiles/fixtures,
  plus nightly; a newer push cancels the older run. Android shards the suite
  three ways across API levels 31, 35 and 36 and caches Gradle and the AVD
  snapshot; iOS is one job running the whole suite in one process
  (`VELORKI_ITEST_COMBINED=1`), because there the Xcode build and the simulator
  boot cost more than the tests, and caches the pods and the derived data),
  `gazetteer-perf.yml` (nightly, times the search against New York off the
  mirror), `brouter-oracle.yml` (weekly). No rd5 comes off brouter.de; the oracle job
  does fetch the pinned upstream release zip. Every workflow declares the least
  privilege it needs (the default token is read-only) and every `uses:` is
  pinned to a commit SHA with the tag in a comment (the repo setting makes an
  unpinned `uses:` a hard error); a `v*` tag push runs `release.yml` (Android)
  and `ios-release.yml` (fastlane, TestFlight; one-time setup in
  `docs/RELEASE_IOS.md`) in the `release` environment, so both wait for the
  maintainer's approval in the Actions UI before anything is signed or
  published.

## Verifying on the emulator

1. `bash app/tool/itest_mirror.sh` serves the Madeira rd5 and its `.gaz` on
   port 8000; `env/local.json` points `VELORKI_SEGMENTS_URL` at
   `http://10.0.2.2:8000` (debug only — a profile build blocks cleartext, so
   use `env/phone.json` or the real mirror there).
2. `cd app && flutter build apk --debug --dart-define-from-file=env/local.json`
   (`--profile` for anything about frame times), then
   `adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk`.
3. Drive the flow and take a picture:
   `adb -s emulator-5554 exec-out screencap -p > /tmp/shot.png`.
4. `app/tool/itest.sh <name>` installs its own test build over the app with
   `adb install -r`, so app data survives and the downloaded tile is reused.
   A build signed differently (a release build over a debug one) does force an
   uninstall, and then the region has to be downloaded again.
