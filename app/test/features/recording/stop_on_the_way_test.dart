import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/application/map_stops_controller.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/domain/follow_choice.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/features/search/presentation/place_card.dart';
import 'package:velorki_brouter/velorki_brouter.dart'
    show RoutingErrorKind, RoutingException;
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../planner/support/fakes.dart' show syntheticRoute;
import '../planner/support/pump.dart' show noMirrorOverride;
import 'support/pump.dart';

/// The ends of the route followed here: the synthetic route's diagonal.
const _start = LatLng(48.0, 11.0);
const _end = LatLng(48.04, 11.04);

/// A café beside the middle of the route.
const _cafe = SearchResult(
  name: 'Café Rad',
  position: LatLng(48.02, 11.021),
  source: SearchSource.local,
  kind: SearchKind.poi,
  detail: 'cafe',
);

RecordingSnapshot _riding({LatLng at = const LatLng(48.005, 11.005)}) =>
    RecordingSnapshot(
      rideId: 'ride-1',
      status: RecordingStatus.active,
      startedAt: DateTime.utc(2026, 9, 12, 10),
      distanceM: 500,
      elapsed: const Duration(minutes: 2),
      moving: const Duration(minutes: 2),
      speedMps: 5,
      avgSpeedMps: 5,
      ascentM: 0,
      descentM: 0,
      lastPosition: at,
      accuracyM: 4,
      pointCount: 20,
    );

/// The Record tab with the café among the stops on the map.
Future<RecordingHarness> _pump(WidgetTester tester) => pumpRecordingScreen(
  tester,
  const RecordingScreen(),
  preferences: const <String, Object>{'map.stops.shown': true},
  extraOverrides: [
    noMirrorOverride,
    mapStopsFinderProvider.overrideWithValue(
      (box, kinds, limit, {ranked = false}) async => [
        if (box.contains(_cafe.position) && kinds.contains(_cafe.detail)) _cafe,
      ],
    ),
  ],
);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(RecordingScreen)));

/// Plans the route from [_start] to [_end] on the Plan tab.
Future<void> _plan(WidgetTester tester) async {
  final planner = _container(tester).read(plannerControllerProvider.notifier);
  planner.addWaypoint(_start);
  planner.addWaypoint(_end);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Taps the café on the map: its card comes up.
Future<void> _tapCafe(WidgetTester tester, RecordingHarness h) async {
  final i = h.map.stops.indexWhere((s) => s.name == _cafe.name);
  expect(i, isNot(-1), reason: 'the café is drawn');
  h.map.onStopTapped!(i);
  await tester.pumpAndSettle();
  expect(find.byType(PlaceCard), findsOneWidget);
}

Finder get _addStop => find.descendant(
  of: find.byType(PlaceCard),
  matching: find.text(l10n.placeCardAddStop),
);

/// Adds the café from its card and answers the dialog with [confirm].
Future<void> _addCafe(
  WidgetTester tester,
  RecordingHarness h, {
  required bool confirm,
  bool savedRoute = false,
}) async {
  await _tapCafe(tester, h);
  await tester.tap(_addStop);
  await tester.pumpAndSettle();
  expect(find.text(l10n.recordingAddStopTitle), findsOneWidget);
  expect(find.text(l10n.recordingAddStopBody), findsOneWidget);
  expect(
    find.text(l10n.recordingAddStopSavedBody),
    savedRoute ? findsOneWidget : findsNothing,
  );
  await tester.tap(
    find.text(confirm ? l10n.recordingAddStopConfirm : l10n.commonCancel),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  expect(find.text(l10n.recordingAddStopTitle), findsNothing);
}

/// Opens the café's card and confirms adding it, without waiting for the
/// route.
Future<void> _confirmCafe(WidgetTester tester, RecordingHarness h) async {
  await _tapCafe(tester, h);
  await tester.tap(_addStop);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.recordingAddStopConfirm));
  await tester.pump();
}

/// Every guided route [container] goes through from now on, `null`s too.
List<GuidedRoute?> _watchGuided(ProviderContainer container) {
  final seen = <GuidedRoute?>[];
  final sub = container.listen(
    guidedRouteProvider,
    (previous, next) => seen.add(next),
  );
  addTearDown(sub.close);
  return seen;
}

/// The keys of [routes], each run of the same key once.
List<String?> _keys(List<GuidedRoute?> routes) => [
  for (final (i, r) in routes.indexed)
    if (i == 0 || routes[i - 1]?.key != r?.key) r?.key,
];

const _noRoute = RoutingException(
  kind: RoutingErrorKind.noRoute,
  message: 'no way there',
);

/// The ride far along the route, past the café.
RecordingSnapshot _farAlong() => _riding(at: const LatLng(48.035, 11.035));

void main() {
  testWidgets('the card offers to add the stop only while a ride is recorded '
      'along a followed route', (tester) async {
    final h = await _pump(tester);
    await _plan(tester);

    // Not recording: nothing to do with the stop.
    await _tapCafe(tester, h);
    expect(_addStop, findsNothing);
    await tester.tap(find.byTooltip(l10n.placeCardClose));
    await tester.pumpAndSettle();

    // Recording along the plan: it can be added, and is picked out on the
    // map while its card is open.
    await emitSnapshot(tester, h, _riding());
    await tester.pumpAndSettle();
    await _tapCafe(tester, h);
    expect(_addStop, findsOneWidget);
    expect(h.map.stops.singleWhere((s) => s.name == _cafe.name).selected, true);
    await tester.tap(find.byTooltip(l10n.placeCardClose));
    await tester.pumpAndSettle();

    // Recording without a route: nothing again.
    _container(tester)
        .read(recordingControllerProvider.notifier)
        .choose(FollowChoice.none);
    await tester.pumpAndSettle();
    await _tapCafe(tester, h);
    expect(_addStop, findsNothing);
    await tester.tap(find.byTooltip(l10n.placeCardClose));
    await tester.pumpAndSettle();

    await unmountApp(tester);
  });

  testWidgets('cancelled, the dialog leaves the plan as it was', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _plan(tester);
    await emitSnapshot(tester, h, _riding());
    await tester.pumpAndSettle();
    final container = _container(tester);
    final before = container.read(plannerControllerProvider);
    final guided = container.read(guidedRouteProvider);

    await _addCafe(tester, h, confirm: false);

    final after = container.read(plannerControllerProvider);
    expect(after.waypoints, before.waypoints);
    expect(after.result, same(before.result));
    expect(container.read(guidedRouteProvider)?.key, guided?.key);
    expect(container.read(recordingControllerProvider).isRecording, isTrue);
    expect(h.map.stops.any((s) => s.selected), isFalse);

    await unmountApp(tester);
  });

  testWidgets('following the plan, the stop goes into it where it fits and '
      'the ride is guided along the recalculated route', (tester) async {
    final h = await _pump(tester);
    await _plan(tester);
    await emitSnapshot(tester, h, _riding());
    await tester.pumpAndSettle();
    final container = _container(tester);
    final guided = container.read(guidedRouteProvider)!;
    expect(container.read(navigationControllerProvider), isNotNull);
    final queries = h.planner.backend.callCount;

    await _addCafe(tester, h, confirm: true);

    final plan = container.read(plannerControllerProvider);
    expect(plan.waypoints.map((w) => w.pos), [_start, _cafe.position, _end]);
    expect(plan.waypoints[1].name, _cafe.name);
    // Both legs either side of the stop were routed again.
    expect(h.planner.backend.callCount, queries + 2);
    final now = container.read(guidedRouteProvider)!;
    expect(now.key, isNot(guided.key));
    expect(now.line, plan.result!.positions);
    expect(now.waypoints, [_start, _cafe.position, _end]);
    // The navigator is guiding along it.
    expect(container.read(navigationControllerProvider), isNotNull);
    expect(container.read(activeGuidedRouteProvider)?.key, now.key);
    final recording = container.read(recordingControllerProvider);
    expect(recording.isRecording, isTrue);
    expect(recording.follow, FollowChoice.plan);
    expect(
      h.service.calls.where((c) => c.startsWith('stop') || c == 'halt'),
      isEmpty,
    );

    await unmountApp(tester);
  });

  testWidgets('following a saved route, it opens in the planner with the '
      'stop added and the ride follows that; the saved route stays as it '
      'was', (tester) async {
    final h = await _pump(tester);
    final container = _container(tester);
    final repository = container.read(routeRepositoryProvider);
    final saved = await tester.runAsync(
      () => repository.savePlannedRoute(
        name: 'Isar loop',
        route: syntheticRoute(),
        waypoints: const [
          Waypoint(pos: _start, kind: WaypointKind.start),
          Waypoint(pos: _end, kind: WaypointKind.end),
        ],
        options: const RoutingOptions(),
      ),
    );
    container
        .read(recordingControllerProvider.notifier)
        .choose(FollowSaved(saved!.id));
    await settleAsync(tester);
    await tester.pumpAndSettle();
    await emitSnapshot(tester, h, _riding());
    await tester.pumpAndSettle();
    expect(container.read(guidedRouteProvider)?.key, 'saved:${saved.id}');
    expect(container.read(plannerControllerProvider).waypoints, isEmpty);

    await _addCafe(tester, h, confirm: true, savedRoute: true);
    await settleAsync(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final plan = container.read(plannerControllerProvider);
    expect(plan.savedRouteId, saved.id);
    expect(plan.waypoints.map((w) => w.pos), [_start, _cafe.position, _end]);
    expect(plan.result, isNotNull);
    final recording = container.read(recordingControllerProvider);
    expect(recording.follow, FollowChoice.plan);
    expect(recording.isRecording, isTrue);
    final guided = container.read(guidedRouteProvider)!;
    expect(guided.key, startsWith('plan:'));
    expect(guided.waypoints, [_start, _cafe.position, _end]);

    final stored = await tester.runAsync(() => repository.routeById(saved.id));
    expect(stored!.waypoints.map((w) => w.pos), [_start, _end]);
    expect(stored.updatedAt, saved.updatedAt);

    await unmountApp(tester);
  });

  testWidgets('while the new route is routed, guidance carries on along the '
      'route as it was, and moves to the new one once, when it is there', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _plan(tester);
    await emitSnapshot(tester, h, _riding());
    await tester.pumpAndSettle();
    final container = _container(tester);
    final old = container.read(guidedRouteProvider)!;
    final seen = _watchGuided(container);
    final progress = <Object?>[];
    final sub = container.listen(
      navigationControllerProvider,
      (previous, next) => progress.add(next),
    );
    addTearDown(sub.close);
    h.planner.backend.delay = const Duration(seconds: 2);

    await _confirmCafe(tester, h);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    // Routing still: the plan has the stop, the guidance the old route.
    expect(container.read(plannerControllerProvider).route.isLoading, isTrue);
    expect(container.read(guidedRouteProvider)?.key, old.key);
    expect(container.read(activeGuidedRouteProvider)?.key, old.key);
    expect(container.read(navigationControllerProvider), isNotNull);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final now = container.read(guidedRouteProvider)!;
    expect(now.key, isNot(old.key));
    expect(now.waypoints, [_start, _cafe.position, _end]);
    expect(seen, isNot(contains(null)));
    expect(_keys([old, ...seen]), [old.key, now.key]);
    expect(progress, isNot(contains(null)));
    expect(container.read(navigationControllerProvider), isNotNull);
    expect(container.read(heldGuidedRouteProvider), isNull);
    expect(find.text(l10n.recordingAddStopFailed), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('if the new route cannot be routed, the stop comes out again, '
      'guidance stays on the route as it was, and the rider is told', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _plan(tester);
    await emitSnapshot(tester, h, _riding());
    await tester.pumpAndSettle();
    final container = _container(tester);
    final old = container.read(guidedRouteProvider)!;
    final seen = _watchGuided(container);
    h.planner.backend.error = _noRoute;

    await _addCafe(tester, h, confirm: true);

    final plan = container.read(plannerControllerProvider);
    expect(plan.waypoints.map((w) => w.pos), [_start, _end]);
    expect(plan.result!.positions, old.line);
    expect(container.read(guidedRouteProvider)?.key, old.key);
    expect(seen, isNot(contains(null)));
    expect(_keys([old, ...seen]), [old.key]);
    expect(container.read(navigationControllerProvider), isNotNull);
    expect(
      container.read(recordingControllerProvider).follow,
      FollowChoice.plan,
    );
    expect(find.text(l10n.recordingAddStopFailed), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('a stop beside the part already ridden is not put behind the '
      'rider: the route goes to it from where they are', (tester) async {
    final h = await _pump(tester);
    await _plan(tester);
    await emitSnapshot(tester, h, _riding());
    await tester.pumpAndSettle();
    final container = _container(tester);

    // The card opened near the café; the rider rides on past it before
    // saying yes.
    await _tapCafe(tester, h);
    await tester.tap(_addStop);
    await tester.pumpAndSettle();
    await emitSnapshot(tester, h, _farAlong());
    await tester.pump();
    expect(
      container.read(navigationControllerProvider.notifier).riddenAlongM,
      greaterThan(4000),
    );
    await tester.tap(find.text(l10n.recordingAddStopConfirm));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final waypoints = container
        .read(plannerControllerProvider)
        .waypoints
        .map((w) => w.pos)
        .toList();
    expect(waypoints, hasLength(4));
    expect(waypoints.first, _start);
    expect(waypoints[2], _cafe.position);
    expect(waypoints.last, _end);
    // The point before the café is where the rider is, not the start.
    expect(
      haversineMeters(waypoints[1], _farAlong().lastPosition!),
      lessThan(20),
    );
    expect(find.text(l10n.recordingAddStopFailed), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('following a saved route that cannot be routed with the stop, '
      'the ride follows the saved route again', (tester) async {
    final h = await _pump(tester);
    final container = _container(tester);
    final repository = container.read(routeRepositoryProvider);
    final saved = await tester.runAsync(
      () => repository.savePlannedRoute(
        name: 'Isar loop',
        route: syntheticRoute(),
        waypoints: const [
          Waypoint(pos: _start, kind: WaypointKind.start),
          Waypoint(pos: _end, kind: WaypointKind.end),
        ],
        options: const RoutingOptions(),
      ),
    );
    container
        .read(recordingControllerProvider.notifier)
        .choose(FollowSaved(saved!.id));
    await settleAsync(tester);
    await tester.pumpAndSettle();
    await emitSnapshot(tester, h, _riding());
    await tester.pumpAndSettle();
    final seen = _watchGuided(container);
    h.planner.backend.error = _noRoute;

    await _addCafe(tester, h, confirm: true, savedRoute: true);
    await settleAsync(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final recording = container.read(recordingControllerProvider);
    expect(recording.follow, FollowSaved(saved.id));
    expect(recording.isRecording, isTrue);
    expect(container.read(guidedRouteProvider)?.key, 'saved:${saved.id}');
    expect(seen, isNot(contains(null)));
    expect(_keys(seen), everyElement('saved:${saved.id}'));
    expect(container.read(navigationControllerProvider), isNotNull);
    expect(find.text(l10n.recordingAddStopFailed), findsOneWidget);

    await unmountApp(tester);
  });
}
