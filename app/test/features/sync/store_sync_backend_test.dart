import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/sync/data/cloud_store.dart';
import 'package:velorki/features/sync/data/store_sync_backend.dart';
import 'package:velorki/features/sync/data/sync_backend.dart';
import 'package:velorki/features/sync/domain/cloud_record.dart';
import 'package:velorki/features/sync/domain/cloud_sync_status.dart';

import 'support/memory_cloud_store.dart';
import 'support/rows.dart';
import 'support/sync_device.dart';

void main() {
  // Two devices, two in-memory databases, on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  late MemoryCloudStore store;
  late SyncDevice phone;
  late SyncDevice pad;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('store_sync');
    store = MemoryCloudStore();
    phone = SyncDevice(store, dir, 'phone', batchSize: 2);
    pad = SyncDevice(store, dir, 'pad');
    await phone.open();
    await pad.open();
  });
  tearDown(() async {
    await phone.close();
    await pad.close();
    await phone.db.close();
    await pad.db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

  test('the library goes in batches, once, then nothing waits', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    await phone.db.routesDao.upsertRoute(fullRoute('r2'));
    await phone.db.ridesDao.upsertRide(fullRide('ride1', routeId: 'r1'));

    await phone.syncNow();
    expect(store.names, {'route_r1', 'route_r2', 'ride_ride1'});
    expect(store.pushes, 2, reason: 'two to a batch');
    expect(store.fields('ride_ride1')!['routeId'], 'r1');
    expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
    expect((await phone.statusNow()).lastSyncedAt, isNotNull);
    expect((await phone.statusNow()).account, CloudAccount.available);

    // The own changes fetched back write nothing, and nothing goes again.
    await phone.syncNow();
    expect(store.pushes, 2);
    expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
  });

  test('a new device gets everything, rides linked to their routes', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1', points: 5000));
    await phone.db.ridesDao.upsertRide(
      fullRide('ride1', points: 20000, routeId: 'r1'),
    );
    await phone.syncNow();

    await pad.syncNow();
    final ride = await pad.db.ridesDao.rideById('ride1');
    expect(ride?.routeId, 'r1');
    expect((await pad.db.routesDao.routeById('r1'))?.geometry, isNotEmpty);
    expect(await pad.db.syncDao.dirtyRecords(), isEmpty);
  });

  test('an error that is not the store\'s ends the round with an error, '
      'never left syncing, and the next round brings the changes '
      'again', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    await phone.syncNow();
    final broken = _BrokenDevice(store, dir, 'broken');
    await broken.open();
    addTearDown(() async {
      await broken.close();
      await broken.db.close();
    });

    await broken.syncNow();
    final status = await broken.statusNow();
    expect(status.syncing, isFalse);
    expect(status.error, CloudSyncError.other);
    expect(broken.state.values['cursor'], isNull);

    broken.fails = false;
    await broken.syncNow();
    expect(await broken.routeNames(), ['Route r1']);
    expect((await broken.statusNow()).error, isNull);
  });

  test('a round that failed after the download hands the same page over '
      'again, without asking the store for it', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    await phone.db.routesDao.upsertRoute(fullRoute('r2'));
    await phone.syncNow();
    final broken = _BrokenDevice(store, dir, 'broken');
    await broken.open();
    addTearDown(() async {
      await broken.close();
      await broken.db.close();
    });

    await broken.syncNow();
    expect((await broken.statusNow()).error, CloudSyncError.other);
    final lists = store.fullLists;
    final pulls = store.pulls;

    broken.fails = false;
    await broken.syncNow();
    expect(store.fullLists, lists, reason: 'nothing downloaded again');
    expect(store.pulls, pulls);
    expect(await broken.routeNames(), ['Route r1', 'Route r2']);
    expect((await broken.statusNow()).error, isNull);
    expect(broken.state.values['cursor'], isNotNull);
  });

  test('a listing cut short goes on from the page that failed', () async {
    for (final id in ['r1', 'r2', 'r3']) {
      await phone.db.routesDao.upsertRoute(fullRoute(id));
    }
    await phone.syncNow();
    store.pageSize = 1;
    final broken = _BrokenDevice(store, dir, 'broken', takes: 1);
    await broken.open();
    addTearDown(() async {
      await broken.close();
      await broken.db.close();
    });
    final lists = store.fullLists;

    await broken.syncNow();
    expect(store.fullLists, lists + 2, reason: 'the first page taken');
    expect(await broken.routeNames(), hasLength(1));

    broken.fails = false;
    await broken.syncNow();
    expect(
      store.fullLists,
      lists + 3,
      reason: 'the second page again from memory, then the third',
    );
    expect(await broken.routeNames(), ['Route r1', 'Route r2', 'Route r3']);
    expect((await broken.statusNow()).error, isNull);
  });

  test('a rename reaches the other device, and one back again', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    await phone.syncNow();
    await pad.syncNow();

    await tick();
    await pad.renameRoute('r1', 'Pad');
    await pad.syncNow();
    await phone.syncNow();
    expect(await phone.routeName('r1'), 'Pad');

    await tick();
    await phone.renameRoute('r1', 'Phone');
    await phone.syncNow();
    await pad.syncNow();
    expect(await pad.routeName('r1'), 'Phone');
    expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
    expect(await pad.db.syncDao.dirtyRecords(), isEmpty);
  });

  group('a conflict goes to the newer change', () {
    setUp(() async {
      await phone.db.ridesDao.upsertRide(fullRide('ride1'));
      await phone.syncNow();
      await pad.syncNow();
      await phone.db.ridesDao.renameRide('ride1', 'Phone');
      await pad.db.ridesDao.renameRide('ride1', 'Pad');
    });

    test('the newer one sent second wins on both', () async {
      await phone.setChangedAt('ride', 'ride1', 1000);
      await pad.setChangedAt('ride', 'ride1', 2000);
      await phone.syncNow();
      await pad.syncNow();
      await phone.syncNow();

      expect(await phone.rideNames(), ['Pad']);
      expect(await pad.rideNames(), ['Pad']);
      expect(store.fields('ride_ride1')!['name'], 'Pad');
    });

    test('the newer one sent first wins on both', () async {
      await phone.setChangedAt('ride', 'ride1', 3000);
      await pad.setChangedAt('ride', 'ride1', 2000);
      await phone.syncNow();
      await pad.syncNow();
      await phone.syncNow();

      expect(await phone.rideNames(), ['Phone']);
      expect(await pad.rideNames(), ['Phone']);
      expect(await pad.db.syncDao.dirtyRecords(), isEmpty);
    });

    test('a tie goes to the copy in the store, alike everywhere', () async {
      await phone.setChangedAt('ride', 'ride1', 2000);
      await pad.setChangedAt('ride', 'ride1', 2000);
      await phone.syncNow();
      await pad.syncNow();
      await phone.syncNow();

      expect(await phone.rideNames(), ['Phone']);
      expect(await pad.rideNames(), ['Phone']);
    });
  });

  test('a rename while the first is on its way: the second reaches the '
      'other device', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    await phone.syncNow();
    await pad.syncNow();

    await tick();
    await phone.renameRoute('r1', 'Name 1');
    await phone.sync.push();
    store
      ..gate = Completer<void>()
      ..atGate = Completer<void>();
    final sending = phone.engine.sendNow();
    await store.atGate!.future;
    await tick();
    await phone.renameRoute('r1', 'Name 2');
    await phone.sync.push();
    final gate = store.gate!;
    store.gate = null;
    gate.complete();
    await sending;
    await phone.engine.sendNow();
    await pad.syncNow();

    expect(store.fields('route_r1')!['name'], 'Name 2');
    expect(await pad.routeName('r1'), 'Name 2');
    expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
  });

  group('delete against edit', () {
    setUp(() async {
      await phone.db.routesDao.upsertRoute(fullRoute('r1'));
      await phone.syncNow();
      await pad.syncNow();
    });

    test('a delete elsewhere removes an unchanged route', () async {
      await pad.db.routesDao.deleteRoute('r1');
      await pad.syncNow();
      expect(store.names, isEmpty);

      await phone.syncNow();
      expect(await phone.routeNames(), isEmpty);
      expect(await phone.db.syncDao.record('route', 'r1'), isNull);
    });

    test('an edit here not yet sent brings a deleted route back', () async {
      await pad.db.routesDao.deleteRoute('r1');
      await pad.syncNow();
      await phone.db.customStatement("UPDATE routes SET name = 'Kept'");

      await phone.engine.fetchNow();
      expect(await phone.routeNames(), ['Kept']);
      await phone.syncNow();
      await pad.syncNow();

      expect(store.names, {'route_r1'});
      expect(await pad.routeNames(), ['Kept']);
    });
  });

  group('a restart', () {
    setUp(() async {
      await phone.db.routesDao.upsertRoute(fullRoute('r1'));
      await phone.syncNow();
      await pad.syncNow();
    });

    test('before a change was sent: it goes after', () async {
      await tick();
      await phone.renameRoute('r1', 'Name 1');
      await phone.sync.push();
      await phone.restart();
      await phone.syncNow();
      await pad.syncNow();
      expect(await pad.routeName('r1'), 'Name 1');
      expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
    });

    test(
      'while a save was on its way, its answer lost: settled after',
      () async {
        await tick();
        await phone.renameRoute('r1', 'Name 1');
        await phone.sync.push();
        store.loseReplies = true;
        await phone.engine.sendNow();
        expect(store.fields('route_r1')!['name'], 'Name 1');
        expect((await phone.statusNow()).error, CloudSyncError.network);
        store.loseReplies = false;

        await phone.restart();
        await tick();
        await phone.renameRoute('r1', 'Name 2');
        await phone.syncNow();
        await phone.syncNow();
        await pad.syncNow();

        expect(store.fields('route_r1')!['name'], 'Name 2');
        expect(await pad.routeName('r1'), 'Name 2');
        expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
        expect((await phone.statusNow()).error, isNull);
      },
    );
  });

  test('changes made while sync was off here arrive when it is on', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    await phone.syncNow();
    await pad.syncNow();
    await pad.close();

    await tick();
    await phone.renameRoute('r1', 'Renamed');
    await phone.db.routesDao.upsertRoute(fullRoute('r2'));
    await phone.syncNow();

    await pad.open();
    await pad.engine.fetchNow();
    expect(await pad.routeNames(), ['Renamed', 'Route r2']);
    expect(await pad.db.syncDao.dirtyRecords(), isEmpty);
  });

  test('an expired cursor lists the whole store again', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    await phone.syncNow();
    await pad.syncNow();

    await tick();
    await phone.renameRoute('r1', 'Renamed');
    await phone.db.routesDao.upsertRoute(fullRoute('r2'));
    await phone.syncNow();
    store
      ..expireCursors()
      ..pageSize = 1;
    final lists = store.fullLists;

    await pad.syncNow();
    expect(store.fullLists, greaterThan(lists + 1), reason: 'page by page');
    expect(await pad.routeNames(), ['Renamed', 'Route r2']);
    expect(await pad.db.syncDao.dirtyRecords(), isEmpty);

    // From the new cursor on, changes come as before.
    await tick();
    await phone.renameRoute('r2', 'Again');
    await phone.syncNow();
    await pad.syncNow();
    expect(await pad.routeNames(), ['Again', 'Renamed']);
  });

  test('another account gets the whole library, deleted nowhere', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    await phone.db.ridesDao.upsertRide(fullRide('ride1'));
    await phone.syncNow();
    expect(store.namesOf('rider-a'), {'route_r1', 'ride_ride1'});

    store.account = 'rider-b';
    await phone.syncNow();
    await phone.engine.sendNow();

    expect(phone.accountChanges, [AccountChange.switchAccounts]);
    expect(store.namesOf('rider-b'), {'route_r1', 'ride_ride1'});
    expect(store.namesOf('rider-a'), {'route_r1', 'ride_ride1'});
    expect(await phone.routeNames(), ['Route r1']);
    expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
  });

  test('signed out, nothing is sent; signed in again, everything is', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    await phone.syncNow();

    store.account = null;
    await phone.engine.fetchNow();
    expect((await phone.statusNow()).account, CloudAccount.noAccount);
    final pushes = store.pushes;
    await phone.db.routesDao.upsertRoute(fullRoute('r2'));
    await phone.syncNow();
    expect(store.pushes, pushes);
    expect(await phone.routeNames(), ['Route r1', 'Route r2']);

    store.account = 'rider-a';
    await phone.syncNow();
    await phone.engine.sendNow();
    expect(phone.accountChanges, [AccountChange.signOut, AccountChange.signIn]);
    expect(store.names, {'route_r1', 'route_r2'});
    expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
  });

  test('a transient failure keeps the change waiting until it goes', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    store.failNext.add(CloudStoreFailure.transient);
    await phone.sync.push();
    await phone.engine.sendNow();
    expect(store.names, isEmpty);
    expect((await phone.statusNow()).error, CloudSyncError.network);
    expect(await phone.db.syncDao.dirtyRecords(), hasLength(1));

    await phone.engine.sendNow();
    expect(store.names, {'route_r1'});
    expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
  });

  test('with scheduling on, a transient failure is tried again after the '
      'backoff, by itself', () async {
    final waits = <int>[];
    final engine = StoreSyncBackend(
      store: store,
      state: MapSyncState(),
      inbox: () async => Directory('${dir.path}/auto/in'),
      sendDelay: Duration.zero,
      backoff: (failures) {
        waits.add(failures);
        return const Duration(milliseconds: 20);
      },
    );
    final saved = Completer<void>();
    engine.setHandler(
      _OneRecord(
        dir,
        onSaved: () {
          if (!saved.isCompleted) saved.complete();
        },
      ),
    );
    addTearDown(engine.stop);
    store.failNext.addAll([
      CloudStoreFailure.transient,
      CloudStoreFailure.transient,
    ]);
    await engine.start();
    await engine.enqueue(saves: ['route_x']);
    await saved.future.timeout(const Duration(seconds: 5));
    expect(waits, [1, 2], reason: 'longer each time');
    expect(store.names, {'route_x'});
  });

  test('the backoff doubles to five minutes, with a little jitter', () {
    final random = math.Random(1);
    for (final (failures, seconds) in [(1, 2), (2, 4), (5, 32), (20, 300)]) {
      final wait = syncBackoff(failures, random).inMilliseconds;
      expect(wait, inInclusiveRange(seconds * 800, seconds * 1200));
    }
  });

  test('a full store says so until a save goes through', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    store.failNext.add(CloudStoreFailure.quotaExceeded);
    await phone.syncNow();
    expect((await phone.statusNow()).error, CloudSyncError.quotaExceeded);
    expect(await phone.db.syncDao.dirtyRecords(), hasLength(1));

    await phone.syncNow();
    expect((await phone.statusNow()).error, isNull);
    expect(store.names, {'route_r1'});
  });

  test('settings written on one device reach the other', () async {
    await phone.engine.writeSettings({'units.system': 'imperial'});
    await pad.engine.fetchNow();
    expect(pad.settingsHeard, [
      {'units.system': 'imperial'},
    ]);
    expect(await pad.engine.readSettings(['units.system', 'other']), {
      'units.system': 'imperial',
    });

    // Both change a key each at once: neither is lost.
    await pad.engine.writeSettings({'appearance.mode': 'dark'});
    await phone.engine.writeSettings({'units.system': null});
    await pad.engine.fetchNow();
    await phone.engine.fetchNow();
    expect(
      await phone.engine.readSettings(['units.system', 'appearance.mode']),
      {'appearance.mode': 'dark'},
    );
    expect(pad.settingsHeard.last, {'units.system': null});
    expect(store.fields('settings'), {'appearance.mode': 'dark'});
  });
}

/// A handler with one route record to save, for an engine on its own.
class _OneRecord implements CloudSyncHandler {
  _OneRecord(this.dir, {required this.onSaved});

  final Directory dir;
  final void Function() onSaved;

  @override
  Future<List<CloudRecord>> recordsToSave(List<String> names) async => [
    for (final name in names)
      CloudRecord(name: name, type: 'Route', fields: const {'name': 'X'}),
  ];

  @override
  Future<void> sent(SentChanges changes) async {
    if (changes.saved.isNotEmpty) onSaved();
  }

  @override
  Future<void> applyRemote(
    List<CloudRecord> modifications,
    List<String> deletions,
  ) async {}

  @override
  Future<void> accountChanged(AccountChange change) async {}

  @override
  Future<void> zoneDeleted(ZoneDeletion reason) async {}

  @override
  Future<void> settingsChanged(Map<String, Object?> values) async {}
}

/// A device whose library throws on what arrives while [fails].
class _BrokenDevice extends SyncDevice {
  _BrokenDevice(super.store, super.dir, super.name, {this.takes = 0});

  bool fails = true;

  /// How many pages are taken before it breaks.
  int takes;

  @override
  Future<void> applyRemote(
    List<CloudRecord> modifications,
    List<String> deletions,
  ) async {
    if (fails && takes-- <= 0) throw StateError('broken');
    return super.applyRemote(modifications, deletions);
  }
}
