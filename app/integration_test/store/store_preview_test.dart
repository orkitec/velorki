// The App Store preview video's footage: five short recordings of the real
// app on Madeira, in one language, each in the theme the preview set gives it.
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
// computed on the device: the plan, its variants, the loops, and the ride,
// which is the 20 km ride of the screenshots, recorded by the real recorder.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/follow_mode.dart';
import 'package:velorki/features/recording/presentation/live_figures_view.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/recording/presentation/ride_charts.dart';
import 'package:velorki/features/recording/presentation/save_ride_sheet.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/smart_loop/application/smart_loop_controller.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
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
  defaultValue: 'plan:dark,variants:light,loop:light,navigation:dark,ride:dark',
);

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

    // ------------------------------------------------------------ plan
    // The camera is put over the featured route first, then the plan is
    // cleared: the points go in one at a time, and the route grows.
    planner
      ..clear()
      ..loadSavedRoute(featured);
    await frameRoute(tester, container, featured.geometry);
    planner.clear();
    await theme('plan');
    await pumpFor(tester, const Duration(seconds: 4));
    await startRecording(tester, clip('plan'));
    await pumpFor(tester, const Duration(milliseconds: 700));
    for (final point in featuredRoute.waypoints) {
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

    // -------------------------------------------------------- variants
    await theme('variants');
    await startRecording(tester, clip('variants'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tap(plannerAction(l10n.plannerVariants));
    await waitUntil(
      tester,
      () {
        final state = container.read(plannerControllerProvider);
        return state.alternatives.length > 2 && !state.loadingAlternatives;
      },
      describe: 'the variants',
      timeout: const Duration(seconds: 120),
    );
    await pumpFor(tester, const Duration(milliseconds: 1200));
    await tap(
      find.text(l10n.plannerAlternativeIndex(1)),
      then: const Duration(milliseconds: 1500),
    );
    await tap(
      find.text(l10n.plannerAlternativeIndex(2)),
      then: const Duration(milliseconds: 1800),
    );
    await stopRecording(tester, clip('variants'));

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
    final rider = Rider(positions, session.clock, demoRide(route));
    await rider.rideTo(tester, 18000);
    Future<void> second() => rider.step(tester, const Duration(seconds: 1));
    // On until a turn is a few seconds ahead, and far enough past the last
    // one that the banner has settled on it.
    var ready = false;
    while (!rider.done && rider.alongM < 21500) {
      await second();
      final next = bannerProgress(tester);
      final ahead = next?.distanceToNextM;
      if (next?.next != null && ahead != null && ahead > 28 && ahead < 70) {
        ready = true;
        break;
      }
    }
    expect(ready, isTrue, reason: 'a turn has to come up on the way');
    // Folded down, the live sheet docks into the figures bar.
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
    await startRecording(tester, clip('navigation'));
    final turn = bannerProgress(tester)!.next!.pointIndex;
    var after = -1;
    for (var i = 0; i < 25 && !rider.done; i++) {
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
