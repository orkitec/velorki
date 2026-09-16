# Velorki — instructions for coding agents

Velorki is a free, open-source Flutter bike route planner and ride recorder
(iOS + Android) on OpenStreetMap data. Routing runs on the phone (a Dart port
of BRouter in `app/packages/brouter_dart`); a thin Node relay in `api/` only
holds OAuth secrets, the hosted LLM and shared links. Read `docs/ARCHITECTURE.md`
before changing structure.

## How to work here

- **Verify on a device before committing.** Unit tests are not enough for UI
  or map changes: build (`flutter build apk --profile --dart-define-from-file=env/local.json`),
  install on the emulator or the phone, drive the flow, look at a screenshot.
  Commit after that, push in batches, never one push per fix.
- **Commits**: plain English, say what changed and why. No AI attribution,
  no `Co-Authored-By` or session trailers.
- **Before any commit**: `dart format`, `flutter analyze`, `dart analyze lib test`
  (riverpod_lint only runs through `dart analyze`), `flutter test` (from `app/`),
  and `dart test` in any package you touched.
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
- `app/integration_test`: emulator flows; run all with `app/tool/itest.sh`.
- BRouter parity: `tools/brouter-oracle` with the two committed tiles in
  `tools/brouter-oracle/tiles/`; the corpus is bound to those exact bytes.
- CI: `app.yml` (every push), `integration.yml` (nightly, boots an emulator),
  `brouter-oracle.yml` (nightly). Everything runs offline; no release to fetch.
