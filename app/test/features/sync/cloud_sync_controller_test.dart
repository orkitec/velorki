import 'dart:async';
import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki/features/sync/application/cloud_sync_controller.dart';
import 'package:velorki/features/sync/application/library_sync.dart';
import 'package:velorki/features/sync/data/cloud_sync_bridge.dart';
import 'package:velorki/features/sync/data/google_drive_sync.dart';
import 'package:velorki/features/sync/data/record_codec.dart';
import 'package:velorki/features/sync/data/sync_backend.dart';
import 'package:velorki/features/sync/domain/cloud_sync_status.dart';
import 'package:velorki/features/sync/domain/sync_service.dart';

import 'support/fake_cloud.dart';
import 'support/memory_cloud_store.dart';
import 'support/rows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late FakeCloudSyncBridge bridge;
  late VelorkiDatabase db;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cloud_sync_controller');
    bridge = FakeCloudSyncBridge(FakeCloud(dir));
    db = VelorkiDatabase.memory();
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  var now = DateTime(2026, 10, 18, 12);

  Future<ProviderContainer> launch({
    Map<String, Object> prefs = const <String, Object>{},
    bool iCloud = true,
    MemoryCloudStore? google,
  }) async {
    now = DateTime(2026, 10, 18, 12);
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        velorkiDatabaseProvider.overrideWithValue(db),
        cloudSyncBridgeProvider.overrideWithValue(iCloud ? bridge : null),
        cloudSyncClockProvider.overrideWithValue(() => now),
        cloudSyncOutboxProvider.overrideWith((ref) async => dir),
        cloudSyncInboxProvider.overrideWith(
          (ref) async => Directory('${dir.path}/in'),
        ),
        if (google != null) googleDriveStoreProvider.overrideWithValue(google),
      ],
    );
    addTearDown(container.dispose);
    container.listen(cloudSyncControllerProvider, (_, _) {});
    await settle();
    return container;
  }

  test('a device that cannot sync never starts the engine', () async {
    bridge.supported = false;
    final container = await launch();
    expect(bridge.started, isFalse);
    expect(container.read(cloudSyncSupportedProvider).value, isFalse);
  });

  test('switched off at launch, nothing touches iCloud', () async {
    await db.routesDao.upsertRoute(fullRoute('r1'));
    await launch(prefs: {'sync.icloud': false});
    expect(bridge.started, isFalse);
    expect(bridge.pendingSaves, isEmpty);
  });

  test('on by default: the library waiting is handed over', () async {
    await db.routesDao.upsertRoute(fullRoute('r1'));
    await launch();
    expect(bridge.started, isTrue);
    expect(bridge.pendingSaves, {'route_r1'});
    expect(bridge.fetchRequests, 1, reason: 'fetched at launch');
  });

  group('the choice of service', () {
    test('the old switch carries over: on is iCloud, off is off', () async {
      var container = await launch(prefs: {'sync.icloud': true});
      expect(container.read(syncServiceChoiceProvider), SyncService.icloud);
      container.dispose();
      container = await launch(prefs: {'sync.icloud': false});
      expect(container.read(syncServiceChoiceProvider), SyncService.off);
      expect(container.read(cloudSyncActiveProvider), isFalse);
    });

    test('a choice made wins over the old switch, and replaces it', () async {
      final container = await launch(
        prefs: {'sync.icloud': true, 'sync.service': 'off'},
      );
      expect(container.read(syncServiceChoiceProvider), SyncService.off);
      await container
          .read(syncServiceChoiceProvider.notifier)
          .select(SyncService.icloud);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString('sync.service'), 'icloud');
      expect(prefs.getBool('sync.icloud'), isNull);
    });

    test('unset, it is iCloud on iOS and off without iCloud', () async {
      var container = await launch();
      expect(container.read(syncServiceChoiceProvider), SyncService.icloud);
      container.dispose();
      container = await launch(iCloud: false, google: MemoryCloudStore());
      expect(container.read(syncServiceChoiceProvider), SyncService.off);
      expect(container.read(offeredSyncServicesProvider), [SyncService.google]);
    });

    test('Google where it is not offered runs nothing', () async {
      final container = await launch(prefs: {'sync.service': 'google'});
      expect(container.read(activeSyncServiceProvider), SyncService.off);
      expect(bridge.started, isFalse);
    });

    test(
      'Google sends the library to the Drive store and fetches from it',
      () async {
        final store = MemoryCloudStore();
        await db.routesDao.upsertRoute(fullRoute('r1'));
        final container = await launch(
          prefs: {'sync.service': 'google'},
          google: store,
        );
        expect(container.read(activeSyncServiceProvider), SyncService.google);
        expect(bridge.started, isFalse);
        await _until(() => store.names.contains('route_r1'));
        await _until(() async => (await db.syncDao.dirtyRecords()).isEmpty);
        await _until(
          () =>
              container.read(cloudSyncControllerProvider).lastSyncedAt != null,
        );
        expect(
          container.read(cloudSyncControllerProvider).account,
          CloudAccount.available,
        );
      },
    );

    test('switching iCloud to Google and back sends the library as new to '
        'each, deleting nothing', () async {
      final store = MemoryCloudStore();
      await db.routesDao.upsertRoute(fullRoute('r1'));
      final container = await launch(google: store);
      await bridge.sync();
      expect(await db.syncDao.dirtyRecords(), isEmpty);
      final choice = container.read(syncServiceChoiceProvider.notifier);

      await choice.select(SyncService.google);
      await settle();
      expect(bridge.started, isFalse);
      await _until(() => store.names.contains('route_r1'));
      await _until(() async => (await db.syncDao.dirtyRecords()).isEmpty);
      expect(
        container
            .read(sharedPreferencesProvider)
            .getString('sync.records_service'),
        'google',
      );

      bridge.pendingSaves.clear();
      await choice.select(SyncService.icloud);
      await settle();
      expect(bridge.started, isTrue);
      expect(bridge.pendingSaves, {'route_r1'});
      expect(bridge.cloud.names, {'route_r1'});
      expect(store.names, {'route_r1'});
      expect((await db.routesDao.allRoutes()).length, 1);
    });

    test('iCloud as before there was a choice keeps its sync state', () async {
      await db.routesDao.upsertRoute(fullRoute('r1'));
      var container = await launch(prefs: {'sync.icloud': true});
      await bridge.sync();
      container.dispose();
      bridge.pendingSaves.clear();
      container = await launch(prefs: {'sync.icloud': true});
      expect(bridge.pendingSaves, isEmpty, reason: 'nothing sent again');
      expect(
        container
            .read(sharedPreferencesProvider)
            .getString('sync.records_service'),
        'icloud',
      );
    });
  });

  test('a database that fails at launch is logged, never uncaught, and the '
      'fetch still runs', () async {
    // As the browser's database whose worker cannot load SQLite.
    await db.close();
    db = VelorkiDatabase(DelegatedDatabase(_NoSqlite()));
    await launch();
    expect(bridge.started, isTrue);
    expect(bridge.fetchRequests, 1);
  });

  test('says what the engine says', () async {
    final container = await launch();
    bridge.emit(const CloudSyncStatus(account: CloudAccount.noAccount));
    await settle();
    expect(
      container.read(cloudSyncControllerProvider).account,
      CloudAccount.noAccount,
    );
    bridge.emit(
      const CloudSyncStatus(
        account: CloudAccount.available,
        error: CloudSyncError.quotaExceeded,
      ),
    );
    await settle();
    expect(
      container.read(cloudSyncControllerProvider).error,
      CloudSyncError.quotaExceeded,
    );
  });

  test('switching off stops the engine, on again starts it', () async {
    final container = await launch();
    final choice = container.read(syncServiceChoiceProvider.notifier);
    await choice.select(SyncService.off);
    await settle();
    expect(bridge.started, isFalse);
    await choice.select(SyncService.icloud);
    await settle();
    expect(bridge.started, isTrue);
  });

  test('a change made elsewhere while sync was off here arrives when it '
      'is switched on, with no push', () async {
    // The phone: another device on the same iCloud.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final phoneDb = VelorkiDatabase.memory();
    addTearDown(phoneDb.close);
    final phone = FakeCloudSyncBridge(bridge.cloud);
    final phoneSync = LibrarySync(
      db: phoneDb,
      backend: phone,
      codec: RecordCodec(Directory('${dir.path}/phone')),
    );
    phone.setHandler(
      LibraryHandler(
        toSave: phoneSync.recordsToSave,
        apply: phoneSync.applyRemote,
        onSent: phoneSync.sent,
      ),
    );
    addTearDown(phoneSync.stop);

    await db.routesDao.upsertRoute(fullRoute('r1'));
    final container = await launch();
    await bridge.sync();
    await phone.fetch();
    expect((await phoneDb.routesDao.routeById('r1'))?.name, isNotNull);

    final choice = container.read(syncServiceChoiceProvider.notifier);
    await choice.select(SyncService.off);
    await settle();

    await RouteRepository(phoneDb.routesDao).rename('r1', 'Renamed');
    await phoneSync.push();
    await phone.send();

    await choice.select(SyncService.icloud);
    await settle();
    expect((await db.routesDao.routeById('r1'))?.name, 'Renamed');
    expect(await db.syncDao.dirtyRecords(), isEmpty);
  });

  test('opening the Library fetches, at most every 30 seconds', () async {
    final container = await launch();
    final tabs = container.read(activeTabProvider.notifier);
    expect(bridge.fetchRequests, 1);
    tabs.show(libraryRoute);
    expect(bridge.fetchRequests, 2);
    tabs.show(plannerRoute);
    tabs.show(libraryRoute);
    expect(bridge.fetchRequests, 2, reason: 'throttled');
    now = now.add(const Duration(seconds: 31));
    tabs.show(plannerRoute);
    tabs.show(libraryRoute);
    expect(bridge.fetchRequests, 3);
  });

  test('with sync off, opening the Library fetches nothing', () async {
    final container = await launch(prefs: {'sync.icloud': false});
    container.read(activeTabProvider.notifier).show(libraryRoute);
    await settle();
    expect(bridge.fetchRequests, 0);
  });

  test('another account gets the whole library, which stays here', () async {
    await db.routesDao.upsertRoute(fullRoute('r1'));
    final container = await launch();
    await bridge.sync();
    expect(await db.syncDao.dirtyRecords(), isEmpty);

    final handler = container.read(cloudSyncControllerProvider.notifier);
    await handler.accountChanged(AccountChange.switchAccounts);

    expect((await db.syncDao.dirtyRecords()).single.recordId, 'r1');
    expect(bridge.pendingSaves, {'route_r1'});
    expect((await db.routesDao.allRoutes()).length, 1);
  });

  test('a signed-out device keeps its library and sends nothing', () async {
    await db.routesDao.upsertRoute(fullRoute('r1'));
    final container = await launch();
    await bridge.sync();

    await container
        .read(cloudSyncControllerProvider.notifier)
        .accountChanged(AccountChange.signOut);

    expect(bridge.pendingSaves, isEmpty);
    expect((await db.routesDao.allRoutes()).length, 1);
  });

  test('data deleted from iCloud in Settings switches sync off here', () async {
    await db.routesDao.upsertRoute(fullRoute('r1'));
    final container = await launch();
    await bridge.sync();

    await container
        .read(cloudSyncControllerProvider.notifier)
        .zoneDeleted(ZoneDeletion.purged);
    await settle();

    expect(container.read(syncServiceChoiceProvider), SyncService.off);
    expect(bridge.started, isFalse);
    expect((await db.routesDao.allRoutes()).length, 1);
  });

  test('a reset zone gets everything again', () async {
    await db.routesDao.upsertRoute(fullRoute('r1'));
    final container = await launch();
    await bridge.sync();

    await container
        .read(cloudSyncControllerProvider.notifier)
        .zoneDeleted(ZoneDeletion.encryptedDataReset);

    expect(bridge.pendingSaves, {'route_r1'});
    expect(container.read(syncServiceChoiceProvider), SyncService.icloud);
  });

  test('a setting changed on another device shows here', () async {
    final container = await launch();
    expect(container.read(appearanceSettingProvider).mode, ThemeMode.system);

    await bridge.settingsFromElsewhere({'appearance.mode': 'dark'});
    expect(container.read(appearanceSettingProvider).mode, ThemeMode.dark);

    await container
        .read(appearanceSettingProvider.notifier)
        .setMode(ThemeMode.light);
    await settle();
    expect(bridge.settings['appearance.mode'], 'light');
  });
}

/// Lets the controller's steps run: microtasks, the database, the engine.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Waits up to five seconds for [done].
Future<void> _until(FutureOr<bool> Function() done) async {
  final until = DateTime.now().add(const Duration(seconds: 5));
  while (!await done()) {
    if (DateTime.now().isAfter(until)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A database whose SQLite never loads, as in a browser whose worker
/// cannot fetch it: every statement fails.
class _NoSqlite extends DatabaseDelegate {
  static Never _fail() => throw StateError('TypeError: Failed to fetch');

  @override
  bool get isOpen => false;

  @override
  Future<void> open(QueryExecutorUser db) async => _fail();

  @override
  DbVersionDelegate get versionDelegate => const NoVersionDelegate();

  @override
  TransactionDelegate get transactionDelegate => const NoTransactionDelegate();

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async =>
      _fail();

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async => _fail();

  @override
  Future<int> runInsert(String statement, List<Object?> args) async => _fail();

  @override
  Future<void> runCustom(String statement, List<Object?> args) async => _fail();
}
