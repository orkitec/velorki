import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/sync/application/library_sync.dart';
import 'package:velorki/features/sync/data/cloud_store.dart';
import 'package:velorki/features/sync/data/record_codec.dart';
import 'package:velorki/features/sync/data/store_sync_backend.dart';
import 'package:velorki/features/sync/data/sync_backend.dart';
import 'package:velorki/features/sync/domain/cloud_record.dart';
import 'package:velorki/features/sync/domain/cloud_sync_status.dart';

import 'support/memory_cloud_store.dart';
import 'support/rows.dart';

/// [SyncEngineState] in a map that outlives the engine, as the shared
/// preferences outlive a restart.
class _MapState implements SyncEngineState {
  final Map<String, String> values = <String, String>{};

  @override
  String? read(String key) => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
}

/// One phone or tablet: its own database, engine state and engine over the
/// shared store, and a handler that does what the controller does.
class _Device implements CloudSyncHandler {
  _Device(this.store, Directory dir, String name, {this.batchSize = 20})
    : db = VelorkiDatabase.memory(),
      _dir = Directory('${dir.path}/$name');

  final VelorkiDatabase db;
  final MemoryCloudStore store;
  final Directory _dir;
  final int batchSize;
  final _MapState state = _MapState();
  late StoreSyncBackend engine;
  late LibrarySync sync;
  CloudSyncStatus status = const CloudSyncStatus();
  final List<Map<String, Object?>> settingsHeard = <Map<String, Object?>>[];
  final List<AccountChange> accountChanges = <AccountChange>[];
  StreamSubscription<CloudSyncStatus>? _statusSub;

  /// The app opened: a new engine over the state kept, a new library sync,
  /// and what waits handed over, as the controller's start does.
  Future<void> open() async {
    engine = StoreSyncBackend(
      store: store,
      state: state,
      inbox: () async => Directory('${_dir.path}/in'),
      batchSize: batchSize,
      scheduling: false,
    );
    sync = LibrarySync(
      db: db,
      backend: engine,
      codec: RecordCodec(Directory('${_dir.path}/out')),
    );
    engine.setHandler(this);
    _statusSub = engine.status.listen((s) => status = s);
    await engine.start();
    await sync.push();
  }

  /// The app killed: the database and the engine state stay.
  Future<void> close() async {
    await _statusSub?.cancel();
    await sync.stop();
    engine.setHandler(null);
    await engine.stop();
  }

  /// The status the engine sent last, once its stream has delivered it.
  Future<CloudSyncStatus> statusNow() async {
    await pumpEventQueue();
    return status;
  }

  Future<void> restart() async {
    await close();
    await open();
  }

  /// Hands the waiting changes over, sends them and fetches.
  Future<void> syncNow() async {
    await sync.push();
    await engine.sendNow();
    await engine.fetchNow();
  }

  Future<void> renameRoute(String id, String name) =>
      RouteRepository(db.routesDao).rename(id, name);

  Future<String?> routeName(String id) async =>
      (await db.routesDao.routeById(id))?.name;

  Future<List<String>> routeNames() async =>
      [for (final r in await db.routesDao.allRoutes()) r.name]..sort();

  Future<List<String>> rideNames() async =>
      [for (final r in await db.ridesDao.allRides()) r.name]..sort();

  Future<void> setChangedAt(String kind, String id, int ms) =>
      db.customStatement(
        'UPDATE sync_records SET changed_at_ms = ? WHERE kind = ? AND record_id = ?',
        [ms, kind, id],
      );

  @override
  Future<List<CloudRecord>> recordsToSave(List<String> names) =>
      sync.recordsToSave(names);

  @override
  Future<void> applyRemote(
    List<CloudRecord> modifications,
    List<String> deletions,
  ) => sync.applyRemote(modifications, deletions);

  @override
  Future<void> sent(SentChanges changes) => sync.sent(changes);

  @override
  Future<void> accountChanged(AccountChange change) async {
    accountChanges.add(change);
    await sync.reset();
    if (change != AccountChange.signOut) await sync.push();
  }

  @override
  Future<void> zoneDeleted(ZoneDeletion reason) async {}

  @override
  Future<void> settingsChanged(Map<String, Object?> values) async =>
      settingsHeard.add(values);
}

void main() {
  // Two devices, two in-memory databases, on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  late MemoryCloudStore store;
  late _Device phone;
  late _Device pad;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('store_sync');
    store = MemoryCloudStore();
    phone = _Device(store, dir, 'phone', batchSize: 2);
    pad = _Device(store, dir, 'pad');
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
      state: _MapState(),
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
