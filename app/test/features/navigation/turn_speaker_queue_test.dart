import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:velorki/features/navigation/data/navigation_audio.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';

const MethodChannel _channel = MethodChannel('flutter_tts');

const MethodChannel _audioChannel = MethodChannel(NavigationAudio.channelName);

/// Answers the calls the speaker makes that [_Engine] does not intercept
/// (`setLanguage`, `awaitSpeakCompletion`, `setVolume`, ...), and writes them
/// down.
List<MethodCall> _mockChannel() {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        if (call.method == 'getVoices') return const <Object?>[];
        return 1;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return calls;
}

/// Answers the native audio helper (`app.velorki/audio`) and writes what it
/// was asked for into [trace] — the same list [_Engine] writes `speak` to, so
/// the order of the lead-in against the cue is visible.
/// [hold], when given, keeps `playLeadIn` playing until it is completed, the
/// way the 1.5 s of silence does on the phone.
void _mockAudio(List<String> trace, {Completer<void>? hold}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_audioChannel, (call) async {
        trace.add(call.method);
        if (call.method == 'playLeadIn' && hold != null) await hold.future;
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioChannel, null),
  );
}

/// A text-to-speech engine that speaks only when the test says so.
///
/// `speak` hangs until [finish] is called, which is what a real engine does
/// with `awaitSpeakCompletion(true)`: the future is the end of the utterance.
/// [stop] drops the utterance without completing it, the way iOS does — there
/// the plugin only hands the result back from `didFinish`, never from
/// `didCancel`.
class _Engine extends FlutterTts {
  /// [trace] is shared with [_mockAudio] when the test cares about the order
  /// of the native audio calls against the cues.
  _Engine({List<String>? trace}) : trace = trace ?? <String>[];

  /// Every cue and every audio call, in the order they went out.
  final List<String> trace;

  final List<String> spoken = <String>[];
  int stops = 0;
  int sessions = 0;

  /// What `autoStopSharedSession` was told, in order.
  final List<bool> autoStops = <bool>[];
  final List<
    ({
      IosTextToSpeechAudioCategory category,
      List<IosTextToSpeechAudioCategoryOptions> options,
      IosTextToSpeechAudioMode mode,
    })
  >
  categories = [];

  Completer<void>? _speaking;

  /// Whether an utterance is in flight.
  bool get isSpeaking => _speaking != null;

  /// Plays the utterance in flight to its end.
  void finish() {
    final speaking = _speaking;
    _speaking = null;
    speaking?.complete();
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) {
    spoken.add(text);
    trace.add('speak');
    final speaking = _speaking = Completer<void>();
    return speaking.future.then((_) => 1);
  }

  @override
  Future<dynamic> stop() async {
    stops++;
    _speaking = null;
    return 1;
  }

  @override
  Future<dynamic> autoStopSharedSession(bool autoStop) async {
    autoStops.add(autoStop);
    return 1;
  }

  @override
  Future<dynamic> setSharedInstance(bool sharedSession) async {
    if (sharedSession) sessions++;
    return 1;
  }

  @override
  Future<dynamic> setIosAudioCategory(
    IosTextToSpeechAudioCategory category,
    List<IosTextToSpeechAudioCategoryOptions> options, [
    IosTextToSpeechAudioMode mode = IosTextToSpeechAudioMode.defaultMode,
  ]) async {
    categories.add((category: category, options: options, mode: mode));
    return 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the audio session', () {
    test('is set up once on iOS, before the first cue', () async {
      _mockChannel();
      final engine = _Engine();
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
      );

      unawaited(speaker.speak('In 200 metres, turn left'));
      await pumpEventQueue();
      expect(engine.spoken, ['In 200 metres, turn left']);
      expect(engine.sessions, 1, reason: 'set up before the cue went out');
      engine.finish();
      await pumpEventQueue();

      unawaited(speaker.speak('Turn left'));
      await pumpEventQueue();

      expect(engine.sessions, 1, reason: 'and not again for the second cue');
      expect(engine.categories, hasLength(1));
      final session = engine.categories.single;
      expect(session.category, IosTextToSpeechAudioCategory.playback);
      expect(session.mode, IosTextToSpeechAudioMode.voicePrompt);
      // Mixed with music and holding spoken audio off: a cue is never the
      // thing that gets silenced. Not ducked — iOS ramps the other app down
      // and back up around every utterance, and on a Bluetooth headset that
      // ramp costs the first word of the cue.
      expect(session.options, [
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        IosTextToSpeechAudioCategoryOptions
            .interruptSpokenAudioAndMixWithOthers,
      ]);
    });

    test('is left alone on Android', () async {
      _mockChannel();
      final engine = _Engine();
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.android,
        engine: engine,
      );

      unawaited(speaker.speak('In 200 metres, turn left'));
      await pumpEventQueue();

      expect(engine.sessions, 0);
      expect(engine.categories, isEmpty);
    });

    test('is held open for the whole of a guided ride', () async {
      _mockChannel();
      final trace = <String>[];
      _mockAudio(trace);
      final engine = _Engine(trace: trace);
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
      );

      await speaker.beginGuidance();

      // The category first, then the plugin's per-utterance deactivation
      // switched off: without that it tears the Bluetooth link down after
      // every cue and the next one starts into a link still coming up.
      expect(engine.categories, hasLength(1));
      expect(engine.autoStops, <bool>[false]);
    });

    test('is given back once, when the guided ride ends', () async {
      _mockChannel();
      final trace = <String>[];
      _mockAudio(trace);
      final engine = _Engine(trace: trace);
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
      );

      await speaker.beginGuidance();
      await speaker.endGuidance();
      await speaker.endGuidance();

      expect(engine.autoStops, <bool>[false, true]);
      expect(
        trace.where((method) => method == 'deactivateSession'),
        hasLength(1),
      );
    });

    test('a cue is preceded by the silent lead-in on iOS', () async {
      _mockChannel();
      final trace = <String>[];
      _mockAudio(trace);
      final engine = _Engine(trace: trace);
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
      );

      await speaker.beginGuidance();
      unawaited(speaker.speak('In 200 metres, turn left'));
      await pumpEventQueue();

      // The silence wakes the headset, and only then does the voice start.
      // One per cue: nothing plays in between.
      expect(trace, <String>['playLeadIn', 'speak']);
    });

    test('no lead-in when muted', () async {
      _mockChannel();
      final trace = <String>[];
      _mockAudio(trace);
      final engine = _Engine(trace: trace);
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
      );

      await speaker.beginGuidance();
      // Muting a ride from the banner is what ends the guidance; a cue said
      // outside one — the voice tried out in Settings — gets no lead-in.
      await speaker.endGuidance();
      trace.clear();
      unawaited(speaker.speak('Now turn left'));
      await pumpEventQueue();

      expect(trace, <String>['speak']);
    });

    test('no lead-in on Android', () async {
      _mockChannel();
      final trace = <String>[];
      _mockAudio(trace);
      final engine = _Engine(trace: trace);
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.android,
        engine: engine,
      );

      await speaker.beginGuidance();
      unawaited(speaker.speak('In 200 metres, turn left'));
      await pumpEventQueue();
      engine.finish();
      await speaker.endGuidance();

      // The session, the lead-in and the plugin's own deactivation are all
      // iOS; Android's guidance rides on the engine's audio attributes.
      expect(trace, <String>['speak']);
      expect(engine.autoStops, isEmpty);
    });

    test('an urgent cue does not wait the lead-in out', () async {
      _mockChannel();
      final trace = <String>[];
      final hold = Completer<void>();
      _mockAudio(trace, hold: hold);
      final engine = _Engine(trace: trace);
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
      );

      await speaker.beginGuidance();
      final first = speaker.speak('In 200 metres, turn left');
      await pumpEventQueue();
      expect(engine.spoken, isEmpty, reason: 'still waiting on the silence');

      final urgent = speaker.speak('Now turn left', urgent: true);
      await first;
      hold.complete();
      await pumpEventQueue();
      engine.finish();
      await urgent;

      // The cue the rider has already ridden past is dropped where it stood,
      // silence and all.
      expect(engine.spoken, <String>['Now turn left']);
    });

    test('is told to speak at full volume on both', () async {
      final calls = _mockChannel();
      final engine = _Engine();
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
      );

      unawaited(speaker.speak('In 200 metres, turn left'));
      await pumpEventQueue();

      expect(
        calls.singleWhere((call) => call.method == 'setVolume').arguments,
        1.0,
      );
      expect(
        calls
            .singleWhere((call) => call.method == 'awaitSpeakCompletion')
            .arguments,
        isTrue,
      );
    });
  });

  group('the cue queue', () {
    test('says one cue after the other, and resolves in order', () async {
      _mockChannel();
      final engine = _Engine();
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
      );
      final done = <String>[];

      final first = speaker
          .speak('In 200 metres, turn left')
          .then((_) => done.add('first'));
      final second = speaker
          .speak('Then keep right')
          .then((_) => done.add('second'));
      await pumpEventQueue();

      // The second cue waits rather than cutting the first one off mid-word.
      expect(engine.spoken, ['In 200 metres, turn left']);
      expect(done, isEmpty);

      engine.finish();
      await pumpEventQueue();
      expect(engine.spoken, ['In 200 metres, turn left', 'Then keep right']);
      expect(done, ['first']);

      engine.finish();
      await Future.wait([first, second]);
      expect(done, ['first', 'second']);
    });

    test('an urgent cue stops the one being said and goes next', () async {
      _mockChannel();
      final engine = _Engine();
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
      );

      final ahead = speaker.speak('In 200 metres, turn left');
      await pumpEventQueue();
      expect(engine.spoken, ['In 200 metres, turn left']);

      final now = speaker.speak('Turn left', urgent: true);
      await pumpEventQueue();

      expect(engine.stops, 1, reason: 'the engine is quietened first');
      expect(engine.spoken, ['In 200 metres, turn left', 'Turn left']);
      // The cut cue is done even though the engine never reported it: on iOS
      // a stopped utterance is never handed back.
      await ahead;

      engine.finish();
      await now;
    });

    test('an urgent cue drops what was queued behind it', () async {
      _mockChannel();
      final engine = _Engine();
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
      );

      final ahead = speaker.speak('In 200 metres, turn left');
      await pumpEventQueue();
      final waiting = speaker.speak('In 100 metres, turn left');
      final now = speaker.speak('Turn left', urgent: true);
      await pumpEventQueue();
      engine.finish();
      await Future.wait([ahead, waiting, now]);

      expect(engine.spoken, ['In 200 metres, turn left', 'Turn left']);
    });

    test('a cue that waited too long is dropped unsaid', () async {
      _mockChannel();
      final engine = _Engine();
      var now = DateTime(2026, 9, 16, 10);
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
        clock: () => now,
      );

      final ahead = speaker.speak('In 200 metres, turn left');
      await pumpEventQueue();
      final stale = speaker.speak('In 100 metres, turn left');
      // The first cue takes longer than it should: a phone waking up, an
      // engine loading a premium voice.
      now = now.add(FlutterTtsSpeaker.staleAfter + const Duration(seconds: 1));
      engine.finish();
      await Future.wait([ahead, stale]);

      expect(engine.spoken, ['In 200 metres, turn left']);
      expect(engine.isSpeaking, isFalse);
    });

    test('a cue that waited a moment is still said', () async {
      _mockChannel();
      final engine = _Engine();
      var now = DateTime(2026, 9, 16, 10);
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
        clock: () => now,
      );

      final ahead = speaker.speak('In 200 metres, turn left');
      await pumpEventQueue();
      final next = speaker.speak('In 100 metres, turn left');
      now = now.add(const Duration(seconds: 3));
      engine.finish();
      await pumpEventQueue();
      engine.finish();
      await Future.wait([ahead, next]);

      expect(engine.spoken, [
        'In 200 metres, turn left',
        'In 100 metres, turn left',
      ]);
    });

    test('an urgent cue is said however long it waited', () async {
      _mockChannel();
      final engine = _Engine();
      var now = DateTime(2026, 9, 16, 10);
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
        clock: () => now,
      );

      final ahead = speaker.speak('The route has changed');
      await pumpEventQueue();
      // Queued, then held up long enough to be stale, but a turn the rider is
      // taking now is still worth saying.
      final urgent = speaker.speak('Turn left', urgent: true);
      now = now.add(FlutterTtsSpeaker.staleAfter + const Duration(seconds: 1));
      await pumpEventQueue();
      engine.finish();
      await Future.wait([ahead, urgent]);

      expect(engine.spoken, ['The route has changed', 'Turn left']);
    });

    test('stop drops what is being said and what is queued', () async {
      _mockChannel();
      final engine = _Engine();
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
      );

      final ahead = speaker.speak('In 200 metres, turn left');
      await pumpEventQueue();
      final waiting = speaker.speak('Then keep right');
      await speaker.stop();
      await Future.wait([ahead, waiting]);

      expect(engine.stops, 1);
      expect(engine.spoken, ['In 200 metres, turn left']);
      expect(engine.isSpeaking, isFalse);
    });

    test('a voice change waits for the cue being said', () async {
      _mockChannel();
      final engine = _Engine();
      final speaker = FlutterTtsSpeaker(
        platform: TargetPlatform.iOS,
        engine: engine,
      );

      final ahead = speaker.speak('In 200 metres, turn left');
      await pumpEventQueue();
      final chosen = speaker.selectVoice(null);
      final next = speaker.speak('Turn left');
      await pumpEventQueue();
      expect(engine.spoken, ['In 200 metres, turn left']);

      engine.finish();
      await pumpEventQueue();
      await chosen;
      // The voice is in place before the cue that follows it goes out.
      expect(engine.spoken, ['In 200 metres, turn left', 'Turn left']);

      engine.finish();
      await Future.wait([ahead, next]);
    });
  });
}
