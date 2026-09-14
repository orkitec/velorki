// Changing the look of the app under a planned route: the map style reloads,
// and the plan and the route line on it have to survive that.
//
//   flutter test integration_test/appearance_test.dart -d emulator-5554 \
//     --dart-define=VELORKI_BROUTER_URL= \
//     --dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
//     --dart-define=VELORKI_API_URL=
//
// A style reload throws every layer away and calls `onControllerReady` again,
// so the only honest check that the line came back is to watch what the app
// asked the map for. The map view builder is therefore wrapped in a proxy
// controller that records `setRouteLine` and forwards it to the real map.
//
// The theme goes to Dark first and the map look to Night second, in the
// order a rider would use them. Going Dark with the look on `auto` swaps the
// style URL and the palette in the same frame; `setPalette` swallows the
// PlatformException a style being torn down answers with, and the reload
// repaints every layer with the new palette.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/features/map/presentation/map_view.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/application/planner_map_binding.dart';
import 'package:velorki/features/planner/presentation/planner_map_host.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';
import 'support/tiles.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('keeps the plan and the route line across a style reload', (
    tester,
  ) async {
    final maps = <RecordingMapController>[];
    final container = await pumpApp(
      tester,
      realMap: false,
      overrides: [
        mapViewBuilderProvider.overrideWithValue(
          (onReady) => MapView(
            onControllerReady: (controller) {
              final recorder = RecordingMapController(controller);
              maps.add(recorder);
              onReady(recorder);
            },
          ),
        ),
      ],
    );
    await ensureRegionTile(tester, container);

    // The emulator keeps its preferences between runs.
    final appearance = container.read(appearanceSettingProvider.notifier);
    await appearance.setMode(ThemeMode.light);
    await appearance.setMapLook(MapLook.auto);
    await pumpFor(tester, const Duration(seconds: 1));

    container.read(plannerControllerProvider.notifier)
      ..addWaypoint(region.start)
      ..addWaypoint(region.end);
    await pumpFor(tester, const Duration(milliseconds: 400));
    await waitUntil(
      tester,
      () {
        final state = container.read(plannerControllerProvider);
        if (state.route.hasError) fail('routing failed: ${state.route.error}');
        return state.result != null && !state.isRouting;
      },
      describe: 'the route to change the look under',
      timeout: const Duration(seconds: 90),
      onTimeout: () => '${container.read(plannerControllerProvider)}',
    );

    final planned = container.read(plannerControllerProvider);
    await waitUntil(
      tester,
      () => maps.isNotEmpty && maps.last.lines.containsKey(mainRouteLineId),
      describe: 'the route line on the map',
      // The first map of the run: on a freshly booted CI emulator the style
      // download alone can take the better part of a minute.
      timeout: const Duration(seconds: 120),
      onTimeout: () => 'maps=${maps.length}',
    );
    final drawnBefore = maps.last.lines[mainRouteLineId]!.length;
    final mapsBefore = maps.length;
    debugPrint(
      'VELORKI_APPEARANCE planned ${planned.result!.lengthM.round()}m, '
      'line has $drawnBefore points on map #$mapsBefore',
    );

    // ------------------------------------------------------- theme to Dark
    await tapAndPump(tester, find.text('Settings'));
    // "Light" is both a theme and a map look, so scope the theme labels.
    await waitForWidget(tester, find.byType(SegmentedButton<ThemeMode>));
    await tapAndPump(
      tester,
      find.descendant(
        of: find.byType(SegmentedButton<ThemeMode>),
        matching: find.text('Dark'),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 4));
    expect(container.read(appearanceSettingProvider).mode, ThemeMode.dark);
    expect(
      tester.takeException(),
      isNull,
      reason: 'changing the theme must not throw',
    );

    // ------------------------------------------------------ map to Night
    await waitForWidget(tester, find.widgetWithText(ChoiceChip, 'Night'));
    await tapAndPump(tester, find.widgetWithText(ChoiceChip, 'Night'));
    await pumpFor(tester, const Duration(seconds: 4));
    expect(container.read(appearanceSettingProvider).mapLook, MapLook.night);
    expect(
      tester.takeException(),
      isNull,
      reason: 'changing the look must not throw',
    );

    // --------------------------------------------------------- back to Plan
    await tapAndPump(tester, find.text('Plan'));
    await pumpFor(tester, const Duration(seconds: 2));

    final after = container.read(plannerControllerProvider);
    expect(after.waypoints, planned.waypoints);
    expect(after.options, planned.options);
    expect(after.result!.lengthM, planned.result!.lengthM);
    expect(after.result!.geometry.length, planned.result!.geometry.length);

    // Whichever controller is current — a style reload hands out a new one —
    // the main route line is on it, with the geometry it had before.
    await waitUntil(
      tester,
      () => maps.last.lines[mainRouteLineId]?.isNotEmpty ?? false,
      describe: 'the route line redrawn after the style reload',
      onTimeout: () => 'maps=${maps.length} calls=${maps.last.routeLineCalls}',
    );
    final drawnAfter = maps.last.lines[mainRouteLineId]!.length;
    debugPrint(
      'VELORKI_APPEARANCE after the reload: maps=${maps.length} '
      'line has $drawnAfter points, calls=${maps.last.routeLineCalls}',
    );
    expect(drawnAfter, drawnBefore);
    expect(
      maps.length,
      greaterThan(mapsBefore),
      reason: 'the Night style has to have been loaded from scratch',
    );
    expect(
      container.read(appearanceSettingProvider).mode,
      ThemeMode.dark,
      reason: 'coming back to Plan must not undo the setting',
    );
    expect(
      toleratedErrors,
      isEmpty,
      reason:
          'the only errors this test allows are render overflows, and it '
          'should not even need those',
    );
    await screenshot(tester, 'appearance-night');

    await appearance.setMode(ThemeMode.system);
    await appearance.setMapLook(MapLook.auto);
    await unmountApp(tester);
  });
}
