// The two halves of the Loop sheet, on the device: closing a planned route
// into a loop and asking for a different way back, then making a loop out of
// nothing but a start and a distance.
//
//   flutter test integration_test/close_loop_test.dart -d emulator-5554 \
//     --dart-define=VELORKI_BROUTER_URL= \
//     --dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
//     --dart-define=VELORKI_API_URL=
//
// The two points are put on the plan through the planner controller rather
// than by tapping the map. The map is a real MapLibre platform view here; its
// gesture recognisers live on the platform side, so a synthesised tap in the
// Flutter test binding never reaches them. Everything the test is actually
// about — the Loop sheet, the switch, the buttons, the slider, the routing —
// is driven through the widgets.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/planner_state.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/smart_loop/application/smart_loop_controller.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';
import 'support/tiles.dart';

/// What the stored loop distance is set to before the sheet opens, so the
/// slider starts somewhere known and the test can prove it moved.
const double _seedLoopKm = 50;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('closes a route into a loop and makes one from a distance', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('loop.distance_km', _seedLoopKm);

    final container = await pumpApp(
      tester,
      overrides: [
        locationPermissionGatewayProvider.overrideWithValue(
          const GrantedLocationPermission(),
        ),
        positionSourceProvider.overrideWithValue(
          FixedPositionSource(region.start),
        ),
      ],
    );
    await ensureRegionTile(tester, container);

    final planner = container.read(plannerControllerProvider.notifier);
    PlannerState state() => container.read(plannerControllerProvider);

    // ---------------------------------------------------------- close a loop
    planner
      ..addWaypoint(region.start)
      ..addWaypoint(region.end);
    await _waitForRoute(tester, container, 'the out-and-back leg');
    final outLength = state().result!.lengthM;
    expect(state().isClosedLoop, isFalse);

    await tapAndPump(tester, find.widgetWithText(LabeledIconButton, 'Loop'));
    await waitForWidget(tester, find.text('Close the loop'));

    // "Different way back" is on by default; assert that rather than toggle
    // it, so a changed default shows up here instead of being papered over.
    final wayBack = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Different way back'),
    );
    expect(wayBack.value, isTrue);

    await tapAndPump(
      tester,
      find.widgetWithText(FilledButton, 'Close the loop'),
    );
    await _waitForRoute(
      tester,
      container,
      'the closed loop',
      // The plan still holds the out-and-back route for the 300 ms the planner
      // debounces, so "there is a route and nothing is loading" is true before
      // the loop is even asked for. The length changing is the real signal.
      changedFrom: outLength,
    );

    final loop = state();
    debugPrint(
      'VELORKI_LOOP closed length=${loop.result!.lengthM.round()}m '
      'from=${outLength.round()}m waypoints=${loop.waypoints.length}',
    );
    expect(loop.isClosedLoop, isTrue);
    expect(loop.waypoints.first.pos, loop.waypoints.last.pos);
    expect(loop.waypoints.length, greaterThanOrEqualTo(3));
    expect(loop.result!.lengthM, greaterThan(outLength));
    expect(loop.ridesBackAnotherWay, isTrue);

    // ------------------------------------------------------ another way back
    final firstVariant = loop.options.returnVariant;
    final firstGeometry = loop.result!.geometry;
    await tapAndPump(
      tester,
      find.widgetWithText(OutlinedButton, 'Another way back'),
    );
    // anotherWayBack walks the return variants until one draws a different
    // road, re-routing for each, so the plain "not routing any more" is true
    // between two attempts as well. The road changing is the real signal.
    await waitUntil(
      tester,
      () {
        final now = container.read(plannerControllerProvider);
        if (now.route.hasError) fail('routing failed: ${now.route.error}');
        if (now.isRouting || now.result == null) return false;
        return !_sameGeometry(now.result!.geometry, firstGeometry);
      },
      describe: 'a different way back',
      timeout: const Duration(seconds: 120),
      onTimeout: () => '${container.read(plannerControllerProvider).options}',
    );

    final varied = state();
    debugPrint(
      'VELORKI_LOOP variant $firstVariant -> ${varied.options.returnVariant} '
      'length=${varied.result!.lengthM.round()}m',
    );
    expect(varied.options.returnVariant, isNot(firstVariant));
    expect(varied.isClosedLoop, isTrue);
    expect(
      _sameGeometry(varied.result!.geometry, firstGeometry),
      isFalse,
      reason: 'another way back has to draw another road',
    );
    await screenshot(tester, 'close-loop');

    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Done'));

    // ----------------------------------------------- a loop from a distance
    await tapAndPump(tester, find.widgetWithText(LabeledIconButton, 'Clear'));
    expect(state().isEmpty, isTrue);
    planner.addWaypoint(region.start);
    await pumpFor(tester, const Duration(milliseconds: 500));

    await tapAndPump(tester, find.widgetWithText(LabeledIconButton, 'Loop'));
    await waitForWidget(tester, find.byType(Slider));

    // Move the slider, so the target is the one the rider set rather than the
    // stored default. A Material Slider seeks to wherever it is touched, so a
    // tap near the left of the track is the deterministic way to land on a
    // short loop; the value is read back rather than assumed.
    final track = tester.getRect(find.byType(Slider));
    await tester.tapAt(
      Offset(track.left + track.width * 0.05, track.center.dy),
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    final km = tester.widget<Slider>(find.byType(Slider)).value;
    debugPrint('VELORKI_LOOP slider $_seedLoopKm km -> $km km');
    expect(km, isNot(_seedLoopKm), reason: 'the slider has to move');
    expect(km, lessThanOrEqualTo(40), reason: 'keep the search short');

    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Make a loop'));
    await waitUntil(
      tester,
      () {
        final loopState = container.read(smartLoopControllerProvider);
        if (loopState.error != null) fail('loop search: ${loopState.error}');
        return !loopState.running && loopState.hasSearched;
      },
      describe: 'the loop search to finish',
      timeout: const Duration(minutes: 2),
      onTimeout: () => '${container.read(smartLoopControllerProvider)}',
    );

    final search = container.read(smartLoopControllerProvider);
    expect(search.foundNothing, isFalse, reason: 'no loop found at all');
    final targetM = search.request!.targetM;
    expect(targetM, closeTo(km * 1000, 1), reason: 'the slider set the target');

    final candidate = search.current!;
    final lengthM = candidate.result.lengthM;
    debugPrint(
      'VELORKI_LOOP made target=${targetM.round()}m '
      'length=${lengthM.round()}m '
      'off=${((lengthM - targetM) / targetM * 100).toStringAsFixed(1)}%',
    );
    expect(lengthM, greaterThan(targetM * 0.7));
    expect(lengthM, lessThan(targetM * 1.3));

    // The controller adopts the winning candidate into the plan itself.
    //
    // Note this loop is NOT a `PlannerState.isClosedLoop`: that flag means
    // "the rider's own points come back to the first one", and a from-scratch
    // loop comes out of BRouter's round-trip mode with the handful of points
    // that query carried, not with a start repeated at the end. What has to
    // close is the road, so that is what is checked.
    final adopted = state();
    expect(adopted.result!.lengthM, candidate.result.lengthM);
    final ride = adopted.result!.geometry;
    final gap = haversineMeters(ride.first.pos, ride.last.pos);
    debugPrint(
      'VELORKI_LOOP adopted ${adopted.waypoints.length} waypoints, '
      'the ride closes to within ${gap.round()}m',
    );
    expect(
      gap,
      lessThan(100),
      reason: 'a round trip has to come back to where it started',
    );

    await unmountApp(tester);
  });
}

Future<void> _waitForRoute(
  WidgetTester tester,
  ProviderContainer container,
  String what, {
  double? changedFrom,
}) async {
  // The planner debounces for 300 ms before it asks the backend anything.
  await pumpFor(tester, const Duration(milliseconds: 400));
  await waitUntil(
    tester,
    () {
      final state = container.read(plannerControllerProvider);
      if (state.route.hasError) fail('routing failed: ${state.route.error}');
      if (state.error != null) fail('planner error: ${state.error}');
      final result = state.result;
      if (result == null || state.isRouting) return false;
      return changedFrom == null || result.lengthM != changedFrom;
    },
    describe: what,
    timeout: const Duration(seconds: 90),
    onTimeout: () => '${container.read(plannerControllerProvider)}',
  );
}

bool _sameGeometry(List<TrackPoint> a, List<TrackPoint> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].pos != b[i].pos) return false;
  }
  return true;
}
