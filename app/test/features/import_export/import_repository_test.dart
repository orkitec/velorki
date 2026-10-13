import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/import_export/data/import_repository.dart';
import 'package:velorki/features/import_export/data/track_decoder.dart';
import 'package:velorki/features/import_export/domain/imported_track.dart';
import 'package:velorki/features/navigation/application/route_turn_generator.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../navigation/support/fake_turns.dart';

import 'support/fixtures.dart';

void main() {
  late VelorkiDatabase db;
  late ImportRepository repository;

  setUp(() {
    db = VelorkiDatabase.memory();
    repository = ImportRepository(
      RouteRepository(db.routesDao, clock: () => DateTime.utc(2026, 9, 12, 10)),
      db.ridesDao,
      clock: () => DateTime.utc(2026, 9, 12, 10),
    );
    addTearDown(db.close);
  });

  test('a GPX route round trips through the routes table', () async {
    final track = decodeTrack(fixtureBytes('route.gpx'));
    final saved = await repository.saveAsRoute(name: 'Imported', track: track);

    expect(saved.source, RouteSource.importedGpx);
    expect(saved.name, 'Imported');
    expect(saved.distanceM, greaterThan(0));
    // 590 → 594 → 601 → 598: 594 is 4 m up (booked), 601 is 7 m up (booked),
    // 598 is 3 m down (booked).
    expect(saved.ascentM, closeTo(11, 1e-9));
    expect(saved.descentM, closeTo(3, 1e-9));
    expect(saved.waypoints, hasLength(2));
    expect(saved.waypoints.first.kind, WaypointKind.start);
    expect(saved.waypoints.last.kind, WaypointKind.end);
    expect(saved.waypoints.first.pos, const LatLng(47.998, 11.34));

    // What comes back out of the database is what went in.
    final reloaded = await RouteRepository(db.routesDao).routeById(saved.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.geometry, hasLength(track.pointCount));
    expect(reloaded.geometry.first.lat, closeTo(47.998, 1e-9));
    expect(reloaded.geometry.first.ele, closeTo(590, 1e-3));
    expect(reloaded.source, RouteSource.importedGpx);
    expect(reloaded.bounds.south, closeTo(47.998, 1e-9));
    expect(reloaded.bounds.north, closeTo(48.010, 1e-9));
  });

  test('a FIT import is stored with the FIT source', () async {
    final track = decodeTrack(fixtureBytes('activity.fit'));
    final saved = await repository.saveAsRoute(
      name: 'From Garmin',
      track: track,
    );
    expect(saved.source, RouteSource.importedFit);
  });

  test('a GPX track round trips through the rides table', () async {
    final track = decodeTrack(fixtureBytes('komoot.gpx'));
    final ride = await repository.saveAsRide(name: 'Ammersee', track: track);

    expect(ride.name, 'Ammersee');
    expect(ride.startedAt, DateTime.utc(2024, 6, 12, 16, 4, 41));
    expect(ride.endedAt, DateTime.utc(2024, 6, 12, 16, 4, 51));
    expect(ride.elapsedTimeS, 10);
    expect(ride.distanceM, greaterThan(0));
    expect(ride.routeId, isNull);

    final row = await db.ridesDao.rideById(ride.id);
    expect(row, isNotNull);
    expect(row!.name, 'Ammersee');
    expect(PackedTrack.decode(row.geometry), hasLength(3));
    expect(
      PackedTrack.decode(row.geometry).first.time,
      DateTime.utc(2024, 6, 12, 16, 4, 41),
    );
    expect(row.pausesJson, '[]');
  });

  test(
    'a ride without timestamps still saves, with the clock as start',
    () async {
      final track = decodeTrack(fixtureBytes('route.gpx'));
      final ride = await repository.saveAsRide(name: 'No times', track: track);

      expect(ride.startedAt, DateTime.utc(2026, 9, 12, 10));
      expect(ride.endedAt, DateTime.utc(2026, 9, 12, 10));
      expect(ride.movingTimeS, 0);
      expect(ride.elapsedTimeS, 0);
      expect(ride.avgSpeedMps, 0);
      expect(await db.ridesDao.rideById(ride.id), isNotNull);
    },
  );

  test('an empty track is refused rather than written', () async {
    const empty = ImportedTrack(format: ImportFormat.gpx, points: []);
    await expectLater(
      repository.saveAsRide(name: 'Nothing', track: empty),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveAsRoute(name: 'Nothing', track: empty),
      throwsArgumentError,
    );
    expect(await db.ridesDao.allRides(), isEmpty);
    expect(await db.routesDao.allRoutes(), isEmpty);
  });

  test('a plain GPX track gets its turns from the map after the import, '
      'when its tiles are on the phone', () async {
    final points = leggedTrack();
    final gpx = StringBuffer(
      '<?xml version="1.0"?><gpx version="1.1" creator="test" '
      'xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>',
    );
    for (final p in points) {
      gpx.write('<trkpt lat="${p.lat}" lon="${p.lon}"></trkpt>');
    }
    gpx.write('</trkseg></trk></gpx>');
    final track = decodeTrack(Uint8List.fromList(utf8.encode('$gpx')));
    expect(track.turns, isEmpty, reason: 'the file has none');

    final backend = TrackFollowingBackend();
    final container = ProviderContainer(
      overrides: [
        velorkiDatabaseProvider.overrideWithValue(db),
        trackTurnServiceProvider.overrideWithValue(fakeTurnService(backend)),
      ],
    );
    addTearDown(container.dispose);

    final saved = await container
        .read(importRepositoryProvider)
        .saveAsRoute(name: 'Plain', track: track);
    expect(saved.turns, isEmpty);

    // In the background, no dialog: wait for it.
    final routes = RouteRepository(db.routesDao);
    for (var i = 0; i < 50; i++) {
      if ((await routes.routeById(saved.id))!.turnsGenerated) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final back = (await routes.routeById(saved.id))!;
    expect(back.turnsGenerated, isTrue);
    expect(back.turns.first.pointIndex, 30);
    expect(back.turns.first.kind, TurnKind.right);
  });
}
