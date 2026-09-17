import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/db/database.dart';

import '../support/app.dart';

Future<void> _pumpShell(WidgetTester tester) async {
  // The settings tab is long — subscription, connections, AI, advanced,
  // about — so the shell is pumped on a tall surface rather than scrolled to
  // every assertion.
  await tester.binding.setSurfaceSize(const Size(1000, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  // The library tab reads the database; give it one that needs no platform.
  final db = VelorkiDatabase.memory();
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        velorkiDatabaseProvider.overrideWithValue(db),
      ],
      child: testRouterApp(routerConfig: createRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(NavigationDestination, label));
  await tester.pumpAndSettle();
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

  testWidgets('shows four navigation destinations and starts on Plan', (
    tester,
  ) async {
    await _pumpShell(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    // The bar floats in its glass pill over a body that runs behind it.
    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(
      tester
          .widget<Scaffold>(
            find.ancestor(
              of: find.byType(FloatingNavigationBar),
              matching: find.byType(Scaffold),
            ),
          )
          .extendBody,
      isTrue,
    );
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    for (final label in [
      l10n.tabPlan,
      l10n.tabRecord,
      l10n.tabLibrary,
      l10n.tabSettings,
    ]) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }
    expect(find.text(l10n.plannerEmptyState), findsOneWidget);
  });

  testWidgets('the bar steps aside while the keyboard is up', (tester) async {
    await _pumpShell(tester);
    expect(find.byType(FloatingNavigationBar), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(find.byType(FloatingNavigationBar), findsNothing);
  });

  testWidgets('switches between all four branches', (tester) async {
    await _pumpShell(tester);

    await _tapTab(tester, l10n.tabRecord);
    expect(find.text(l10n.recordingIdleTitle), findsOneWidget);

    await _tapTab(tester, l10n.tabLibrary);
    expect(find.textContaining(l10n.libraryEmpty), findsOneWidget);

    await _tapTab(tester, l10n.tabSettings);
    // Advanced sits below the fold as the settings list grows.
    await tester.scrollUntilVisible(
      find.text(l10n.settingsServerUrls),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.settingsServerUrls), findsOneWidget);
    // The About section sits below it again, the version at its top and the
    // attribution under it — far enough apart that one scroll per line is
    // what it takes as the list grows.
    await tester.scrollUntilVisible(
      find.text('Version 0.1.0+1'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Version 0.1.0+1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(l10n.osmAttribution),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.osmAttribution), findsOneWidget);

    await _tapTab(tester, l10n.tabPlan);
    expect(find.text(l10n.plannerEmptyState), findsOneWidget);

    // Unmount so the library's database stream can finish closing; drift
    // schedules a zero-duration timer when its last listener goes away.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('editing a server URL is stored in the overrides', (
    tester,
  ) async {
    await _pumpShell(tester);
    await _tapTab(tester, l10n.tabSettings);
    // Advanced sits below the fold as the settings list grows.
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, l10n.settingsBrouterUrl),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.enterText(
      find.widgetWithText(TextField, l10n.settingsBrouterUrl),
      'http://10.0.2.2:17777',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NavigationBar));
    final container = ProviderScope.containerOf(context);
    expect(
      container.read(effectiveConfigProvider).brouterUrl,
      'http://10.0.2.2:17777',
    );
  });
}
