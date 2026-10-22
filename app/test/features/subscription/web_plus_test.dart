import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/subscription/application/web_plus.dart';
import 'package:velorki/features/sync/application/cloud_sync_controller.dart';
import 'package:velorki/features/sync/application/plus_id_sync.dart';
import 'package:velorki/features/sync/application/web_plus_devices.dart';
import 'package:velorki/features/sync/data/cloud_store.dart';
import 'package:velorki/features/sync/data/cloud_sync_bridge.dart';
import 'package:velorki/features/sync/data/google_drive_sync.dart';
import 'package:velorki/features/sync/data/record_codec.dart';
import 'package:velorki/features/sync/domain/cloud_record.dart';
import 'package:velorki/features/sync/domain/sync_service.dart';
import 'package:velorki_api/velorki_api.dart';

import '../../support/mock_relay.dart';
import '../../support/openapi_schema.dart';
import '../sync/support/memory_cloud_store.dart';
import '../sync/support/rows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 19, 12);

  PlusDeviceSeen device(
    String id, {
    required Duration ago,
    bool entitled = true,
  }) => PlusDeviceSeen(
    appUserId: id,
    platform: 'ios',
    entitled: entitled,
    lastSeen: now.subtract(ago),
  );

  group('pickPlusDevice', () {
    test('the freshest of the records seen within 30 days', () {
      final picked = pickPlusDevice([
        device('anon-old', ago: const Duration(days: 3)),
        device('anon-new', ago: const Duration(hours: 2)),
      ], now);
      expect(picked?.appUserId, 'anon-new');
    });

    test('ignores records not seen for more than 30 days', () {
      expect(
        pickPlusDevice([
          device('anon-stale', ago: const Duration(days: 31)),
        ], now),
        isNull,
      );
      expect(
        pickPlusDevice([
          device('anon-stale', ago: const Duration(days: 31)),
          device('anon-fresh', ago: const Duration(days: 29)),
        ], now)?.appUserId,
        'anon-fresh',
      );
    });

    test('prefers a device with Plus over a fresher one without', () {
      final picked = pickPlusDevice([
        device('anon-free', ago: const Duration(hours: 1), entitled: false),
        device('anon-plus', ago: const Duration(days: 2)),
      ], now);
      expect(picked?.appUserId, 'anon-plus');
      expect(
        pickPlusDevice([
          device('anon-free', ago: const Duration(hours: 1), entitled: false),
        ], now)?.entitled,
        isFalse,
      );
    });
  });

  group('in the browser', () {
    late Directory dir;
    late VelorkiDatabase db;
    late MemoryCloudStore store;
    late MockRelay relay;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('web_plus');
      db = VelorkiDatabase.memory();
      store = MemoryCloudStore();
      relay = MockRelay(schemas: OpenApi.load().check);
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    /// A phone's record, as [PlusIdSync] writes it.
    Future<void> phoneWrote(
      String device,
      String appUserId, {
      required Duration ago,
      bool entitled = true,
    }) async {
      final seen = now.subtract(ago).millisecondsSinceEpoch;
      await store.push([
        StoreSave(
          '$plusRecordPrefix$device',
          type: plusRecordType,
          fields: {
            'schemaVersion': 1,
            'modifiedAt': seen,
            'appUserId': appUserId,
            'platform': 'ios',
            'entitled': entitled ? 1 : 0,
            'lastSeen': seen,
          },
          body: null,
          ifVersion: null,
        ),
      ]);
    }

    /// The web planner syncing with Google: no store, no record of its own.
    Future<ProviderContainer> launch({
      Map<String, Object>? prefs,
      List<Override> overrides = const [],
    }) async {
      if (prefs != null) SharedPreferences.setMockInitialValues(prefs);
      final shared = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          appConfigProvider.overrideWithValue(
            const AppConfig(apiUrl: MockRelay.baseUrl),
          ),
          relayHttpClientProvider.overrideWithValue(relay.httpClient),
          velorkiDatabaseProvider.overrideWithValue(db),
          cloudSyncBridgeProvider.overrideWithValue(null),
          cloudSyncClockProvider.overrideWithValue(() => now),
          cloudSyncOutboxProvider.overrideWith((ref) async => dir),
          cloudSyncInboxProvider.overrideWith(
            (ref) async => Directory('${dir.path}/in'),
          ),
          plusDeviceIdentityProvider.overrideWithValue(null),
          keepsPlusDevicesProvider.overrideWithValue(true),
          googleDriveStoreProvider.overrideWithValue(store),
          ...overrides,
        ],
      );
      addTearDown(container.dispose);
      startWebPlus(container);
      container.listen(cloudSyncControllerProvider, (_, _) {});
      return container;
    }

    test('uses the freshest phone id with Plus towards the relay, and '
        'writes no record of its own', () async {
      await phoneWrote('old', 'anon-old', ago: const Duration(days: 40));
      await phoneWrote('ipad', 'anon-ipad', ago: const Duration(days: 4));
      await phoneWrote('phone', 'anon-phone', ago: const Duration(hours: 3));
      final container = await launch(prefs: {'sync.service': 'google'});
      expect(container.read(plusEntitledProvider), isFalse);

      await _until(() => container.read(webPlusDeviceProvider) != null);
      expect(container.read(webPlusDeviceProvider)?.appUserId, 'anon-phone');
      expect(container.read(plusEntitledProvider), isTrue);
      expect(container.read(relayClientProvider)?.appUserId, 'anon-phone');

      await container
          .read(relayClientProvider)!
          .routeWeather(
            from: now.toUtc(),
            hours: 3,
            cells: const [WeatherRequestCell(lat: 32.65, lon: -16.9)],
          );
      expect(
        relay.weatherRequests.single.headers['authorization'],
        'Bearer anon-phone',
      );

      await _settle();
      expect(store.names.where(PlusIdSync.isPlusRecord), {
        'plus_old',
        'plus_ipad',
        'plus_phone',
      }, reason: 'the browser writes none');
      expect(
        container.read(sharedPreferencesProvider).getString('sync.plus.device'),
        isNull,
      );
    });

    test('Plus records that cannot be taken fail no round: the library '
        'arrives, and nothing is fetched again', () async {
      await phoneWrote('phone', 'anon-phone', ago: const Duration(hours: 3));
      final other = VelorkiDatabase.memory();
      addTearDown(other.close);
      await other.routesDao.upsertRoute(fullRoute('r1'));
      final route = await RecordCodec(
        Directory('${dir.path}/enc'),
      ).encodeRoute((await other.routesDao.routeById('r1'))!, changedAtMs: 1);
      await store.push([
        StoreSave(
          route.name,
          type: route.type,
          fields: {
            for (final MapEntry(:key, :value) in route.fields.entries)
              key: ?value,
          },
          body: await File(route.assetPath!).readAsBytes(),
          ifVersion: null,
        ),
      ]);

      final container = await launch(
        prefs: {'sync.service': 'google'},
        overrides: [
          webPlusDevicesProvider.overrideWith(_BrokenPlusDevices.new),
        ],
      );
      await _until(() async => await db.routesDao.routeById('r1') != null);
      await _settle();
      final status = container.read(cloudSyncControllerProvider);
      expect(status.error, isNull);
      expect(status.lastSyncedAt, isNotNull);
      expect(container.read(plusEntitledProvider), isFalse);

      final lists = store.fullLists;
      await container.read(cloudSyncControllerProvider.notifier).refresh();
      expect(store.fullLists, lists, reason: 'the cursor moved on');
      expect(container.read(cloudSyncControllerProvider).error, isNull);
    });

    test('keeps the ids it saw across a reload', () async {
      await phoneWrote('phone', 'anon-phone', ago: const Duration(hours: 3));
      var container = await launch(prefs: {'sync.service': 'google'});
      await _until(() => container.read(webPlusDeviceProvider) != null);
      await _settle();
      container.dispose();

      // The cursor is kept too: the next fetch brings nothing new.
      container = await launch();
      expect(container.read(webPlusDeviceProvider)?.appUserId, 'anon-phone');
      expect(container.read(plusEntitledProvider), isTrue);
      await _settle();
      expect(container.read(webPlusDeviceProvider)?.appUserId, 'anon-phone');
    });

    test('a phone without Plus: its id, and Plus stays closed', () async {
      await phoneWrote(
        'phone',
        'anon-free',
        ago: const Duration(hours: 1),
        entitled: false,
      );
      final container = await launch(prefs: {'sync.service': 'google'});
      await _until(() => container.read(webPlusDeviceProvider) != null);
      expect(container.read(relayClientProvider)?.appUserId, 'anon-free');
      expect(container.read(plusEntitledProvider), isFalse);
    });

    test('only stale records: no id, Plus stays closed', () async {
      await phoneWrote('phone', 'anon-stale', ago: const Duration(days: 31));
      final container = await launch(prefs: {'sync.service': 'google'});
      await _until(
        () => container.read(webPlusDevicesProvider).containsKey('plus_phone'),
      );
      expect(container.read(webPlusDeviceProvider), isNull);
      expect(container.read(plusEntitledProvider), isFalse);
      expect(
        container.read(relayClientProvider)?.appUserId,
        isNot('anon-stale'),
      );
    });

    test('switched off, the ids are forgotten and Plus closes', () async {
      await phoneWrote('phone', 'anon-phone', ago: const Duration(hours: 3));
      final container = await launch(prefs: {'sync.service': 'google'});
      await _until(() => container.read(plusEntitledProvider));

      await container
          .read(syncServiceChoiceProvider.notifier)
          .select(SyncService.off);
      expect(container.read(webPlusDeviceProvider), isNull);
      expect(container.read(plusEntitledProvider), isFalse);
      expect(
        container
            .read(sharedPreferencesProvider)
            .getString('sync.plus.web_devices'),
        isNull,
      );
    });

    test('a phone build keeps no other device\'s record', () async {
      await phoneWrote('phone', 'anon-phone', ago: const Duration(hours: 3));
      SharedPreferences.setMockInitialValues({'sync.service': 'google'});
      final shared = await SharedPreferences.getInstance();
      final phone = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          velorkiDatabaseProvider.overrideWithValue(db),
          cloudSyncBridgeProvider.overrideWithValue(null),
          cloudSyncClockProvider.overrideWithValue(() => now),
          cloudSyncOutboxProvider.overrideWith((ref) async => dir),
          cloudSyncInboxProvider.overrideWith(
            (ref) async => Directory('${dir.path}/in'),
          ),
          plusDeviceIdentityProvider.overrideWithValue(null),
          googleDriveStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(phone.dispose);
      phone.listen(cloudSyncControllerProvider, (_, _) {});
      await _until(() => store.fullLists > 0);
      await _settle();
      expect(phone.read(webPlusDevicesProvider), isEmpty);
      expect(phone.read(webPlusDeviceProvider), isNull);
    });
  });
}

/// Plus records that throw on what arrives, as a relay or a storage
/// failure behind them would.
class _BrokenPlusDevices extends WebPlusDevices {
  @override
  Future<void> applyRemote(
    List<CloudRecord> modifications,
    List<String> deletions,
  ) async => throw StateError('Plus broken');
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
