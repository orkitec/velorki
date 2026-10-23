// iCloud sync on a device that has no iCloud account (a simulator nobody
// signed in to, the CI one): the native engine starts, CloudKit says there
// is no account, Settings says so, and the app goes on as before.
//
//   flutter test integration_test/icloud_sync_test.dart -d <simulator> \
//     --dart-define=VELORKI_BROUTER_URL= --dart-define=VELORKI_API_URL=
//
// On Android, and below iOS 17, there is no engine: the section is not in
// Settings at all. With `--dart-define=VELORKI_ITEST_HOLD_S=<s>` the test
// stays on the section that long, for a screenshot.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/features/settings/presentation/settings_screen.dart';
import 'package:velorki/features/sync/application/cloud_sync_controller.dart';
import 'package:velorki/features/sync/domain/cloud_sync_status.dart';
import 'package:velorki/features/sync/domain/sync_service.dart';
import 'package:velorki/features/sync/presentation/cloud_sync_section.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

import 'support/harness.dart';

const int _holdSeconds = int.fromEnvironment('VELORKI_ITEST_HOLD_S');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Settings shows where iCloud sync stands, and the app runs on', (
    tester,
  ) async {
    final container = await pumpApp(tester, realMap: false);
    // What bootstrap does at launch.
    final sync = container.listen(cloudSyncControllerProvider, (_, _) {});
    addTearDown(sync.close);
    await container
        .read(syncServiceChoiceProvider.notifier)
        .select(SyncService.icloud);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Navigator).first),
    );
    await tester.tap(find.text(l10n.tabSettings).last);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(SettingsScreen), findsOneWidget);

    final supported = await container.read(cloudSyncSupportedProvider.future);
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      expect(supported, isFalse);
      expect(find.byType(CloudSyncSection), findsNothing);
      await unmountApp(tester);
      return;
    }

    if (!supported) {
      // iOS 15 or 16.
      expect(find.byType(CloudSyncSection), findsNothing);
      await unmountApp(tester);
      return;
    }
    // Sync is the overview's first row.
    await tester.tap(find.byKey(const ValueKey(SettingsTopic.sync)));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(CloudSyncSection), findsOneWidget);
    await waitUntil(
      tester,
      () =>
          container.read(cloudSyncControllerProvider).account !=
          CloudAccount.unknown,
      describe: 'CloudKit to say what account there is',
      onTimeout: () => '${container.read(cloudSyncControllerProvider).account}',
    );
    final status = container.read(cloudSyncControllerProvider);
    debugPrint('VELORKI_ITEST iCloud account: ${status.account.name}');
    expect(find.text(l10n.cloudSyncWith), findsOneWidget);
    if (status.account == CloudAccount.noAccount) {
      expect(find.text(l10n.cloudSyncNoAccount), findsOneWidget);
    }
    if (_holdSeconds > 0) {
      await pumpFor(tester, const Duration(seconds: _holdSeconds));
    }

    // Off and on again: the engine stops and starts without a hitch.
    await tester.tap(find.text(l10n.cloudSyncServiceOff));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text(l10n.cloudSyncOff), findsOneWidget);
    await tester.tap(find.text(l10n.cloudSyncServiceICloud));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text(l10n.cloudSyncOff), findsNothing);

    await unmountApp(tester);
  });
}
