import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/sync/data/cloud_store.dart';
import 'package:velorki/features/sync/data/cloudkit_js_cloud_store.dart';
import 'package:velorki/features/sync/data/cloudkit_web.dart';
import 'package:velorki/features/sync/data/record_codec.dart';
import 'package:velorki/features/sync/data/sync_backend.dart';
import 'package:velorki/features/sync/domain/cloud_record.dart';
import 'package:velorki/features/sync/domain/cloud_sync_status.dart';

import 'support/fake_cloudkit.dart';
import 'support/rows.dart';
import 'support/sync_device.dart';

StoreSave _save(
  String name, {
  String? ifVersion,
  Map<String, Object?> fields = const {
    'name': 'A',
    'modifiedAt': 1,
    'distanceM': 42000.0,
    'ascentM': 310.5,
  },
  List<int>? body = const [0x1f, 0x8b, 1, 2, 3],
}) => StoreSave(
  name,
  type: 'Route',
  fields: fields,
  body: body == null ? null : Uint8List.fromList(body),
  ifVersion: ifVersion,
);

List<int> _gz(String content, {int level = 6}) =>
    ZLibCodec(gzip: true, level: level).encode(utf8.encode(content));

String _versionOf(StoreResult result) => (result as StoreDone).version!;

void main() {
  late FakeCloudKit cloud;
  late FakeCloudKitWeb browser;
  late FakeCloudKitWeb other;
  late CloudKitJsCloudStore store;
  late CloudKitJsCloudStore otherStore;

  setUp(() {
    cloud = FakeCloudKit();
    browser = cloud.client();
    other = cloud.client();
    store = CloudKitJsCloudStore(api: browser, state: MapSyncState());
    otherStore = CloudKitJsCloudStore(api: other, state: MapSyncState());
  });

  test('only CloudKit upload URLs are routed to the relay', () {
    const ok = 'https://cws.icloud-content.com/B/a/singleFileUpload?tk=t';
    expect(isCloudKitUploadUrl(ok), isTrue);
    expect(
      isCloudKitUploadUrl(
        'https://p57-contentws.icloud.com/a/singleFileUpload?tk=t',
      ),
      isTrue,
    );
    for (final bad in [
      'http://cws.icloud-content.com/B/a/singleFileUpload?tk=t',
      'https://cws.icloud-content.com.evil.example/a/singleFileUpload?tk=t',
      'https://cws.icloud-content.com:8443/a/singleFileUpload?tk=t',
      'https://u:p@cws.icloud-content.com/a/singleFileUpload?tk=t',
      'https://cws.icloud-content.com/a/other?tk=t',
      'https://cws.icloud-content.com/a/singleFileUpload',
      'https://cvws.icloud-content.com/a/singleFileUpload?tk=t',
      'https://api.apple-cloudkit.com/database/1/x',
    ]) {
      expect(isCloudKitUploadUrl(bad), isFalse, reason: bad);
    }
  });

  group('an unchanged body', () {
    final track = 'x' * 4000;

    test('is not uploaded again: a rename sends the fields alone', () async {
      final [first] = await store.push([_save('route_1', body: _gz(track))]);
      final [renamed] = await store.push([
        _save(
          'route_1',
          ifVersion: _versionOf(first),
          fields: const {
            'name': 'B',
            'modifiedAt': 2,
            'distanceM': 42000.0,
            'ascentM': 310.5,
          },
          // Another compressor, the same content.
          body: _gz(track, level: 1),
        ),
      ]);
      expect(renamed, isA<StoreDone>());
      expect(cloud.writes, ['create route_1', 'update route_1']);

      final read = (await otherStore.get('route_1'))!;
      expect(read.fields['name'], 'B');
      expect(read.body, _gz(track), reason: 'the body on the server is kept');
      expect(read.version, _versionOf(renamed));

      // And the next save after it is an update again.
      final [again] = await store.push([
        _save(
          'route_1',
          ifVersion: _versionOf(renamed),
          fields: const {
            'name': 'C',
            'modifiedAt': 3,
            'distanceM': 42000.0,
            'ascentM': 310.5,
          },
          body: _gz(track),
        ),
      ]);
      expect(again, isA<StoreDone>());
      expect(cloud.writes.last, 'update route_1');
    });

    test('is known from what was downloaded, too', () async {
      await otherStore.push([_save('route_1', body: _gz(track))]);
      final read = (await store.get('route_1'))!;
      final [saved] = await store.push([
        _save('route_1', ifVersion: read.version, body: _gz(track)),
      ]);
      expect(saved, isA<StoreDone>());
      expect(cloud.writes.last, 'update route_1');
    });

    test('a changed track is replaced, body and all', () async {
      final [first] = await store.push([_save('route_1', body: _gz(track))]);
      final [second] = await store.push([
        _save('route_1', ifVersion: _versionOf(first), body: _gz('${track}y')),
      ]);
      expect(cloud.writes, ['create route_1', 'replace route_1']);
      expect((await otherStore.get('route_1'))!.body, _gz('${track}y'));
      // The new body is the one known now.
      await store.push([
        _save('route_1', ifVersion: _versionOf(second), body: _gz('${track}y')),
      ]);
      expect(cloud.writes.last, 'update route_1');
    });

    test('with no digest known the body goes up as before', () async {
      final [first] = await store.push([_save('route_1', body: _gz(track))]);
      final tag = _versionOf(first).split('#').first;
      await store.push([_save('route_1', ifVersion: tag, body: _gz(track))]);
      expect(cloud.writes, ['create route_1', 'replace route_1']);
    });

    test('a changed set of fields is replaced, not updated', () async {
      final [first] = await store.push([_save('route_1', body: _gz(track))]);
      await store.push([
        _save(
          'route_1',
          ifVersion: _versionOf(first),
          fields: const {'name': 'A', 'modifiedAt': 1},
          body: _gz(track),
        ),
      ]);
      expect(cloud.writes.last, 'replace route_1');
      expect(cloud.fieldsOf('user-a', 'route_1')!.keys, {'name', 'modifiedAt'});
    });
  });

  group('a record', () {
    test('goes up with its body as an asset and its fields typed as the '
        "iPhone's schema has them, and reads back whole", () async {
      final [saved] = await store.push([_save('route_1')]);
      expect(saved, isA<StoreDone>());
      expect(cloud.writes, ['create route_1']);
      final fields = cloud.fieldsOf('user-a', 'route_1')!;
      expect(fields['name']!.type, 'STRING');
      expect(fields['modifiedAt']!.type, 'INT64');
      expect(
        (fields['distanceM']!.type, fields['distanceM']!.value),
        ('DOUBLE', 42000.0),
        reason: 'a whole number in a Double field stays a double',
      );

      final read = (await otherStore.get('route_1'))!;
      expect(read.type, 'Route');
      expect(read.body, [0x1f, 0x8b, 1, 2, 3]);
      expect(read.fields, {
        'name': 'A',
        'modifiedAt': 1,
        'distanceM': 42000.0,
        'ascentM': 310.5,
      });
      expect(read.fields['distanceM'], isA<double>());
      expect(read.version, _versionOf(saved));
      expect(await store.get('route_2'), isNull);
    });

    test('goes over the change tag it was read at, and only that', () async {
      final v1 = _versionOf((await store.push([_save('route_1')])).single);
      final v2 = _versionOf(
        (await store.push([_save('route_1', ifVersion: v1)])).single,
      );
      expect(cloud.writes.last, 'replace route_1');

      final [stale] = await otherStore.push([
        _save('route_1', ifVersion: v1, fields: {'name': 'B'}),
      ]);
      expect(stale, isA<StoreConflict>());
      final server = (stale as StoreConflict).server;
      expect(server.version, v2);
      expect(server.fields['name'], 'A');
      expect(server.body, isNotNull);
    });

    test('new where there is one already is a conflict', () async {
      await store.push([_save('route_1')]);
      final [result] = await otherStore.push([_save('route_1')]);
      expect(result, isA<StoreConflict>());
    });

    test('over a tag of one deleted since is missing', () async {
      final v1 = _versionOf((await store.push([_save('route_1')])).single);
      cloud.deleteElsewhere('user-a', 'route_1');
      expect(
        (await store.push([_save('route_1', ifVersion: v1)])).single,
        isA<StoreMissing>(),
      );
    });

    test('deleted where it is gone already is deleted', () async {
      expect(
        (await store.push([const StoreDelete('route_9')])).single,
        isA<StoreDone>(),
      );
    });

    test('a zone not there yet is made by the first save', () async {
      cloud.zoneExists = false;
      final fresh = CloudKitJsCloudStore(
        api: cloud.client(user: 'user-new'),
        state: MapSyncState(),
      );
      expect(
        await fresh.pull(''),
        isA<StoreChanges>().having((c) => c.changed, 'changed', isEmpty),
      );
      expect(cloud.hasZone('user-new'), isFalse);
      expect((await fresh.push([_save('route_1')])).single, isA<StoreDone>());
      expect(cloud.hasZone('user-new'), isTrue);
      expect(cloud.namesOf('user-new'), {'route_1'});
    });
  });

  group('failures', () {
    test('a full iCloud refuses the save as over quota', () async {
      browser.failure = const CkError('QUOTA_EXCEEDED');
      await expectLater(
        store.push([_save('route_1')]),
        throwsA(
          isA<CloudStoreException>().having(
            (e) => e.failure,
            'failure',
            CloudStoreFailure.quotaExceeded,
          ),
        ),
      );
    });

    test('a busy or unreachable CloudKit is transient', () async {
      for (final code in [
        'THROTTLED',
        'NETWORK_ERROR',
        'SERVICE_UNAVAILABLE',
      ]) {
        browser.failure = CkError(code);
        await expectLater(
          store.pull(''),
          throwsA(
            isA<CloudStoreException>().having(
              (e) => e.failure,
              'failure',
              CloudStoreFailure.transient,
            ),
          ),
        );
      }
    });

    test('a throttled download says how long to wait, and names the '
        'record', () async {
      await otherStore.push([_save('route_1')]);
      browser.downloadFailure = const CkError(
        'THROTTLED',
        reason: 'asset HTTP 429',
        retryAfter: Duration(seconds: 30),
      );
      await expectLater(
        store.pull(''),
        throwsA(
          isA<CloudStoreException>()
              .having((e) => e.failure, 'failure', CloudStoreFailure.transient)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 30),
              ),
        ),
      );
    });

    test('a session run out keeps the account, and every call wants the '
        'rider to sign in again', () async {
      expect(await store.accountId(), 'user-a');
      browser.expired = true;
      expect(await store.accountId(), 'user-a', reason: 'still theirs');
      await expectLater(
        store.push([_save('route_1')]),
        throwsA(
          isA<CloudStoreException>().having(
            (e) => e.failure,
            'failure',
            CloudStoreFailure.signInNeeded,
          ),
        ),
      );
      browser.signIn('user-a');
      await pumpEventQueue();
      expect((await store.push([_save('route_1')])).single, isA<StoreDone>());
    });

    test('a session CloudKit refuses (HTTP 421) is asked nothing more until '
        'the rider signs in again', () async {
      expect(await store.accountId(), 'user-a');
      browser.expired = true;
      final signOuts = <String?>[];
      final sub = browser.users.listen(signOuts.add);
      addTearDown(sub.cancel);
      Matcher signInNeeded() => throwsA(
        isA<CloudStoreException>().having(
          (e) => e.failure,
          'failure',
          CloudStoreFailure.signInNeeded,
        ),
      );
      await expectLater(store.pull(''), signInNeeded());
      await pumpEventQueue();
      expect(signOuts, [null], reason: 'signed out in the browser');
      final asked = browser.requests;
      await expectLater(store.push([_save('route_1')]), signInNeeded());
      await expectLater(store.get('route_1'), signInNeeded());
      expect(browser.requests, asked);

      browser.signIn('user-a');
      expect(await store.accountId(), 'user-a');
      expect((await store.push([_save('route_1')])).single, isA<StoreDone>());
    });

    test('signed out by the rider, there is no account', () async {
      expect(await store.accountId(), 'user-a');
      await browser.signOut();
      await store.signedOut();
      expect(await store.accountId(), isNull);
    });

    test('never signed in, there is no account', () async {
      final none = CloudKitJsCloudStore(
        api: cloud.client(user: null),
        state: MapSyncState(),
      );
      expect(await none.accountId(), isNull);
    });
  });

  group('changes', () {
    test('come from the sync token: saves whole, deletions by name', () async {
      await otherStore.push([_save('route_1'), _save('route_2')]);
      final first = await store.fullList();
      expect({for (final r in first.changed) r.name}, {'route_1', 'route_2'});
      expect(first.more, isFalse);

      final v = (await otherStore.get('route_1'))!.version;
      await otherStore.push([
        _save('route_1', ifVersion: v, fields: {'name': 'B'}),
        const StoreDelete('route_2'),
      ]);
      final next = await store.pull(first.cursor);
      expect([for (final r in next.changed) r.fields['name']], ['B']);
      expect(next.deleted, ['route_2']);
      expect((await store.pull(next.cursor)).changed, isEmpty);
    });

    test('written from here are not downloaded again', () async {
      final start = (await store.fullList()).cursor;
      await store.push([_save('route_1')]);
      final downloads = cloud.downloads.length;
      final changes = await store.pull(start);
      expect(changes.changed, isEmpty);
      expect(cloud.downloads, hasLength(downloads));
    });

    test('come a page at a time', () async {
      cloud.pageSize = 2;
      final start = (await store.fullList()).cursor;
      await otherStore.push([for (var i = 0; i < 5; i++) _save('route_$i')]);
      final first = await store.pull(start);
      expect(first.changed, hasLength(2));
      expect(first.more, isTrue);
    });

    test(
      'from a sync token CloudKit no longer takes: the cursor expired',
      () async {
        final cursor = (await store.fullList()).cursor;
        cloud.expireTokens('user-a');
        await expectLater(
          store.pull(cursor),
          throwsA(isA<StoreCursorExpired>()),
        );
      },
    );
  });

  group('two browsers over one iCloud', () {
    // Two devices, two in-memory databases, on purpose.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    late Directory dir;
    late SyncDevice web;
    late SyncDevice pad;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('cloudkit_sync');
      web = SyncDevice(store, dir, 'web', batchSize: 2, syncsSettings: false);
      pad = SyncDevice(otherStore, dir, 'pad', syncsSettings: false);
      await web.open();
      await pad.open();
    });
    tearDown(() async {
      await web.close();
      await pad.close();
      await web.db.close();
      await pad.db.close();
      dir.deleteSync(recursive: true);
    });

    Future<void> tick() =>
        Future<void>.delayed(const Duration(milliseconds: 5));

    test('the library goes once, and reaches the other whole', () async {
      await web.db.routesDao.upsertRoute(fullRoute('r1', points: 2000));
      await web.db.routesDao.upsertRoute(fullRoute('r2'));
      await web.db.ridesDao.upsertRide(
        fullRide('ride1', points: 5000, routeId: 'r1'),
      );
      await web.syncNow();
      expect(cloud.namesOf('user-a'), {'route_r1', 'route_r2', 'ride_ride1'});
      expect(await web.db.syncDao.dirtyRecords(), isEmpty);
      expect((await web.statusNow()).account, CloudAccount.available);
      // The schema's Double fields go up as doubles, whole or not.
      expect(cloud.fieldsOf('user-a', 'route_r1')!['ascentM']!.type, 'DOUBLE');

      final writes = cloud.writes.length;
      await web.syncNow();
      expect(cloud.writes, hasLength(writes), reason: 'nothing goes again');

      await pad.syncNow();
      expect((await pad.db.ridesDao.rideById('ride1'))?.routeId, 'r1');
      final route = (await pad.db.routesDao.routeById('r1'))!;
      expect(route.geometry, isNotEmpty);
      expect(route.ascentM, 310);
      expect(await pad.routeNames(), ['Route r1', 'Route r2']);
      expect(await pad.db.syncDao.dirtyRecords(), isEmpty);
    });

    test('a rename reaches the other, and one back again', () async {
      await web.db.routesDao.upsertRoute(fullRoute('r1'));
      await web.syncNow();
      await pad.syncNow();

      await tick();
      await pad.renameRoute('r1', 'Pad');
      await pad.syncNow();
      await web.syncNow();
      expect(await web.routeName('r1'), 'Pad');

      await tick();
      await web.renameRoute('r1', 'Web');
      await web.syncNow();
      await pad.syncNow();
      expect(await pad.routeName('r1'), 'Web');
    });

    test('a conflict goes to the newer change on both', () async {
      await web.db.ridesDao.upsertRide(fullRide('ride1'));
      await web.syncNow();
      await pad.syncNow();
      await web.db.ridesDao.renameRide('ride1', 'Web');
      await pad.db.ridesDao.renameRide('ride1', 'Pad');
      await web.setChangedAt('ride', 'ride1', 1000);
      await pad.setChangedAt('ride', 'ride1', 2000);
      await web.syncNow();
      await pad.syncNow();
      await web.syncNow();
      expect(await web.rideNames(), ['Pad']);
      expect(await pad.rideNames(), ['Pad']);
      expect(await web.db.syncDao.dirtyRecords(), isEmpty);
    });

    test('a delete elsewhere removes the route here', () async {
      await web.db.routesDao.upsertRoute(fullRoute('r1'));
      await web.syncNow();
      await pad.syncNow();
      await pad.db.routesDao.deleteRoute('r1');
      await pad.syncNow();
      expect(cloud.namesOf('user-a'), isEmpty);
      await web.syncNow();
      expect(await web.routeNames(), isEmpty);
    });

    test('an expired sync token lists the zone again', () async {
      await web.db.routesDao.upsertRoute(fullRoute('r1'));
      await web.syncNow();
      await pad.syncNow();
      await tick();
      await web.renameRoute('r1', 'Renamed');
      await web.db.routesDao.upsertRoute(fullRoute('r2'));
      await web.syncNow();
      cloud.expireTokens('user-a');
      await pad.syncNow();
      expect(await pad.routeNames(), ['Renamed', 'Route r2']);
    });

    test('a session run out holds what waits, sends it once signed in '
        'again, and resends nothing else', () async {
      await web.db.routesDao.upsertRoute(fullRoute('r1'));
      await web.syncNow();
      browser.expired = true;
      await tick();
      await web.renameRoute('r1', 'Offline');
      await web.syncNow();
      expect((await web.statusNow()).error, CloudSyncError.signInNeeded);
      expect(web.accountChanges, isEmpty, reason: 'still the same account');

      final writes = cloud.writes.length;
      browser.signIn('user-a');
      await web.syncNow();
      expect(cloud.writes.sublist(writes), ['update route_r1']);
      expect((await web.statusNow()).error, isNull);
      await pad.syncNow();
      expect(await pad.routeName('r1'), 'Offline');
    });

    test('a session refused mid-sync signs out here and stops: no retries, '
        'what waits kept, and sent once signed in again', () async {
      await web.db.routesDao.upsertRoute(fullRoute('r1'));
      await web.syncNow();
      final users = <String?>[];
      final sub = browser.users.listen(users.add);
      addTearDown(sub.cancel);
      browser.expired = true;
      await tick();
      await web.renameRoute('r1', 'Offline');
      await web.sync.push();
      await web.engine.sendNow();
      final status = await web.statusNow();
      expect(status.error, CloudSyncError.signInNeeded);
      expect(status.syncing, isFalse);
      expect(users, [null]);
      expect(await web.db.syncDao.dirtyRecords(), isNotEmpty);

      final asked = browser.requests;
      final writes = cloud.writes.length;
      await web.syncNow();
      await web.syncNow();
      expect(browser.requests, asked, reason: 'nothing sent with it again');
      expect((await web.statusNow()).error, CloudSyncError.signInNeeded);
      expect(await web.db.syncDao.dirtyRecords(), isNotEmpty);

      browser.signIn('user-a');
      // As the controller's resume: the account looked at first.
      await web.engine.fetchNow();
      await web.syncNow();
      expect(cloud.writes.sublist(writes), ['update route_r1']);
      expect((await web.statusNow()).error, isNull);
      expect(await web.db.syncDao.dirtyRecords(), isEmpty);
      expect(web.accountChanges, isEmpty);
    });

    test('another Apple Account: the library goes to it as new', () async {
      await web.db.routesDao.upsertRoute(fullRoute('r1'));
      await web.syncNow();
      browser.signIn('user-b');
      // As the controller's resume: the account looked at first.
      await web.engine.fetchNow();
      await web.syncNow();
      expect(web.accountChanges, [AccountChange.switchAccounts]);
      expect(cloud.namesOf('user-b'), {'route_r1'});
      expect(cloud.namesOf('user-a'), {'route_r1'}, reason: 'nothing deleted');
    });

    test('settings stay in the browser', () async {
      await web.engine.writeSettings({'units.system': 'imperial'});
      await web.syncNow();
      expect(cloud.namesOf('user-a'), isEmpty);
      expect(await web.engine.readSettings(['units.system']), isEmpty);
    });
  });

  group('records as the iPhone saves them', () {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('cloudkit_ios'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// What CKSyncEngine saves for [record] (`CloudSync.swift`'s
    /// `makeRecord`): its fields as NSNumber and String, typed as the
    /// schema has them, and its body file as the `body` asset.
    CkSave asSaved(CloudRecord record) => CkSave(
      record.name,
      type: record.type,
      fields: {
        for (final MapEntry(:key, :value) in record.fields.entries)
          if (value != null)
            key: switch (value) {
              final String s => CkValue(s, 'STRING'),
              final num n when cloudKitDoubleFields.contains(key) => CkValue(
                n.toDouble(),
                'DOUBLE',
              ),
              final num n => CkValue(n, 'INT64'),
              _ => throw ArgumentError(value),
            },
      },
      body: File(record.assetPath!).readAsBytesSync(),
      changeTag: null,
    );

    /// The iPhone's library in [other]'s zone: [routes] routes and
    /// [rides] rides, the first rides following the first routes, and a
    /// Plus record beside them.
    Future<void> iPhoneLibrary({int routes = 3, int rides = 4}) async {
      final db = VelorkiDatabase.memory();
      addTearDown(db.close);
      final codec = RecordCodec(Directory('${dir.path}/phone'));
      final saves = <CkWrite>[];
      for (var i = 1; i <= routes; i++) {
        await db.routesDao.upsertRoute(fullRoute('r$i', points: 3000));
        final row = (await db.routesDao.routeById('r$i'))!;
        saves.add(asSaved(await codec.encodeRoute(row, changedAtMs: 1000 + i)));
      }
      for (var i = 1; i <= rides; i++) {
        await db.ridesDao.upsertRide(fullRide('d$i', points: 3000));
        final row = (await db.ridesDao.rideById('d$i'))!;
        saves.add(
          asSaved(
            await codec.encodeRide(
              row,
              changedAtMs: 2000 + i,
              routeId: i <= routes ? 'r$i' : null,
            ),
          ),
        );
      }
      saves.add(
        CkSave(
          'plus_ios',
          type: 'PlusId',
          fields: {
            'appUserId': const CkValue(r'$RCAnonymousID:1', 'STRING'),
            'platform': const CkValue('ios', 'STRING'),
            'entitled': const CkValue(1, 'INT64'),
            'lastSeen': const CkValue(1760000000000, 'INT64'),
          },
          body: null,
          changeTag: null,
        ),
      );
      final results = await other.modify(saves);
      expect(results.where((r) => r.error != null), isEmpty);
    }

    test('reach the browser\'s library whole, rides on their routes, and '
        'the round ends synced', () async {
      await iPhoneLibrary();
      final web = SyncDevice(store, dir, 'web', syncsSettings: false);
      await web.open();
      addTearDown(() async {
        await web.close();
        await web.db.close();
      });

      await web.syncNow();

      expect(await web.routeNames(), ['Route r1', 'Route r2', 'Route r3']);
      expect(await web.rideNames(), [
        'Ride d1',
        'Ride d2',
        'Ride d3',
        'Ride d4',
      ]);
      expect((await web.db.ridesDao.rideById('d2'))?.routeId, 'r2');
      final route = (await web.db.routesDao.routeById('r1'))!;
      expect(route.geometry, isNotEmpty);
      expect(route.distanceM, 42000.5);
      expect(route.ascentM, 310, reason: 'a whole Double comes back');
      expect(await web.db.syncDao.dirtyRecords(), isEmpty);
      final status = await web.statusNow();
      expect(status.syncing, isFalse);
      expect(status.error, isNull);
      expect(status.lastSyncedAt, isNotNull);
    });

    test('a record the database does not write in time ends the round with '
        'an error, never left syncing, and the next round brings it '
        'again', () async {
      await iPhoneLibrary(routes: 2, rides: 0);
      final gate = _Gate();
      final web = SyncDevice(
        store,
        dir,
        'web',
        syncsSettings: false,
        recordTimeout: const Duration(milliseconds: 200),
        db: VelorkiDatabase(NativeDatabase.memory().interceptWith(gate)),
      );
      await web.open();
      addTearDown(() async {
        await web.close();
        await web.db.close();
      });

      gate.closed = Completer<void>();
      await web.syncNow();
      final stalled = await web.statusNow();
      expect(stalled.syncing, isFalse);
      expect(stalled.error, CloudSyncError.other);
      expect(web.state.values['cursor'], isNull, reason: 'nothing skipped');

      gate.closed!.complete();
      gate.closed = null;
      await web.syncNow();
      expect(await web.routeNames(), ['Route r1', 'Route r2']);
      final synced = await web.statusNow();
      expect(synced.error, isNull);
      expect(synced.syncing, isFalse);
    });
  });
}

/// Holds every write to `routes` while [closed] is pending: a database that
/// does not answer.
class _Gate extends QueryInterceptor {
  Completer<void>? closed;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (statement.contains('"routes"')) await closed?.future;
    return executor.runInsert(statement, args);
  }
}
