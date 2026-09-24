import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/core/geo/track_surface.dart';
import 'package:velorki/features/library/application/route_surface.dart';
import 'package:velorki/features/planner/application/track_surface_service.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/fakes.dart';

/// A track [lengthM] long, due north, a point every 10 m.
List<TrackPoint> _track(double lengthM) {
  var position = const LatLng(48, 11);
  final count = (lengthM / 10).round();
  return <TrackPoint>[
    for (var i = 0; i <= count; i++)
      TrackPoint(
        i == 0 ? position : position = destinationPoint(position, 0, 10),
      ),
  ];
}

const RoutingDecision _covered = RoutingDecision(
  source: RoutingSource.local,
  requiredTiles: <TileName>[TileName(10, 45)],
  missingTiles: <TileName>[],
);

const RoutingDecision _uncovered = RoutingDecision(
  source: null,
  requiredTiles: <TileName>[TileName(10, 45)],
  missingTiles: <TileName>[TileName(10, 45)],
);

void main() {
  late VelorkiDatabase db;
  late RouteRepository repository;

  setUp(() {
    db = VelorkiDatabase.memory();
    repository = RouteRepository(db.routesDao);
  });
  tearDown(() => db.close());

  /// A route read from a file: a real track, and no surfaces, because
  /// nobody ever routed it.
  Future<SavedRoute> imported({double lengthM = 3000}) =>
      repository.saveImportedRoute(
        name: 'From a file',
        points: _track(lengthM),
        source: RouteSource.importedGpx,
      );

  TrackSurfaceService service(
    FakeRoutingBackend? backend, {
    RoutingDecision decision = _covered,
  }) => TrackSurfaceService(local: backend, decide: (_) => decision);

  /// Reads a route's surface off a fresh container, kept listened to while
  /// it loads, as a card would.
  Future<TrackSurface> resolve(String id, TrackSurfaceService matcher) async {
    final c = ProviderContainer(
      overrides: [
        velorkiDatabaseProvider.overrideWithValue(db),
        trackSurfaceServiceProvider.overrideWithValue(matcher),
      ],
    );
    addTearDown(c.dispose);
    final sub = c.listen(routeSurfaceProvider(id), (_, _) {});
    try {
      return await c.read(routeSurfaceProvider(id).future);
    } finally {
      sub.close();
    }
  }

  test('a route with no surfaces gets them from the matcher and keeps '
      'them', () async {
    final route = await imported();
    expect(route.surfaceStats, isNull);
    final backend = FakeRoutingBackend(
      result: syntheticRoute(lengthM: route.distanceM),
    );

    final outcome = await resolve(route.id, service(backend));

    expect(outcome.state, TrackSurfaceState.matched);
    expect(outcome.stats, isNotNull);
    // Written to the route's own column, so the next look is free.
    final stored = await repository.routeById(route.id);
    expect(stored!.surfaceStats, isNotNull);
    expect(stored.surfaceStats!.totalLengthM, greaterThan(0));
    expect(stored.surfaceUnavailable, isFalse);
  });

  test('a route that already has them is not matched again', () async {
    final route = await imported();
    final backend = FakeRoutingBackend(
      result: syntheticRoute(lengthM: route.distanceM),
    );
    await resolve(route.id, service(backend));
    final routed = backend.callCount;
    expect(routed, greaterThan(0));

    // A second look, with a container of its own, reads the stored answer.
    final again = await resolve(route.id, service(backend));

    expect(again.state, TrackSurfaceState.matched);
    expect(backend.callCount, routed, reason: 'the answer was kept');
  });

  test('a route whose area has no routing tile says so, and is not written '
      'off', () async {
    final route = await imported();
    final backend = FakeRoutingBackend();

    final outcome = await resolve(
      route.id,
      service(backend, decision: _uncovered),
    );

    expect(outcome.state, TrackSurfaceState.noTiles);
    expect(backend.callCount, 0, reason: 'nothing is asked without tiles');
    // Nothing written: it is matched as soon as the region is downloaded.
    final stored = await repository.routeById(route.id);
    expect(stored!.surfaceStats, isNull);
    expect(stored.surfaceUnavailable, isFalse);
  });

  test('a track the router cannot follow is marked, once', () async {
    final route = await imported();
    // An answer of quite another length: the router found a way, but not
    // the way the file drew.
    final backend = FakeRoutingBackend(
      result: syntheticRoute(lengthM: route.distanceM * 3),
    );

    final outcome = await resolve(route.id, service(backend));

    expect(outcome.state, TrackSurfaceState.unmatched);
    final stored = await repository.routeById(route.id);
    expect(stored!.surfaceUnavailable, isTrue);
    expect(stored.surfaceStats, isNull);

    final routed = backend.callCount;
    final again = await resolve(route.id, service(backend));
    expect(again.state, TrackSurfaceState.unmatched);
    expect(backend.callCount, routed, reason: 'the marker stops a retry');
  });

  test('a build with no on-device routing keeps quiet', () async {
    final route = await imported();

    final outcome = await resolve(route.id, service(null));

    expect(outcome.state, TrackSurfaceState.noRouting);
    final stored = await repository.routeById(route.id);
    expect(stored!.surfaceStats, isNull);
    expect(stored.surfaceUnavailable, isFalse);
  });

  test('matching a route leaves its edited date alone', () async {
    final route = await imported();
    final backend = FakeRoutingBackend(
      result: syntheticRoute(lengthM: route.distanceM),
    );

    await resolve(route.id, service(backend));

    final stored = await repository.routeById(route.id);
    expect(
      stored!.updatedAt,
      route.updatedAt,
      reason: 'the figures describe the track that was always there',
    );
  });
}
