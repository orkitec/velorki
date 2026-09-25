// Leaving the route on the simulator's own GPS, once in each re-routing
// mode: a route planned on the device, the simulated rider riding it, off it
// for most of a kilometre and back onto it, with the lines on the map, the
// banner and the routing asked of the device held to what the mode
// promises. Skipped off iOS, because only the simulator can be driven along
// a scripted path (tool/sim_ride.py).
//
// The rider is held away from the route — riding to and fro a stretch of
// street well off it — until every check about being away has been made,
// and only then sent home: nothing here depends on how fast the machine
// running it is.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/map/presentation/map_view.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/navigation/application/off_route_machine.dart'
    show detourAfter;
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/navigation/domain/off_route_guidance.dart';
import 'package:velorki/features/navigation/presentation/turn_banner.dart';
import 'package:velorki/features/navigation/presentation/turn_phrases.dart';
import 'package:velorki/features/navigation/testing/fake_turn_speaker.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/presentation/planner_map_host.dart';
import 'package:velorki/features/planner/presentation/poi_markers.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/recording/presentation/save_ride_sheet.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';
import 'support/sim_gps.dart';
import 'support/tiles.dart';

/// The planned ride, through streets with other streets beside them: the
/// region's own start is on a mountain road with nowhere to go but back.
(LatLng, LatLng) get _plan => region.name == 'madeira'
    // Funchal, the Lido road to the Sé cathedral.
    ? (const LatLng(32.6405, -16.9290), const LatLng(32.6477, -16.9086))
    // Penn Station to Madison Square Park.
    : (const LatLng(40.7506, -73.9935), const LatLng(40.7424, -73.9881));

/// Where the rider leaves it, and how long a stretch of it they ride round.
const List<double> _leaveAtM = <double>[300, 500, 700];
const double _roundM = 800;

/// How far to the side the way round goes.
const List<double> _asidesM = <double>[200, 300, 400];

/// How long a stretch of street the rider is held on while away.
const double _holdM = 80;

/// The simulated rider's pace: brisk, so three rides fit the suite's budget,
/// and still slow enough that every threshold is met in its own time.
const double _speedMps = 10;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in RerouteMode.values) {
    testWidgets('leaving the route on the simulator GPS: ${mode.name}', (
      tester,
    ) async {
      if (!Platform.isIOS) {
        markTestSkipped('needs the iOS simulator and tool/sim_ride.py');
        return;
      }
      await _leaveAndComeBack(tester, mode);
    });
  }
}

Future<void> _leaveAndComeBack(WidgetTester tester, RerouteMode mode) async {
  RecordingRecovery.overrideWith(
    Future<RecoveryResult>.value(const NoRecovery()),
  );
  addTearDown(RecordingRecovery.reset);
  final maps = <RecordingMapController>[];
  final router = _CountingRouter();
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
      routingBackendProvider.overrideWith((ref) {
        router.inner = routingBackend(ref);
        return router.inner == null ? null : router;
      }),
      locationPermissionGatewayProvider.overrideWithValue(
        const GrantedLocationPermission(),
      ),
      notificationPermissionProvider.overrideWithValue(
        const GrantedNotificationPermission(),
      ),
      batteryOptimizationProvider.overrideWithValue(
        const ExemptBatteryOptimization(),
      ),
      screenWakeProvider.overrideWithValue(RecordingScreenWake()),
      turnSpeakerProvider.overrideWithValue(FakeTurnSpeaker()),
      recordingRecoveryProvider.overrideWith((ref) async => const NoRecovery()),
    ],
  );
  await ensureRegionTile(tester, container);
  final settings = container.read(navigationSettingsProvider.notifier);
  await settings.setTurns(true);
  await settings.setVoice(false);
  await settings.setRerouteMode(mode);

  // ------------------------------------------------------------- the plan
  final planner = container.read(plannerControllerProvider.notifier);
  planner
    ..addWaypoint(_plan.$1)
    ..addWaypoint(_plan.$2);
  final line = (await _routed(tester, container, 'the ride')).positions;

  // ------------------------------------------------ the way the rider rides
  final (:away, :home) = await _wayRound(router.inner!, line);
  debugPrint(
    'VELORKI_REROUTE ${mode.name}: plan ${polylineLengthMeters(line).round()} '
    'm, home ${polylineLengthMeters(home).round()} m',
  );
  await rideSimulatorAlong(tester, away, speedMps: _speedMps);

  await tapAndPump(tester, find.text('Record'));
  final sheet = find
      .descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.dragUntilVisible(
    find.widgetWithText(FilledButton, 'Start ride'),
    sheet,
    const Offset(0, 220),
  );
  await tapAndPump(tester, find.widgetWithText(FilledButton, 'Start ride'));
  await waitForWidget(tester, find.text('RECORDING'));
  final l10n = AppLocalizations.of(tester.element(find.text('RECORDING')));
  final units = container.read(unitSystemProvider);
  await waitUntil(
    tester,
    () => _progress(tester)?.offRoute == false,
    describe: 'the rider to be on the route',
    timeout: const Duration(seconds: 60),
    onTimeout: () => '${_progress(tester)}',
  );
  // Everything asked of the router from here on is the ride's.
  router.calls = 0;
  RecordingMapController map() => maps.last;
  expect(map().lines[followedRouteLineId], isNotEmpty);
  // The plan's own points are on the map too: the start, behind the rider
  // now, and the destination with its flag.
  await waitUntil(
    tester,
    () => map().waypoints.length == 2 && map().waypoints.first.passed,
    describe: 'the start and the destination on the map',
    onTimeout: () => '${map().waypoints}',
  );
  expect(map().waypoints.last.kind, MapWaypointKind.end);
  expect(map().waypoints.last.icon, destinationIcon);
  expect(map().waypoints.last.passed, isFalse);

  // ----------------------------------------------------- off the route
  await waitUntil(
    tester,
    () => _progress(tester)?.offRouteState == OffRouteState.guiding,
    describe: 'the rider to be off the route',
    timeout: const Duration(seconds: 150),
    onTimeout: () => '${_progress(tester)}',
  );
  final leftAt = DateTime.now();
  // The banner in the tree was built from this progress: the way back as a
  // distance and a direction, whatever the mode.
  final guided = _progress(tester)!;
  final guidance = guided.guidance!;
  expect(find.text(backToRouteLabel(guidance.direction, l10n)), findsOneWidget);
  expect(
    find.text(distanceLabel(guidance.distanceM, l10n, units)),
    findsOneWidget,
  );
  await screenshot(tester, 'reroute-${mode.name}-off');

  switch (mode) {
    case RerouteMode.guideBack:
      await waitUntil(
        tester,
        () => container.read(detourRouteProvider) != null,
        describe: 'a way back',
        timeout: const Duration(seconds: 90),
        onTimeout: () => '${_progress(tester)} calls=${router.calls}',
      );
      final wayBack = container.read(detourRouteProvider)!;
      expect(wayBack.replacesPlan, isFalse, reason: 'the plan is kept');
      await waitUntil(
        tester,
        () => map().lines[detourRouteLineId]?.isNotEmpty ?? false,
        describe: 'the way back on the map',
        onTimeout: () => '${map().lines.keys}',
      );
      // The plan stays drawn, the way back beside it, nothing faint.
      expect(map().lines[followedRouteLineId], hasLength(line.length));
      expect(map().lines.containsKey(replacedRouteLineId), isFalse);
      // The banner follows the way back: a turn on it, not "off route".
      expect(find.text(l10n.navOffRoute), findsNothing);
      expect(router.calls, greaterThan(0));
      await screenshot(tester, 'reroute-${mode.name}-way-back');

      // Back on the plan, the way back is gone and the plan carries on.
      await rideSimulatorAlong(tester, home, speedMps: _speedMps);
      await waitUntil(
        tester,
        () =>
            container.read(detourRouteProvider) == null &&
            _progress(tester)?.offRouteState == OffRouteState.onRoute,
        describe: 'the rider back on the plan',
        timeout: const Duration(seconds: 150),
        onTimeout: () => '${_progress(tester)}',
      );
      await pumpFor(tester, const Duration(seconds: 1));
      expect(map().lines.containsKey(detourRouteLineId), isFalse);
      expect(map().lines[followedRouteLineId], hasLength(line.length));
      expect(_progress(tester)!.offRoute, isFalse);
    case RerouteMode.newRoute:
      await waitUntil(
        tester,
        () => container.read(detourRouteProvider)?.replacesPlan ?? false,
        describe: 'a new route to the destination',
        timeout: const Duration(seconds: 90),
        onTimeout: () => '${_progress(tester)} calls=${router.calls}',
      );
      final fresh = container.read(detourRouteProvider)!;
      await waitUntil(
        tester,
        () => map().lines[replacedRouteLineId]?.isNotEmpty ?? false,
        describe: 'the old plan faint under the new route',
        onTimeout: () => '${map().lines.keys}',
      );
      // The new route is the route now; the old one faint, no branch.
      expect(map().lines[followedRouteLineId], hasLength(fresh.line.length));
      expect(map().lines[replacedRouteLineId], hasLength(line.length));
      expect(map().lines.containsKey(detourRouteLineId), isFalse);
      expect(_progress(tester)!.offRoute, isFalse);
      expect(find.text(l10n.navOffRoute), findsNothing);
      await screenshot(tester, 'reroute-${mode.name}-new-route');

      // Held within a short stretch of street, the rider cannot get the
      // 300 m from where the new route started that another would take,
      // whatever they do on it: none is asked for.
      final asked = router.calls;
      await pumpFor(tester, const Duration(seconds: 30));
      expect(router.calls, asked, reason: 'no re-planning loop');
      await rideSimulatorAlong(tester, home, speedMps: _speedMps);
    case RerouteMode.off:
      // Away longer than a way back or a new route would wait for, counted
      // from leaving and checked all the while: off the route, guided, and
      // nothing routed or drawn.
      while (DateTime.now().difference(leftAt) <
          detourAfter + const Duration(seconds: 15)) {
        await pumpFor(tester, const Duration(seconds: 5));
        final progress = _progress(tester)!;
        expect(progress.offRoute, isTrue);
        expect(progress.guidance, isNotNull);
        expect(container.read(detourRouteProvider), isNull);
        expect(map().lines.containsKey(detourRouteLineId), isFalse);
        expect(map().lines.containsKey(replacedRouteLineId), isFalse);
        expect(
          find.text(backToRouteLabel(progress.guidance!.direction, l10n)),
          findsOneWidget,
        );
      }
      expect(router.calls, 0, reason: "don't re-route asks for nothing");
      await rideSimulatorAlong(tester, home, speedMps: _speedMps);
      await waitUntil(
        tester,
        () => _progress(tester)?.offRouteState == OffRouteState.onRoute,
        describe: 'the rider back on the plan',
        timeout: const Duration(seconds: 150),
        onTimeout: () => '${_progress(tester)}',
      );
      expect(router.calls, 0, reason: "don't re-route asks for nothing");
      expect(map().lines[followedRouteLineId], hasLength(line.length));
  }
  debugPrint('VELORKI_REROUTE ${mode.name}: ${router.calls} routing calls');

  await tapAndPump(
    tester,
    find.byTooltip('Finish'),
    settle: const Duration(seconds: 2),
  );
  await waitForWidget(tester, find.byType(SaveRideSheet));
  await tapAndPump(
    tester,
    find.widgetWithText(FilledButton, 'Save'),
    settle: const Duration(seconds: 2),
  );
  await waitUntil(
    tester,
    () => !container.read(recordingControllerProvider).isRecording,
    describe: 'the ride to finish',
  );
  // The simulated rider goes back to the runner's own ride, at its own
  // pace, which is what the tests after this one ride on.
  await rideSimulatorAlong(tester, <LatLng>[
    region.start,
    region.via,
    region.end,
  ]);
  await unmountApp(tester);
}

/// The ride in two legs. [away]: [line] up to a point, then a way round a
/// stretch of it through two points to one side as far as its furthest
/// point from [line], and then to and fro the last stretch of street before
/// that point for ten minutes, which holds the rider off the route for as
/// long as the test needs. [home]: from that point along the rest of the way
/// round, back onto [line] and on to its end.
///
/// Only a way round that really leaves: at least 150 m from the plan, and
/// more than 60 m from it within 250 m of leaving, rather than following the
/// plan most of the way and looping out at the end.
Future<({List<LatLng> away, List<LatLng> home})> _wayRound(
  RoutingBackend router,
  List<LatLng> line,
) async {
  final cumulative = <double>[0];
  for (var i = 1; i < line.length; i++) {
    cumulative.add(cumulative.last + haversineMeters(line[i - 1], line[i]));
  }
  double offPlan(LatLng p) {
    var nearest = double.infinity;
    for (final q in line) {
      final d = haversineMeters(p, q);
      if (d < nearest) nearest = d;
    }
    return nearest;
  }

  for (final leaveM in _leaveAtM) {
    final backM = leaveM + _roundM;
    if (backM > cumulative.last - 100) continue;
    final leave = _pointAlong(line, leaveM);
    final back = _pointAlong(line, backM);
    final heading = bearingDegrees(leave, back);
    for (final asideM in _asidesM) {
      for (final side in const <double>[90, -90]) {
        // Out early and back late: two points to the side, a third and two
        // thirds of the way along the stretch.
        final out = destinationPoint(
          _pointAlong(line, leaveM + _roundM / 3),
          heading + side,
          asideM,
        );
        final home = destinationPoint(
          _pointAlong(line, leaveM + _roundM * 2 / 3),
          heading + side,
          asideM,
        );
        final RouteResult round;
        try {
          round = await router.route(
            RouteQuery(
              points: <LatLng>[leave, out, home, back],
              profile: RouteProfile.trekking.engineName,
              alternativeIdx: 0,
            ),
          );
        } on RoutingException {
          continue;
        }
        final around = round.positions;
        if (polylineLengthMeters(around) > 4 * _roundM) continue;
        var furthest = 0.0;
        var furthestAt = 0;
        double? leftAtM;
        var ridden = 0.0;
        for (var i = 0; i < around.length; i++) {
          if (i > 0) ridden += haversineMeters(around[i - 1], around[i]);
          final off = offPlan(around[i]);
          if (off > furthest) {
            furthest = off;
            furthestAt = i;
          }
          if (off > 60) leftAtM ??= ridden;
        }
        if (furthest < 150 || leftAtM == null || leftAtM > 250) continue;
        // The stretch to hold the rider on: up to [_holdM] of the way
        // round just before its furthest point, all of it well off the
        // plan. Short, so riding it to and fro never takes the rider the
        // 300 m from one spot that would earn another way back or route.
        final hold = <LatLng>[around[furthestAt]];
        var held = 0.0;
        for (var i = furthestAt - 1; i >= 0; i--) {
          if (offPlan(around[i]) < 100) break;
          held += haversineMeters(around[i + 1], around[i]);
          hold.add(around[i]);
          if (held >= _holdM) break;
        }
        if (held < 20) continue;
        final laps = (_speedMps * 600 / (2 * held)).ceil();
        return (
          away: <LatLng>[
            for (var i = 0; i < line.length; i++)
              if (cumulative[i] < leaveM) line[i],
            ...around.sublist(0, furthestAt + 1),
            for (var lap = 0; lap < laps; lap++) ...[
              ...hold.skip(1),
              ...hold.reversed.skip(1),
            ],
          ],
          home: <LatLng>[
            ...around.sublist(furthestAt),
            for (var i = 0; i < line.length; i++)
              if (cumulative[i] > backM) line[i],
          ],
        );
      }
    }
  }
  fail('no way round the plan that really leaves it');
}

/// Hands every query to the app's own router and counts them.
class _CountingRouter implements RoutingBackend {
  RoutingBackend? inner;
  int calls = 0;

  @override
  Future<RouteResult> route(RouteQuery query, {CancelToken? cancel}) {
    calls++;
    return inner!.route(query, cancel: cancel);
  }
}

NavigationProgress? _progress(WidgetTester tester) {
  final banner = find.byType(TurnBanner).evaluate();
  if (banner.isEmpty) return null;
  return (banner.first.widget as TurnBanner).progress;
}

Future<RouteResult> _routed(
  WidgetTester tester,
  ProviderContainer container,
  String describe,
) async {
  await pumpFor(tester, const Duration(milliseconds: 400));
  await waitUntil(
    tester,
    () {
      final state = container.read(plannerControllerProvider);
      if (state.route.hasError) fail('routing failed: ${state.route.error}');
      return state.result != null && !state.isRouting;
    },
    describe: 'the on-device router to answer for $describe',
    timeout: const Duration(seconds: 90),
    onTimeout: () => '${container.read(plannerControllerProvider).route}',
  );
  return container.read(plannerControllerProvider).result!;
}

LatLng _pointAlong(List<LatLng> line, double metres) {
  var covered = 0.0;
  for (var i = 1; i < line.length; i++) {
    covered += haversineMeters(line[i - 1], line[i]);
    if (covered >= metres) return line[i];
  }
  return line.last;
}
