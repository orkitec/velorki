// The App Store preview video's footage: six short recordings of the real
// app on Madeira (the cycle map in New York), in one language, each in the
// theme the preview set gives it.
//
//   tool/store_preview.sh            # the whole video; see there
//
// Not part of the suite, for the same reasons as store_screenshots_test.dart:
// it clears the library of the device it runs on, and refuses to run without
// --dart-define=VELORKI_STORE_SHOTS=true.
//
// The host records the simulator's screen around each clip (see shutter.dart:
// startRecording and stopRecording), so the recordings hold the platform-view
// map and the status bar as a rider sees them. Every tap in a clip is a real
// tap on a Flutter widget; points go on the map through the planner, because
// a synthetic tap never reaches the native map view. What each clip shows is
// computed on the device: the cycle map and its stops, the plan, the rain on
// it, the loops, and the ride, which is the 20 km ride of the screenshots,
// recorded by the real recorder.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/domain/cycle_map.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/map/presentation/weather_time_row.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/follow_mode.dart';
import 'package:velorki/features/recording/presentation/live_figures_view.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/recording/presentation/ride_charts.dart';
import 'package:velorki/features/recording/presentation/save_ride_sheet.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/smart_loop/application/smart_loop_controller.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/tiles.dart';
import 'demo_data.dart';
import 'shutter.dart';
import 'store_support.dart';

const bool _enabled = bool.fromEnvironment('VELORKI_STORE_SHOTS');
const String _locale = String.fromEnvironment(
  'VELORKI_STORE_LOCALE',
  defaultValue: 'en',
);

/// The theme of each clip, as `clip:theme` pairs; store/preview_set.json via
/// tool/store_preview.sh.
const String _set = String.fromEnvironment(
  'VELORKI_PREVIEW_SET',
  defaultValue: 'plan:dark,weather:light,loop:light,cyclemap:dark,navigation:dark,ride:dark',
);

/// How far in from either end of the time control's slider its track
/// starts: the overlay's radius the row gives it.
const double _sliderInset = 14;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final l10n = lookupAppLocalizations(Locale(_locale));
  final themes = <String, ThemeMode>{
    for (final pair in _set.split(','))
      pair.split(':').first.trim(): ThemeMode.values.byName(
        pair.split(':').last.trim(),
      ),
  };
  ThemeMode themeOf(String clip) => themes[clip] ?? ThemeMode.dark;

  testWidgets('store preview, $_locale', (tester) async {
    if (!_enabled) {
      markTestSkipped('only tool/store_preview.sh runs this');
      return;
    }
    final session = await startStoreApp(
      tester,
      locale: _locale,
      mode: themeOf('plan'),
      origin: featuredRoute.waypoints.first,
    );
    final container = session.container;
    final positions = session.positions;
    final appearance = container.read(appearanceSettingProvider.notifier);
    final planner = container.read(plannerControllerProvider.notifier);
    final featured = await seedLibrary(tester, container);
    String clip(String name) => 'preview/$_locale/$name';

    /// Switches the app to the clip's theme and gives the map time to load
    /// its style and tiles before anything is recorded.
    Future<void> theme(String name) async {
      await appearance.setMode(themeOf(name));
      await pumpFor(tester, const Duration(seconds: 4));
    }

    /// A tap as a rider makes it: straight on the widget, nothing scrolled
    /// into view first.
    Future<void> tap(Finder finder, {Duration then = Duration.zero}) async {
      await waitForWidget(tester, finder);
      await tester.tap(finder.first, warnIfMissed: false);
      await pumpFor(tester, then);
    }

    // -------------------------------------------------------- cyclemap
    // The offline cycle map and the stops, drawn on the device from New
    // York's routing tile and gazetteer as on the cycle map slide, with the
    // parts and the kinds of stop the app starts with, while the camera
    // draws back from Chelsea.
    await ensureRegionTile(tester, container, name: cycleMapTile);
    await (await container.read(gazetteerStoreProvider.future)).refresh();
    final cycleMap = container.read(cycleMapPreferencesProvider.notifier);
    for (final part in CycleMapPart.values) {
      await cycleMap.setPart(part, shown: defaultCycleMapParts.contains(part));
    }
    final stops = container.read(mapStopsPreferencesProvider.notifier);
    for (final kind in {
      ...container.read(mapStopsPreferencesProvider).kinds,
      ...defaultStopKinds,
    }) {
      await stops.setKind(kind, shown: defaultStopKinds.contains(kind));
    }
    await cycleMap.setShown(true);
    await stops.setShown(true);
    planner.clear();
    await theme('cyclemap');
    // Both ends of the move drawn once first, so nothing loads on the way:
    // from the lanes close up the camera draws back to the north-east, and
    // the stops come into view.
    const wide = LatLng(40.7505, -74.0010);
    const wideZoom = chelseaZoom - 1.1;
    await frameArea(tester, container, wide, wideZoom);
    await pumpFor(tester, const Duration(seconds: 15));
    await frameArea(tester, container, chelsea, chelseaZoom);
    await pumpFor(tester, const Duration(seconds: 10));
    await startRecording(tester, clip('cyclemap'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    unawaited(
      frameArea(
        tester,
        container,
        wide,
        wideZoom,
        glide: const Duration(seconds: 4),
      ),
    );
    await pumpFor(tester, const Duration(milliseconds: 4800));
    await stopRecording(tester, clip('cyclemap'));
    await cycleMap.setShown(false);
    await stops.setShown(false);
    await pumpFor(tester, const Duration(seconds: 1));

    // ------------------------------------------------------------ plan
    // The camera is put over the featured route first, then the plan is
    // cleared: the points go in one at a time, and the route grows.
    planner
      ..clear()
      ..loadSavedRoute(featured);
    await frameRoute(tester, container, featured.geometry);
    planner.clear();
    await theme('plan');
    // The start is set before the recording, so the clip opens on the line
    // drawing in rather than on an empty map.
    planner.addWaypoint(featuredRoute.waypoints.first);
    await pumpFor(tester, const Duration(seconds: 4));
    await startRecording(tester, clip('plan'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    for (final point in featuredRoute.waypoints.skip(1)) {
      planner.addWaypoint(point);
      await pumpFor(tester, const Duration(milliseconds: 1400));
    }
    await waitUntil(
      tester,
      () {
        final state = container.read(plannerControllerProvider);
        return state.result != null && !state.isRouting;
      },
      describe: 'the planned route',
      timeout: const Duration(seconds: 60),
    );
    await pumpFor(tester, const Duration(seconds: 2));
    await stopRecording(tester, clip('plan'));

    // --------------------------------------------------------- weather
    // The route coloured by the rain on the way, under the map's rain, and
    // the time control dragged slowly from an hour on to four: the rain
    // drifts in over Camacha (store_weather.dart) and the route's colours
    // follow it. The map's forecast starts an hour on.
    await theme('weather');
    final restoreWeather = await showRouteRain(
      tester,
      container,
      featured,
      offsetMinutes: 60,
      save: l10n.plannerSave,
    );
    // The frames the drag passes through load before it starts.
    await pumpFor(tester, const Duration(seconds: 8));
    final slider = tester.getRect(
      find
          .descendant(
            of: find.byType(WeatherTimeRow),
            matching: find.byType(Slider),
          )
          .first,
    );
    // The thumb's place at each step: the track is inset by the overlay's
    // radius the row gives the slider.
    final step =
        (slider.width - 2 * _sliderInset) / (weatherRadarOffsets.length - 1);
    double xOf(int minutes) =>
        slider.left +
        _sliderInset +
        step * weatherRadarOffsets.indexOf(minutes);
    // The finger goes down on the thumb, as near as the slider's geometry
    // says, and is moved onto "+1 h" by what the slider reports. Now and
    // then a drag is lost on its way there; it is begun again.
    int under() => container.read(weatherRadarPreviewProvider) ?? 60;
    DeviceFinger? finger;
    for (var attempt = 1; finger == null; attempt++) {
      final pressed = await DeviceFinger.press(
        tester,
        Offset(xOf(60), slider.center.dy),
      );
      try {
        if (under() != 60) {
          await pressed.slideUntil(
            () => under() == 60,
            pixelsPerSecond: under() < 60 ? 30 : -30,
            timeout: const Duration(seconds: 3),
          );
        }
        finger = pressed;
      } on TestFailure {
        await pressed.lift();
        if (attempt == 3) rethrow;
        container.read(weatherRadarOffsetProvider.notifier).set(60);
        await pumpFor(tester, const Duration(seconds: 3));
      }
    }
    await pumpFor(tester, const Duration(seconds: 1));
    await startRecording(tester, clip('weather'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    // Six steps, a little over half a second each; a slow frame can carry
    // the finger past "+4 h", and it goes back.
    await finger.slideUntil(
      () => under() >= 240,
      pixelsPerSecond: 6 * step / 3.4,
      describe: () => 'the slider under the finger at ${under()}',
    );
    if (under() > 240) {
      await finger.slideUntil(() => under() == 240, pixelsPerSecond: -20);
    }
    await pumpFor(tester, const Duration(milliseconds: 200));
    await finger.lift();
    await pumpFor(tester, const Duration(milliseconds: 1400));
    await stopRecording(tester, clip('weather'));
    expect(container.read(weatherRadarOffsetProvider), 240);
    await restoreWeather();

    // ------------------------------------------------------------ loop
    // From the rider's position in the middle of Funchal.
    positions.emit(fix(funchal, seconds: 0, speed: 0));
    planner.clear();
    await theme('loop');
    await tap(plannerAction(l10n.loopAction), then: const Duration(seconds: 1));
    await startRecording(tester, clip('loop'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    // The sheet's title says the same as the button.
    await tap(
      find.ancestor(
        of: find.text(l10n.loopMake),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    await waitUntil(
      tester,
      () {
        final loop = container.read(smartLoopControllerProvider);
        if (loop.error != null) fail('loop search: ${loop.error}');
        return !loop.running && loop.hasSearched;
      },
      describe: 'the loop search',
      timeout: const Duration(minutes: 3),
    );
    await pumpFor(tester, const Duration(milliseconds: 1800));
    await tap(
      find.text(l10n.loopAnother),
      then: const Duration(milliseconds: 2200),
    );
    await stopRecording(tester, clip('loop'));
    await tap(
      find.ancestor(
        of: find.text(l10n.loopDone),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
      then: const Duration(milliseconds: 600),
    );

    // ------------------------------------------------------ navigation
    // The ride of the screenshots: Funchal to Santa Cruz by Camacha, fast
    // forward to about 18 km, then a fix a second.
    final route = await planRoute(tester, container, liveRideWaypoints);
    await container
        .read(followModeProvider.notifier)
        .select(FollowMode.headingUp);
    await theme('navigation');
    await tapAndPump(tester, find.text(l10n.tabRecord));
    final sheet = find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    final start = find.widgetWithText(FilledButton, l10n.recordingStart);
    await tester.dragUntilVisible(start, sheet, const Offset(0, 220));
    await tapAndPump(tester, start);
    await waitUntil(
      tester,
      () => positions.isListenedTo,
      describe: 'the recorder to subscribe to the GPS',
    );
    // A fix a second of ride time, so the rider moves a few metres at a
    // time and the camera glides rather than jumps.
    final rider = Rider(
      positions,
      session.clock,
      demoRide(route, stepSeconds: 1),
    );
    await rider.rideTo(tester, 18000);
    Future<void> second() => rider.step(tester, const Duration(seconds: 1));
    // Folded down, the live sheet docks into the figures bar; one step in
    // on the zoom buttons brings the streets, the line and the rider close.
    await tester.dragFrom(
      tester.getCenter(
        find
            .descendant(
              of: find.byType(RecordingScreen),
              matching: find.byType(SheetHandle),
            )
            .first,
      ),
      const Offset(0, 700),
    );
    await second();
    await waitForWidget(tester, find.byType(FiguresBar));
    // On a slow machine the sheet can still be moving when the drag comes,
    // and a drag that lands on the map lets the rider go; asking for the
    // rider again picks the following up whichever it was.
    await tap(find.byTooltip(l10n.mapLocateMe));
    await second();
    await tap(find.byTooltip(l10n.mapZoomIn));
    // On until a real turn, one the map turns through, is a little ahead.
    bool turns(TurnKind kind) => const <TurnKind>{
      TurnKind.left,
      TurnKind.right,
      TurnKind.sharpLeft,
      TurnKind.sharpRight,
    }.contains(kind);
    var ready = false;
    while (!rider.done && rider.alongM < 21500) {
      await second();
      final next = bannerProgress(tester);
      final ahead = next?.distanceToNextM;
      if (next?.next != null &&
          turns(next!.next!.kind) &&
          ahead != null &&
          ahead > 45 &&
          ahead < 60) {
        ready = true;
        break;
      }
    }
    expect(ready, isTrue, reason: 'a turn has to come up on the way');
    await startRecording(tester, clip('navigation'));
    final turn = bannerProgress(tester)!.next!.pointIndex;
    var after = -1;
    for (var i = 0; i < 20 && !rider.done; i++) {
      await second();
      final next = bannerProgress(tester)?.next?.pointIndex;
      if (after < 0 && next != null && next != turn) after = i;
      if (after >= 0 && i - after >= 3) break;
    }
    await stopRecording(tester, clip('navigation'));

    // ------------------------------------------------------------ ride
    await theme('ride');
    await startRecording(tester, clip('ride'));
    await pumpFor(tester, const Duration(milliseconds: 700));
    // The figures bar opens the live sheet again, where Finish is.
    await tap(find.byType(FiguresBar), then: const Duration(milliseconds: 900));
    await tap(
      find.byTooltip(l10n.recordingFinish),
      then: const Duration(milliseconds: 900),
    );
    await waitForWidget(tester, find.byType(SaveRideSheet));
    await pumpFor(tester, const Duration(milliseconds: 700));
    await tap(
      find.descendant(
        of: find.byType(SaveRideSheet),
        matching: find.widgetWithText(FilledButton, l10n.commonSave),
      ),
    );
    await waitForWidget(
      tester,
      find.byType(RideElevationChart),
      timeout: const Duration(seconds: 30),
    );
    clearSnackBars(tester);
    await pumpFor(tester, const Duration(milliseconds: 1200));
    await dragSheetUp(tester);
    await pumpFor(tester, const Duration(milliseconds: 600));
    // A slow scroll down the charts. Driven on the list itself rather than
    // by a drag: a pointer anywhere on this page lands on a chart or leaves
    // the charts' scrub marker behind.
    final list = tester.state<ScrollableState>(
      find
          .ancestor(
            of: find.byType(RideElevationChart),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final scrolled = list.position.animateTo(
      list.position.pixels + 360,
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeInOut,
    );
    await pumpFor(tester, const Duration(milliseconds: 1900));
    await scrolled;
    await pumpFor(tester, const Duration(milliseconds: 1400));
    await stopRecording(tester, clip('ride'));

    expect(container.read(recordingControllerProvider).isRecording, isFalse);
    await container
        .read(followModeProvider.notifier)
        .select(FollowMode.northUp);
    planner.clear();
    await unmountApp(tester);
  });
}
