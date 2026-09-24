import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/planner/application/track_surface_service.dart';
import 'package:velorki/features/recording/application/ride_surface.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki/core/geo/track_surface.dart';
import 'package:velorki/core/geo/track_thinning.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/fakes.dart';

/// [lengthM] due north at 20 km/h, one fix a second.
List<TrackPoint> _track(double lengthM) {
  const speedMps = 1000 / 180;
  var position = const LatLng(48, 11);
  final count = (lengthM / speedMps).round();
  return <TrackPoint>[
    for (var i = 0; i <= count; i++)
      TrackPoint(
        i == 0 ? position : position = destinationPoint(position, 0, speedMps),
        time: DateTime.utc(2026, 9, 12, 10).add(Duration(seconds: i)),
      ),
  ];
}

/// A routing answer of [lengthM] that is 60 % asphalt and 40 % gravel track.
RouteResult _answer(double lengthM) => syntheticRoute(lengthM: lengthM);

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

TrackSurfaceService _service(
  FakeRoutingBackend? backend, {
  RoutingDecision decision = _covered,
  int maxPointsPerQuery = 50,
}) => TrackSurfaceService(
  local: backend,
  decide: (_) => decision,
  maxPointsPerQuery: maxPointsPerQuery,
);

void main() {
  late VelorkiDatabase db;
  late RideRepository repository;

  setUp(() {
    db = VelorkiDatabase.memory();
    repository = RideRepository(db.ridesDao);
  });

  tearDown(() => db.close());

  Future<Ride> save(List<TrackPoint> points, {String id = 'ride-1'}) =>
      repository.finalizeRide(
        rideId: id,
        name: 'Loop',
        points: points,
        startedAt: points.first.time!,
        endedAt: points.last.time!,
      );

  group('TrackSurfaceService', () {
    test('routes the thinned track with the shortest profile', () async {
      final ride = await save(_track(3000));
      final backend = FakeRoutingBackend(result: _answer(3000));

      final result = await _service(backend).matchRide(ride);

      expect(result.state, TrackSurfaceState.matched);
      expect(result.stats!.pavedShare, closeTo(0.6, 1e-9));
      expect(result.stats!.unpavedShare, closeTo(0.4, 1e-9));
      expect(backend.callCount, 1);
      final query = backend.queries.single;
      expect(query.profile, 'shortest');
      expect(query.alternativeIdx, 0);
      expect(query.timeout, const Duration(seconds: 60));
      expect(query.points, thinTrack(ride.points));
      expect(query.points.length, inInclusiveRange(10, 20));
    });

    test('rejects a route 20 % longer than the ride', () async {
      final ride = await save(_track(3000));
      final backend = FakeRoutingBackend(result: _answer(3600));

      expect(
        (await _service(backend).matchRide(ride)).state,
        TrackSurfaceState.unmatched,
      );
      expect((await _service(backend).matchRide(ride)).stats, isNull);
    });

    test('accepts a route 10 % shorter than the ride', () async {
      final ride = await save(_track(3000));
      final backend = FakeRoutingBackend(result: _answer(2700));

      expect(
        (await _service(backend).matchRide(ride)).state,
        TrackSurfaceState.matched,
      );
    });

    test('says no tiles without coverage, and never routes', () async {
      final ride = await save(_track(3000));
      final backend = FakeRoutingBackend(result: _answer(3000));

      final result = await _service(
        backend,
        decision: _uncovered,
      ).matchRide(ride);

      expect(result.state, TrackSurfaceState.noTiles);
      expect(backend.callCount, 0);
    });

    test('says no routing without an on-device backend', () async {
      final ride = await save(_track(3000));

      expect(
        (await _service(null).matchRide(ride)).state,
        TrackSurfaceState.noRouting,
      );
    });

    test('does not route a 300 m ride', () async {
      final ride = await save(_track(300));
      final backend = FakeRoutingBackend(result: _answer(300));

      expect(
        (await _service(backend).matchRide(ride)).state,
        TrackSurfaceState.unmatched,
      );
      expect(backend.callCount, 0);
    });

    test('a routing failure is unmatched, not an error', () async {
      final ride = await save(_track(3000));
      final backend = FakeRoutingBackend(
        error: const RoutingException(
          kind: RoutingErrorKind.noRoute,
          message: 'no track found',
        ),
      );

      expect(
        (await _service(backend).matchRide(ride)).state,
        TrackSurfaceState.unmatched,
      );
    });

    test('chunks a long waypoint list and merges the answers', () async {
      final ride = await save(_track(3000));
      final waypoints = thinTrack(ride.points);
      const perQuery = 5;
      final chunks = ((waypoints.length - 1) / (perQuery - 1)).ceil();
      expect(chunks, greaterThan(2));
      final backend = FakeRoutingBackend(result: _answer(3000 / chunks));

      final result = await _service(
        backend,
        maxPointsPerQuery: perQuery,
      ).matchRide(ride);

      expect(backend.callCount, chunks);
      // Every chunk starts where the one before ended, and together they
      // are the whole list.
      for (var i = 1; i < backend.queries.length; i++) {
        expect(
          backend.queries[i].points.first,
          backend.queries[i - 1].points.last,
        );
      }
      expect(backend.queries.first.points.first, waypoints.first);
      expect(backend.queries.last.points.last, waypoints.last);
      for (final q in backend.queries) {
        expect(q.points.length, lessThanOrEqualTo(perQuery));
      }
      expect(result.state, TrackSurfaceState.matched);
      expect(result.stats!.totalLengthM, closeTo(3000, 1e-6));
      expect(result.stats!.pavedShare, closeTo(0.6, 1e-9));
    });
  });

  group('rideSurfaceProvider', () {
    /// Reads the ride's surface off a fresh container, kept listened to
    /// while it loads, as a screen would.
    Future<TrackSurface> resolve(TrackSurfaceService service) async {
      final c = ProviderContainer(
        overrides: [
          velorkiDatabaseProvider.overrideWithValue(db),
          trackSurfaceServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(rideSurfaceProvider('ride-1'), (_, _) {});
      try {
        return await c.read(rideSurfaceProvider('ride-1').future);
      } finally {
        sub.close();
      }
    }

    test(
      'computes once, writes the row, and reads it back next time',
      () async {
        await save(_track(3000));
        final backend = FakeRoutingBackend(result: _answer(3000));
        final service = _service(backend);

        final first = await resolve(service);
        expect(first.state, TrackSurfaceState.matched);
        expect(backend.callCount, 1);

        final row = await db.ridesDao.rideById('ride-1');
        expect(row!.surfaceStatsJson, contains('"paved"'));
        expect(
          (await repository.rideById('ride-1'))!.surfaceStats,
          first.stats,
        );

        final second = await resolve(service);
        expect(second.stats, first.stats);
        expect(backend.callCount, 1, reason: 'the row answered');
      },
    );

    test('a track the map cannot follow is marked and not retried', () async {
      await save(_track(3000));
      final backend = FakeRoutingBackend(result: _answer(5000));
      final service = _service(backend);

      final first = await resolve(service);
      expect(first.state, TrackSurfaceState.unmatched);
      expect(backend.callCount, 1);
      expect(
        (await db.ridesDao.rideById('ride-1'))!.surfaceStatsJson,
        '{"unavailable":true}',
      );

      final second = await resolve(service);
      expect(second.state, TrackSurfaceState.unmatched);
      expect(backend.callCount, 1);
    });

    test(
      'missing tiles leave the row alone, so the ride is tried again',
      () async {
        await save(_track(3000));
        final backend = FakeRoutingBackend(result: _answer(3000));

        final first = await resolve(_service(backend, decision: _uncovered));
        expect(first.state, TrackSurfaceState.noTiles);
        expect(
          (await db.ridesDao.rideById('ride-1'))!.surfaceStatsJson,
          isNull,
        );

        final second = await resolve(_service(backend));
        expect(second.state, TrackSurfaceState.matched);
      },
    );

    test('a new tile clears the markers, not the matches', () async {
      await save(_track(3000));
      await save(_track(4000), id: 'ride-2');
      await repository.markSurfaceUnavailable('ride-1');
      await repository.setSurface('ride-2', _answer(4000).surfaceStats);

      await db.ridesDao.clearUnmatchedSurfaces();

      expect((await repository.rideById('ride-1'))!.surface, isNull);
      expect((await repository.rideById('ride-2'))!.surfaceStats, isNotNull);
    });
  });
}
