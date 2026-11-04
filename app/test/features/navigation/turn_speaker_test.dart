import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speak/speak.dart' as tts;
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';
import 'package:velorki/features/navigation/domain/voice_option.dart';
import 'package:velorki/features/subscription/data/subscription_service.dart';

/// One call of the speaker: what was said, and how it was queued.
typedef _Said = ({String text, tts.SpeakQueue queue, Duration? expireAfter});

/// The `speak` speaker without an engine: it writes down what it was asked
/// and answers with what the test says.
class _FakeSpeak implements tts.Speak {
  _FakeSpeak(this.audio, [this.ios = const tts.IosSpeakOptions()]);

  @override
  final tts.SpeakAudio audio;

  /// The iOS options the speaker was built with.
  final tts.IosSpeakOptions ios;

  /// What [voices] lists; read on every call, so a test can play a voice
  /// being downloaded mid-run.
  List<tts.Voice> installed = [];

  /// Thrown by the next call, when set.
  Object? failNext;

  /// How the next calls end: a call on the phone makes it `blocked`.
  tts.SpeakOutcome outcome = tts.SpeakOutcome.completed;

  final said = <_Said>[];

  /// The voice each utterance was spoken in, by id.
  final voicesUsed = <String?>[];
  int stops = 0;
  bool disposed = false;

  @override
  tts.Voice? voice;

  @override
  String? language;

  @override
  double rate = 1;

  @override
  Future<tts.SpeakOutcome> call(
    String text, {
    tts.Voice? voice,
    String? language,
    double? rate,
    double? pitch,
    double? volume,
    tts.SpeakQueue queue = tts.SpeakQueue.append,
    Duration? expireAfter,
    void Function(tts.SpeechProgress progress)? onProgress,
  }) async {
    if (failNext case final error?) {
      failNext = null;
      throw error;
    }
    said.add((text: text, queue: queue, expireAfter: expireAfter));
    voicesUsed.add(this.voice?.id);
    return outcome;
  }

  @override
  Future<List<tts.Voice>> voices({String? language}) async => [
    for (final voice in installed)
      if (language == null || voice.language.startsWith(language)) voice,
  ];

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

tts.Voice _apple(
  String name,
  String quality, {
  String language = 'en-US',
  tts.VoiceGender gender = tts.VoiceGender.female,
}) => tts.Voice(
  id: 'com.apple.voice.$quality.$language.$name',
  name: name,
  language: language,
  gender: gender,
  quality: switch (quality) {
    'premium' => tts.VoiceQuality.premium,
    'enhanced' => tts.VoiceQuality.enhanced,
    _ => tts.VoiceQuality.normal,
  },
);

/// Android names a voice by its name alone: `speak`'s id is the name.
tts.Voice _android(
  String name, {
  tts.VoiceQuality quality = tts.VoiceQuality.unknown,
  bool network = false,
  bool installed = true,
}) => tts.Voice(
  id: name,
  name: name,
  language: 'en-US',
  quality: quality,
  requiresNetwork: network,
  isInstalled: installed,
);

/// The voices an iPhone with the compact English voices installed reports.
final List<tts.Voice> _appleVoices = [
  _apple('Samantha', 'compact'),
  _apple('Zoe', 'enhanced'),
  _apple('Anna', 'premium', language: 'de-DE'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSpeak engine;

  SpeakTurnSpeaker speaker({
    TargetPlatform platform = TargetPlatform.iOS,
    String? voiceId,
    InstructionAudio otherAudio = InstructionAudio.pausePodcasts,
    List<tts.Voice>? voices,
  }) => SpeakTurnSpeaker(
    voiceId: voiceId,
    otherAudio: otherAudio,
    platform: platform,
    create: (audio, ios) =>
        engine = _FakeSpeak(audio)..installed = voices ?? _appleVoices,
  );

  group('speaking', () {
    test(
      'a cue waits its turn and goes stale; an urgent one cuts in',
      () async {
        final turns = speaker();

        await turns.speak('In 200 metres, turn left');
        await turns.speak('Turn left now', urgent: true);

        expect(engine.said, [
          (
            text: 'In 200 metres, turn left',
            queue: tts.SpeakQueue.append,
            expireAfter: SpeakTurnSpeaker.staleAfter,
          ),
          (
            text: 'Turn left now',
            queue: tts.SpeakQueue.interrupt,
            expireAfter: null,
          ),
        ]);
      },
    );

    test('says the cues in the language they are written in', () async {
      final turns = SpeakTurnSpeaker(
        localeTag: 'de-DE',
        create: (audio, ios) => engine = _FakeSpeak(audio),
      );
      await turns.speak('Links abbiegen');
      expect(engine.language, 'de-DE');
    });

    test('on iOS the rate is nudged above the normal speed', () {
      speaker();
      // AVFoundation's 0.52 against its normal 0.5.
      expect(engine.rate, 1.04);
    });

    test('on Android the rate is left alone', () {
      speaker(platform: TargetPlatform.android);
      expect(engine.rate, 1);
    });

    test('says nothing for an empty cue', () async {
      final turns = speaker();
      await turns.speak('');
      expect(engine.said, isEmpty);
    });

    test(
      'a cue that fails is logged, and the next one is still said',
      () async {
        final turns = speaker();
        engine.failNext = const tts.SpeakException(tts.SpeakError.timeout);
        await turns.speak('One');
        await turns.speak('Two');
        expect(engine.said.map((s) => s.text), ['Two']);
      },
    );

    test(
      'a cue blocked by a phone call ends quietly, and the voice stays on',
      () async {
        final turns = speaker();
        engine.outcome = tts.SpeakOutcome.blocked;
        await turns.speak('During the call');
        engine.outcome = tts.SpeakOutcome.completed;
        await turns.speak('After the call');
        expect(engine.said.map((s) => s.text), [
          'During the call',
          'After the call',
        ]);
        expect(await turns.voices(), isNotEmpty);
      },
    );

    test('an engine that is not there turns the voice off for good', () async {
      final turns = speaker();
      engine.failNext = const tts.SpeakException(
        tts.SpeakError.engineUnavailable,
      );
      await turns.speak('One');
      await turns.speak('Two');
      expect(engine.said, isEmpty);
      expect(await turns.voices(), isEmpty);
    });

    test(
      'ending the guidance stops the speaker; dispose releases it',
      () async {
        final turns = speaker();
        await turns.beginGuidance();
        await turns.endGuidance();
        expect(engine.stops, 1);
        await turns.dispose();
        expect(engine.disposed, isTrue);
      },
    );
  });

  group('other audio', () {
    test('by default podcasts pause and music is lowered, as guidance', () {
      speaker();
      expect(engine.audio.otherAudio, tts.OtherAudio.duckAndPauseSpoken);
      expect(engine.audio.usage, tts.AudioUsage.navigation);
      // Claimed only while speaking: Velorki's lead-in for Bluetooth, a
      // short linger.
      expect(engine.audio.leadIn, SpeakTurnSpeaker.leadIn);
      expect(engine.audio.linger, tts.SpeakAudio.defaultLinger);
      // Nothing is said over a phone call, and nothing is kept for after it.
      expect(engine.audio.duringCalls, tts.SpeakDuringCalls.skip);
    });

    test('"lower the volume" lowers everything, still as guidance', () {
      speaker(otherAudio: InstructionAudio.lowerVolume);
      expect(engine.audio.otherAudio, tts.OtherAudio.duck);
      expect(engine.audio.usage, tts.AudioUsage.navigation);
    });
  });

  group('voices', () {
    test('the default is the best voice the phone actually has', () async {
      final turns = speaker();
      await turns.speak('Hello');
      // Anna is better still, but she speaks German.
      expect(engine.voicesUsed.single, 'com.apple.voice.enhanced.en-US.Zoe');
    });

    test('an online voice is not the one to fall back on', () async {
      final turns = speaker(
        voices: [
          _android('en-us-x-iom-network', quality: tts.VoiceQuality.premium),
          _apple('Samantha', 'compact'),
        ],
      );
      await turns.speak('Hello');
      // Left to the language: the compact voice, what the engine would use.
      expect(engine.voicesUsed.single, isNull);
      expect(engine.language, 'en-US');
    });

    test('on Android a downloaded voice is used as well', () async {
      final turns = speaker(
        platform: TargetPlatform.android,
        voices: [
          _android('en-us-x-iog-local', quality: tts.VoiceQuality.enhanced),
        ],
      );
      await turns.speak('Hello');
      expect(engine.voicesUsed.single, 'en-us-x-iog-local');
    });

    test('on Android a plain voice is still left to the language', () async {
      final turns = speaker(
        platform: TargetPlatform.android,
        voices: [
          _android('en-us-x-iog-local', quality: tts.VoiceQuality.normal),
          // Most of Android's voices come with no grade at all.
          _android('en-us-x-tpd-local'),
        ],
      );
      await turns.speak('Hello');
      expect(engine.voicesUsed.single, isNull);
    });

    test('a voice downloaded while the app runs is picked up', () async {
      final turns = speaker(voices: [_apple('Samantha', 'compact')]);
      await turns.selectVoice(null);
      await turns.speak('One');
      expect(engine.voicesUsed.last, isNull);

      engine.installed = [..._appleVoices];
      await turns.selectVoice(null);
      await turns.speak('Two');
      expect(engine.voicesUsed.last, 'com.apple.voice.enhanced.en-US.Zoe');
    });

    test('a chosen voice is used', () async {
      final turns = speaker(voiceId: 'com.apple.voice.compact.en-US.Samantha');
      await turns.speak('Hello');
      expect(
        engine.voicesUsed.single,
        'com.apple.voice.compact.en-US.Samantha',
      );
    });

    test('the ranking never overrules the rider', () async {
      final turns = speaker();
      await turns.selectVoice(null);
      await turns.selectVoice('com.apple.voice.compact.en-US.Samantha');
      await turns.speak('Hello');
      expect(
        engine.voicesUsed.single,
        'com.apple.voice.compact.en-US.Samantha',
      );
    });

    test('a chosen voice that is gone falls back to the ranking', () async {
      final turns = speaker(voiceId: 'com.apple.voice.compact.en-US.Nobody');
      await turns.speak('Hello');
      expect(engine.voicesUsed.single, 'com.apple.voice.enhanced.en-US.Zoe');
    });

    test('an Android choice stored as name and locale still counts', () async {
      final turns = speaker(
        platform: TargetPlatform.android,
        voiceId: 'en-us-x-tpd-local|en-US',
        voices: [
          _android('en-us-x-iog-local', quality: tts.VoiceQuality.enhanced),
          _android('en-us-x-tpd-local'),
        ],
      );
      await turns.speak('Hello');
      expect(engine.voicesUsed.single, 'en-us-x-tpd-local');
    });

    test(
      'only installed voices for the language of the cues are offered',
      () async {
        final turns = speaker(
          voices: [
            ..._appleVoices,
            _android('en-us-x-missing-local', installed: false),
          ],
        );
        final voices = await turns.voices();
        expect(voices.map((voice) => voice.name), ['Zoe', 'Samantha']);
      },
    );

    test('the cues wait for the voice, so they stay in order', () async {
      final turns = speaker();
      final first = turns.speak('One');
      final second = turns.speak('Two');
      await Future.wait([first, second]);
      expect(engine.said.map((s) => s.text), ['One', 'Two']);
      expect(engine.voicesUsed, everyElement(isNotNull));
    });
  });

  group('the provider', () {
    Future<_FakeSpeak> speakerIn(String? storeCountry) async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final made = <_FakeSpeak>[];
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          storeCountryProvider.overrideWith((ref) async => storeCountry),
          speakFactoryProvider.overrideWithValue((audio, ios) {
            final engine = _FakeSpeak(audio, ios)..installed = _appleVoices;
            made.add(engine);
            return engine;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(turnSpeakerProvider, (_, _) {});
      await container.read(storeCountryProvider.future);
      await container.read(turnSpeakerProvider).speak('Hello');
      return made.last;
    }

    test('asks CallKit about calls on a store outside China', () async {
      expect((await speakerIn('DEU')).ios.callKit, isTrue);
    });

    test("never asks CallKit on China's App Store", () async {
      expect((await speakerIn('CHN')).ios.callKit, isFalse);
    });

    test('never asks CallKit while the store has not said where', () async {
      expect((await speakerIn(null)).ios.callKit, isFalse);
    });

    test(
      'a new choice for other audio builds a new speaker for the next cue',
      () async {
        SharedPreferences.setMockInitialValues(const {});
        final prefs = await SharedPreferences.getInstance();
        final made = <_FakeSpeak>[];
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            speakFactoryProvider.overrideWithValue((audio, ios) {
              final engine = _FakeSpeak(audio)..installed = _appleVoices;
              made.add(engine);
              return engine;
            }),
          ],
        );
        addTearDown(container.dispose);

        await container.read(turnSpeakerProvider).speak('One');
        await container
            .read(navigationSettingsProvider.notifier)
            .setOtherAudio(InstructionAudio.lowerVolume);
        await container.read(turnSpeakerProvider).speak('Two');

        expect(made.map((e) => e.audio.otherAudio), [
          tts.OtherAudio.duckAndPauseSpoken,
          tts.OtherAudio.duck,
        ]);
        expect(made.first.disposed, isTrue);
        expect(made.last.said.map((s) => s.text), ['Two']);
      },
    );

    test('the rebuilt speaker keeps the rider\'s voice', () async {
      SharedPreferences.setMockInitialValues(const {
        'navigation.voiceId': 'com.apple.voice.compact.en-US.Samantha',
      });
      final prefs = await SharedPreferences.getInstance();
      final made = <_FakeSpeak>[];
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          speakFactoryProvider.overrideWithValue((audio, ios) {
            final engine = _FakeSpeak(audio)..installed = _appleVoices;
            made.add(engine);
            return engine;
          }),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(navigationSettingsProvider.notifier)
          .setOtherAudio(InstructionAudio.lowerVolume);
      await container.read(turnSpeakerProvider).speak('Hello');

      expect(
        made.last.voicesUsed.single,
        'com.apple.voice.compact.en-US.Samantha',
      );
    });
  });

  group('voiceOptionFrom', () {
    test('keeps quality, gender and the online flag', () {
      final option = voiceOptionFrom(
        _apple('Zoe', 'enhanced', gender: tts.VoiceGender.female),
      );
      expect(option.id, 'com.apple.voice.enhanced.en-US.Zoe');
      expect(option.quality, VoiceQuality.enhanced);
      expect(option.gender, VoiceGender.female);
      expect(option.needsNetwork, isFalse);
      expect(option.localeTag, 'en-US');
    });

    test('gives an Android voice the id it was stored by before', () {
      final option = voiceOptionFrom(_android('en-us-x-iog-local'));
      expect(option.id, 'en-us-x-iog-local|en-US');
      expect(option.rawIdentifier, 'en-us-x-iog-local');
    });

    test('a voice with the network suffix needs the network', () {
      expect(
        voiceOptionFrom(_android('en-us-x-iom-network')).needsNetwork,
        isTrue,
      );
      expect(
        voiceOptionFrom(_android('en-us-x-iom-local', network: true))
            .needsNetwork,
        isTrue,
      );
    });
  });

  group('cueLocaleTag', () {
    final dispatcher =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;

    tearDown(dispatcher.clearLocaleTestValue);

    test('a picked language borrows the phone region when it can', () {
      dispatcher.localeTestValue = const Locale('de', 'DE');
      expect(cueLocaleTag(), 'de-DE');
      expect(cueLocaleTag(const Locale('de')), 'de-DE');
    });

    test('English picked on a phone that is not English is en-US', () {
      dispatcher.localeTestValue = const Locale('de', 'DE');
      // A bare "en" is refused by some engines, and there is no English region
      // on this phone to borrow.
      expect(cueLocaleTag(const Locale('en')), 'en-US');
    });

    test('English picked on an English phone keeps that region', () {
      dispatcher.localeTestValue = const Locale('en', 'GB');
      expect(cueLocaleTag(const Locale('en')), 'en-GB');
    });

    test('a language the app is not translated into speaks English', () {
      dispatcher.localeTestValue = const Locale('ja', 'JP');
      expect(cueLocaleTag(), 'en-US');
      expect(cueLocaleTag(const Locale('ja')), 'en-US');
    });
  });
}
