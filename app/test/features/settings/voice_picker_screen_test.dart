import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';
import 'package:velorki/features/navigation/domain/voice_option.dart';
import 'package:velorki/features/navigation/testing/fake_turn_speaker.dart';
import 'package:velorki/features/settings/presentation/voice_picker_screen.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

import '../../support/units.dart';

const VoiceOption _samantha = VoiceOption(
  id: 'ios.samantha',
  name: 'Samantha',
  localeTag: 'en-US',
  quality: VoiceQuality.enhanced,
);
const VoiceOption _online = VoiceOption(
  id: 'online|en-GB',
  name: 'Online voice',
  localeTag: 'en-GB',
  needsNetwork: true,
);

Future<(ProviderContainer, FakeTurnSpeaker)> _pump(
  WidgetTester tester, {
  List<VoiceOption> voices = const [_samantha, _online],
  Map<String, Object> initial = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final speaker = FakeTurnSpeaker(available: voices);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      turnSpeakerProvider.overrideWithValue(speaker),
      metricUnits,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const VoicePickerScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, speaker);
}

void main() {
  testWidgets('lists the voices with their quality, marks the online one and '
      'explains it', (tester) async {
    await _pump(tester);

    expect(find.text('System default'), findsOneWidget);
    expect(find.text('Samantha'), findsOneWidget);
    expect(find.text('en-US · Enhanced'), findsOneWidget);
    expect(find.text('Online voice'), findsOneWidget);
    expect(find.text('Needs internet'), findsOneWidget);
    expect(find.text('Some voices need the internet'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsNWidgets(2));
  });

  testWidgets('without an online voice there is nothing to explain', (
    tester,
  ) async {
    await _pump(tester, voices: const [_samantha]);

    expect(find.text('Some voices need the internet'), findsNothing);
    expect(find.byIcon(Icons.cloud_outlined), findsNothing);
  });

  testWidgets('tapping a voice stores it, hands it to the speaker and says a '
      'sample', (tester) async {
    final (container, speaker) = await _pump(tester);

    await tester.tap(find.text('Samantha'));
    await tester.pumpAndSettle();

    expect(container.read(navigationSettingsProvider).voiceId, 'ios.samantha');
    expect(speaker.selections, ['ios.samantha']);
    expect(speaker.spoken, ['In 100 metres, turn left']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('navigation.voiceId'), 'ios.samantha');
  });

  testWidgets('the system default clears the choice', (tester) async {
    final (container, speaker) = await _pump(
      tester,
      initial: const {'navigation.voiceId': 'ios.samantha'},
    );

    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();

    expect(container.read(navigationSettingsProvider).voiceId, isNull);
    expect(speaker.selections, [null]);
  });

  testWidgets('no voices at all says where to get one', (tester) async {
    await _pump(tester, voices: const []);

    expect(find.textContaining('No voice for your language'), findsOneWidget);
  });
}
