import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';
import 'package:velorki/features/navigation/testing/fake_turn_speaker.dart';
import 'package:velorki/features/settings/presentation/voice_picker_screen.dart';
import 'package:velorki/features/settings/presentation/navigation_section.dart';

import '../../support/app.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> initial = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      turnSpeakerProvider.overrideWithValue(FakeTurnSpeaker()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testApp(home: const Scaffold(body: NavigationSection())),
    ),
  );
  await tester.pumpAndSettle();
  expectNoClippedText(tester);
  return container;
}

SwitchListTile _tile(WidgetTester tester, String title) =>
    tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title));

void main() {
  testWidgets('all three switches start on', (tester) async {
    await _pump(tester);

    expect(find.text(l10n.settingsTurnDirections), findsOneWidget);
    expect(find.text(l10n.settingsTurnDirectionsHint), findsOneWidget);
    expect(find.text(l10n.settingsVoiceDirections), findsOneWidget);
    expect(find.text(l10n.settingsVoiceDirectionsHint), findsOneWidget);
    expect(find.text(l10n.settingsReroute), findsOneWidget);
    expect(find.text(l10n.settingsRerouteHint), findsOneWidget);
    expect(_tile(tester, l10n.settingsTurnDirections).value, isTrue);
    expect(_tile(tester, l10n.settingsVoiceDirections).value, isTrue);
    expect(_tile(tester, l10n.settingsReroute).value, isTrue);
  });

  testWidgets('switching the turns off persists and greys out the rest', (
    tester,
  ) async {
    final container = await _pump(tester);

    await tester.tap(find.text(l10n.settingsTurnDirections));
    await tester.pumpAndSettle();

    expect(container.read(navigationSettingsProvider).turns, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('navigation.turns'), isFalse);
    expect(_tile(tester, l10n.settingsVoiceDirections).onChanged, isNull);
    expect(_tile(tester, l10n.settingsReroute).onChanged, isNull);
  });

  testWidgets('switching the voice off persists', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.text(l10n.settingsVoiceDirections));
    await tester.pumpAndSettle();

    expect(container.read(navigationSettingsProvider).voice, isFalse);
    expect(_tile(tester, l10n.settingsVoiceDirections).value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('navigation.voice'), isFalse);
  });

  testWidgets('the voice switch is dead while the turns are off', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      initial: const <String, Object>{'navigation.turns': false},
    );

    expect(_tile(tester, l10n.settingsVoiceDirections).onChanged, isNull);

    await tester.tap(
      find.text(l10n.settingsVoiceDirections),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(container.read(navigationSettingsProvider).voice, isTrue);
  });

  testWidgets('switching re-routing off persists', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.text(l10n.settingsReroute));
    await tester.pumpAndSettle();

    expect(container.read(navigationSettingsProvider).reroute, isFalse);
    expect(_tile(tester, l10n.settingsReroute).value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('navigation.reroute'), isFalse);
  });

  testWidgets('the re-route switch is dead while the turns are off', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      initial: const <String, Object>{'navigation.turns': false},
    );

    expect(_tile(tester, l10n.settingsReroute).onChanged, isNull);

    await tester.tap(find.text(l10n.settingsReroute), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(container.read(navigationSettingsProvider).reroute, isTrue);
  });

  testWidgets('the stored switches are the ones shown', (tester) async {
    await _pump(
      tester,
      initial: const <String, Object>{
        'navigation.voice': false,
        'navigation.reroute': false,
      },
    );

    expect(_tile(tester, l10n.settingsTurnDirections).value, isTrue);
    expect(_tile(tester, l10n.settingsVoiceDirections).value, isFalse);
    expect(_tile(tester, l10n.settingsReroute).value, isFalse);
  });

  testWidgets('the announce-turns slider shows and stores the lead', (
    tester,
  ) async {
    final container = await _pump(tester);

    expect(find.text(l10n.settingsTurnLead), findsOneWidget);
    expect(find.text(l10n.settingsTurnLeadHint(10)), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 10);
    expect(slider.min, 5);
    expect(slider.max, 30);

    slider.onChanged!(20);
    await tester.pumpAndSettle();

    expect(container.read(navigationSettingsProvider).leadSeconds, 20);
    expect(find.text(l10n.settingsTurnLeadHint(20)), findsOneWidget);
  });

  testWidgets('the slider greys out without a voice', (tester) async {
    await _pump(tester, initial: const {'navigation.voice': false});

    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });

  testWidgets('the speaking voice row shows the default and opens the list', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text(l10n.settingsVoicePick), findsOneWidget);
    expect(find.text(l10n.settingsVoiceSystemDefault), findsOneWidget);

    await tester.tap(find.text(l10n.settingsVoicePick));
    await tester.pumpAndSettle();

    expect(find.byType(VoicePickerScreen), findsOneWidget);
  });

  testWidgets('the speaking voice row greys out without a voice', (
    tester,
  ) async {
    await _pump(tester, initial: const {'navigation.voice': false});

    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, l10n.settingsVoicePick),
    );
    expect(tile.enabled, isFalse);
  });
}
