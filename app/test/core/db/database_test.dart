import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';

/// The `routes` table exactly as schema 1 created it: everything the app has
/// now except `turns_json`.
const _routesV1Ddl = '''
CREATE TABLE routes (
  id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT NULL,
  source TEXT NOT NULL,
  profile TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  distance_m REAL NOT NULL,
  ascent_m REAL NOT NULL,
  descent_m REAL NOT NULL,
  bbox_min_lat REAL NOT NULL,
  bbox_min_lon REAL NOT NULL,
  bbox_max_lat REAL NOT NULL,
  bbox_max_lon REAL NOT NULL,
  geometry BLOB NOT NULL,
  waypoints_json TEXT NOT NULL,
  routing_options_json TEXT NOT NULL,
  surface_stats_json TEXT NULL,
  external_ids_json TEXT NULL,
  external_fetched_at TEXT NULL,
  ai_description_generated INTEGER NOT NULL DEFAULT 0 CHECK (
    ai_description_generated IN (0, 1)
  ),
  PRIMARY KEY (id)
)''';

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

/// The `rides` table exactly as schema 3 created it: everything the app has
/// now except the four sensor averages.
const String _ridesV3Ddl = '''
CREATE TABLE rides (
  id TEXT NOT NULL,
  name TEXT NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT NOT NULL,
  distance_m REAL NOT NULL,
  moving_time_s INTEGER NOT NULL,
  elapsed_time_s INTEGER NOT NULL,
  ascent_m REAL NOT NULL,
  descent_m REAL NOT NULL,
  avg_speed_mps REAL NOT NULL,
  max_speed_mps REAL NOT NULL,
  route_id TEXT NULL REFERENCES routes (id) ON DELETE SET NULL,
  geometry BLOB NOT NULL,
  pauses_json TEXT NOT NULL,
  uploads_json TEXT NULL,
  notes TEXT NULL,
  PRIMARY KEY (id)
)''';

/// The `offline_regions` table as schemas 1 and 2 created it, without the
/// download date.
const String _offlineRegionsV1Ddl =
    'CREATE TABLE offline_regions (id TEXT NOT NULL, name TEXT NOT NULL, bbox_min_lat REAL NOT NULL, bbox_min_lon REAL NOT NULL, bbox_max_lat REAL NOT NULL, bbox_max_lon REAL NOT NULL, maplibre_region_id INTEGER NULL, size_bytes INTEGER NOT NULL, PRIMARY KEY (id))';

void main() {
  late VelorkiDatabase db;

  setUp(() => db = VelorkiDatabase.memory());
  tearDown(() => db.close());

  test('schema version is 8', () {
    expect(db.schemaVersion, 8);
  });

  test('a schema 1 database is upgraded and keeps its routes', () async {
    // One database at a time on the same isolate, or drift complains.
    await db.close();

    // A database as schema 1 left it: the routes table without turns_json and
    // one row in it, plus the two tables the later upgrades alter. Nothing
    // else is created — the migrations touch nothing else.
    final v1 = VelorkiDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw
            ..execute(_routesV1Ddl)
            ..execute(_offlineRegionsV1Ddl)
            ..execute(_ridesV3Ddl)
            ..execute(
              "INSERT INTO routes VALUES ('old', 'Before the upgrade', NULL, "
              "'planned', 'trekking', '2026-09-12T10:00:00.000Z', "
              "'2026-09-12T10:00:00.000Z', 1000.0, 10.0, 5.0, "
              "48.0, 11.0, 48.1, 11.1, x'010203', '[]', '{}', "
              'NULL, NULL, NULL, 0)',
            )
            ..userVersion = 1;
        },
      ),
    );
    addTearDown(v1.close);

    final row = await v1.routesDao.routeById('old');

    expect(row, isNotNull);
    expect(row!.name, 'Before the upgrade');
    expect(row.distanceM, 1000);
    expect(row.createdAt, DateTime.utc(2026, 9, 12, 10));
    expect(row.turnsJson, isNull, reason: 'the new column starts empty');
    expect(row.poisJson, isNull, reason: 'and so does the later one');
  });

  test(
    'a schema 2 database gains the download date of its map areas',
    () async {
      await db.close();

      final v2 = VelorkiDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw
              ..execute(_routesV1Ddl)
              ..execute('ALTER TABLE routes ADD COLUMN turns_json TEXT NULL')
              ..execute(_offlineRegionsV1Ddl)
              ..execute(_ridesV3Ddl)
              ..execute(
                "INSERT INTO offline_regions VALUES ('area', 'Old area', "
                '47.0, 8.0, 47.5, 8.6, 7, 4096)',
              )
              ..userVersion = 2;
          },
        ),
      );
      addTearDown(v2.close);

      final row = await v2.offlineRegionsDao.regionById('area');

      expect(row, isNotNull);
      expect(row!.sizeBytes, 4096);
      expect(row.downloadedAt, isNull, reason: 'the new column starts empty');
    },
  );

  test('a schema 3 database gains the sensor averages of its rides', () async {
    await db.close();

    final v3 = VelorkiDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw
            ..execute(_routesV1Ddl)
            ..execute('ALTER TABLE routes ADD COLUMN turns_json TEXT NULL')
            ..execute(_offlineRegionsV1Ddl)
            ..execute(
              'ALTER TABLE offline_regions ADD COLUMN downloaded_at TEXT NULL',
            )
            ..execute(_ridesV3Ddl)
            ..execute(
              "INSERT INTO rides VALUES ('old', 'Before the upgrade', "
              "'2026-09-12T08:00:00.000Z', '2026-09-12T10:00:00.000Z', "
              "38000.0, 6400, 7200, 280.0, 275.0, 5.9, 13.2, NULL, x'0909', "
              "'[]', NULL, NULL)",
            )
            ..userVersion = 3;
        },
      ),
    );
    addTearDown(v3.close);

    final row = await v3.ridesDao.rideById('old');

    expect(row, isNotNull);
    expect(row!.name, 'Before the upgrade');
    expect(row.distanceM, 38000);
    expect(row.maxSpeedMps, 13.2);
    expect(row.avgHeartRateBpm, isNull, reason: 'the new column starts empty');
    expect(row.maxHeartRateBpm, isNull);
    expect(row.avgCadenceRpm, isNull);
    expect(row.avgPowerW, isNull);
  });

  test('a schema 5 database gains the surface of its rides', () async {
    await db.close();

    final v5 = VelorkiDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw
            ..execute(_routesV1Ddl)
            ..execute('ALTER TABLE routes ADD COLUMN turns_json TEXT NULL')
            ..execute('ALTER TABLE routes ADD COLUMN pois_json TEXT NULL')
            ..execute(_offlineRegionsV1Ddl)
            ..execute(
              'ALTER TABLE offline_regions ADD COLUMN downloaded_at TEXT NULL',
            )
            ..execute(_ridesV3Ddl)
            ..execute(
              'ALTER TABLE rides ADD COLUMN avg_heart_rate_bpm INT NULL',
            )
            ..execute(
              'ALTER TABLE rides ADD COLUMN max_heart_rate_bpm INT NULL',
            )
            ..execute('ALTER TABLE rides ADD COLUMN avg_cadence_rpm INT NULL')
            ..execute('ALTER TABLE rides ADD COLUMN avg_power_w INT NULL')
            ..execute(
              "INSERT INTO rides VALUES ('old', 'Before the upgrade', "
              "'2026-09-12T08:00:00.000Z', '2026-09-12T10:00:00.000Z', "
              "38000.0, 6400, 7200, 280.0, 275.0, 5.9, 13.2, NULL, x'0909', "
              "'[]', NULL, NULL, 150, 180, 85, 210)",
            )
            ..userVersion = 5;
        },
      ),
    );
    addTearDown(v5.close);

    final row = await v5.ridesDao.rideById('old');

    expect(row, isNotNull);
    expect(row!.name, 'Before the upgrade');
    expect(row.avgHeartRateBpm, 150);
    expect(row.surfaceStatsJson, isNull, reason: 'the new column starts empty');

    await v5.ridesDao.setRideSurface('old', '{"unavailable":true}');
    expect(
      (await v5.ridesDao.rideById('old'))!.surfaceStatsJson,
      '{"unavailable":true}',
    );
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
      expect(row.avgHeartRateBpm, isNull);
    });

    test('keeps the sensor averages it was given', () async {
      await db.ridesDao.upsertRide(
        _ride('ride1').copyWith(
          avgHeartRateBpm: const Value(148),
          maxHeartRateBpm: const Value(176),
          avgCadenceRpm: const Value(82),
          avgPowerW: const Value(198),
        ),
      );

      final row = await db.ridesDao.rideById('ride1');
      expect(row!.avgHeartRateBpm, 148);
      expect(row.maxHeartRateBpm, 176);
      expect(row.avgCadenceRpm, 82);
      expect(row.avgPowerW, 198);
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
