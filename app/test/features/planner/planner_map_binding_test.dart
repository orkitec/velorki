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
        .setWaypointDetails(1, name: 'Top', poiKind: PoiKind.summit);
    await tester.pump();
    expect(map.waypoints.last.icon, poiIcon(PoiKind.summit));
    expect(map.waypoints.first.icon, isNull, reason: 'a plain point');

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
    expect(points.map((w) => w.icon != null), [false, true, false]);
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
    // The ends of a route read from a file are the same plain markers.
    final ends = endMarkers(start: _a, finish: _b, finishSelected: true);
    expect(ends.map((w) => w.kind), [
      MapWaypointKind.start,
      MapWaypointKind.end,
    ]);
    expect(ends.map((w) => w.icon), [isNull, isNull]);
    expect(ends.map((w) => w.selected), [false, true]);
  });

  testWidgets('detaching stops the gestures', (tester) async {
    binding.detach();
    expect(map.onTap, isNull);
    expect(map.onLongPress, isNull);
    expect(map.onWaypointDragged, isNull);
    expect(map.onPoiTapped, isNull);
  });
}
