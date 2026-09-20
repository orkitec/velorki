import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';

const List<Waypoint> _waypoints = [
  Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start, name: 'Home'),
  Waypoint(pos: LatLng(48.2, 11.2), kind: WaypointKind.via),
  Waypoint(pos: LatLng(48.4, 11.4), kind: WaypointKind.end),
];

void main() {
  late VelorkiDatabase db;
  late RouteRepository repository;

  setUp(() {
    db = VelorkiDatabase.memory();
    repository = RouteRepository(
      db.routesDao,
      clock: () => DateTime.utc(2026, 9, 12, 10),
    );
  });

  tearDown(() => db.close());

  test('save and load round trip', () async {
    final route = syntheticRoute();

    final saved = await repository.savePlannedRoute(
      name: 'Isar loop',
      route: route,
      waypoints: _waypoints,
      options: const RoutingOptions(
        profile: RouteProfile.gravel,
        alternativeIdx: 2,
      ),
    );

    final loaded = await repository.routeById(saved.id);
    expect(loaded, isNotNull);
    expect(loaded!.name, 'Isar loop');
    expect(loaded.source, RouteSource.planned);
    expect(loaded.profile, RouteProfile.gravel);
    expect(loaded.options.alternativeIdx, 2);
    expect(loaded.distanceM, route.lengthM);
    expect(loaded.ascentM, route.ascentM);
    expect(loaded.descentM, route.descentM);
    expect(loaded.createdAt, DateTime.utc(2026, 9, 12, 10));

    expect(loaded.waypoints, hasLength(3));
    expect(loaded.waypoints.first.name, 'Home');
    expect(loaded.waypoints.first.kind, WaypointKind.start);
    expect(loaded.waypoints.last.kind, WaypointKind.end);
    expect(
      loaded.waypoints.map((w) => w.pos).toList(),
      _waypoints.map((w) => w.pos).toList(),
    );

    final geometry = loaded.geometry;
    expect(geometry, hasLength(route.geometry.length));
    expect(geometry.first.pos, route.geometry.first.pos);
    expect(geometry.last.ele, route.geometry.last.ele);

    expect(loaded.bounds.south, route.bounds!.south);
    expect(loaded.bounds.east, route.bounds!.east);

    expect(loaded.surfaceStats, isNotNull);
    expect(
      loaded.surfaceStats!.pavedShare,
      closeTo(route.surfaceStats.pavedShare, 1e-9),
    );
    expect(
      loaded.surfaceStats!.unpavedShare,
      closeTo(route.surfaceStats.unpavedShare, 1e-9),
    );

    // 10 km at the gravel profile's 16 km/h.
    expect(loaded.estimatedTime, const Duration(seconds: 2250));
  });

  test('saving with an existing id updates that row', () async {
    final first = await repository.savePlannedRoute(
      name: 'First',
      route: syntheticRoute(),
      waypoints: _waypoints,
      options: const RoutingOptions(),
    );

    final second = await repository.savePlannedRoute(
      name: 'Second',
      route: syntheticRoute(lengthM: 20000),
      waypoints: _waypoints,
      options: const RoutingOptions(),
      id: first.id,
    );

    expect(second.id, first.id);
    expect(second.createdAt, first.createdAt);
    expect(await db.routesDao.allRoutes(), hasLength(1));
    expect((await repository.routeById(first.id))!.name, 'Second');
    expect((await repository.routeById(first.id))!.distanceM, 20000);
  });

  test('watchRoutes emits the library, newest first', () async {
    final stream = repository.watchRoutes();
    await repository.savePlannedRoute(
      name: 'One',
      route: syntheticRoute(),
      waypoints: _waypoints,
      options: const RoutingOptions(),
    );

    expect((await stream.first).single.name, 'One');
  });

  test('delete, restore and rename', () async {
    final saved = await repository.savePlannedRoute(
      name: 'Throwaway',
      route: syntheticRoute(),
      waypoints: _waypoints,
      options: const RoutingOptions(),
    );

    await repository.delete(saved.id);
    expect(await repository.routeById(saved.id), isNull);

    await repository.restore(saved);
    expect((await repository.routeById(saved.id))!.name, 'Throwaway');

    await repository.rename(saved.id, 'Kept');
    expect((await repository.routeById(saved.id))!.name, 'Kept');

    // Renaming an unknown route is a no-op.
    await repository.rename('nope', 'Kept');
  });

  test('a route without way tags stores no surface statistics', () async {
    final saved = await repository.savePlannedRoute(
      name: 'Bare',
      route: syntheticRoute(withMessages: false),
      waypoints: _waypoints,
      options: const RoutingOptions(),
    );

    expect((await repository.routeById(saved.id))!.surfaceStats, isNull);
  });

  test('the turn instructions survive a save and a load', () async {
    const turns = <TurnHint>[
      TurnHint(
        pointIndex: 1,
        kind: TurnKind.right,
        distanceToNextM: 120.5,
        angleDeg: 88,
      ),
      TurnHint(
        pointIndex: 3,
        kind: TurnKind.roundabout,
        exitNumber: 2,
        distanceToNextM: 40,
        angleDeg: -95,
      ),
      TurnHint(
        pointIndex: 4,
        kind: TurnKind.end,
        note: 'Finish line at the café',
      ),
    ];

    final saved = await repository.savePlannedRoute(
      name: 'Turny',
      route: syntheticRoute(turns: turns),
      waypoints: _waypoints,
      options: const RoutingOptions(),
    );

    expect(saved.turns, turns);
    expect((await repository.routeById(saved.id))!.turns, turns);
  });

  test('the points of interest survive a save and a load', () async {
    const pois = <RoutePoi>[
      RoutePoi(
        pos: LatLng(48.001, 11.001),
        name: 'START DISMOUNT ZONE',
        description: 'All riders must dismount',
        kind: PoiKind.danger,
      ),
      RoutePoi(
        pos: LatLng(48.02, 11.02),
        name: 'Water Fountain',
        kind: PoiKind.water,
      ),
    ];

    final saved = await repository.saveImportedRoute(
      name: 'Ride Queens',
      points: syntheticRoute().geometry,
      source: RouteSource.importedGpx,
      pois: pois,
    );

    expect(saved.pois, pois);
    expect((await repository.routeById(saved.id))!.pois, pois);
    // A planned route has none, and its column stays empty.
    final planned = await repository.savePlannedRoute(
      name: 'Plain',
      route: syntheticRoute(),
      waypoints: _waypoints,
      options: const RoutingOptions(),
    );
    expect((await repository.routeById(planned.id))!.pois, isEmpty);
  });

  test('a route without turn instructions leaves the column null', () async {
    final saved = await repository.savePlannedRoute(
      name: 'Silent',
      route: syntheticRoute(),
      waypoints: _waypoints,
      options: const RoutingOptions(),
    );

    expect((await db.routesDao.routeById(saved.id))!.turnsJson, isNull);
    expect((await repository.routeById(saved.id))!.turns, isEmpty);
  });

  test('an imported route has no turns and still saves', () async {
    final saved = await repository.saveImportedRoute(
      name: 'From a file',
      points: syntheticRoute().geometry,
      source: RouteSource.importedGpx,
    );

    expect(saved.turns, isEmpty);
    expect((await repository.routeById(saved.id))!.turns, isEmpty);
  });

  test('unreadable JSON columns degrade to empty defaults', () {
    expect(decodeWaypoints('not json'), isEmpty);
    expect(decodeWaypoints('{}'), isEmpty);
    expect(decodeOptions('nonsense'), const RoutingOptions());
    expect(decodeSurfaceStats(null), isNull);
    expect(decodeSurfaceStats('['), isNull);
    expect(decodeTurns(null), isEmpty);
    expect(decodeTurns(''), isEmpty);
    expect(decodeTurns('['), isEmpty);
    expect(decodeTurns('{"i":1}'), isEmpty);
    // A row that is not a hint is dropped, the rest of the list survives.
    expect(decodeTurns('[1, {"i":2,"k":5}, {"k":99}]'), [
      const TurnHint(pointIndex: 2, kind: TurnKind.right),
    ]);
    expect(encodeTurns(const <TurnHint>[]), isNull);
  });
}
