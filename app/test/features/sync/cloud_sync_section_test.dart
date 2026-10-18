import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/settings/presentation/settings_screen.dart';
import 'package:velorki/features/sync/application/cloud_sync_controller.dart';
import 'package:velorki/features/sync/data/cloud_sync_bridge.dart';
import 'package:velorki/features/sync/domain/cloud_sync_status.dart';
import 'package:velorki/features/sync/presentation/cloud_sync_section.dart';

import '../../support/app.dart';
import '../planner/support/pump.dart';
import 'support/fake_cloud.dart';

/// Lets the controller start the engine: its steps run partly in the
/// test's fake time, partly on the database's real one.
Future<void> settleSync(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  await tester.pump();
}

/// The controller without the engine behind it, for screens that only
/// need the section drawn.
class _IdleSync extends CloudSyncController {
  @override
  CloudSyncStatus build() => const CloudSyncStatus();
}

void main() {
  late Directory dir;
  late FakeCloudSyncBridge bridge;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cloud_sync_section');
    bridge = FakeCloudSyncBridge(FakeCloud(dir));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  List<Override> syncOverrides() => [
    cloudSyncBridgeProvider.overrideWithValue(bridge),
    cloudSyncOutboxProvider.overrideWith((ref) async => dir),
  ];

  group('the status line', () {
    setUpAll(() => initializeDateFormatting(l10n.localeName));
    final now = DateTime(2026, 10, 16, 12);
    String line(CloudSyncStatus status, {bool enabled = true}) =>
        cloudSyncStatusLine(l10n, status, enabled: enabled, now: now);

    test('says what is wrong before when it last synced', () {
      final synced = now.subtract(const Duration(minutes: 2));
      expect(
        line(CloudSyncStatus(lastSyncedAt: synced), enabled: false),
        l10n.cloudSyncOff,
      );
      expect(
        line(
          CloudSyncStatus(
            account: CloudAccount.noAccount,
            lastSyncedAt: synced,
          ),
        ),
        l10n.cloudSyncNoAccount,
      );
      expect(
        line(const CloudSyncStatus(account: CloudAccount.restricted)),
        l10n.cloudSyncRestricted,
      );
      expect(
        line(
          const CloudSyncStatus(
            account: CloudAccount.available,
            syncing: true,
            error: CloudSyncError.quotaExceeded,
          ),
        ),
        l10n.cloudSyncQuota,
      );
      expect(
        line(
          const CloudSyncStatus(account: CloudAccount.available, syncing: true),
        ),
        l10n.cloudSyncSyncing,
      );
      expect(
        line(const CloudSyncStatus(error: CloudSyncError.network)),
        l10n.cloudSyncOffline,
      );
      expect(
        line(const CloudSyncStatus(error: CloudSyncError.other)),
        l10n.cloudSyncFailed,
      );
      expect(line(const CloudSyncStatus()), l10n.cloudSyncWaiting);
    });

    test('says how long ago it synced', () {
      String ago(Duration d) => line(
        CloudSyncStatus(
          account: CloudAccount.available,
          lastSyncedAt: now.subtract(d),
        ),
      );
      expect(ago(const Duration(seconds: 20)), l10n.cloudSyncJustNow);
      expect(ago(const Duration(minutes: 2)), l10n.cloudSyncMinutesAgo(2));
      expect(ago(const Duration(hours: 3)), l10n.cloudSyncHoursAgo(3));
      expect(
        ago(const Duration(days: 3)),
        l10n.cloudSyncOnDate(
          DateFormat.MMMd(l10n.localeName).format(DateTime(2026, 10, 13, 12)),
        ),
      );
    });
  });

  group('the switch', () {
    Future<ProviderContainer> pumpSection(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final db = VelorkiDatabase.memory();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          velorkiDatabaseProvider.overrideWithValue(db),
          ...syncOverrides(),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            home: Scaffold(
              body: ListView(children: const [CloudSyncSection()]),
            ),
          ),
        ),
      );
      await settleSync(tester);
      expectNoClippedText(tester);
      return container;
    }

    testWidgets('is on, and shows what the engine says', (tester) async {
      await pumpSection(tester);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(find.text(l10n.cloudSyncWaiting), findsOneWidget);
      expect(find.text(l10n.cloudSyncHint), findsOneWidget);

      expect(bridge.started, isTrue);
      await tester.runAsync(() async {
        bridge.emit(const CloudSyncStatus(account: CloudAccount.noAccount));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
      expect(find.text(l10n.cloudSyncNoAccount), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('switched off, says the library stays here', (tester) async {
      final container = await pumpSection(tester);
      await tester.tap(find.byType(SwitchListTile));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text(l10n.cloudSyncOff), findsOneWidget);
      expect(container.read(cloudSyncEnabledProvider), isFalse);
      expect(bridge.started, isFalse, reason: 'the engine stopped');
      expect(
        container.read(sharedPreferencesProvider).getBool('sync.icloud'),
        isFalse,
      );
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('in Settings', () {
    List<Override> idle() => [
      ...syncOverrides(),
      cloudSyncControllerProvider.overrideWith(_IdleSync.new),
    ];

    testWidgets('is not there where the device cannot sync', (tester) async {
      bridge.supported = false;
      await pumpApp(
        tester,
        initialLocation: settingsRoute,
        extraOverrides: idle(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(CloudSyncSection), findsNothing);
      await unmountApp(tester);
    });

    testWidgets('is not there without an engine (Android)', (tester) async {
      await pumpApp(tester, initialLocation: settingsRoute);
      await tester.pumpAndSettle();
      expect(find.byType(CloudSyncSection), findsNothing);
      await unmountApp(tester);
    });

    testWidgets('is there on iOS 17 and later', (tester) async {
      await pumpApp(
        tester,
        initialLocation: settingsRoute,
        extraOverrides: idle(),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(CloudSyncSection),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(l10n.cloudSyncTitle), findsOneWidget);
      await unmountApp(tester);
    });
  });
}
