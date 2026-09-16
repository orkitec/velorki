import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/domain/voice_option.dart';

void main() {
  test('an iOS voice is read with its identifier, quality and gender', () {
    final voice = VoiceOption.fromPlatform(const {
      'name': 'Samantha',
      'locale': 'en-US',
      'quality': 'enhanced',
      'gender': 'female',
      'identifier': 'com.apple.voice.enhanced.en-US.Samantha',
    });

    expect(voice, isNotNull);
    expect(voice!.id, 'com.apple.voice.enhanced.en-US.Samantha');
    expect(voice.name, 'Samantha');
    expect(voice.displayName, 'Samantha');
    expect(voice.rawIdentifier, 'com.apple.voice.enhanced.en-US.Samantha');
    expect(voice.language, 'en');
    expect(voice.quality, VoiceQuality.enhanced);
    expect(voice.gender, VoiceGender.female);
    expect(voice.needsNetwork, isFalse);
    expect(voice.platformVoice, {
      'name': 'Samantha',
      'locale': 'en-US',
      'identifier': 'com.apple.voice.enhanced.en-US.Samantha',
    });
  });

  test('iOS calls its everyday voice "default"', () {
    final voice = VoiceOption.fromPlatform(const {
      'name': 'Anna',
      'locale': 'de-DE',
      'quality': 'default',
      'gender': 'unspecified',
      'identifier': 'com.apple.voice.compact.de-DE.Anna',
    });

    expect(voice!.quality, VoiceQuality.normal);
    expect(voice.gender, VoiceGender.unknown);
  });

  test('an Android voice is keyed by name and locale and knows about the '
      'network', () {
    final voice = VoiceOption.fromPlatform(const {
      'name': 'en-us-x-tpf-network',
      'locale': 'en-US',
      'quality': 'very high',
      'latency': 'very high',
      'network_required': '1',
      'features': 'networkTts',
    });

    expect(voice!.id, 'en-us-x-tpf-network|en-US');
    expect(voice.rawIdentifier, 'en-us-x-tpf-network');
    expect(voice.quality, VoiceQuality.premium);
    expect(voice.gender, VoiceGender.unknown);
    expect(voice.needsNetwork, isTrue);
    expect(voice.platformVoice, {
      'name': 'en-us-x-tpf-network',
      'locale': 'en-US',
    });
  });

  test('a voice whose identifier ends in -network is online, whatever the '
      'engine says about it', () {
    final voice = VoiceOption.fromPlatform(const {
      'name': 'en-gb-x-gbb-network',
      'locale': 'en-GB',
      'quality': 'normal',
      'network_required': '0',
      'features': '',
    });

    expect(voice!.needsNetwork, isTrue);
  });

  test('an entry without a name or locale is dropped', () {
    expect(VoiceOption.fromPlatform(const {'locale': 'en-US'}), isNull);
    expect(VoiceOption.fromPlatform(const {'name': 'x', 'locale': ''}), isNull);
  });

  test('a quality nobody reports is unknown', () {
    expect(
      VoiceOption.fromPlatform(const {'name': 'a', 'locale': 'de-DE'})!.quality,
      VoiceQuality.unknown,
    );
    expect(
      VoiceOption.fromPlatform(const {
        'name': 'a',
        'locale': 'de_DE',
        'quality': 'normal',
      })!.language,
      'de',
    );
    expect(
      VoiceOption.fromPlatform(const {
        'name': 'a',
        'locale': 'de-DE',
        'quality': 'very low',
      })!.quality,
      VoiceQuality.low,
    );
  });

  test('better voices come first, then by the name the rider reads', () {
    const unknown = VoiceOption(id: '1', name: 'Alpha', localeTag: 'en-US');
    const normal = VoiceOption(
      id: '2',
      name: 'Zed',
      localeTag: 'en-US',
      quality: VoiceQuality.normal,
    );
    const low = VoiceOption(
      id: '5',
      name: 'Delta',
      localeTag: 'en-US',
      quality: VoiceQuality.low,
    );
    const premium = VoiceOption(
      id: '3',
      name: 'Beta',
      localeTag: 'en-GB',
      quality: VoiceQuality.premium,
    );
    const enhanced = VoiceOption(
      id: '4',
      name: 'Gamma',
      localeTag: 'en-AU',
      quality: VoiceQuality.enhanced,
    );

    final sorted = [unknown, normal, low, premium, enhanced]
      ..sort(VoiceOption.compare);

    expect(sorted, [premium, enhanced, normal, low, unknown]);
  });

  test('the name the rider reads is what the sort goes by', () {
    const first = VoiceOption(
      id: '1',
      name: 'zzz-local',
      localeTag: 'en-US',
      displayName: 'Anna',
      quality: VoiceQuality.normal,
    );
    const second = VoiceOption(
      id: '2',
      name: 'aaa-local',
      localeTag: 'en-US',
      displayName: 'Bert',
      quality: VoiceQuality.normal,
    );

    expect([second, first]..sort(VoiceOption.compare), [first, second]);
  });
}
