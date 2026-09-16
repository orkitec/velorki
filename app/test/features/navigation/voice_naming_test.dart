import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/data/voice_catalogue_asset.dart';
import 'package:velorki/features/navigation/domain/voice_catalogue.dart';
import 'package:velorki/features/navigation/domain/voice_naming.dart';
import 'package:velorki/features/navigation/domain/voice_option.dart';
import 'package:velorki/features/navigation/presentation/voice_labels.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

/// The real translations: every label the rider reads comes out of these,
/// so the tests never spell one out themselves.
final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));
final VoiceNaming _naming = namingFrom(_l10n);

/// The catalogue only ever contributes gender and quality; its English
/// labels are deliberately nothing like what the list shows.
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
  'samantha': {
    'label': 'Samantha',
    'gender': 'female',
    'quality': 'normal',
    'language': 'en-US',
  },
});

VoiceOption _android(String name, {String locale = 'en-US'}) =>
    VoiceOption.fromPlatform({
      'name': name,
      'locale': locale,
      'quality': 'unknown',
      'network_required': '0',
      'features': '',
    })!;

void main() {
  group('the catalogue', () {
    test('gives an Android voice its gender and quality, never its name', () {
      final named = describeVoices(
        [_android('en-us-x-iog-local')],
        catalogue: _catalogue,
        naming: _naming,
      );

      expect(
        named.single.displayName,
        _l10n.voiceLabel(_l10n.voiceFemale, 1, _l10n.regionUS),
      );
      expect(named.single.gender, VoiceGender.female);
      expect(named.single.quality, VoiceQuality.enhanced);
      // The English label from the asset is never shown.
      expect(named.single.displayName, isNot('Female voice 3 (US)'));
      // The identifier is still there for the subtitle.
      expect(named.single.rawIdentifier, 'en-us-x-iog-local');
    });

    test("Google's region aliases hide behind the voices they stand for", () {
      final named = describeVoices(
        [
          _android('en-AU-language', locale: 'en-AU'),
          _android('en-au-x-aua-local', locale: 'en-AU'),
          _android('en-NG-language', locale: 'en-NG'),
        ],
        catalogue: _catalogue,
        naming: _naming,
      );

      // The Australian alias duplicates a real voice and goes; the Nigerian
      // one has no voice of its own and stays.
      expect(named.map((v) => v.rawIdentifier), [
        'en-au-x-aua-local',
        'en-NG-language',
      ]);
    });

    test('online voices are numbered on their own', () {
      final named = describeVoices(
        [
          _android('en-us-x-aaa-local'),
          _android('en-us-x-aaa-network'),
          _android('en-us-x-bbb-local'),
        ],
        catalogue: const VoiceCatalogue.empty(),
        naming: _naming,
      );
      final local = named.where((v) => !v.needsNetwork).toList();
      // Hidden online voices must not leave gaps: the two local ones are
      // 1 and 2 whatever sits between them in the engine's list.
      expect(local.map((v) => v.displayName).toSet(), hasLength(2));
      expect(
        local.map((v) => v.displayName),
        everyElement(isNot(contains('3'))),
      );
    });

    test("the rider's own region comes first", () {
      final named = describeVoices(
        [
          _android('en-au-x-aua-local', locale: 'en-AU'),
          _android('en-us-x-iog-local'),
        ],
        catalogue: _catalogue,
        naming: _naming,
        preferredLocaleTag: 'en-US',
      );

      expect(named.first.rawIdentifier, 'en-us-x-iog-local');
    });

    test('lets the engine have the last word on quality', () {
      final voice = VoiceOption.fromPlatform(const {
        'name': 'en-us-x-iog-local',
        'locale': 'en-US',
        'quality': 'normal',
      })!;

      final named = describeVoices(
        [voice],
        catalogue: _catalogue,
        naming: _naming,
      );

      expect(named.single.quality, VoiceQuality.normal);
      expect(named.single.gender, VoiceGender.female);
    });

    test('finds an Apple voice behind its identifier', () {
      const voice = VoiceOption(
        id: 'com.apple.ttsbundle.Samantha-compact',
        name: 'Samantha',
        localeTag: 'en-US',
      );

      expect(_catalogue.lookup(voice)?.gender, VoiceGender.female);
      expect(
        VoiceCatalogue.candidateKeys(voice),
        contains('com.apple.ttsbundle.samantha-compact'),
      );
    });

    test('voices are numbered per language, region and gender', () {
      final named = describeVoices(
        [
          _android('en-us-x-aaa-local'),
          _android('en-gb-x-bbb-local', locale: 'en-GB'),
          _android('en-us-x-ccc-local'),
          VoiceOption.fromPlatform(const {
            'name': 'en-us-x-ddd-local',
            'locale': 'en-US',
            'gender': 'male',
          })!,
        ],
        catalogue: const VoiceCatalogue.empty(),
        naming: _naming,
      );

      expect(named.map((voice) => voice.displayName), [
        _l10n.voiceLabel(_l10n.voiceMale, 1, _l10n.regionUS),
        _l10n.voiceLabelGeneric(1, _l10n.regionGB),
        _l10n.voiceLabelGeneric(1, _l10n.regionUS),
        _l10n.voiceLabelGeneric(2, _l10n.regionUS),
      ]);
    });

    test('a region nobody has translated keeps its tag', () {
      final named = describeVoices(
        [_android('xx-zz-x-aaa-local', locale: 'xx-ZZ')],
        catalogue: const VoiceCatalogue.empty(),
        naming: _naming,
      );

      expect(named.single.displayName, _l10n.voiceLabelGeneric(1, 'xx-ZZ'));
    });

    test('a German voice is named from the same template', () {
      final named = describeVoices(
        [_android('de-de-x-dea-local', locale: 'de-DE')],
        catalogue: _catalogue,
        naming: _naming,
      );

      expect(
        named.single.displayName,
        _l10n.voiceLabel(_l10n.voiceFemale, 1, _l10n.regionDE),
      );
    });
  });

  group('on iOS', () {
    test('the Apple name carries a quality badge', () {
      final voices = [
        VoiceOption.fromPlatform(const {
          'name': 'Samantha',
          'locale': 'en-US',
          'quality': 'default',
          'gender': 'female',
          'identifier': 'com.apple.voice.compact.en-US.Samantha',
        })!,
        VoiceOption.fromPlatform(const {
          'name': 'Evan',
          'locale': 'en-US',
          'quality': 'premium',
          'gender': 'male',
          'identifier': 'com.apple.voice.premium.en-US.Evan',
        })!,
        VoiceOption.fromPlatform(const {
          'name': 'Zoe',
          'locale': 'en-US',
          'quality': 'enhanced',
          'gender': 'female',
          'identifier': 'com.apple.voice.enhanced.en-US.Zoe',
        })!,
      ];

      final named = describeVoices(
        voices,
        catalogue: _catalogue,
        naming: _naming,
        apple: true,
      );

      // Best first, and the everyday voice keeps its bare name.
      expect(named.map((voice) => voice.displayName), [
        'Evan (${_l10n.voiceQualityPremium})',
        'Zoe (${_l10n.voiceQualityEnhanced})',
        'Samantha',
      ]);
    });
  });

  group('the bundled asset', () {
    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    test('knows the gender of the Google voices the complaint was about', () {
      // Nothing here reads a label: only what the engine will not say.
      expect(
        _catalogue.lookup(_android('en-us-x-iog-local'))?.label,
        isNotNull,
      );
    });

    test('covers the Google voices the complaint was about', () async {
      final catalogue = await loadVoiceCatalogue(rootBundle);

      expect(catalogue.length, greaterThan(400));
      final voice = describeVoices(
        [_android('en-us-x-iog-local')],
        catalogue: catalogue,
        naming: _naming,
      ).single;
      expect(voice.displayName, isNot(contains('x-iog')));
      expect(voice.gender, VoiceGender.female);
      expect(voice.quality, VoiceQuality.enhanced);
    });
  });
}
