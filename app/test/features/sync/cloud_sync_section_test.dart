import 'dart:async';
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
import 'package:velorki/features/sync/data/google_account.dart';
import 'package:velorki/features/sync/data/google_drive_sync.dart';
import 'package:velorki/features/sync/data/icloud_web_sync.dart';
import 'package:velorki/features/sync/domain/cloud_sync_status.dart';
import 'package:velorki/features/sync/domain/sync_service.dart';
import 'package:velorki/features/sync/presentation/cloud_sync_section.dart';

import '../../support/app.dart';
import '../planner/support/pump.dart';
import 'support/fake_cloud.dart';
import 'support/fake_cloudkit.dart';
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

/// The controller at a status the test sets, counting resumes.
class _FixedSync extends CloudSyncController {
  _FixedSync(this._status);

  final CloudSyncStatus _status;
  int resumes = 0;

  @override
  CloudSyncStatus build() => _status;

  @override
  Future<void> resume() async => resumes++;
}

/// Google's sign-in as a browser has it: Google's button, and a token only
/// after a click.
class _FakeButtonGoogle implements ButtonGoogleSignIn {
  final StreamController<GoogleAccount> _signIns =
      StreamController<GoogleAccount>.broadcast();
  int authorizations = 0;
  int signOuts = 0;

  /// Signs [account] in, as a click on Google's button does.
  void click(GoogleAccount account) => _signIns.add(account);

  @override
  Widget button({required bool dark}) => const SizedBox(key: Key('gis'));

  @override
  Stream<GoogleAccount> get signIns => _signIns.stream;

  @override
  Future<String> authorize(GoogleAccount account) async {
    authorizations++;
    return 'token-$authorizations';
  }

  @override
  Future<GoogleAccount> signIn() =>
      throw const GoogleSignInFailure(canceled: false);

  @override
  Future<void> signOut() async => signOuts++;

  @override
  Future<String?> accessToken(GoogleAccount account, {String? stale}) async =>
      authorizations == 0 ? null : 'token-$authorizations';
}

/// Google's sign-in, answering as told.
class _FakeGoogleSignIn implements GoogleSignInService {
  /// What the next sign-in does: null signs in, else it fails so.
  GoogleSignInFailure? failure;
  int signIns = 0;
  int signOuts = 0;

  @override
  Future<GoogleAccount> signIn() async {
    signIns++;
    if (failure case final failure?) throw failure;
    return const GoogleAccount(id: 'g-1', email: 'rider@example.com');
  }

  @override
  Future<void> signOut() async => signOuts++;

  @override
  Future<String?> accessToken(GoogleAccount account, {String? stale}) async =>
      'token';
}

void main() {
  late Directory dir;
  late FakeCloudSyncBridge bridge;
  late _FakeGoogleSignIn googleSignIn;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cloud_sync_section');
    bridge = FakeCloudSyncBridge(FakeCloud(dir));
    googleSignIn = _FakeGoogleSignIn();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  List<Override> syncOverrides({bool google = false, bool iCloud = true}) => [
    cloudSyncBridgeProvider.overrideWithValue(iCloud ? bridge : null),
    cloudSyncOutboxProvider.overrideWith((ref) async => dir),
    if (google) ...[
      googleDriveStoreProvider.overrideWithValue(MemoryCloudStore()),
      googleSignInServiceProvider.overrideWithValue(googleSignIn),
    ],
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

    test('in the browser, asks to sign in to iCloud, and again when the '
        'sign-in ran out', () {
      expect(
        cloudSyncStatusLine(
          l10n,
          const CloudSyncStatus(account: CloudAccount.noAccount),
          service: SyncService.icloud,
          now: now,
          browser: true,
        ),
        l10n.cloudSyncICloudSignedOut,
      );
      for (final service in [SyncService.icloud, SyncService.google]) {
        expect(
          line(
            const CloudSyncStatus(
              account: CloudAccount.available,
              error: CloudSyncError.signInNeeded,
            ),
            service: service,
          ),
          l10n.cloudSyncSignInAgain,
        );
      }
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

    testWidgets('offers Google where there is a Drive store, and signs in '
        'when it is chosen', (tester) async {
      final container = await pumpSection(tester, google: true);
      expect(segments(tester), {
        SyncService.icloud,
        SyncService.google,
        SyncService.off,
      });
      await tester.tap(find.text(l10n.cloudSyncServiceGoogle));
      await settleSync(tester);
      expect(googleSignIn.signIns, 1);
      expect(selected(tester), {SyncService.google});
      expect(container.read(activeSyncServiceProvider), SyncService.google);
      expect(bridge.started, isFalse, reason: 'one cloud at a time');
      expect(find.text(l10n.cloudSyncGoogleHint), findsOneWidget);
      expect(find.text('rider@example.com'), findsOneWidget);
      expect(find.text(l10n.cloudSyncGoogleSignOut), findsOneWidget);
      expectNoClippedText(tester);
      await tester.pump(const Duration(milliseconds: 1));
    });

    for (final canceled in [true, false]) {
      testWidgets(
        canceled
            ? 'a sign-in closed keeps the choice, and says so'
            : 'a sign-in failed keeps the choice, and says so',
        (tester) async {
          googleSignIn.failure = GoogleSignInFailure(canceled: canceled);
          final container = await pumpSection(tester, google: true);
          await tester.tap(find.text(l10n.cloudSyncServiceGoogle));
          await settleSync(tester);
          expect(selected(tester), {SyncService.icloud});
          expect(container.read(syncServiceChoiceProvider), SyncService.icloud);
          expect(container.read(googleAccountControllerProvider), isNull);
          expect(
            find.text(
              canceled
                  ? l10n.cloudSyncGoogleSignInCancelled
                  : l10n.cloudSyncGoogleSignInFailed,
            ),
            findsOneWidget,
          );
          expect(bridge.started, isTrue);
          await tester.pump(const Duration(milliseconds: 1));
        },
      );
    }

    testWidgets('signing out turns sync off and forgets the account', (
      tester,
    ) async {
      final container = await pumpSection(tester, google: true);
      await tester.tap(find.text(l10n.cloudSyncServiceGoogle));
      await settleSync(tester);
      await tester.tap(find.text(l10n.cloudSyncGoogleSignOut));
      await settleSync(tester);

      expect(googleSignIn.signOuts, 1);
      expect(selected(tester), {SyncService.off});
      expect(container.read(googleAccountControllerProvider), isNull);
      expect(find.text('rider@example.com'), findsNothing);
      expect(find.text(l10n.cloudSyncOff), findsOneWidget);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString('sync.google.user'), isNull);

      // Chosen again, Google asks to sign in again.
      await tester.tap(find.text(l10n.cloudSyncServiceGoogle));
      await settleSync(tester);
      expect(googleSignIn.signIns, 2);
      expect(selected(tester), {SyncService.google});
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('Google without an account offers to sign in again', (
      tester,
    ) async {
      final container = await pumpSection(tester, google: true);
      await container
          .read(syncServiceChoiceProvider.notifier)
          .select(SyncService.google);
      await settleSync(tester);
      expect(find.text(l10n.cloudSyncGoogleSignOut), findsNothing);
      await tester.tap(find.text(l10n.cloudSyncGoogleSignIn));
      await settleSync(tester);
      expect(googleSignIn.signIns, 1);
      expect(find.text('rider@example.com'), findsOneWidget);
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

  group('in the web planner', () {
    Future<ProviderContainer> pumpWeb(
      WidgetTester tester,
      List<Override> overrides, {
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final shared = await SharedPreferences.getInstance();
      final db = VelorkiDatabase.memory();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          velorkiDatabaseProvider.overrideWithValue(db),
          cloudSyncBridgeProvider.overrideWithValue(null),
          cloudSyncOutboxProvider.overrideWith((ref) async => dir),
          cloudSyncInboxProvider.overrideWith((ref) async => dir),
          ...overrides,
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
      return container;
    }

    testWidgets("iCloud is off until chosen, then signs in with Apple's "
        'button, and signs out to off', (tester) async {
      final cloud = FakeCloudKit();
      final browser = cloud.client(user: null);
      final container = await pumpWeb(tester, [
        cloudKitWebProvider.overrideWithValue(browser),
      ]);
      expect(find.text(l10n.cloudSyncServiceICloud), findsOneWidget);
      expect(find.text(l10n.cloudSyncServiceGoogle), findsNothing);
      expect(container.read(activeSyncServiceProvider), SyncService.off);
      expect(find.text(l10n.cloudSyncICloudWebHint), findsOneWidget);

      await tester.tap(find.text(l10n.cloudSyncServiceICloud));
      await settleSync(tester);
      expect(container.read(activeSyncServiceProvider), SyncService.icloud);
      expect(find.text(l10n.cloudSyncICloudSignedOut), findsOneWidget);
      expect(find.byKey(const Key('cloudSyncAppleButton')), findsOneWidget);
      expectNoClippedText(tester);

      await tester.runAsync(() async {
        browser.signIn('user-a');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await settleSync(tester);
      expect(find.byKey(const Key('cloudSyncAppleButton')), findsNothing);
      expect(find.text(l10n.cloudSyncICloudSignedIn), findsOneWidget);
      expect(find.text(l10n.cloudSyncICloudSignedOut), findsNothing);
      expectNoClippedText(tester);

      await tester.tap(find.text(l10n.cloudSyncGoogleSignOut));
      await settleSync(tester);
      expect(container.read(activeSyncServiceProvider), SyncService.off);
      expect(browser.user, isNull);
      expect(
        await tester.runAsync(
          () => container.read(iCloudWebStoreProvider)!.accountId(),
        ),
        isNull,
      );
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('a sign-in to iCloud starts the sync at once', (tester) async {
      final cloud = FakeCloudKit();
      final browser = cloud.client(user: null);
      final sync = _FixedSync(
        const CloudSyncStatus(account: CloudAccount.noAccount),
      );
      await pumpWeb(
        tester,
        [
          cloudKitWebProvider.overrideWithValue(browser),
          cloudSyncControllerProvider.overrideWith(() => sync),
        ],
        prefs: {'sync.service': 'icloud'},
      );
      expect(sync.resumes, 0);
      await tester.runAsync(() async {
        browser.signIn('user-a');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await settleSync(tester);
      expect(sync.resumes, 1);
    });

    testWidgets("Google is chosen at once and signs in with Google's button", (
      tester,
    ) async {
      final google = _FakeButtonGoogle();
      final sync = _FixedSync(
        const CloudSyncStatus(account: CloudAccount.noAccount),
      );
      final container = await pumpWeb(tester, [
        googleSignInServiceProvider.overrideWithValue(google),
        googleDriveStoreProvider.overrideWithValue(MemoryCloudStore()),
        cloudSyncControllerProvider.overrideWith(() => sync),
      ]);
      await tester.tap(find.text(l10n.cloudSyncServiceGoogle));
      await settleSync(tester);
      expect(container.read(activeSyncServiceProvider), SyncService.google);
      expect(find.byKey(const Key('gis')), findsOneWidget);
      expect(find.text(l10n.cloudSyncGoogleNoAccount), findsOneWidget);

      await tester.runAsync(() async {
        google.click(
          const GoogleAccount(id: 'g-1', email: 'rider@example.com'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await settleSync(tester);
      expect(find.byKey(const Key('gis')), findsNothing);
      expect(find.text('rider@example.com'), findsOneWidget);
      expect(sync.resumes, 1);
      expect(
        container.read(sharedPreferencesProvider).getString('sync.google.user'),
        contains('g-1'),
      );
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('a Google token gone (an hour, a reload): Sign in asks '
        "Google's popup for another, and syncs", (tester) async {
      final google = _FakeButtonGoogle();
      final sync = _FixedSync(
        const CloudSyncStatus(
          account: CloudAccount.available,
          error: CloudSyncError.signInNeeded,
        ),
      );
      await pumpWeb(
        tester,
        [
          googleSignInServiceProvider.overrideWithValue(google),
          googleDriveStoreProvider.overrideWithValue(MemoryCloudStore()),
          cloudSyncControllerProvider.overrideWith(() => sync),
        ],
        prefs: {
          'sync.service': 'google',
          'sync.google.user': '{"id":"g-1","email":"rider@example.com"}',
        },
      );
      expect(find.text(l10n.cloudSyncSignInAgain), findsOneWidget);
      expect(find.text('rider@example.com'), findsOneWidget);
      expect(find.text(l10n.cloudSyncGoogleSignOut), findsNothing);
      await tester.tap(find.text(l10n.cloudSyncGoogleSignIn));
      await settleSync(tester);
      expect(google.authorizations, 1);
      expect(sync.resumes, 1);
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
