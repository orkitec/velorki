import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/links/link_opener.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';
import 'package:velorki/features/navigation/data/voice_catalogue_asset.dart';
import 'package:velorki/features/navigation/domain/voice_catalogue.dart';
import 'package:velorki/features/navigation/domain/voice_option.dart';
import 'package:velorki/features/navigation/testing/fake_turn_speaker.dart';
import 'package:velorki/features/settings/presentation/voice_picker_screen.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

import '../../support/app.dart';
import '../../support/units.dart';

/// Every label the rider reads comes from the translations, so no test here
/// spells one out; `l10n` is the locale the suite runs in.
final AppLocalizations _l10n = l10n;

/// An Apple name is a proper noun; only the badge behind it is translated.
final String _zoeLabel = 'Zoe (${_l10n.voiceQualityEnhanced})';

/// What the system default row reads once it resolves to Zoe.
final String _defaultIsZoe = _l10n.settingsVoiceSystemDefaultNow(_zoeLabel);

/// The compact voice an iPhone ships with.
const VoiceOption _samantha = VoiceOption(
  id: 'com.apple.voice.compact.en-US.Samantha',
  name: 'Samantha',
  localeTag: 'en-US',
  quality: VoiceQuality.normal,
  gender: VoiceGender.female,
);
const VoiceOption _zoe = VoiceOption(
  id: 'com.apple.voice.enhanced.en-US.Zoe',
  name: 'Zoe',
  localeTag: 'en-US',
  quality: VoiceQuality.enhanced,
  gender: VoiceGender.female,
);

/// What Android hands out: a machine identifier and nothing else.
const VoiceOption _google = VoiceOption(
  id: 'en-us-x-iog-local|en-US',
  name: 'en-us-x-iog-local',
  localeTag: 'en-US',
  quality: VoiceQuality.normal,
);
const VoiceOption _germanGoogle = VoiceOption(
  id: 'de-de-x-dea-local|de-DE',
  name: 'de-de-x-dea-local',
  localeTag: 'de-DE',
  quality: VoiceQuality.normal,
);

/// An enhanced voice that is only there with a signal.
const VoiceOption _appleOnline = VoiceOption(
  id: 'com.apple.voice.enhanced.en-US.Cloud',
  name: 'Cloud',
  localeTag: 'en-US',
  quality: VoiceQuality.enhanced,
  needsNetwork: true,
);

/// An Android voice the engine does grade.
const VoiceOption _googleHigh = VoiceOption(
  id: 'en-us-x-tpd-local|en-US',
  name: 'en-us-x-tpd-local',
  localeTag: 'en-US',
  quality: VoiceQuality.enhanced,
);
const VoiceOption _online = VoiceOption(
  id: 'en-us-x-iom-network|en-US',
  name: 'en-us-x-iom-network',
  localeTag: 'en-US',
  quality: VoiceQuality.normal,
  needsNetwork: true,
);

final VoiceCatalogue _catalogue = VoiceCatalogue.fromJson(const {
  'en-us-x-iog-local': {
    'label': 'Female voice 3 (US)',
    'gender': 'female',
    'quality': 'enhanced',
    'language': 'en-US',
  },
  'de-de-x-dea-local': {
    'label': 'Female voice 1 (DE)',
    'gender': 'female',
    'quality': 'normal',
    'language': 'de-DE',
  },
});

Future<(ProviderContainer, FakeTurnSpeaker)> _pump(
  WidgetTester tester, {
  List<VoiceOption> voices = const [_samantha, _zoe],
  Map<String, Object> initial = const <String, Object>{},
  TargetPlatform platform = TargetPlatform.iOS,
  VoiceCatalogue? catalogue,
  List<Uri>? opened,
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final speaker = FakeTurnSpeaker(available: voices);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      turnSpeakerProvider.overrideWithValue(speaker),
      voiceCatalogueProvider.overrideWith((ref) => catalogue ?? _catalogue),
      linkOpenerProvider.overrideWithValue((url) async {
        opened?.add(url);
        return true;
      }),
      metricUnits,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testApp(
        theme: buildLightTheme().copyWith(platform: platform),
        home: const VoicePickerScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expectNoClippedText(tester);
  return (container, speaker);
}

void main() {
  testWidgets('an Android voice gets a name and keeps its identifier '
      'underneath', (tester) async {
    await _pump(
      tester,
      voices: const [_google],
      platform: TargetPlatform.android,
    );

    expect(
      find.text(_l10n.voiceLabel(_l10n.voiceFemale, 1, _l10n.regionUS)),
      findsOneWidget,
    );
    expect(find.text('en-us-x-iog-local'), findsOneWidget);
  });

  testWidgets('a voice the catalogue has never heard of is numbered', (
    tester,
  ) async {
    await _pump(
      tester,
      voices: const [_google],
      platform: TargetPlatform.android,
      catalogue: const VoiceCatalogue.empty(),
    );

    expect(
      find.text(_l10n.voiceLabelGeneric(1, _l10n.regionUS)),
      findsOneWidget,
    );
  });

  testWidgets('an iOS voice keeps its Apple name and wears its quality', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text(_zoeLabel), findsOneWidget);
    expect(find.text('Samantha'), findsOneWidget);
    expect(find.text('com.apple.voice.enhanced.en-US.Zoe'), findsOneWidget);
    // Best first.
    final names = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(names.indexOf(_zoeLabel), lessThan(names.indexOf('Samantha')));
  });

  testWidgets('online voices are left out until they are asked for', (
    tester,
  ) async {
    await _pump(
      tester,
      voices: const [_google, _online],
      platform: TargetPlatform.android,
    );

    expect(find.text('en-us-x-iom-network'), findsNothing);
    expect(find.text(_l10n.settingsVoiceNetworkTitle), findsNothing);

    await tester.tap(find.text(_l10n.voiceShowOnline));
    await tester.pumpAndSettle();

    expect(find.text('en-us-x-iom-network'), findsOneWidget);
    expect(find.text(_l10n.voiceNeedsNetwork), findsOneWidget);
    expect(find.text(_l10n.settingsVoiceNetworkTitle), findsOneWidget);
  });

  testWidgets('without an online voice there is nothing to switch on', (
    tester,
  ) async {
    await _pump(tester, voices: const [_samantha]);

    expect(find.text(_l10n.voiceShowOnline), findsNothing);
  });

  testWidgets('an iPhone with only compact voices is told where the better '
      'ones are', (tester) async {
    final opened = <Uri>[];
    await _pump(tester, voices: const [_samantha], opened: opened);

    expect(find.text(_l10n.voiceBetterTitle), findsOneWidget);
    expect(find.text(_l10n.voiceBetterBody(_l10n.languageEn)), findsOneWidget);
    // The way there, step by step, since Apple has no link to that page.
    expect(find.text(_l10n.voiceBetterStep1), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text(_l10n.voiceBetterStep2), findsOneWidget);
    expect(find.text(_l10n.voiceBetterStep3), findsOneWidget);
    expect(find.text(_l10n.voiceBetterStep4(_l10n.languageEn)), findsOneWidget);
    expect(find.text(_l10n.voiceBetterStep5), findsOneWidget);
    expect(find.text('5.'), findsOneWidget);
    expect(find.text(_l10n.voiceBetterAfter), findsOneWidget);
    // And where the button lands, which is not the voices page.
    expect(find.text(_l10n.voiceBetterOpenSettingsHint), findsOneWidget);

    await tester.tap(find.text(_l10n.voiceBetterOpenSettings));
    await tester.pumpAndSettle();

    expect(opened, [Uri.parse('app-settings:')]);
  });

  testWidgets('an iPhone whose best voice is only online is told too', (
    tester,
  ) async {
    await _pump(tester, voices: const [_samantha, _appleOnline]);

    expect(find.text(_l10n.voiceBetterTitle), findsOneWidget);
  });

  testWidgets('the system default row says which voice it comes out as', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text(_defaultIsZoe), findsOneWidget);
    expect(find.text(_l10n.settingsVoiceSystemDefault), findsNothing);
    // The hint about the phone's own voice stays under it.
    expect(find.text(_l10n.settingsVoiceSystemDefaultHint), findsOneWidget);
  });

  testWidgets('with nothing better than compact the row stays plain', (
    tester,
  ) async {
    await _pump(tester, voices: const [_samantha]);

    expect(find.text(_l10n.settingsVoiceSystemDefault), findsOneWidget);
  });

  testWidgets('on Android the row names the downloaded voice as well', (
    tester,
  ) async {
    await _pump(
      tester,
      voices: const [_googleHigh],
      platform: TargetPlatform.android,
      catalogue: const VoiceCatalogue.empty(),
    );

    expect(
      find.text(
        _l10n.settingsVoiceSystemDefaultNow(
          _l10n.voiceLabelGeneric(1, _l10n.regionUS),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('with an enhanced voice installed there is nothing to explain', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text(_l10n.voiceBetterTitle), findsNothing);
  });

  testWidgets('Android is not told to go looking in the iPhone settings', (
    tester,
  ) async {
    await _pump(
      tester,
      voices: const [_google],
      platform: TargetPlatform.android,
      catalogue: const VoiceCatalogue.empty(),
    );

    expect(find.text(_l10n.voiceBetterTitle), findsNothing);
  });

  testWidgets('tapping a voice stores it, hands it to the speaker and says a '
      'sample', (tester) async {
    final (container, speaker) = await _pump(tester);

    await tester.tap(find.text('Samantha'));
    await tester.pumpAndSettle();

    expect(
      container.read(navigationSettingsProvider).voiceId,
      'com.apple.voice.compact.en-US.Samantha',
    );
    expect(speaker.selections, ['com.apple.voice.compact.en-US.Samantha']);
    expect(speaker.spoken, ['In 200 metres, turn left']);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('navigation.voiceId'),
      'com.apple.voice.compact.en-US.Samantha',
    );
  });

  testWidgets('the try button speaks in that voice and puts the chosen one '
      'back', (tester) async {
    final (container, speaker) = await _pump(
      tester,
      initial: const {
        'navigation.voiceId': 'com.apple.voice.compact.en-US.Samantha',
      },
    );

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, _zoeLabel),
        matching: find.text(_l10n.voiceTry),
      ),
    );
    await tester.pumpAndSettle();

    expect(speaker.spoken, ['In 200 metres, turn left']);
    expect(speaker.selections, [
      'com.apple.voice.enhanced.en-US.Zoe',
      'com.apple.voice.compact.en-US.Samantha',
    ]);
    // The stored choice never moved.
    expect(
      container.read(navigationSettingsProvider).voiceId,
      'com.apple.voice.compact.en-US.Samantha',
    );
  });

  testWidgets('the system default clears the choice', (tester) async {
    final (container, speaker) = await _pump(
      tester,
      initial: const {
        'navigation.voiceId': 'com.apple.voice.compact.en-US.Samantha',
      },
    );

    await tester.tap(find.text(_defaultIsZoe));
    await tester.pumpAndSettle();

    expect(container.read(navigationSettingsProvider).voiceId, isNull);
    expect(speaker.selections, [null]);
  });

  testWidgets('a German phone still gets a name from the template', (
    tester,
  ) async {
    // The ARB only ships English, so the strings themselves fall back; the
    // point is that the template and the region key resolve either way and
    // the rider never sees `de-de-x-dea-local`.
    tester.platformDispatcher.localeTestValue = const Locale('de', 'DE');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    await _pump(
      tester,
      voices: const [_germanGoogle],
      platform: TargetPlatform.android,
    );

    expect(
      find.text(_l10n.voiceLabel(_l10n.voiceFemale, 1, _l10n.regionDE)),
      findsOneWidget,
    );
    expect(find.text('de-de-x-dea-local'), findsOneWidget);
  });

  testWidgets('no voices at all says where to get one', (tester) async {
    await _pump(tester, voices: const []);

    expect(find.text(_l10n.settingsVoiceNone), findsOneWidget);
  });
}
