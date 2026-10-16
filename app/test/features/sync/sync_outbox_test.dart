import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/domain/ride_upload.dart';
import 'package:velorki_brouter/velorki_brouter.dart' show SurfaceStats;
import 'package:velorki_geo/velorki_geo.dart';

import 'support/rows.dart';

/// Every way the app writes a route or a ride reaches `sync_records`: the
/// triggers sit under the repositories, the import and the Strava checks.
void main() {
  late VelorkiDatabase db;
  late RouteRepository routes;
  late RideRepository rides;

  setUp(() {
    db = VelorkiDatabase.memory();
    routes = RouteRepository(db.routesDao);
    rides = RideRepository(db.ridesDao);
  });
  tearDown(() => db.close());

  Future<SyncRecordRow?> record(String kind, String id) =>
      db.syncDao.record(kind, id);

  /// Clears every mark, as a finished sync leaves them.
  Future<void> settle() =>
      db.customStatement('UPDATE sync_records SET dirty = 0');

  Future<void> expectMarked(
    String kind,
    String id, {
    bool deleted = false,
  }) async {
    final r = await record(kind, id);
    expect(r, isNotNull, reason: '$kind $id has a record');
    expect(r!.dirty, isTrue, reason: '$kind $id is marked');
    expect(r.deleted, deleted);
  }

  Future<void> expectClean(String kind, String id) async {
    expect((await record(kind, id))?.dirty, isFalse);
  }

  final points = [
    for (var i = 0; i < 20; i++)
      TrackPoint(LatLng(32.65 + i * 1e-3, -16.9), ele: 10),
  ];

  group('routes', () {
    late String id;

    setUp(() async {
      id = (await routes.saveImportedRoute(
        name: 'Imported',
        points: points,
        source: RouteSource.importedGpx,
      )).id;
    });

    test('an import is marked', () async {
      await expectMarked('route', id);
    });

    test('each edit is marked, and counts', () async {
      final edits = <Future<void> Function()>[
        () => routes.rename(id, 'New name'),
        () => routes.setDescription(id, 'About it'),
        () => routes.setLink(id, 'https://example.org'),
        () => routes.setPois(id, [
          RoutePoi(pos: const LatLng(32.66, -16.9), name: 'Café'),
        ]),
        () => routes.setWaypoints(id, [
          Waypoint(pos: points.first.pos, name: 'Start'),
          Waypoint(pos: points.last.pos),
        ]),
      ];
      var version = (await record('route', id))!.version;
      for (final edit in edits) {
        await settle();
        await edit();
        await expectMarked('route', id);
        final now = (await record('route', id))!.version;
        expect(now, greaterThan(version));
        version = now;
      }
    });

    test('what each device works out for itself is not a change', () async {
      await settle();
      await routes.setSurfaceStats(id, SurfaceStats.empty);
      await db.routesDao.setExternalFetchedAt(id, DateTime(2026, 10));
      await expectClean('route', id);
    });

    test('a write of the same values is not a change', () async {
      await settle();
      final row = (await db.routesDao.routeById(id))!;
      await db.routesDao.updateRoute(row);
      await expectClean('route', id);
    });

    test('a delete leaves a tombstone, an undo takes it back', () async {
      final route = (await routes.routeById(id))!;
      await settle();
      await routes.delete(id);
      await expectMarked('route', id, deleted: true);
      await routes.restore(route);
      await expectMarked('route', id);
    });

    test('the Strava purge marks only Strava routes', () async {
      await db.routesDao.upsertRoute(
        fullRoute('s1', source: RouteSource.strava),
      );
      await db.routesDao.upsertRoute(
        fullRoute('s2')
            .copyWith(externalIdsJson: const Value('{"strava_route_id":"7"}')),
      );
      await settle();
      expect(await routes.deleteStravaRoutes(), 2);
      await expectClean('route', id);
      await expectMarked('route', 's1', deleted: true);
      await expectMarked('route', 's2', deleted: true);
      expect(await db.syncDao.stravaRouteIds(), isEmpty);
    });
  });

  group('rides', () {
    setUp(() => db.ridesDao.upsertRide(fullRide('ride1')));

    test('a new ride is marked', () async {
      await expectMarked('ride', 'ride1');
    });

    test('a rename and a delete are marked', () async {
      await settle();
      await rides.rename('ride1', 'Morning');
      await expectMarked('ride', 'ride1');
      await rides.delete('ride1');
      await expectMarked('ride', 'ride1', deleted: true);
    });

    test('uploads and the matched surface are not changes', () async {
      await settle();
      await rides.recordUpload(
        'ride1',
        serviceId: 'strava',
        upload: RideUpload(
          status: RideUploadStatus.done,
          uploadedAt: DateTime.utc(2026, 9, 12),
          url: 'https://www.strava.com/activities/1',
        ),
      );
      await rides.setSurface('ride1', SurfaceStats.empty);
      await db.ridesDao.clearUnmatchedSurfaces();
      await expectClean('ride', 'ride1');
    });

    test('a ride whose route goes loses the link, which is a change', () async {
      await db.routesDao.upsertRoute(fullRoute('r1'));
      await db.ridesDao.upsertRide(fullRide('ride2', routeId: 'r1'));
      await settle();
      await routes.delete('r1');
      await expectMarked('ride', 'ride2');
    });
  });
}
