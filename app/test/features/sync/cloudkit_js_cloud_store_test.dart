import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/sync/data/cloud_store.dart';
import 'package:velorki/features/sync/data/cloudkit_js_cloud_store.dart';
import 'package:velorki/features/sync/data/cloudkit_web.dart';
import 'package:velorki/features/sync/data/sync_backend.dart';
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
      expect(cloud.writes.sublist(writes), ['replace route_r1']);
      expect((await web.statusNow()).error, isNull);
      await pad.syncNow();
      expect(await pad.routeName('r1'), 'Offline');
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
}
