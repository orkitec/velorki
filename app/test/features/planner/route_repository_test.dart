import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
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

  test('unreadable JSON columns degrade to empty defaults', () {
    expect(decodeWaypoints('not json'), isEmpty);
    expect(decodeWaypoints('{}'), isEmpty);
    expect(decodeOptions('nonsense'), const RoutingOptions());
    expect(decodeSurfaceStats(null), isNull);
    expect(decodeSurfaceStats('['), isNull);
  });
}
