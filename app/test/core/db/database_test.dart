import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';

RoutesCompanion _route(
  String id, {
  String name = 'Route',
  DateTime? updatedAt,
  RouteSource source = RouteSource.planned,
}) {
  final now = updatedAt ?? DateTime.utc(2026, 9, 12, 10);
  return RoutesCompanion.insert(
    id: id,
    name: name,
    source: source,
    profile: 'trekking',
    createdAt: now,
    updatedAt: now,
    distanceM: 42000,
    ascentM: 310,
    descentM: 305,
    bboxMinLat: 47.3,
    bboxMinLon: 8.4,
    bboxMaxLat: 47.5,
    bboxMaxLon: 8.7,
    geometry: Uint8List.fromList([1, 2, 3]),
    waypointsJson: '[]',
    routingOptionsJson: '{"profile":"trekking"}',
  );
}

RidesCompanion _ride(
  String id, {
  String? routeId,
  DateTime? startedAt,
  String name = 'Ride',
}) {
  final start = startedAt ?? DateTime.utc(2026, 9, 12, 8);
  return RidesCompanion.insert(
    id: id,
    name: name,
    startedAt: start,
    endedAt: start.add(const Duration(hours: 2)),
    distanceM: 38000,
    movingTimeS: 6400,
    elapsedTimeS: 7200,
    ascentM: 280,
    descentM: 275,
    avgSpeedMps: 5.9,
    maxSpeedMps: 13.2,
    geometry: Uint8List.fromList([9, 9]),
    pausesJson: '[]',
    routeId: Value(routeId),
  );
}

void main() {
  late VelorkiDatabase db;

  setUp(() => db = VelorkiDatabase.memory());
  tearDown(() => db.close());

  test('schema version is 1', () {
    expect(db.schemaVersion, 1);
  });

  group('routes', () {
    test('insert and read back', () async {
      await db.routesDao.upsertRoute(
        _route('r1', name: 'Uetliberg loop', source: RouteSource.loop),
      );

      final row = await db.routesDao.routeById('r1');
      expect(row, isNotNull);
      expect(row!.name, 'Uetliberg loop');
      expect(row.source, RouteSource.loop);
      expect(row.aiDescriptionGenerated, isFalse);
      expect(row.geometry, [1, 2, 3]);
      expect(row.createdAt, DateTime.utc(2026, 9, 12, 10));
      expect(await db.routesDao.routeById('missing'), isNull);
    });

    test('upsert replaces an existing row', () async {
      await db.routesDao.upsertRoute(_route('r1', name: 'First'));
      await db.routesDao.upsertRoute(_route('r1', name: 'Second'));

      expect((await db.routesDao.allRoutes()).single.name, 'Second');
    });

    test('watchRoutes emits newest updated_at first', () async {
      final stream = db.routesDao.watchRoutes();
      final emissions = <List<String>>[];
      final sub = stream.listen((rows) {
        emissions.add([for (final r in rows) r.id]);
      });
      await pumpEventQueue();

      await db.routesDao.upsertRoute(
        _route('old', updatedAt: DateTime.utc(2026, 1, 1)),
      );
      await db.routesDao.upsertRoute(
        _route('new', updatedAt: DateTime.utc(2026, 6, 1)),
      );
      await pumpEventQueue();

      expect(emissions.first, isEmpty);
      expect(emissions.last, ['new', 'old']);
      await sub.cancel();
    });

    test('delete removes the row', () async {
      await db.routesDao.upsertRoute(_route('r1'));
      expect(await db.routesDao.deleteRoute('r1'), 1);
      expect(await db.routesDao.allRoutes(), isEmpty);
    });
  });

  group('rides', () {
    test('insert and read back', () async {
      await db.ridesDao.upsertRide(_ride('ride1'));

      final row = await db.ridesDao.rideById('ride1');
      expect(row, isNotNull);
      expect(row!.movingTimeS, 6400);
      expect(row.routeId, isNull);
      expect(row.uploadsJson, isNull);
    });

    test('watchRides emits newest started_at first', () async {
      final emissions = <List<String>>[];
      final sub = db.ridesDao.watchRides().listen((rows) {
        emissions.add([for (final r in rows) r.id]);
      });

      await db.ridesDao.upsertRide(
        _ride('early', startedAt: DateTime.utc(2026, 3, 1)),
      );
      await db.ridesDao.upsertRide(
        _ride('late', startedAt: DateTime.utc(2026, 8, 1)),
      );
      await pumpEventQueue();

      expect(emissions.last, ['late', 'early']);
      await sub.cancel();
    });

    test('rejects a ride pointing at an unknown route', () async {
      await expectLater(
        db.ridesDao.upsertRide(_ride('ride1', routeId: 'nope')),
        throwsA(isA<Exception>()),
      );
    });

    test('deleting the route clears route_id but keeps the ride', () async {
      await db.routesDao.upsertRoute(_route('r1'));
      await db.ridesDao.upsertRide(_ride('ride1', routeId: 'r1'));
      expect((await db.ridesDao.rideById('ride1'))!.routeId, 'r1');

      await db.routesDao.deleteRoute('r1');

      final row = await db.ridesDao.rideById('ride1');
      expect(row, isNotNull);
      expect(row!.routeId, isNull);
    });
  });
}
