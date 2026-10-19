import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/sync/application/cloud_sync_controller.dart';
import 'package:velorki/features/sync/application/plus_id_sync.dart';
import 'package:velorki/features/sync/data/cloud_sync_bridge.dart';
import 'package:velorki/features/sync/data/google_drive_sync.dart';
import 'package:velorki/features/sync/data/sync_backend.dart';
import 'package:velorki/features/sync/domain/sync_service.dart';

import 'support/fake_cloud.dart';
import 'support/memory_cloud_store.dart';
import 'support/rows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late FakeCloudSyncBridge bridge;
  late VelorkiDatabase db;
  late DateTime now;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('plus_id_sync');
    bridge = FakeCloudSyncBridge(FakeCloud(dir));
    db = VelorkiDatabase.memory();
    now = DateTime(2026, 10, 19, 12);
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  const identity = PlusDeviceIdentity(appUserId: 'anon-phone', platform: 'ios');

  Future<ProviderContainer> launch({
    Map<String, Object>? prefs,
    PlusDeviceIdentity? id = identity,
    MemoryCloudStore? google,
    bool iCloud = true,
  }) async {
    if (prefs != null) SharedPreferences.setMockInitialValues(prefs);
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
        plusDeviceIdentityProvider.overrideWithValue(id),
        if (google != null) googleDriveStoreProvider.overrideWithValue(google),
      ],
    );
    addTearDown(container.dispose);
    container.listen(cloudSyncControllerProvider, (_, _) {});
    await _settle();
    return container;
  }

  Set<String> plusNames(Iterable<String> names) =>
      names.where(PlusIdSync.isPlusRecord).toSet();

  test('writes its own record into the cloud it syncs with', () async {
    final container = await launch(prefs: {});
    expect(plusNames(bridge.pendingSaves), hasLength(1));
    await bridge.sync();

    final name = plusNames(bridge.cloud.names).single;
    expect(name, startsWith('plus_'));
    final fields = bridge.cloud.fields(name)!;
    expect(fields['appUserId'], 'anon-phone');
    expect(fields['platform'], 'ios');
    expect(fields['lastSeen'], now.millisecondsSinceEpoch);
    expect(
      container.read(sharedPreferencesProvider).getString('sync.plus.target'),
      'icloud',
    );
  });

  test('a browser or a build without a store writes nothing', () async {
    await launch(prefs: {}, id: null);
    await bridge.sync();
    expect(plusNames(bridge.cloud.names), isEmpty);
  });

  test('lastSeen is written again on a sync after six hours', () async {
    var container = await launch(prefs: {});
    await bridge.sync();
    final name = plusNames(bridge.cloud.names).single;
    container.dispose();

    now = now.add(const Duration(hours: 1));
    container = await launch();
    expect(plusNames(bridge.pendingSaves), isEmpty, reason: 'fresh enough');
    container.dispose();

    now = now.add(const Duration(hours: 6));
    await launch();
    expect(plusNames(bridge.pendingSaves), {name});
    await bridge.sync();
    expect(bridge.cloud.fields(name)!['lastSeen'], now.millisecondsSinceEpoch);
    expect(plusNames(bridge.cloud.names), {name}, reason: 'one per device');
  });

  test(
    'a record already there (a restored install) goes over its tag',
    () async {
      var container = await launch(prefs: {});
      await bridge.sync();
      final name = plusNames(bridge.cloud.names).single;
      container.dispose();
      // The tag kept here is lost; the server still has the record.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('sync.plus.system_fields');
      await prefs.remove('sync.plus.saved_at');

      now = now.add(const Duration(minutes: 5));
      container = await launch();
      await bridge.sync();
      expect(
        bridge.cloud.fields(name)!['lastSeen'],
        now.millisecondsSinceEpoch,
      );
    },
  );

  group('never follows into another account by itself', () {
    test('an account switch stops writing, and deletes nothing', () async {
      final container = await launch(prefs: {});
      await bridge.sync();
      final name = plusNames(bridge.cloud.names).single;
      final handler = container.read(cloudSyncControllerProvider.notifier);

      await handler.accountChanged(AccountChange.switchAccounts);
      expect(plusNames(bridge.pendingSaves), isEmpty);
      expect(await handler.recordsToSave([name]), isEmpty);

      // Later launches write nothing either.
      now = now.add(const Duration(days: 2));
      container.dispose();
      await launch();
      expect(plusNames(bridge.pendingSaves), isEmpty);
      expect(bridge.cloud.names, contains(name), reason: 'nothing deleted');
    });

    test(
      'a sign-out stops writing; signing in again does not resume',
      () async {
        final container = await launch(prefs: {});
        await bridge.sync();
        final handler = container.read(cloudSyncControllerProvider.notifier);
        await handler.accountChanged(AccountChange.signOut);
        await handler.accountChanged(AccountChange.signIn);
        now = now.add(const Duration(days: 1));
        container.dispose();
        await launch();
        expect(plusNames(bridge.pendingSaves), isEmpty);
      },
    );

    test('the first account appearing is no change', () async {
      final container = await launch(prefs: {});
      // Before anything was saved (a fresh install's first sign-in).
      await container
          .read(cloudSyncControllerProvider.notifier)
          .accountChanged(AccountChange.signIn);
      await bridge.sync();
      expect(plusNames(bridge.cloud.names), hasLength(1));
    });

    test('picking the service again in Settings writes there', () async {
      final container = await launch(prefs: {});
      await bridge.sync();
      final handler = container.read(cloudSyncControllerProvider.notifier);
      await handler.accountChanged(AccountChange.switchAccounts);
      final choice = container.read(syncServiceChoiceProvider.notifier);

      await choice.select(SyncService.off);
      await _settle();
      await choice.select(SyncService.icloud);
      await _settle();
      expect(plusNames(bridge.pendingSaves), hasLength(1));
    });

    test(
      'switched off, nothing is written until a service is picked',
      () async {
        final store = MemoryCloudStore();
        final container = await launch(prefs: {}, google: store);
        await bridge.sync();
        final choice = container.read(syncServiceChoiceProvider.notifier);
        await choice.select(SyncService.off);
        await _settle();
        expect(
          container
              .read(sharedPreferencesProvider)
              .getString('sync.plus.target'),
          'held',
        );

        await choice.select(SyncService.google);
        await _until(() => plusNames(store.names).isNotEmpty);
        final name = plusNames(store.names).single;
        expect(store.fields(name)!['appUserId'], 'anon-phone');
      },
    );

    test('Google: another account gets the library but not the id', () async {
      final store = MemoryCloudStore();
      await db.routesDao.upsertRoute(fullRoute('r1'));
      final container = await launch(
        prefs: {'sync.service': 'google'},
        google: store,
        iCloud: false,
      );
      await _until(() => plusNames(store.namesOf('rider-a')).isNotEmpty);
      await _until(() async => (await db.syncDao.dirtyRecords()).isEmpty);

      store.account = 'rider-b';
      await container.read(cloudSyncControllerProvider.notifier).refresh();
      await _until(() => store.namesOf('rider-b').contains('route_r1'));
      await _settle();
      expect(plusNames(store.namesOf('rider-b')), isEmpty);
      final name = plusNames(store.namesOf('rider-a')).single;
      expect(
        await container
            .read(cloudSyncControllerProvider.notifier)
            .recordsToSave([name]),
        isEmpty,
      );
    });
  });
}

/// Lets the controller's steps run: microtasks, the database, the engine.
Future<void> _settle() async {
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
