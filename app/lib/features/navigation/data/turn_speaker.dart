import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Says a turn out loud.
///
/// An interface so the feature can be driven by a fake in tests: the real
/// implementation talks to the phone's text-to-speech engine, which no test
/// has.
abstract class TurnSpeaker {
  /// Says [text], queued behind anything already being said.
  Future<void> speak(String text);

  /// Drops whatever is being said and whatever is queued.
  Future<void> stop();

  /// Releases the engine.
  Future<void> dispose();
}

/// The real speaker, on top of the `flutter_tts` plugin.
///
/// The engine is set up on the first cue rather than in the constructor: a
/// rider who never starts a guided ride never touches text-to-speech, and on
/// Android the first call is what starts the engine's service.
///
/// Nothing here throws. A phone with no engine installed (or with the voice
/// data missing) makes the plugin fail on the platform channel; the rider
/// still has the banner, so the failure is logged once and then ignored.
class FlutterTtsSpeaker implements TurnSpeaker {
  /// Creates a speaker that talks in [localeTag], e.g. `en-GB`.
  FlutterTtsSpeaker({this.localeTag = 'en-US', FlutterTts? engine})
    : _tts = engine ?? FlutterTts();

  /// The BCP-47 tag the cues are spoken in.
  final String localeTag;

  final FlutterTts _tts;
  bool _configured = false;
  bool _broken = false;

  @override
  Future<void> speak(String text) async {
    if (text.isEmpty || _broken) return;
    await _configure();
    if (_broken) return;
    try {
      await _tts.speak(text);
    } catch (error) {
      _fail(error);
    }
  }

  @override
  Future<void> stop() async {
    if (!_configured || _broken) return;
    try {
      await _tts.stop();
    } catch (error) {
      _fail(error);
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
  }

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    try {
      await _tts.setLanguage(localeTag);
      // Wait for a cue to finish before the next one is handed over, so the
      // queue below actually holds.
      await _tts.awaitSpeakCompletion(true);
      if (!kIsWeb && Platform.isAndroid) {
        // QUEUE_ADD: a second cue waits instead of cutting the first one off
        // mid-word.
        await _tts.setQueueMode(1);
        // Tells Android this is navigation guidance, so music ducks rather
        // than stopping and the cue follows the car/bike audio route.
        await _tts.setAudioAttributesForNavigation();
      }
      if (!kIsWeb && Platform.isIOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions
              .interruptSpokenAudioAndMixWithOthers,
        ], IosTextToSpeechAudioMode.voicePrompt);
      }
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    if (_broken) return;
    _broken = true;
    debugPrint('Voice directions are off: text-to-speech failed ($error)');
  }
}

/// The speaker the navigation feature uses.
///
/// Kept alive for the whole app (a plain [Provider] is not auto-disposed), so
/// the engine is configured once rather than on every guided ride.
final turnSpeakerProvider = Provider<TurnSpeaker>((ref) {
  final speaker = FlutterTtsSpeaker();
  ref.onDispose(speaker.dispose);
  return speaker;
});
