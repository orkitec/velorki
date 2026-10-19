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
import 'package:velorki/features/sync/data/google_drive_sync.dart';
import 'package:velorki/features/sync/domain/cloud_sync_status.dart';
import 'package:velorki/features/sync/domain/sync_service.dart';
import 'package:velorki/features/sync/presentation/cloud_sync_section.dart';

import '../../support/app.dart';
import '../planner/support/pump.dart';
import 'support/fake_cloud.dart';
import 'support/memory_cloud_store.dart';

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

  List<Override> syncOverrides({bool google = false, bool iCloud = true}) => [
    cloudSyncBridgeProvider.overrideWithValue(iCloud ? bridge : null),
    cloudSyncOutboxProvider.overrideWith((ref) async => dir),
    if (google) googleDriveStoreProvider.overrideWithValue(MemoryCloudStore()),
  ];

  group('the status line', () {
    setUpAll(() => initializeDateFormatting(l10n.localeName));
    final now = DateTime(2026, 10, 16, 12);
    String line(
      CloudSyncStatus status, {
      SyncService service = SyncService.icloud,
    }) => cloudSyncStatusLine(l10n, status, service: service, now: now);

    test('says what is wrong before when it last synced', () {
      final synced = now.subtract(const Duration(minutes: 2));
      expect(
        line(CloudSyncStatus(lastSyncedAt: synced), service: SyncService.off),
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

    test('names Google where Google is the service', () {
      expect(
        line(
          const CloudSyncStatus(account: CloudAccount.noAccount),
          service: SyncService.google,
        ),
        l10n.cloudSyncGoogleNoAccount,
      );
      expect(
        line(
          const CloudSyncStatus(error: CloudSyncError.quotaExceeded),
          service: SyncService.google,
        ),
        l10n.cloudSyncGoogleQuota,
      );
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

  group('the choice', () {
    Future<ProviderContainer> pumpSection(
      WidgetTester tester, {
      bool google = false,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final db = VelorkiDatabase.memory();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          velorkiDatabaseProvider.overrideWithValue(db),
          ...syncOverrides(google: google),
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

    Set<SyncService> segments(WidgetTester tester) => {
      for (final s
          in tester
              .widget<SegmentedButton<SyncService>>(
                find.byType(SegmentedButton<SyncService>),
              )
              .segments)
        s.value,
    };

    Set<SyncService> selected(WidgetTester tester) => tester
        .widget<SegmentedButton<SyncService>>(
          find.byType(SegmentedButton<SyncService>),
        )
        .selected;

    testWidgets('is iCloud, and shows what the engine says', (tester) async {
      await pumpSection(tester);
      expect(find.text(l10n.cloudSyncWith), findsOneWidget);
      expect(segments(tester), {SyncService.icloud, SyncService.off});
      expect(find.text(l10n.cloudSyncServiceGoogle), findsNothing);
      expect(selected(tester), {SyncService.icloud});
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

    testWidgets('off, says the library stays here', (tester) async {
      final container = await pumpSection(tester);
      await tester.tap(find.text(l10n.cloudSyncServiceOff));
      await settleSync(tester);
      expect(find.text(l10n.cloudSyncOff), findsOneWidget);
      expect(selected(tester), {SyncService.off});
      expect(container.read(syncServiceChoiceProvider), SyncService.off);
      expect(bridge.started, isFalse, reason: 'the engine stopped');
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString('sync.service'), 'off');
      expect(prefs.getBool('sync.icloud'), isNull);
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('offers Google where there is a Drive store', (tester) async {
      final container = await pumpSection(tester, google: true);
      expect(segments(tester), {
        SyncService.icloud,
        SyncService.google,
        SyncService.off,
      });
      await tester.tap(find.text(l10n.cloudSyncServiceGoogle));
      await settleSync(tester);
      expect(selected(tester), {SyncService.google});
      expect(container.read(activeSyncServiceProvider), SyncService.google);
      expect(bridge.started, isFalse, reason: 'one cloud at a time');
      expect(find.text(l10n.cloudSyncGoogleHint), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('in Settings', () {
    List<Override> idle({bool google = false, bool iCloud = true}) => [
      ...syncOverrides(google: google, iCloud: iCloud),
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
      expect(find.text(l10n.cloudSyncWith), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('with Google only (Android), offers Google and off, and is '
        'off until chosen', (tester) async {
      await pumpApp(
        tester,
        initialLocation: settingsRoute,
        extraOverrides: idle(google: true, iCloud: false),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(CloudSyncSection),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(l10n.cloudSyncServiceGoogle), findsOneWidget);
      expect(find.text(l10n.cloudSyncServiceICloud), findsNothing);
      expect(find.text(l10n.cloudSyncOff), findsOneWidget);
      await unmountApp(tester);
    });
  });
}
