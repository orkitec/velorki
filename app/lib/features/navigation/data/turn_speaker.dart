import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../domain/voice_option.dart';

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

  /// The voices the phone has for the language the cues are in, best first.
  Future<List<VoiceOption>> voices();

  /// Says the turns in the voice with [id] from now on, or in the phone's
  /// own voice for the language when [id] is `null` or no longer installed.
  Future<void> selectVoice(String? id);

  /// Releases the engine.
  Future<void> dispose();
}

/// The real speaker, on top of the `flutter_tts` plugin.
///
/// The engine is set up on the first cue rather than in the constructor: a
/// rider who never starts a guided ride never touches text-to-speech, and on
/// Android the first call is what starts the engine's service.
///
/// Cues are said one after the other. The plugin keeps a single result slot
/// per `speak` on iOS, so two calls in flight at once leave the first
/// hanging, and a cue that arrives while the engine is still being set up
/// would go out with the wrong voice and audio session; a chain of futures
/// keeps every call behind the one before it.
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
  Future<void> _queue = Future<void>.value();

  @override
  Future<void> speak(String text) {
    if (text.isEmpty || _broken) return Future<void>.value();
    return _queue = _queue.then((_) => _speakNow(text));
  }

  Future<void> _speakNow(String text) async {
    await _configure();
    if (_broken) return;
    try {
      await _tts.speak(text);
    } catch (error) {
      _fail(error);
    }
  }

  @override
  Future<List<VoiceOption>> voices() async {
    if (_broken) return const <VoiceOption>[];
    await _configure();
    if (_broken) return const <VoiceOption>[];
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const <VoiceOption>[];
      final language = VoiceOption(
        id: '',
        name: '',
        localeTag: localeTag,
      ).language;
      return raw
          .whereType<Map<Object?, Object?>>()
          .map(VoiceOption.fromPlatform)
          .whereType<VoiceOption>()
          .where((voice) => voice.language == language)
          .toList()
        ..sort(VoiceOption.compare);
    } catch (error) {
      _fail(error);
      return const <VoiceOption>[];
    }
  }

  @override
  Future<void> selectVoice(String? id) {
    if (_broken) return Future<void>.value();
    // Behind the queue, so a cue being said finishes in the voice it started.
    return _queue = _queue.then((_) => _selectNow(id));
  }

  Future<void> _selectNow(String? id) async {
    await _configure();
    if (_broken) return;
    try {
      VoiceOption? voice;
      if (id != null) {
        for (final option in await voices()) {
          if (option.id == id) voice = option;
        }
      }
      if (voice == null) {
        await _tts.clearVoice();
        await _tts.setLanguage(localeTag);
      } else {
        await _tts.setVoice(voice.platformVoice);
      }
    } catch (error) {
      _fail(error);
    }
  }

  @override
  Future<void> stop() async {
    if (!_configured || _broken) return;
    // Whatever is waiting its turn is dropped with what is being said.
    _queue = Future<void>.value();
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
/// the engine is configured once rather than on every guided ride. It speaks
/// the language the cues are written in: the phone's, when the app has that
/// translation, otherwise English, which is what the cue text falls back to.
final turnSpeakerProvider = Provider<TurnSpeaker>((ref) {
  final speaker = FlutterTtsSpeaker(localeTag: cueLocaleTag());
  ref.onDispose(speaker.dispose);
  return speaker;
});

/// The BCP-47 tag the cues are spoken in. See [turnSpeakerProvider].
String cueLocaleTag() {
  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  final translated = AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );
  return translated ? locale.toLanguageTag() : 'en-US';
}

/// The voices the phone offers for the cues, best first. Auto-disposed so a
/// voice installed while the app runs shows up the next time the list is
/// opened.
final availableVoicesProvider = FutureProvider.autoDispose<List<VoiceOption>>(
  (ref) => ref.watch(turnSpeakerProvider).voices(),
);
