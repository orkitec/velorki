import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart' show RouteSource;
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/application/planner_map_binding.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/planner_state.dart';
import 'package:velorki/features/navigation/presentation/turn_phrases.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/planner/presentation/poi_markers.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';

const LatLng _a = LatLng(48.0, 11.0);
const LatLng _b = LatLng(48.2, 11.2);

void main() {
  late FakeRoutingBackend backend;
  late ProviderContainer container;
  late TestMapController map;
  late PlannerMapBinding binding;

  setUp(() async {
    backend = FakeRoutingBackend();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        routingBackendProvider.overrideWithValue(backend),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    map = TestMapController();
    binding = PlannerMapBinding(
      map: map,
      planner: container.read(plannerControllerProvider.notifier),
    )..attach();
    // The screen syncs the current state as soon as the map is ready, which
    // makes it the baseline; only changes from there move the camera.
    await binding.sync(container.read(plannerControllerProvider));
    container.listen<PlannerState>(
      plannerControllerProvider,
      (_, next) => binding.sync(next),
    );
  });

  testWidgets('an avoided stretch is drawn dashed until it is let back on', (
    tester,
  ) async {
    container.read(plannerControllerProvider.notifier)
      ..addWaypoint(_a)
      ..addWaypoint(_b);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    container.read(plannerControllerProvider.notifier).avoidStretch(100, 600);
    await tester.pump();
    expect(map.styles[avoidedLineId(0)], RouteLineStyle.avoided);
    expect(
      map.lines[avoidedLineId(0)],
      container.read(plannerControllerProvider).avoid.single.line,
    );

    container.read(plannerControllerProvider.notifier).clearAvoided();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(map.lines.containsKey(avoidedLineId(0)), isFalse);
  });

  testWidgets('map gestures reach the planner', (tester) async {
    map.onTap!(_a);
    map.onTap!(_b);
    expect(container.read(plannerControllerProvider).positions, [_a, _b]);

    // A long press is the screen's to answer: it opens the sheet for a
    // place there rather than routing through it.
    LatLng? held;
    binding.onLongPress = (pos) => held = pos;
    map.onLongPress!(const LatLng(48.1, 11.1));
    expect(held, const LatLng(48.1, 11.1));
    expect(container.read(plannerControllerProvider).positions, [_a, _b]);

    map.onWaypointDragged!(0, const LatLng(47.5, 10.5));
    expect(
      container.read(plannerControllerProvider).positions.first,
      const LatLng(47.5, 10.5),
    );

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  });

  testWidgets('waypoints and the route line are pushed to the map', (
    tester,
  ) async {
    map.onTap!(_a);
    await tester.pump();
    expect(map.waypoints.single.kind, MapWaypointKind.start);

    map.onTap!(_b);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(map.waypoints.map((w) => w.kind).toList(), [
      MapWaypointKind.start,
      MapWaypointKind.end,
    ]);
    expect(map.lines[mainRouteLineId], isNotNull);
    expect(map.lines[mainRouteLineId], hasLength(5));
    expect(map.styles[mainRouteLineId], RouteLineStyle.main);
  });

  testWidgets('alternatives are drawn in the alternative style', (
    tester,
  ) async {
    map.onTap!(_a);
    map.onTap!(_b);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    await container.read(plannerControllerProvider.notifier).loadAlternatives();
    await tester.pump();

    expect(map.lines[alternativeLineId(0)], isNull, reason: 'the shown one');
    for (final i in [1, 2, 3]) {
      expect(map.styles[alternativeLineId(i)], RouteLineStyle.alternative);
    }

    container.read(plannerControllerProvider.notifier).setAlternative(2);
    await tester.pump();
    expect(map.lines[alternativeLineId(2)], isNull);
    expect(map.styles[alternativeLineId(0)], RouteLineStyle.alternative);
    // The chosen alternative is drawn on top like the main route, under an
    // id that carries its index so it keeps its own colour; the plain main
    // line is gone.
    expect(map.styles[chosenRouteLineId(2)], RouteLineStyle.main);
    expect(map.lines[mainRouteLineId], isNull);
  });

  testWidgets('clearing the plan removes every line', (tester) async {
    map.onTap!(_a);
    map.onTap!(_b);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(map.lines, isNotEmpty);

    container.read(plannerControllerProvider.notifier).clear();
    await tester.pump();

    expect(map.lines, isEmpty);
    expect(map.waypoints, isEmpty);
  });

  testWidgets('a route that appears at once fits the camera to it', (
    tester,
  ) async {
    expect(map.fittedBounds, isNull);

    container
        .read(plannerControllerProvider.notifier)
        .loadSavedRoute(
          SavedRoute(
            id: 'r1',
            name: 'Saved',
            source: RouteSource.planned,
            profile: RouteProfile.trekking,
            createdAt: DateTime(2026, 9, 12),
            updatedAt: DateTime(2026, 9, 12),
            distanceM: 10000,
            ascentM: 120,
            descentM: 80,
            bounds: const BoundingBox(
              south: 48,
              west: 11,
              north: 48.1,
              east: 11.1,
            ),
            geometryBlob: PackedTrack.encode(syntheticRoute().geometry),
            waypoints: const [
              Waypoint(pos: _a, kind: WaypointKind.start),
              Waypoint(pos: _b, kind: WaypointKind.end),
            ],
            options: const RoutingOptions(),
          ),
        );
    await tester.pump();

    expect(map.fittedBounds, isNotNull);
    expect(map.lines[mainRouteLineId], hasLength(5));
  });

  test(
    'a clear does not wipe what the next tab draws right after it',
    () async {
      const place = MapPoi(position: _a, name: 'Tap', kind: MapPoiKind.water);
      const start = MapWaypoint(position: _b, kind: MapWaypointKind.start);

      // The Plan tab leaves; the Record tab draws in the same turn.
      final clearing = binding.clear();
      unawaited(map.setPois(const <MapPoi>[place]));
      unawaited(map.setWaypoints(const <MapWaypoint>[start]));
      await clearing;
      await pumpEventQueue();

      expect(map.pois, const <MapPoi>[place]);
      expect(map.waypoints, const <MapWaypoint>[start]);
    },
  );

  test('a sync still in flight when the screen goes neither asks it for '
      'its padding nor moves the camera', () async {
    final gated = _GatedMapController();
    var asked = 0;
    final owned = PlannerMapBinding(
      map: gated,
      planner: container.read(plannerControllerProvider.notifier),
      // What a disposed screen's padding did: read a context it no longer
      // has.
      fitPadding: () {
        asked++;
        throw StateError('This widget has been unmounted');
      },
    )..attach();
    await owned.sync(const PlannerState());

    // A saved route arrives whole, which fits the camera, and the sync
    // is held up at its first call to the map...
    container.read(plannerControllerProvider.notifier).loadSavedRoute(_saved());
    gated.gate = Completer<void>();
    final syncing = owned.sync(container.read(plannerControllerProvider));
    // ...while the screen is disposed, which detaches the binding.
    owned.detach();
    gated.gate!.complete();
    await syncing;

    expect(asked, 0);
    expect(gated.fittedBounds, isNull);
    expect(gated.lines, isEmpty, reason: 'nothing drawn after the detach');
  });

  testWidgets('the plan\'s places are drawn with their kind icon and go '
      'when the tab leaves the map', (tester) async {
    map.onTap!(_a);
    map.onTap!(_b);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(map.pois, isEmpty);

    container
        .read(plannerControllerProvider.notifier)
        .addPoi(const LatLng(48.1, 11.1), name: 'Tap', kind: PoiKind.water);
    await tester.pump();

    expect(map.pois.single.name, 'Tap');
    expect(map.pois.single.kind, MapPoiKind.water);
    expect(map.pois.single.icon, poiIcon(PoiKind.water));

    // A point on the route that stands for something wears its icon too.
    container
        .read(plannerControllerProvider.notifier)
        .setWaypointDetails(0, name: 'Top', poiKind: PoiKind.summit);
    await tester.pump();
    expect(map.waypoints.first.icon, poiIcon(PoiKind.summit));
    // The destination wears the flag, whatever else it stands for.
    expect(map.waypoints.last.icon, destinationIcon);

    await binding.clear();
    expect(map.pois, isEmpty);
    expect(map.waypoints, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
  });

  test('every screen builds its markers the same way', () {
    // The one rule, in one place: a kind puts the icon on the disc and the
    // number in the name; a plain point keeps the number on the disc.
    final points = waypointMarkers(const [
      Waypoint(pos: _a, kind: WaypointKind.start, name: 'Home'),
      Waypoint(pos: LatLng(48.1, 11.1), name: 'Pico', poiKind: PoiKind.summit),
      Waypoint(pos: _b, kind: WaypointKind.end),
    ], selected: 1);

    expect(points.map((w) => w.label), ['Home', 'Pico', null]);
    expect(points.map((w) => w.icon), [
      isNull,
      poiIcon(PoiKind.summit),
      destinationIcon,
    ], reason: 'the destination wears the flag');
    expect(points.map((w) => w.selected), [false, true, false]);
    expect(points.map((w) => w.kind), [
      MapWaypointKind.start,
      MapWaypointKind.via,
      MapWaypointKind.end,
    ]);
    // A turn is a cue of the route, not a place, so it wears no icon.
    expect(
      waypointMarkers(const [
        Waypoint(pos: _a, poiKind: PoiKind.turn, name: 'Left at the mill'),
      ]).single.icon,
      isNull,
    );
    // The ends of a route read from a file are the same markers.
    final ends = endMarkers(start: _a, finish: _b, finishSelected: true);
    expect(ends.map((w) => w.kind), [
      MapWaypointKind.start,
      MapWaypointKind.end,
    ]);
    expect(ends.map((w) => w.icon), [isNull, destinationIcon]);
    expect(ends.map((w) => w.selected), [false, true]);
  });

  testWidgets('detaching stops the gestures', (tester) async {
    binding.detach();
    expect(map.onTap, isNull);
    expect(map.onLongPress, isNull);
    expect(map.onWaypointDragged, isNull);
    expect(map.onPoiTapped, isNull);
  });

  group('while an edit is routed', () {
    late _HeldBackend held;
    late ProviderContainer planner;
    late TestMapController drawn;
    const moved = LatLng(48.3, 11.3);

    PlannerController controller() =>
        planner.read(plannerControllerProvider.notifier);

    /// Plans A to B and answers it, so a route is on the map.
    Future<void> routed(WidgetTester tester) async {
      drawn.onTap!(_a);
      drawn.onTap!(_b);
      await tester.pump(plannerDebounce);
      held.answer(0);
      await tester.pump();
      expect(drawn.lines[mainRouteLineId], [_a, _mid(_a, _b), _b]);
    }

    setUp(() async {
      held = _HeldBackend();
      final prefs = await SharedPreferences.getInstance();
      planner = ProviderContainer(
        overrides: [
          routingBackendProvider.overrideWithValue(held),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(planner.dispose);
      drawn = TestMapController();
      final bound = PlannerMapBinding(
        map: drawn,
        planner: planner.read(plannerControllerProvider.notifier),
      )..attach();
      await bound.sync(planner.read(plannerControllerProvider));
      planner.listen<PlannerState>(
        plannerControllerProvider,
        (_, next) => bound.sync(next),
      );
    });

    testWidgets('the old line stays, dimmed, until the answer replaces it', (
      tester,
    ) async {
      await routed(tester);
      final since = drawn.calls.length;

      controller().moveWaypoint(1, moved);
      await tester.pump();
      expect(planner.read(plannerControllerProvider).isRouting, isTrue);
      expect(drawn.lines[mainRouteLineId], [_a, _mid(_a, _b), _b]);
      expect(drawn.styles[mainRouteLineId], RouteLineStyle.stale);

      await tester.pump(plannerDebounce);
      expect(drawn.styles[mainRouteLineId], RouteLineStyle.stale);

      held.answer(1);
      await tester.pump();
      expect(drawn.lines[mainRouteLineId], [_a, _mid(_a, moved), moved]);
      expect(drawn.styles[mainRouteLineId], RouteLineStyle.main);
      // Swapped in place: the line was never taken off in between.
      expect(
        drawn.calls
            .skip(since)
            .where((c) => c.method == 'removeRouteLine')
            .toList(),
        isEmpty,
      );
    });

    testWidgets('a failed edit takes the old line off', (tester) async {
      await routed(tester);

      controller().moveWaypoint(1, moved);
      await tester.pump(plannerDebounce);
      expect(drawn.styles[mainRouteLineId], RouteLineStyle.stale);

      held.fail(1);
      await tester.pump();
      expect(planner.read(plannerControllerProvider).error, isNotNull);
      expect(drawn.lines, isEmpty);

      // The next edit that routes has nothing old to keep.
      controller().moveWaypoint(1, _b);
      await tester.pump();
      expect(drawn.lines, isEmpty);
      await tester.pump(plannerDebounce);
      held.answer(2);
      await tester.pump();
      expect(drawn.styles[mainRouteLineId], RouteLineStyle.main);
    });

    testWidgets('clearing while routing takes the line off at once', (
      tester,
    ) async {
      await routed(tester);

      controller().moveWaypoint(1, moved);
      await tester.pump(plannerDebounce);
      expect(drawn.lines[mainRouteLineId], isNotNull);

      controller().clear();
      await tester.pump();
      expect(drawn.lines, isEmpty);

      // The answer to the edit that was cleared away draws nothing.
      held.answer(1);
      await tester.pump();
      expect(drawn.lines, isEmpty);

      // Undo puts the edit back, whose route never came: routed afresh,
      // with the cleared line nowhere, then drawn once it is there.
      controller().undo();
      await tester.pump();
      expect(drawn.lines, isEmpty);
      await tester.pump(plannerDebounce);
      held.answer(2);
      await tester.pump();
      expect(drawn.lines[mainRouteLineId], [_a, _mid(_a, moved), moved]);
      expect(drawn.styles[mainRouteLineId], RouteLineStyle.main);

      // And the step before it brings its own route back at once.
      controller().undo();
      await tester.pump();
      expect(drawn.lines[mainRouteLineId], [_a, _mid(_a, _b), _b]);
      expect(drawn.styles[mainRouteLineId], RouteLineStyle.main);
    });

    testWidgets('a late answer to a superseded edit is never drawn', (
      tester,
    ) async {
      await routed(tester);
      const later = LatLng(48.4, 11.4);

      controller().moveWaypoint(1, moved);
      await tester.pump(plannerDebounce);
      controller().moveWaypoint(1, later);
      await tester.pump(plannerDebounce);
      expect(held.queries, hasLength(3));

      held.answer(2);
      await tester.pump();
      expect(drawn.lines[mainRouteLineId], [_a, _mid(_a, later), later]);

      // The older request comes back last, as if it had not been cancelled.
      held.answer(1);
      await tester.pump();
      expect(drawn.lines[mainRouteLineId], [_a, _mid(_a, later), later]);
      expect(drawn.styles[mainRouteLineId], RouteLineStyle.main);
    });

    testWidgets('a switch of profile keeps the old line dimmed too', (
      tester,
    ) async {
      await routed(tester);

      controller().setProfile(RouteProfile.values.last);
      await tester.pump(plannerDebounce);
      expect(drawn.styles[mainRouteLineId], RouteLineStyle.stale);

      held.answer(1);
      await tester.pump();
      expect(drawn.styles[mainRouteLineId], RouteLineStyle.main);
    });
  });
}

/// The point halfway between [a] and [b], as [_HeldBackend] draws it.
LatLng _mid(LatLng a, LatLng b) =>
    LatLng((a.lat + b.lat) / 2, (a.lon + b.lon) / 2);

/// A router that answers only when the test says so, in any order, and
/// ignores cancellation: the planner alone must keep a late answer off the
/// map. Each answer is a line through the query's points, via the midpoint.
class _HeldBackend implements RoutingBackend {
  /// Every query that arrived, in order.
  final List<RouteQuery> queries = <RouteQuery>[];
  final List<Completer<RouteResult>> _answers = <Completer<RouteResult>>[];

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) {
    queries.add(q);
    final answer = Completer<RouteResult>();
    _answers.add(answer);
    return answer.future;
  }

  /// Answers query [index].
  void answer(int index) {
    final points = queries[index].points;
    _answers[index].complete(
      RouteResult(
        geometry: [
          TrackPoint(points.first),
          TrackPoint(_mid(points.first, points.last)),
          TrackPoint(points.last),
        ],
        lengthM: 1000,
        ascentM: 0,
        descentM: 0,
        messages: const <SegmentMessage>[],
        raw: const <String, dynamic>{},
      ),
    );
  }

  /// Fails query [index] with no route found.
  void fail(int index) => _answers[index].completeError(
    const RoutingException(kind: RoutingErrorKind.noRoute, message: 'no way'),
  );
}

/// A saved route of two points, whole.
SavedRoute _saved() => SavedRoute(
  id: 'r2',
  name: 'Saved',
  source: RouteSource.planned,
  profile: RouteProfile.trekking,
  createdAt: DateTime(2026, 9, 12),
  updatedAt: DateTime(2026, 9, 12),
  distanceM: 10000,
  ascentM: 0,
  descentM: 0,
  bounds: const BoundingBox(south: 48, west: 11, north: 48.1, east: 11.1),
  geometryBlob: PackedTrack.encode(syntheticRoute().geometry),
  waypoints: const [
    Waypoint(pos: _a, kind: WaypointKind.start),
    Waypoint(pos: _b, kind: WaypointKind.end),
  ],
  options: const RoutingOptions(),
);

/// A map whose markers wait for [gate], as a real one waits for its
/// platform channel.
class _GatedMapController extends TestMapController {
  Completer<void>? gate;

  @override
  Future<void> setWaypoints(List<MapWaypoint> waypoints) async {
    await gate?.future;
    return super.setWaypoints(waypoints);
  }
}
