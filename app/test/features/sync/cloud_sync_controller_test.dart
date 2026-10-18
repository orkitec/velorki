import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki/features/sync/application/cloud_sync_controller.dart';
import 'package:velorki/features/sync/data/cloud_sync_bridge.dart';
import 'package:velorki/features/sync/domain/cloud_sync_status.dart';

import 'support/fake_cloud.dart';
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

  Future<ProviderContainer> launch({
    Map<String, Object> prefs = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        velorkiDatabaseProvider.overrideWithValue(db),
        cloudSyncBridgeProvider.overrideWithValue(bridge),
        cloudSyncOutboxProvider.overrideWith((ref) async => dir),
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
    await container.read(cloudSyncEnabledProvider.notifier).set(enabled: false);
    await settle();
    expect(bridge.started, isFalse);
    await container.read(cloudSyncEnabledProvider.notifier).set(enabled: true);
    await settle();
    expect(bridge.started, isTrue);
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

    expect(container.read(cloudSyncEnabledProvider), isFalse);
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
    expect(container.read(cloudSyncEnabledProvider), isTrue);
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
