import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/domain/voice_option.dart';
import 'package:velorki/features/navigation/domain/voice_ranking.dart';

/// A voice as the plugin would report it.
VoiceOption _voice(
  String name, {
  String locale = 'en-US',
  VoiceQuality quality = VoiceQuality.normal,
  bool needsNetwork = false,
}) => VoiceOption(
  id: 'id.$name',
  name: name,
  localeTag: locale,
  quality: quality,
  needsNetwork: needsNetwork,
);

void main() {
  test('nothing installed leaves the choice to the engine', () {
    expect(bestVoiceFor(const <VoiceOption>[], 'en-US'), isNull);
  });

  test('premium beats enhanced beats the everyday voice', () {
    final voices = [
      _voice('Samantha'),
      _voice('Zoe', quality: VoiceQuality.enhanced),
      _voice('Ava', quality: VoiceQuality.premium),
    ];

    expect(bestVoiceFor(voices, 'en-US')?.name, 'Ava');
    expect(bestVoiceFor(voices.sublist(0, 2), 'en-US')?.name, 'Zoe');
  });

  test('a voice no better than the engine default is not worth setting', () {
    final voices = [
      _voice('Samantha'),
      _voice('Fred', quality: VoiceQuality.low),
    ];

    expect(bestVoiceFor(voices, 'en-US'), isNull);
  });

  test('the exact locale wins when the grades are equal', () {
    final voices = [
      _voice('Daniel', locale: 'en-GB', quality: VoiceQuality.enhanced),
      _voice('Zoe', locale: 'en-US', quality: VoiceQuality.enhanced),
    ];

    expect(bestVoiceFor(voices, 'en-US')?.name, 'Zoe');
    expect(bestVoiceFor(voices, 'en-GB')?.name, 'Daniel');
    // Written the other way round, or with an underscore, is the same tag.
    expect(bestVoiceFor(voices, 'en_us')?.name, 'Zoe');
  });

  test('a language-only tag takes any region of that language', () {
    final voices = [
      _voice('Daniel', locale: 'en-GB', quality: VoiceQuality.enhanced),
    ];

    expect(bestVoiceFor(voices, 'en')?.name, 'Daniel');
  });

  test('a voice for another language is never the answer', () {
    final voices = [
      _voice('Anna', locale: 'de-DE', quality: VoiceQuality.premium),
      _voice('Zoe', quality: VoiceQuality.enhanced),
    ];

    expect(bestVoiceFor(voices, 'en-US')?.name, 'Zoe');
    expect(bestVoiceFor([voices.first], 'en-US'), isNull);
  });

  test('a voice synthesised online loses to one on the phone', () {
    final voices = [
      _voice(
        'en-us-x-iom-network',
        quality: VoiceQuality.premium,
        needsNetwork: true,
      ),
      _voice('Zoe', quality: VoiceQuality.enhanced),
    ];

    expect(bestVoiceFor(voices, 'en-US')?.name, 'Zoe');
  });

  test('an online voice is not taken even when it is the only good one', () {
    final voices = [
      _voice(
        'en-us-x-iom-network',
        quality: VoiceQuality.premium,
        needsNetwork: true,
      ),
      _voice('Samantha'),
    ];

    expect(bestVoiceFor(voices, 'en-US'), isNull);
  });

  test('a voice the platform will not grade counts as the everyday one', () {
    final mystery = _voice('en-us-x-iog-local', quality: VoiceQuality.unknown);

    // Not better than what the engine would have picked by itself.
    expect(bestVoiceFor([mystery], 'en-US'), isNull);
    // And a graded voice beats it, but a poor one does not.
    expect(
      bestVoiceFor([
        mystery,
        _voice('Zoe', quality: VoiceQuality.enhanced),
      ], 'en-US')?.name,
      'Zoe',
    );
    expect(
      bestVoiceFor([
        mystery,
        _voice('Fred', quality: VoiceQuality.low),
      ], 'en-US'),
      isNull,
    );
  });

  test("Google's alias for a voice loses to the voice itself", () {
    final voices = [
      _voice('en-US-language', quality: VoiceQuality.enhanced),
      _voice('en-us-x-iog-local', quality: VoiceQuality.enhanced),
    ];

    expect(bestVoiceFor(voices, 'en-US')?.name, 'en-us-x-iog-local');
  });

  test('the answer does not depend on the order the engine listed them', () {
    final voices = [
      _voice('Zoe', quality: VoiceQuality.enhanced),
      _voice('Allison', quality: VoiceQuality.enhanced),
    ];

    expect(bestVoiceFor(voices, 'en-US')?.name, 'Allison');
    expect(bestVoiceFor(voices.reversed.toList(), 'en-US')?.name, 'Allison');
  });
}
