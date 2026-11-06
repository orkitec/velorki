import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/domain/voice_option.dart';

void main() {
  test('an iOS voice shows its identifier; its language is the first part', () {
    const voice = VoiceOption(
      id: 'com.apple.voice.enhanced.en-US.Samantha',
      name: 'Samantha',
      localeTag: 'en-US',
    );

    expect(voice.displayName, 'Samantha');
    expect(voice.rawIdentifier, 'com.apple.voice.enhanced.en-US.Samantha');
    expect(voice.language, 'en');
  });

  test('an Android voice keyed by name and locale shows its name', () {
    const voice = VoiceOption(
      id: 'en-us-x-tpf-network|en-US',
      name: 'en-us-x-tpf-network',
      localeTag: 'en-US',
    );

    expect(voice.rawIdentifier, 'en-us-x-tpf-network');
    expect(
      const VoiceOption(id: 'a|de_DE', name: 'a', localeTag: 'de_DE').language,
      'de',
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
