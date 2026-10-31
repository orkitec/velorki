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

RecordingSnapshot _riding() => RecordingSnapshot(
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
  lastPosition: const LatLng(48.005, 11.005),
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
}
