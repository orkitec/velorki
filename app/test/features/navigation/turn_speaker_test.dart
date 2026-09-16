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

/// Records what the plugin was asked to do. [installed] is read on every
/// `getVoices`, so a test can play a voice being downloaded mid-run.
List<MethodCall> _mockEngine({
  List<Map<String, String>> voices = const [],
  List<Map<String, String>>? installed,
}) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        if (call.method == 'getVoices') return installed ?? voices;
        return 1;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return calls;
}

/// The last argument [method] was called with.
Object? _lastArgumentOf(List<MethodCall> calls, String method) {
  Object? argument;
  for (final call in calls) {
    if (call.method == method) argument = call.arguments;
  }
  return argument;
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

  test('an online voice is not the one to fall back on', () async {
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

    // The compact voice is what the engine would have used anyway.
    expect(calls.map((call) => call.method), contains('clearVoice'));
    expect(calls.map((call) => call.method), isNot(contains('setVoice')));
  });

  test('on Android a downloaded voice is used as well', () async {
    final calls = _mockEngine(
      voices: const [
        {'name': 'en-us-x-iog-local', 'locale': 'en-US', 'quality': 'high'},
      ],
    );
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.android);

    await speaker.selectVoice(null);

    // Android has no identifier, so name and locale are the whole voice.
    expect(_argumentOf(calls, 'setVoice'), {
      'name': 'en-us-x-iog-local',
      'locale': 'en-US',
    });
  });

  test('on Android a plain voice is still left to the engine', () async {
    final calls = _mockEngine(
      voices: const [
        {'name': 'en-us-x-iog-local', 'locale': 'en-US', 'quality': 'normal'},
        // Most of Android's voices come with no grade at all.
        {'name': 'en-us-x-tpd-local', 'locale': 'en-US'},
      ],
    );
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.android);

    await speaker.selectVoice(null);

    expect(calls.map((call) => call.method), contains('clearVoice'));
    expect(calls.map((call) => call.method), isNot(contains('setVoice')));
  });

  test('a voice downloaded while the app runs is picked up', () async {
    final installed = <Map<String, String>>[
      {
        'name': 'Samantha',
        'locale': 'en-US',
        'quality': 'default',
        'identifier': 'com.apple.voice.compact.en-US.Samantha',
      },
    ];
    final calls = _mockEngine(installed: installed);
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.iOS);

    await speaker.selectVoice(null);
    expect(calls.map((call) => call.method), isNot(contains('setVoice')));

    installed.add(const {
      'name': 'Zoe',
      'locale': 'en-US',
      'quality': 'enhanced',
      'identifier': 'com.apple.voice.enhanced.en-US.Zoe',
    });
    await speaker.selectVoice(null);

    expect((_argumentOf(calls, 'setVoice')! as Map)['name'], 'Zoe');
  });

  test('a chosen voice is used on both platforms', () async {
    final calls = _mockEngine(voices: _appleVoices);
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.iOS);

    await speaker.selectVoice('com.apple.voice.compact.en-US.Samantha');

    expect((_argumentOf(calls, 'setVoice')! as Map)['name'], 'Samantha');
  });

  test('the ranking never overrules the rider', () async {
    // Zoe is the better voice, but Samantha is the one that was chosen.
    final calls = _mockEngine(voices: _appleVoices);
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.iOS);

    await speaker.selectVoice(null);
    await speaker.selectVoice('com.apple.voice.compact.en-US.Samantha');

    expect((_lastArgumentOf(calls, 'setVoice')! as Map)['name'], 'Samantha');
  });

  test('a chosen voice that is gone falls back to the ranking', () async {
    final calls = _mockEngine(voices: _appleVoices);
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.iOS);

    await speaker.selectVoice('com.apple.voice.compact.en-US.Nobody');

    expect((_argumentOf(calls, 'setVoice')! as Map)['name'], 'Zoe');
  });

  test('only the voices for the language of the cues are offered', () async {
    _mockEngine(voices: _appleVoices);
    final speaker = FlutterTtsSpeaker(platform: TargetPlatform.iOS);

    final voices = await speaker.voices();

    expect(voices.map((voice) => voice.name), ['Zoe', 'Samantha']);
  });
}
