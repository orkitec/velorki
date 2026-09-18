import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/sensors/data/health_gateway.dart';
import 'package:velorki/features/sensors/data/sensor_settings.dart';
import 'package:velorki/features/sensors/presentation/sensors_section.dart';
import 'package:velorki/features/sensors/testing/fake_health_gateway.dart';

import '../../support/app.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  HealthGateway? gateway,
  Map<String, Object> initial = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      healthGatewayProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testApp(home: const Scaffold(body: SensorsSection())),
    ),
  );
  await tester.pumpAndSettle();
  expectNoClippedText(tester);
  return container;
}

SwitchListTile _tile(WidgetTester tester, String title) =>
    tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title));

void main() {
  // The widget suite runs as Android, so the store is Health Connect.
  final String healthTitle = l10n.settingsSensorsHealthConnect;

  testWidgets('starts off, and the write switch is dead with it', (
    tester,
  ) async {
    await _pump(tester, gateway: FakeHealthGateway());

    expect(find.text(healthTitle), findsOneWidget);
    expect(find.text(l10n.settingsSensorsHealthHint), findsOneWidget);
    expect(_tile(tester, healthTitle).value, isFalse);
    expect(_tile(tester, l10n.settingsSensorsHealthWrite).value, isTrue);
    expect(_tile(tester, l10n.settingsSensorsHealthWrite).onChanged, isNull);
  });

  testWidgets('switching it on asks the store and persists', (tester) async {
    final gateway = FakeHealthGateway();
    final container = await _pump(tester, gateway: gateway);

    await tester.tap(find.text(healthTitle));
    await tester.pumpAndSettle();

    expect(gateway.authorizations, <bool>[true], reason: 'asked to write too');
    expect(container.read(sensorSettingsProvider).health, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sensors.health'), isTrue);
    expect(_tile(tester, l10n.settingsSensorsHealthWrite).onChanged, isNotNull);
  });

  testWidgets('an operating system that refuses leaves the switch off', (
    tester,
  ) async {
    final gateway = FakeHealthGateway(grants: false);
    final container = await _pump(tester, gateway: gateway);

    await tester.tap(find.text(healthTitle));
    await tester.pumpAndSettle();

    expect(container.read(sensorSettingsProvider).health, isFalse);
    expect(_tile(tester, healthTitle).value, isFalse);
    expect(find.text(l10n.settingsSensorsHealthDenied), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sensors.health'), isNull);
  });

  testWidgets('switching it off asks nothing and clears the key', (
    tester,
  ) async {
    final gateway = FakeHealthGateway();
    final container = await _pump(
      tester,
      gateway: gateway,
      initial: const <String, Object>{'sensors.health': true},
    );
    expect(_tile(tester, healthTitle).value, isTrue);

    await tester.tap(find.text(healthTitle));
    await tester.pumpAndSettle();

    expect(gateway.authorizations, isEmpty);
    expect(container.read(sensorSettingsProvider).health, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sensors.health'), isNull, reason: 'the default');
  });

  testWidgets('switching the writing off persists', (tester) async {
    final container = await _pump(
      tester,
      gateway: FakeHealthGateway(),
      initial: const <String, Object>{'sensors.health': true},
    );

    await tester.tap(find.text(l10n.settingsSensorsHealthWrite));
    await tester.pumpAndSettle();

    expect(container.read(sensorSettingsProvider).healthWrite, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sensors.health.write'), isFalse);
  });

  testWidgets('a platform without a health store shows nothing', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byType(SwitchListTile), findsNothing);
  });
}
