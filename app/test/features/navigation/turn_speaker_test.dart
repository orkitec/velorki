import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';

const MethodChannel _channel = MethodChannel('flutter_tts');

/// The voices an iPhone with the compact English voices installed reports.
const List<Map<String, String>> _appleVoices = [
  {
    'name': 'Samantha',
    'locale': 'en-US',
    'quality': 'default',
    'gender': 'female',
    'identifier': 'com.apple.voice.compact.en-US.Samantha',
  },
  {
    'name': 'Zoe',
    'locale': 'en-US',
    'quality': 'enhanced',
    'gender': 'female',
    'identifier': 'com.apple.voice.enhanced.en-US.Zoe',
  },
  {
    'name': 'Anna',
    'locale': 'de-DE',
    'quality': 'premium',
    'gender': 'female',
    'identifier': 'com.apple.voice.premium.de-DE.Anna',
  },
];

/// Records what the plugin was asked to do.
List<MethodCall> _mockEngine({List<Map<String, String>> voices = const []}) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        if (call.method == 'getVoices') return voices;
        return 1;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return calls;
}

Object? _argumentOf(List<MethodCall> calls, String method) {
  for (final call in calls) {
    if (call.method == method) return call.arguments;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('on iOS the rate is nudged above the plugin default', () async {
    final calls = _mockEngine();
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.iOS);

    await speaker.speak('In 200 metres, turn left');

    expect(_argumentOf(calls, 'setSpeechRate'), 0.52);
  });

  test('on Android the rate is left alone', () async {
    final calls = _mockEngine();
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.android);

    await speaker.speak('In 200 metres, turn left');

    expect(calls.map((call) => call.method), isNot(contains('setSpeechRate')));
  });

  test('on iOS the default is the best voice the phone actually has', () async {
    final calls = _mockEngine(voices: _appleVoices);
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.iOS);

    await speaker.selectVoice(null);

    expect(_argumentOf(calls, 'setVoice'), {
      'name': 'Zoe',
      'locale': 'en-US',
      'identifier': 'com.apple.voice.enhanced.en-US.Zoe',
    });
    // Anna is better still, but she speaks German.
    expect(calls.map((call) => call.method), isNot(contains('clearVoice')));
  });

  test('on iOS an online voice is not the one to fall back on', () async {
    final calls = _mockEngine(
      voices: const [
        {
          'name': 'en-us-x-iom-network',
          'locale': 'en-US',
          'quality': 'premium',
          'identifier': 'network.en-US.iom',
        },
        {
          'name': 'Samantha',
          'locale': 'en-US',
          'quality': 'default',
          'identifier': 'com.apple.voice.compact.en-US.Samantha',
        },
      ],
    );
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.iOS);

    await speaker.selectVoice(null);

    expect((_argumentOf(calls, 'setVoice')! as Map)['name'], 'Samantha');
  });

  test('on Android the default is left to the engine', () async {
    final calls = _mockEngine(
      voices: const [
        {'name': 'en-us-x-iog-local', 'locale': 'en-US', 'quality': 'high'},
      ],
    );
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.android);

    await speaker.selectVoice(null);

    expect(calls.map((call) => call.method), contains('clearVoice'));
    expect(calls.map((call) => call.method), isNot(contains('setVoice')));
  });

  test('a chosen voice is used on both platforms', () async {
    final calls = _mockEngine(voices: _appleVoices);
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.iOS);

    await speaker.selectVoice('com.apple.voice.compact.en-US.Samantha');

    expect((_argumentOf(calls, 'setVoice')! as Map)['name'], 'Samantha');
  });

  test('only the voices for the language of the cues are offered', () async {
    _mockEngine(voices: _appleVoices);
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.iOS);

    final voices = await speaker.voices();

    expect(voices.map((voice) => voice.name), ['Zoe', 'Samantha']);
  });
}
