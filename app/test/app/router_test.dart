import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

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
      child: MaterialApp.router(
        theme: buildLightTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: createRouter(),
      ),
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
    for (final label in ['Plan', 'Record', 'Library', 'Settings']) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }
    expect(find.text('Tap the map to set a start.'), findsOneWidget);
  });

  testWidgets('switches between all four branches', (tester) async {
    await _pumpShell(tester);

    await _tapTab(tester, 'Record');
    expect(find.text('Ready to ride'), findsOneWidget);

    await _tapTab(tester, 'Library');
    expect(find.textContaining('No saved routes yet.'), findsOneWidget);

    await _tapTab(tester, 'Settings');
    // Advanced sits below the fold as the settings list grows.
    await tester.scrollUntilVisible(
      find.text('Server URLs'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Server URLs'), findsOneWidget);
    // The About section sits below it again.
    await tester.scrollUntilVisible(
      find.text('© OpenStreetMap contributors'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(find.text('Version 0.1.0+1'), findsOneWidget);

    await _tapTab(tester, 'Plan');
    expect(find.text('Tap the map to set a start.'), findsOneWidget);

    // Unmount so the library's database stream can finish closing; drift
    // schedules a zero-duration timer when its last listener goes away.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('editing a server URL is stored in the overrides', (
    tester,
  ) async {
    await _pumpShell(tester);
    await _tapTab(tester, 'Settings');
    // Advanced sits below the fold as the settings list grows.
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'BRouter URL'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'BRouter URL'),
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
