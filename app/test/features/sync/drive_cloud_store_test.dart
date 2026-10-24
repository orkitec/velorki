import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/sync/data/cloud_store.dart';
import 'package:velorki/features/sync/data/drive_cloud_store.dart';
import 'package:velorki/features/sync/domain/cloud_sync_status.dart';

import 'support/fake_drive.dart';
import 'support/rows.dart';
import 'support/sync_device.dart';

StoreSave _save(
  String name, {
  String? ifVersion,
  Map<String, Object?> fields = const {'name': 'A', 'modifiedAt': 1},
  List<int>? body = const [0x1f, 0x8b, 1, 2, 3],
}) => StoreSave(
  name,
  type: 'Route',
  fields: fields,
  body: body == null ? null : Uint8List.fromList(body),
  ifVersion: ifVersion,
);

String _versionOf(StoreResult result) => (result as StoreDone).version!;

void main() {
  late FakeDrive drive;
  late DriveCloudStore phone;
  late DriveCloudStore pad;

  setUp(() {
    drive = FakeDrive();
    phone = driveStore(drive);
    pad = driveStore(drive);
  });

  group('a record', () {
    test('is one file in the app data folder, read back whole', () async {
      final [done] = await phone.push([
        _save(
          'route_r1',
          fields: {'name': 'Über den Pass', 'modifiedAt': 7, 'distanceM': 1.5},
        ),
      ]);
      final version = _versionOf(done);
      final [file] = drive.filesOf('rider-a');
      expect(file.name, 'route_r1');
      expect(file.appProperties, {'kind': 'Route', 'modifiedAt': '7'});
      expect(version, '${file.id}:1');

      final record = (await pad.get('route_r1'))!;
      expect(record.type, 'Route');
      expect(record.fields, {
        'name': 'Über den Pass',
        'modifiedAt': 7,
        'distanceM': 1.5,
      });
      expect(record.body, [0x1f, 0x8b, 1, 2, 3]);
      expect(record.version, version);
      expect(await pad.get('route_none'), isNull);
    });

    test('without a body reads back without one', () async {
      await phone.push([_save('settings', body: null)]);
      expect((await pad.get('settings'))!.body, isNull);
    });

    test('goes over the version it was read at, and only that', () async {
      final [created] = await phone.push([_save('route_r1')]);
      final v1 = _versionOf(created);
      final [updated] = await pad.push([
        _save('route_r1', ifVersion: v1, fields: {'name': 'Pad'}),
      ]);
      final v2 = _versionOf(updated);
      expect(v2, isNot(v1));

      final [refused] = await phone.push([
        _save('route_r1', ifVersion: v1, fields: {'name': 'Phone'}),
      ]);
      expect(refused, isA<StoreConflict>());
      final server = (refused as StoreConflict).server;
      expect(server.fields, {'name': 'Pad'});
      expect(server.version, v2);
      expect(drive.fields('rider-a', 'route_r1'), {'name': 'Pad'});
    });

    test('new where there is one already is a conflict', () async {
      await phone.push([_save('route_r1')]);
      final [result] = await pad.push([_save('route_r1')]);
      expect(result, isA<StoreConflict>());
      expect(drive.filesOf('rider-a'), hasLength(1));
    });

    test('over a version of one deleted since is missing', () async {
      final [created] = await phone.push([_save('route_r1')]);
      await pad.push([const StoreDelete('route_r1')]);
      final [result] = await phone.push([
        _save('route_r1', ifVersion: _versionOf(created)),
      ]);
      expect(result, isA<StoreMissing>());
    });

    test('deleted where it is gone already is deleted', () async {
      final [result] = await phone.push([const StoreDelete('route_none')]);
      expect(result, isA<StoreDone>());
    });

    test('two devices made at once: the older file counts, the other is '
        'deleted', () async {
      final older = drive.put('rider-a', 'route_r1', {
        'name': 'Older',
      }, created: DateTime.utc(2026));
      drive.put('rider-a', 'route_r1', {'name': 'Newer'});
      expect((await phone.get('route_r1'))!.fields, {'name': 'Older'});
      expect([for (final f in drive.filesOf('rider-a')) f.id], [older.id]);
    });

    test('a batch is one lookup and a write each', () async {
      drive.requests.clear();
      final results = await phone.push([
        for (var i = 0; i < 30; i++) _save('route_r$i'),
        const StoreDelete('route_gone'),
      ]);
      expect(results.whereType<StoreDone>(), hasLength(31));
      final lookups = drive.requests.where((r) => r == 'GET /drive/v3/files');
      expect(lookups, hasLength(2), reason: '25 names to a query');
      expect(
        drive.requests.where((r) => r == 'POST /upload/drive/v3/files'),
        hasLength(30),
      );
    });
  });

  group('failures', () {
    test('a full Drive refuses the save as over quota', () async {
      drive.quotaFull = true;
      final [result] = await phone.push([_save('route_r1')]);
      expect((result as StoreFailed).failure, CloudStoreFailure.quotaExceeded);
    });

    test('a busy or rate-limited Drive is transient', () async {
      await phone.push([_save('route_r1')]);
      drive.failNext.addAll([503]);
      await expectLater(
        phone.pull('0:0'),
        throwsA(
          isA<CloudStoreException>().having(
            (e) => e.failure,
            'failure',
            CloudStoreFailure.transient,
          ),
        ),
      );
      // The lookup goes through, the writes are rate-limited.
      drive.failWrites.addAll([403, 429]);
      final results = await phone.push([_save('route_r2'), _save('route_r3')]);
      expect(
        [for (final r in results) (r as StoreFailed).failure],
        [CloudStoreFailure.transient, CloudStoreFailure.transient],
      );
    });

    test('a token Drive refuses is replaced without the rider', () async {
      final auth = FakeDriveAuth(drive, 'rider-a');
      final store = driveStore(drive, auth: auth);
      await store.push([_save('route_r1')]);
      expect(auth.refreshes, 1);
      drive.expireTokens();
      expect((await store.get('route_r1'))?.name, 'route_r1');
      expect(auth.refreshes, 2);
    });

    test('access taken back: no account, until signed in again', () async {
      final auth = FakeDriveAuth(drive, 'rider-a');
      final store = driveStore(drive, auth: auth);
      await store.push([_save('route_r1')]);
      drive.expireTokens();
      auth.lostAccess = true;
      await expectLater(
        store.get('route_r1'),
        throwsA(isA<CloudStoreException>()),
      );
      expect(await store.accountId(), isNull);
    });
  });

  group('changes', () {
    test('come from a page token: saves whole, deletions by name', () async {
      final [r1, _] = await phone.push([_save('route_r1'), _save('route_r2')]);
      final start = (await pad.fullList()).cursor;

      await phone.push([
        _save('route_r1', ifVersion: _versionOf(r1), fields: {'name': 'B'}),
        const StoreDelete('route_r2'),
        _save('ride_x'),
      ]);
      final changes = await pad.pull(start);
      expect(
        {for (final r in changes.changed) r.name: r.fields['name']},
        {'route_r1': 'B', 'ride_x': 'A'},
      );
      expect(changes.deleted, ['route_r2']);
      expect(changes.more, isFalse);

      final again = await pad.pull(changes.cursor);
      expect(again.changed, isEmpty);
      expect(again.deleted, isEmpty);
    });

    test('written from here are not downloaded again', () async {
      final start = (await phone.fullList()).cursor;
      await phone.push([_save('route_r1')]);
      final before = drive.downloads;
      final changes = await phone.pull(start);
      expect(changes.changed, isEmpty);
      expect(drive.downloads, before);
    });

    test('come a page at a time', () async {
      final small = driveStore(drive, pageSize: 2);
      final start = (await small.fullList()).cursor;
      await phone.push([for (var i = 0; i < 5; i++) _save('route_r$i')]);
      var page = await small.pull(start);
      final names = <String>{for (final r in page.changed) r.name};
      while (page.more) {
        page = await small.pull(page.cursor);
        names.addAll([for (final r in page.changed) r.name]);
      }
      expect(names, hasLength(5));
    });

    test('from a page token Drive no longer takes: the cursor expired, and '
        'the whole folder is listed a page at a time', () async {
      final start = (await pad.fullList()).cursor;
      await phone.push([for (var i = 0; i < 5; i++) _save('route_r$i')]);
      drive.expirePageTokens('rider-a');
      await expectLater(pad.pull(start), throwsA(isA<StoreCursorExpired>()));

      final small = driveStore(drive, pageSize: 2);
      var page = await small.fullList();
      final names = <String>{for (final r in page.changed) r.name};
      var pages = 1;
      while (page.more) {
        page = await small.fullList(page.cursor);
        names.addAll([for (final r in page.changed) r.name]);
        pages++;
      }
      expect(pages, 3);
      expect(names, hasLength(5));

      // The listing ends on a page token taken before it.
      await phone.push([_save('ride_new')]);
      final after = await small.pull(page.cursor);
      expect([for (final r in after.changed) r.name], ['ride_new']);
    });
  });

  test('the account is the signed-in Google user', () async {
    expect(await phone.accountId(), 'rider-a');
    expect(await driveStore(drive, account: 'rider-b').accountId(), 'rider-b');
  });

  group('two devices over one Drive', () {
    // Two devices, two in-memory databases, on purpose.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    late Directory dir;
    late SyncDevice phoneDevice;
    late SyncDevice padDevice;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('drive_sync');
      phoneDevice = SyncDevice(phone, dir, 'phone', batchSize: 2);
      padDevice = SyncDevice(pad, dir, 'pad');
      await phoneDevice.open();
      await padDevice.open();
    });
    tearDown(() async {
      await phoneDevice.close();
      await padDevice.close();
      await phoneDevice.db.close();
      await padDevice.db.close();
      dir.deleteSync(recursive: true);
    });

    Future<void> tick() =>
        Future<void>.delayed(const Duration(milliseconds: 5));

    test('the library goes once, and reaches the other device whole', () async {
      await phoneDevice.db.routesDao.upsertRoute(fullRoute('r1', points: 2000));
      await phoneDevice.db.routesDao.upsertRoute(fullRoute('r2'));
      await phoneDevice.db.ridesDao.upsertRide(
        fullRide('ride1', points: 5000, routeId: 'r1'),
      );
      await phoneDevice.syncNow();
      expect(drive.namesOf('rider-a'), {'route_r1', 'route_r2', 'ride_ride1'});
      expect(await phoneDevice.db.syncDao.dirtyRecords(), isEmpty);
      expect((await phoneDevice.statusNow()).account, CloudAccount.available);

      final uploads = drive.requests.where((r) => r.startsWith('POST')).length;
      await phoneDevice.syncNow();
      expect(
        drive.requests.where((r) => r.startsWith('POST')),
        hasLength(uploads),
        reason: 'nothing goes again',
      );

      await padDevice.syncNow();
      expect((await padDevice.db.ridesDao.rideById('ride1'))?.routeId, 'r1');
      expect(
        (await padDevice.db.routesDao.routeById('r1'))?.geometry,
        isNotEmpty,
      );
      expect(await padDevice.routeNames(), ['Route r1', 'Route r2']);
      expect(await padDevice.db.syncDao.dirtyRecords(), isEmpty);
    });

    test('a rename reaches the other device, and one back again', () async {
      await phoneDevice.db.routesDao.upsertRoute(fullRoute('r1'));
      await phoneDevice.syncNow();
      await padDevice.syncNow();

      await tick();
      await padDevice.renameRoute('r1', 'Pad');
      await padDevice.syncNow();
      await phoneDevice.syncNow();
      expect(await phoneDevice.routeName('r1'), 'Pad');

      await tick();
      await phoneDevice.renameRoute('r1', 'Phone');
      await phoneDevice.syncNow();
      await padDevice.syncNow();
      expect(await padDevice.routeName('r1'), 'Phone');
      expect(await phoneDevice.db.syncDao.dirtyRecords(), isEmpty);
      expect(await padDevice.db.syncDao.dirtyRecords(), isEmpty);
    });

    group('a conflict goes to the newer change', () {
      setUp(() async {
        await phoneDevice.db.ridesDao.upsertRide(fullRide('ride1'));
        await phoneDevice.syncNow();
        await padDevice.syncNow();
        await phoneDevice.db.ridesDao.renameRide('ride1', 'Phone');
        await padDevice.db.ridesDao.renameRide('ride1', 'Pad');
      });

      test('the newer one sent second wins on both', () async {
        await phoneDevice.setChangedAt('ride', 'ride1', 1000);
        await padDevice.setChangedAt('ride', 'ride1', 2000);
        await phoneDevice.syncNow();
        await padDevice.syncNow();
        await phoneDevice.syncNow();
        expect(await phoneDevice.rideNames(), ['Pad']);
        expect(await padDevice.rideNames(), ['Pad']);
        expect(drive.fields('rider-a', 'ride_ride1')!['name'], 'Pad');
      });

      test('the newer one sent first wins on both', () async {
        await phoneDevice.setChangedAt('ride', 'ride1', 3000);
        await padDevice.setChangedAt('ride', 'ride1', 2000);
        await phoneDevice.syncNow();
        await padDevice.syncNow();
        await phoneDevice.syncNow();
        expect(await phoneDevice.rideNames(), ['Phone']);
        expect(await padDevice.rideNames(), ['Phone']);
        expect(await padDevice.db.syncDao.dirtyRecords(), isEmpty);
      });
    });

    test('a delete elsewhere removes the route here', () async {
      await phoneDevice.db.routesDao.upsertRoute(fullRoute('r1'));
      await phoneDevice.syncNow();
      await padDevice.syncNow();

      await padDevice.db.routesDao.deleteRoute('r1');
      await padDevice.syncNow();
      expect(drive.namesOf('rider-a'), isEmpty);
      await phoneDevice.syncNow();
      expect(await phoneDevice.routeNames(), isEmpty);
      expect(await phoneDevice.db.syncDao.record('route', 'r1'), isNull);
    });

    test('an expired page token lists the whole folder again', () async {
      await phoneDevice.db.routesDao.upsertRoute(fullRoute('r1'));
      await phoneDevice.syncNow();
      await padDevice.syncNow();

      await tick();
      await phoneDevice.renameRoute('r1', 'Renamed');
      await phoneDevice.db.routesDao.upsertRoute(fullRoute('r2'));
      await phoneDevice.syncNow();
      drive.expirePageTokens('rider-a');

      await padDevice.syncNow();
      expect(await padDevice.routeNames(), ['Renamed', 'Route r2']);
      expect(await padDevice.db.syncDao.dirtyRecords(), isEmpty);

      await tick();
      await phoneDevice.renameRoute('r2', 'Again');
      await phoneDevice.syncNow();
      await padDevice.syncNow();
      expect(await padDevice.routeNames(), ['Again', 'Renamed']);
    });

    test('settings written on one device reach the other', () async {
      await phoneDevice.engine.writeSettings({'units.system': 'imperial'});
      await padDevice.engine.fetchNow();
      expect(padDevice.settingsHeard, [
        {'units.system': 'imperial'},
      ]);
      expect(drive.fields('rider-a', 'settings'), {'units.system': 'imperial'});
    });

    test('a full Drive says so until a save goes through', () async {
      await phoneDevice.db.routesDao.upsertRoute(fullRoute('r1'));
      drive.quotaFull = true;
      await phoneDevice.syncNow();
      expect(
        (await phoneDevice.statusNow()).error,
        CloudSyncError.quotaExceeded,
      );
      drive.quotaFull = false;
      await phoneDevice.syncNow();
      expect((await phoneDevice.statusNow()).error, isNull);
      expect(drive.namesOf('rider-a'), {'route_r1'});
    });
  });

  group('the file layout', () {
    test('a record with a body: a versioned JSON line, then the body', () {
      final (:properties, :content) = driveRecordFile('Ride', {
        'name': 'x',
        'modifiedAt': 5,
        'schemaVersion': 1,
      }, Uint8List.fromList([10, 13, 0]));
      expect(properties, {'kind': 'Ride', 'modifiedAt': '5', 'codec': '1'});
      final line = utf8.decode(content.sublist(0, content.indexOf(10)));
      expect(jsonDecode(line), {
        'v': 1,
        'type': 'Ride',
        'fields': {'name': 'x', 'modifiedAt': 5, 'schemaVersion': 1},
        'body': true,
      });
      final record = readDriveRecord(
        'ride_a',
        properties,
        content,
        version: 'v',
      )!;
      expect(record.body, [10, 13, 0]);
      expect(record.fields['modifiedAt'], 5);
    });

    test('short text fields alone: all in the properties, no content', () {
      final fields = {'appUserId': r'$RCAnonymousID:abc', 'platform': 'ios'};
      final (:properties, :content) = driveRecordFile(
        'PlusDevice',
        fields,
        null,
      );
      expect(content, isEmpty);
      expect(properties, {'kind': 'PlusDevice', ...fields});
      final record = readDriveRecord(
        'plus_d1',
        properties,
        content,
        version: 'v',
      )!;
      expect(record.type, 'PlusDevice');
      expect(record.fields, fields);
      expect(record.body, isNull);
    });

    test('typed or long fields go into the JSON line', () {
      for (final fields in [
        {'units.system': 'imperial', 'navigation.voice': true},
        {'name': 'x' * 200},
      ]) {
        final (:properties, :content) = driveRecordFile(
          'Settings',
          fields,
          null,
        );
        expect(properties, {'kind': 'Settings'});
        expect(
          readDriveRecord('settings', properties, content, version: '')!.fields,
          fields,
        );
      }
    });

    test('a header newer than this build, or junk, is no record', () {
      final newer = utf8.encode('{"v":2,"type":"Route","fields":{}}\n');
      for (final bytes in [newer, utf8.encode('junk')]) {
        expect(
          readDriveRecord(
            'route_a',
            const {'kind': 'Route'},
            Uint8List.fromList(bytes),
            version: '',
          ),
          isNull,
        );
      }
    });

    test(
      'a record turned into fields alone loses the old properties',
      () async {
        final [created] = await phone.push([
          _save('plus_d1', fields: {'name': 'x' * 200}, body: null),
        ]);
        await phone.push([
          _save(
            'plus_d1',
            ifVersion: _versionOf(created),
            fields: {'platform': 'ios'},
            body: null,
          ),
        ]);
        final [file] = drive.filesOf('rider-a');
        expect(file.appProperties, {'kind': 'Route', 'platform': 'ios'});
        expect((await pad.get('plus_d1'))!.fields, {'platform': 'ios'});
        expect(drive.downloads, 0, reason: 'nothing to download');
      },
    );
  });
}
