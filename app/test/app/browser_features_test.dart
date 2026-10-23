import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
import 'package:velorki/features/settings/presentation/settings_screen.dart';
import 'package:velorki/features/sync/data/cloud_sync_bridge.dart';
import 'package:velorki/features/sync/presentation/cloud_sync_section.dart';

import '../support/app.dart';
import '../support/settings.dart';

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
    expect(find.byType(SettingsScreen), findsOneWidget);
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
      SettingsTopic.plus,
      SettingsTopic.rider,
      SettingsTopic.appearance,
      SettingsTopic.mapsData,
    ]) {
      expect(settingsRow(kept), findsOneWidget, reason: '$kept');
    }
    for (final gone in [
      SettingsTopic.navigation,
      SettingsTopic.recording,
      SettingsTopic.sensors,
      SettingsTopic.connections,
    ]) {
      expect(settingsRow(gone), findsNothing, reason: '$gone');
    }
    await openSettingsTopic(tester, SettingsTopic.mapsData);
    expect(find.byType(OfflineEntry), findsNothing);
    // It routes on its own: no choice of where, no routing server's address.
    expect(find.text(l10n.settingsRouting), findsNothing);
    expect(find.text(l10n.settingsBrouterUrl), findsNothing);
    expect(find.text(l10n.settingsPhotonUrl), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a browser on an Apple device gets no iCloud sync: no engine, '
      'no setting', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _pumpBrowserShell(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NavigationBar)),
    );
    expect(container.read(cloudSyncBridgeProvider), isNull);
    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabSettings),
    );
    await tester.pumpAndSettle();
    expect(settingsRow(SettingsTopic.sync), findsNothing);
    expect(find.byType(CloudSyncSection), findsNothing);
    debugDefaultTargetPlatformOverride = null;
    await _unmount(tester);
  });

  testWidgets('a mouse drag scrolls where the browser says it may, and not '
      'with the default behaviour', (tester) async {
    expect(PlatformFeatures.browser.mouseDrags, isTrue);
    expect(PlatformFeatures.device.mouseDrags, isFalse);
    Future<double> dragged(ScrollBehavior? behavior) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: behavior,
          home: ListView(
            controller: controller,
            children: [
              for (var i = 0; i < 50; i++)
                SizedBox(height: 50, child: Text('$i')),
            ],
          ),
        ),
      );
      await tester.drag(
        find.byType(ListView),
        const Offset(0, -200),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      return controller.offset;
    }

    expect(await dragged(null), 0);
    expect(await dragged(const PointerDragScrollBehavior()), greaterThan(100));
  });

  testWidgets('a list in the browser gets no scrollbar of its own, as on '
      'the phone', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    Future<int> scrollbars(ScrollBehavior? behavior) async {
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: behavior,
          home: ListView(
            children: [
              for (var i = 0; i < 50; i++)
                SizedBox(height: 50, child: Text('$i')),
            ],
          ),
        ),
      );
      return find.byType(Scrollbar).evaluate().length;
    }

    // Material's desktop default, which made the second bar on a sheet.
    expect(await scrollbars(null), 1);
    expect(await scrollbars(const PointerDragScrollBehavior()), 0);
    debugDefaultTargetPlatformOverride = null;
  });
}
