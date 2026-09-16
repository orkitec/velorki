import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/domain/voice_option.dart';

void main() {
  test('an iOS voice is read with its identifier and quality', () {
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
    expect(voice.language, 'en');
    expect(voice.quality, VoiceQuality.enhanced);
    expect(voice.needsNetwork, isFalse);
    expect(voice.platformVoice, {
      'name': 'Samantha',
      'locale': 'en-US',
      'identifier': 'com.apple.voice.enhanced.en-US.Samantha',
    });
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
    expect(voice.quality, VoiceQuality.premium);
    expect(voice.needsNetwork, isTrue);
    expect(voice.platformVoice, {
      'name': 'en-us-x-tpf-network',
      'locale': 'en-US',
    });
  });

  test('an entry without a name or locale is dropped', () {
    expect(VoiceOption.fromPlatform(const {'locale': 'en-US'}), isNull);
    expect(VoiceOption.fromPlatform(const {'name': 'x', 'locale': ''}), isNull);
  });

  test('unknown qualities are standard', () {
    expect(
      VoiceOption.fromPlatform(const {'name': 'a', 'locale': 'de-DE'})!.quality,
      VoiceQuality.standard,
    );
    expect(
      VoiceOption.fromPlatform(const {
        'name': 'a',
        'locale': 'de_DE',
        'quality': 'normal',
      })!.language,
      'de',
    );
  });

  test('better voices come first, online voices after on-device ones', () {
    const standardOnline = VoiceOption(
      id: '1',
      name: 'Alpha',
      localeTag: 'en-US',
      needsNetwork: true,
    );
    const standard = VoiceOption(id: '2', name: 'Zed', localeTag: 'en-US');
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

    final sorted = [standardOnline, standard, premium, enhanced]
      ..sort(VoiceOption.compare);

    expect(sorted, [premium, enhanced, standard, standardOnline]);
  });
}
