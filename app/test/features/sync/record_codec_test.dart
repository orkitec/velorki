import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/sync/data/record_codec.dart';
import 'package:velorki/features/sync/domain/cloud_record.dart';

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
      row.copyWith(externalIdsJson: const Value(null)),
    );
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

    final everything = jsonEncode([
      record.fields,
      jsonDecode(
        utf8.decode(gzip.decode(File(record.assetPath!).readAsBytesSync())),
      ),
    ]);
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
      utf8.decode(gzip.decode(file.readAsBytesSync())),
      isNot(contains('strava')),
    );

    final decoded = (await codec.decodeRide(roundTrip(record)))!;
    expect(decoded.row.uploadsJson, const Value<String?>.absent());
    await db.ridesDao.deleteRide('ride1');
    await db.ridesDao.upsertRide(decoded.row);
    final back = (await db.ridesDao.rideById('ride1'))!;
    expect(back, row.copyWith(uploadsJson: const Value(null)));
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
}
