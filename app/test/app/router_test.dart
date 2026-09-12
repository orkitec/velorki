import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

Future<void> _pumpShell(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    for (final label in ['Plan', 'Record', 'Library', 'Settings']) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }
    expect(
      find.text('Route planning arrives with the map milestone.'),
      findsOneWidget,
    );
  });

  testWidgets('switches between all four branches', (tester) async {
    await _pumpShell(tester);

    await _tapTab(tester, 'Record');
    expect(
      find.text('Ride recording arrives with the recording milestone.'),
      findsOneWidget,
    );

    await _tapTab(tester, 'Library');
    expect(
      find.text('Saved routes and rides will be listed here.'),
      findsOneWidget,
    );

    await _tapTab(tester, 'Settings');
    expect(find.text('Server URLs'), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(find.text('Version 0.1.0+1'), findsOneWidget);

    await _tapTab(tester, 'Plan');
    expect(
      find.text('Route planning arrives with the map milestone.'),
      findsOneWidget,
    );
  });

  testWidgets('editing a server URL is stored in the overrides', (
    tester,
  ) async {
    await _pumpShell(tester);
    await _tapTab(tester, 'Settings');

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
