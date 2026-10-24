import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/sync/data/record_codec.dart';
import 'package:velorki/features/sync/domain/cloud_record.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/rows.dart';

void main() {
  late Directory dir;
  late RecordCodec codec;
  late VelorkiDatabase db;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('record_codec');
    codec = RecordCodec(Directory('${dir.path}/out'));
    db = VelorkiDatabase.memory();
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  /// [record] as it comes back from the server: the same fields, its body
  /// in a file of its own.
  CloudRecord roundTrip(CloudRecord record) {
    final copy = File('${dir.path}/in_${record.name}.json.gz');
    File(record.assetPath!).copySync(copy.path);
    return CloudRecord(
      name: record.name,
      type: record.type,
      fields: record.fields,
      assetPath: copy.path,
    );
  }

  /// A track as it comes back from a body: quantized.
  Uint8List quantized(Uint8List packed) =>
      CompactTrack.decode(CompactTrack.encode(packed));

  /// The decompressed body of [record].
  Uint8List bodyOf(CloudRecord record) => Uint8List.fromList(
    gzip.decode(File(record.assetPath!).readAsBytesSync()),
  );

  /// [record] with its body replaced by the gzip JSON the first build wrote.
  CloudRecord asOldFormat(CloudRecord record, Map<String, Object?> body) {
    final file = File('${dir.path}/old_${record.name}.json.gz')
      ..writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(body))));
    return CloudRecord(
      name: record.name,
      type: record.type,
      fields: record.fields,
      assetPath: file.path,
    );
  }

  test('a route comes back as the row it was, every column', () async {
    await db.routesDao.upsertRoute(fullRoute('r1', points: 2000));
    final row = (await db.routesDao.routeById('r1'))!;

    final record = await codec.encodeRoute(row, changedAtMs: 1234);
    expect(record.name, 'route_r1');
    expect(record.type, 'Route');
    expect(record.fields['schemaVersion'], recordSchemaVersion);
    expect(record.fields['modifiedAt'], 1234);

    final decoded = (await codec.decodeRoute(roundTrip(record)))!;
    expect(decoded.modifiedAtMs, 1234);
    await db.routesDao.deleteRoute('r1');
    await db.routesDao.upsertRoute(decoded.row);
    final back = (await db.routesDao.routeById('r1'))!;

    expect(
      back.copyWith(externalIdsJson: const Value(null)),
      row.copyWith(
        externalIdsJson: const Value(null),
        geometry: quantized(row.geometry),
        originalGeometry: Value(quantized(row.originalGeometry!)),
      ),
    );
  });

  test('a route body is the same bytes every time', () async {
    await db.routesDao.upsertRoute(fullRoute('r1', points: 300));
    final row = (await db.routesDao.routeById('r1'))!;
    final a = await codec.encodeRoute(row, changedAtMs: 1);
    final first = bodyOf(a);
    final b = await codec.encodeRoute(row, changedAtMs: 2);
    expect(bodyOf(b), first);
    expect(first.sublist(0, 4), [0, 0x56, 0x42, 2]);
  });

  test('a body in the first build\'s gzip JSON format still decodes', () async {
    await db.routesDao.upsertRoute(fullRoute('r1', points: 40));
    final row = (await db.routesDao.routeById('r1'))!;
    final record = asOldFormat(await codec.encodeRoute(row, changedAtMs: 3), {
      'geometry': base64Encode(row.geometry),
      'waypoints': row.waypointsJson,
      'routingOptions': row.routingOptionsJson,
      'surfaceStats': row.surfaceStatsJson,
      'turns': row.turnsJson,
      'pois': row.poisJson,
      'original': row.originalJson,
      'originalGeometry': base64Encode(row.originalGeometry!),
    });
    final decoded = (await codec.decodeRoute(record))!;
    expect(decoded.row.geometry.value, row.geometry);
    expect(decoded.row.originalGeometry.value, row.originalGeometry);
    expect(decoded.row.waypointsJson.value, row.waypointsJson);
    expect(decoded.row.turnsJson.value, row.turnsJson);
  });

  test('an old ride body decodes, temperatures included', () async {
    await db.ridesDao.upsertRide(fullRide('ride1', points: 30));
    final row = (await db.ridesDao.rideById('ride1'))!;
    final record = asOldFormat(
      await codec.encodeRide(row, changedAtMs: 3, routeId: null),
      {
        'geometry': base64Encode(row.geometry),
        'pauses': row.pausesJson,
        'surfaceStats': row.surfaceStatsJson,
        'laps': row.lapsJson,
        'deviceTotals': row.deviceTotalsJson,
        'temperatures': base64Encode(row.temperatures!),
      },
    );
    final decoded = (await codec.decodeRide(record))!;
    expect(decoded.row.geometry.value, row.geometry);
    expect(decoded.row.temperatures.value, row.temperatures);
  });

  test('a column that is not a packed track travels as it is', () async {
    await db.ridesDao.upsertRide(
      fullRide('ride1', points: 5).copyWith(
        geometry: Value(Uint8List.fromList([9, 1, 2, 3])),
        temperatures: Value(Uint8List.fromList([1, 2, 3])),
      ),
    );
    final row = (await db.ridesDao.rideById('ride1'))!;
    final record = await codec.encodeRide(row, changedAtMs: 1, routeId: null);
    final decoded = (await codec.decodeRide(roundTrip(record)))!;
    expect(decoded.row.geometry.value, row.geometry);
    expect(decoded.row.temperatures.value, row.temperatures);
  });

  test('a ride without temperatures or sensors comes back without', () async {
    await db.ridesDao.upsertRide(
      fullRide('ride1', points: 5).copyWith(temperatures: const Value(null)),
    );
    final row = (await db.ridesDao.rideById('ride1'))!;
    final record = await codec.encodeRide(row, changedAtMs: 1, routeId: null);
    final decoded = (await codec.decodeRide(roundTrip(record)))!;
    expect(decoded.row.temperatures.value, isNull);
  });

  test('a route record carries no partner ids', () async {
    await db.routesDao.upsertRoute(
      fullRoute('r1', source: RouteSource.rwgps).copyWith(
        externalIdsJson: const Value('{"rwgps_route_id":"42"}'),
        externalFetchedAt: Value(DateTime(2026, 9)),
      ),
    );
    final row = (await db.routesDao.routeById('r1'))!;
    final record = await codec.encodeRoute(row, changedAtMs: 1);

    final everything =
        jsonEncode(record.fields) +
        utf8.decode(bodyOf(record), allowMalformed: true);
    expect(everything, isNot(contains('rwgps_route_id')));
    expect(everything, isNot(contains('42"')));
    final decoded = (await codec.decodeRoute(roundTrip(record)))!;
    expect(decoded.row.externalIdsJson, const Value<String?>.absent());
    expect(decoded.row.externalFetchedAt, const Value<DateTime?>.absent());
    expect(decoded.row.source.value, RouteSource.rwgps);
  });

  test('a ride with a long track comes back whole, uploads left out', () async {
    // Ten hours at one point a second.
    await db.ridesDao.upsertRide(
      fullRide('ride1', points: 36000).copyWith(
        uploadsJson: const Value(
          '{"strava":{"id":"1","url":"https://www.strava.com/activities/1"}}',
        ),
      ),
    );
    final row = (await db.ridesDao.rideById('ride1'))!;

    final record = await codec.encodeRide(row, changedAtMs: 99, routeId: null);
    final file = File(record.assetPath!);
    expect(
      file.lengthSync(),
      lessThan(row.geometry.length),
      reason: 'the body is compressed',
    );
    expect(jsonEncode(record.fields), isNot(contains('strava')));
    expect(
      utf8.decode(bodyOf(record), allowMalformed: true),
      isNot(contains('strava')),
    );

    final decoded = (await codec.decodeRide(roundTrip(record)))!;
    expect(decoded.row.uploadsJson, const Value<String?>.absent());
    await db.ridesDao.deleteRide('ride1');
    await db.ridesDao.upsertRide(decoded.row);
    final back = (await db.ridesDao.rideById('ride1'))!;
    expect(
      back,
      row.copyWith(
        uploadsJson: const Value(null),
        geometry: quantized(row.geometry),
        temperatures: Value(row.temperatures),
      ),
    );
    // A second trip changes nothing more.
    expect(quantized(back.geometry), back.geometry);
  });

  test(
    'a record from a newer build is read for what this build knows',
    () async {
      await db.routesDao.upsertRoute(fullRoute('r1'));
      final record = await codec.encodeRoute(
        (await db.routesDao.routeById('r1'))!,
        changedAtMs: 5,
      );
      final newer = CloudRecord(
        name: record.name,
        type: record.type,
        fields: {
          ...record.fields,
          'schemaVersion': recordSchemaVersion + 1,
          'somethingNew': 'ignored',
        }..remove('description'),
        assetPath: roundTrip(record).assetPath,
      );

      final decoded = (await codec.decodeRoute(newer))!;
      expect(decoded.row.name.value, 'Route r1');
      expect(decoded.row.description.value, isNull, reason: 'missing: default');
    },
  );

  test('a record without its body is not read', () async {
    final decoded = await codec.decodeRide(
      const CloudRecord(
        name: 'ride_x',
        type: 'Ride',
        fields: {'name': 'No body'},
      ),
    );
    expect(decoded, isNull);
  });

  test('record names say kind and id', () {
    expect(recordNameOf(SyncKind.ride, 'a_b'), 'ride_a_b');
    expect(parseRecordName('ride_a_b'), (SyncKind.ride, 'a_b'));
    expect(parseRecordName('route_1'), (SyncKind.route, '1'));
    expect(parseRecordName('stop_1'), isNull);
    expect(parseRecordName('nothing'), isNull);
  });

  test('the incoming body file is deleted once read', () async {
    await db.ridesDao.upsertRide(fullRide('ride1', points: 10));
    final record = roundTrip(
      await codec.encodeRide(
        (await db.ridesDao.rideById('ride1'))!,
        changedAtMs: 1,
        routeId: null,
      ),
    );
    await codec.decodeRide(record);
    expect(File(record.assetPath!).existsSync(), isFalse);
  });

  group('body size', () {
    Uint8List ride(int n) {
      final rnd = Random(3);
      var lat = 48.1;
      var lon = 11.5;
      var heading = 0.0;
      return PackedTrack.encode([
        for (var i = 0; i < n; i++)
          () {
            heading += (rnd.nextDouble() - 0.5) * 0.2;
            lat += cos(heading) * 5e-5 + (rnd.nextDouble() - 0.5) * 4e-6;
            lon += sin(heading) * 7e-5 + (rnd.nextDouble() - 0.5) * 4e-6;
            return TrackPoint(
              LatLng(lat, lon),
              ele: 500 + 80 * sin(i / 900) + rnd.nextDouble() * 1.5,
              time: DateTime.utc(2026, 9, 12, 6).add(Duration(seconds: i)),
              speedMps: 6 + rnd.nextDouble() * 4,
              accuracyM: 3 + rnd.nextInt(6).toDouble(),
              heartRateBpm: 120 + rnd.nextInt(40),
              cadenceRpm: rnd.nextInt(100),
              powerW: rnd.nextInt(300),
            );
          }(),
      ]);
    }

    Uint8List route(int n) {
      final rnd = Random(4);
      var lat = 48.1;
      var lon = 11.5;
      var heading = 0.0;
      return PackedTrack.encode([
        for (var i = 0; i < n; i++)
          () {
            heading += (rnd.nextDouble() - 0.5) * 0.3;
            // Routing nodes sit on a 1e-6 degree grid.
            lat = (lat + cos(heading) * 8e-5) * 1e6;
            lat = lat.roundToDouble() / 1e6;
            lon = ((lon + sin(heading) * 1.2e-4) * 1e6).roundToDouble() / 1e6;
            return TrackPoint(
              LatLng(lat, lon),
              ele: (500 + 80 * sin(i / 900) + rnd.nextDouble()).roundToDouble(),
            );
          }(),
      ]);
    }

    /// What the first format made of the same track.
    int oldSize(Uint8List geometry) => gzip
        .encode(utf8.encode(jsonEncode({'geometry': base64Encode(geometry)})))
        .length;

    Future<int> newSize(Uint8List geometry) async {
      final id = 'size${geometry.length}';
      await db.ridesDao.upsertRide(
        fullRide(id, points: 1).copyWith(geometry: Value(geometry)),
      );
      final row = (await db.ridesDao.rideById(id))!;
      final record = await codec.encodeRide(
        row.copyWith(temperatures: const Value(null)),
        changedAtMs: 1,
        routeId: null,
      );
      return File(record.assetPath!).lengthSync();
    }

    test('tracks shrink by a factor of several', () async {
      for (final (label, track, maxBytes) in [
        ('4 h ride', ride(14400), 250 * 1000),
        ('24 h ride', ride(86400), 1000 * 1000),
        ('300 km route', route(30000), 150 * 1000),
        ('200k-point route', route(200000), 1000 * 1000),
      ]) {
        final before = oldSize(track);
        final after = await newSize(track);
        // ignore: avoid_print
        print('$label: $before -> $after bytes');
        expect(after, lessThan(maxBytes), reason: label);
        expect(after, lessThan(before ~/ 3), reason: label);
      }
    });
  });
}
