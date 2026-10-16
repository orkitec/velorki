import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/platform_features.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/offline/presentation/offline_entry.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';

import '../support/app.dart';

/// The app as a browser gets it: [PlatformFeatures.browser] and the router
/// built without the Record tab, on a tall window so the settings fit.
Future<GoRouter> _pumpBrowserShell(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = const Size(3000, 7200);
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = VelorkiDatabase.memory();
  addTearDown(db.close);
  final router = createRouter(recording: false);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        velorkiDatabaseProvider.overrideWithValue(db),
        platformFeaturesProvider.overrideWithValue(PlatformFeatures.browser),
      ],
      child: testRouterApp(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Takes the app down and lets what it scheduled on the way run out.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Velorki',
      packageName: 'com.orkitec.velorki',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('a phone or a tablet can do everything, a browser cannot', () {
    const device = PlatformFeatures.device;
    expect(<bool>[
      device.recording,
      device.storePurchases,
      device.accountConnections,
      device.offlineMapAreas,
    ], everyElement(isTrue));
    const browser = PlatformFeatures.browser;
    expect(<bool>[
      browser.recording,
      browser.storePurchases,
      browser.accountConnections,
      browser.offlineMapAreas,
    ], everyElement(isFalse));
    // Tests run on the VM: the provider answers the device's set there.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(platformFeaturesProvider),
      same(PlatformFeatures.device),
    );
  });

  testWidgets('the bar offers Plan, Library and Settings, and no Record', (
    tester,
  ) async {
    await _pumpBrowserShell(tester);

    expect(find.byType(NavigationDestination), findsNWidgets(3));
    for (final label in [l10n.tabPlan, l10n.tabLibrary, l10n.tabSettings]) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }
    expect(
      find.widgetWithText(NavigationDestination, l10n.tabRecord),
      findsNothing,
    );
    expect(find.text(l10n.plannerEmptyState), findsOneWidget);

    // The positions in the bar map onto the right tabs past the gap.
    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabSettings),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsAppearance.toUpperCase()), findsOneWidget);
    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabLibrary),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await _unmount(tester);
  });

  testWidgets('a link to the Record tab lands on the planner', (tester) async {
    final router = await _pumpBrowserShell(tester);

    router.go(recordingRoute);
    await tester.pumpAndSettle();

    expect(find.byType(RecordingScreen), findsNothing);
    expect(router.state.matchedLocation, plannerRoute);
    await _unmount(tester);
  });

  testWidgets('settings leave out navigation, recording, sensors, the '
      'connections and offline map areas', (tester) async {
    await _pumpBrowserShell(tester);
    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabSettings),
    );
    await tester.pumpAndSettle();

    for (final kept in [
      l10n.settingsAppearance,
      l10n.settingsRider,
      l10n.settingsSubscription,
      l10n.settingsAdvanced,
    ]) {
      expect(find.text(kept.toUpperCase()), findsOneWidget, reason: kept);
    }
    for (final gone in [
      l10n.settingsNavigation,
      l10n.settingsRecording,
      l10n.settingsSensors,
      l10n.settingsConnections,
    ]) {
      expect(find.text(gone.toUpperCase()), findsNothing, reason: gone);
    }
    expect(find.byType(OfflineEntry), findsNothing);
    await _unmount(tester);
  });
}
