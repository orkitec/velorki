import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../settings/data/language_controller.dart';
import '../domain/voice_option.dart';
import '../domain/voice_ranking.dart';

/// Says a turn out loud.
///
/// An interface so the feature can be driven by a fake in tests: the real
/// implementation talks to the phone's text-to-speech engine, which no test
/// has.
abstract class TurnSpeaker {
  /// Says [text], queued behind anything already being said.
  ///
  /// The future is done when the cue has been said, or dropped. An [urgent]
  /// cue — "turn now", the one the rider has seconds to act on — does not
  /// wait: whatever is being said is cut off and the cues still queued are
  /// dropped, because they were worked out before the turn that is happening
  /// now.
  Future<void> speak(String text, {bool urgent = false});

  /// Drops whatever is being said and whatever is queued.
  Future<void> stop();

  /// The voices the phone has for the language the cues are in, best first.
  Future<List<VoiceOption>> voices();

  /// Says the turns in the voice with [id] from now on, or in the best
  /// voice the phone has for the language when [id] is `null` or no longer
  /// installed; see [defaultVoice].
  Future<void> selectVoice(String? id);

  /// The voice "System default" resolves to right now, or `null` when the
  /// choice is left to the engine. See [bestVoiceFor].
  Future<VoiceOption?> defaultVoice();

  /// Releases the engine.
  Future<void> dispose();
}

/// The real speaker, on top of the `flutter_tts` plugin.
///
/// The engine is set up on the first cue rather than in the constructor: a
/// rider who never starts a guided ride never touches text-to-speech, and on
/// Android the first call is what starts the engine's service.
///
/// Cues are said one after the other, out of a queue this class keeps itself.
/// The plugin holds a single result slot per `speak` on iOS, so two calls in
/// flight at once leave the first hanging, and handing the engine a second
/// cue while it is still speaking is what cuts a cue off mid-word. Only an
/// urgent cue jumps that queue, and then the engine is stopped first.
///
/// Nothing here throws. A phone with no engine installed (or with the voice
/// data missing) makes the plugin fail on the platform channel; the rider
/// still has the banner, so the failure is logged once and then ignored.
class FlutterTtsSpeaker implements TurnSpeaker {
  /// Creates a speaker that talks in [localeTag], e.g. `en-GB`.
  FlutterTtsSpeaker({
    this.localeTag = 'en-US',
    FlutterTts? engine,
    TargetPlatform? platform,
    DateTime Function()? clock,
  }) : _tts = engine ?? FlutterTts(),
       _platform = platform ?? defaultTargetPlatform,
       _now = clock ?? DateTime.now;

  /// How long a cue may wait its turn before it is dropped unsaid.
  ///
  /// A distance callout is about where the rider was when it was worked out.
  /// Six seconds on is 30 m at 20 km/h: far enough for "in 200 metres" to be
  /// wrong, and long enough that a cue queued behind an ordinary one is still
  /// said.
  static const Duration staleAfter = Duration(seconds: 6);

  /// The BCP-47 tag the cues are spoken in.
  final String localeTag;

  /// Which set of engine quirks to work around; injected so tests can play
  /// either phone on the desktop.
  final TargetPlatform _platform;

  /// Reads the clock cues are aged by; injected so tests can move it.
  final DateTime Function() _now;

  bool get _isAndroid => !kIsWeb && _platform == TargetPlatform.android;

  bool get _isIOS => !kIsWeb && _platform == TargetPlatform.iOS;

  final FlutterTts _tts;
  bool _configured = false;
  bool _broken = false;
  String? _defaultKey;
  VoiceOption? _defaultVoice;

  /// What is waiting to be said, oldest first.
  final List<_Job> _waiting = <_Job>[];

  /// Completes when the utterance in flight is cut short. On iOS a stopped
  /// `speak` never returns — the plugin hands the result back from
  /// `didFinish`, and a cancelled utterance only reports `didCancel` — so a
  /// cut is what ends the wait, not the plugin's own future.
  Completer<void>? _cut;

  bool _working = false;

  @override
  Future<void> speak(String text, {bool urgent = false}) {
    if (text.isEmpty || _broken) return Future<void>.value();
    if (urgent) {
      // A cue worked out before the turn the rider is taking right now is out
      // of date by definition, so the queue goes with the utterance in
      // flight.
      for (final job in _waiting) {
        job.finish();
      }
      _waiting.clear();
    }
    final job = _SpeakJob(text, urgent: urgent, at: _now());
    _waiting.add(job);
    if (urgent) _interrupt();
    unawaited(_work());
    return job.future;
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
    // Behind the queue, so a cue being said finishes in the voice it started
    // in. A voice change is never urgent and never goes stale.
    final job = _VoiceJob(id, at: _now());
    _waiting.add(job);
    unawaited(_work());
    return job.future;
  }

  Future<void> _selectNow(String? id) async {
    await _configure();
    if (_broken) return;
    try {
      VoiceOption? voice;
      if (id != null) {
        // A voice the rider chose is used as it is: it is never second-
        // guessed by the ranking, however thin it sounds.
        for (final option in await voices()) {
          if (option.id == id) voice = option;
        }
      }
      if (id == null || voice == null) {
        // Nothing chosen, or the chosen voice has been deleted. The engine's
        // own default is whatever was installed first, compact included, so
        // a rider who never opened the picker still gets the best voice the
        // phone actually has.
        voice = await defaultVoice();
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
  Future<VoiceOption?> defaultVoice() async {
    final installed = await voices();
    // The ranking is worked out once per list of installed voices — the
    // locale is fixed for the life of a speaker. Asking the engine is what
    // spots a voice downloaded while the app runs; the answer only changes
    // when that list does.
    final key = installed.map((voice) => voice.id).join('\u0000');
    if (key == _defaultKey) return _defaultVoice;
    _defaultKey = key;
    return _defaultVoice = bestVoiceFor(installed, localeTag);
  }

  @override
  Future<void> stop() async {
    // Whatever is waiting its turn is dropped with what is being said.
    for (final job in _waiting) {
      job.finish();
    }
    _waiting.clear();
    await _stopEngine();
    _release();
  }

  @override
  Future<void> dispose() async {
    await stop();
  }

  /// Works through [_waiting] until it runs out, one job at a time: the
  /// engine is handed the next cue only once the one before it is done.
  Future<void> _work() async {
    if (_working) return;
    _working = true;
    try {
      while (_waiting.isNotEmpty) {
        final job = _waiting.removeAt(0);
        if (job is _SpeakJob) {
          if (!job.urgent && _now().difference(job.at) > staleAfter) {
            // A distance callout that waited this long is about a stretch of
            // road the rider has already ridden.
            job.finish();
            continue;
          }
          await _say(job);
        } else if (job is _VoiceJob) {
          await _selectNow(job.id);
          job.finish();
        }
      }
    } finally {
      _working = false;
    }
  }

  Future<void> _say(_SpeakJob job) async {
    await _configure();
    if (_broken) {
      job.finish();
      return;
    }
    final cut = _cut = Completer<void>();
    // `_fail` swallows the error, so the cue's own future is a plain
    // completion whichever way the utterance ends.
    final said = _tts.speak(job.text).then<void>((_) {}, onError: _fail);
    await Future.any<void>(<Future<void>>[said, cut.future]);
    if (identical(_cut, cut)) _cut = null;
    job.finish();
  }

  /// Stops the utterance in flight for an urgent cue, and lets [_work] move
  /// on once the engine has actually gone quiet.
  void _interrupt() {
    final cut = _cut;
    if (cut == null) return;
    _cut = null;
    unawaited(
      _stopEngine().whenComplete(() {
        if (!cut.isCompleted) cut.complete();
      }),
    );
  }

  /// Ends the wait on the utterance in flight without stopping the engine
  /// again.
  void _release() {
    final cut = _cut;
    _cut = null;
    if (cut != null && !cut.isCompleted) cut.complete();
  }

  Future<void> _stopEngine() async {
    if (!_configured || _broken) return;
    try {
      await _tts.stop();
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    try {
      await _tts.setLanguage(localeTag);
      // Wait for a cue to finish before the next one is handed over, so the
      // queue above actually holds.
      await _tts.awaitSpeakCompletion(true);
      // A cue carries the whole instruction in three or four words; there is
      // nothing to gain from saying it quietly.
      await _tts.setVolume(1);
      if (_isAndroid) {
        // QUEUE_ADD: a second cue waits instead of cutting the first one off
        // mid-word.
        await _tts.setQueueMode(1);
        // Tells Android this is navigation guidance, so music ducks rather
        // than stopping and the cue follows the car/bike audio route.
        await _tts.setAudioAttributesForNavigation();
      }
      if (_isIOS) {
        // The plugin's own default of 0.5 drawls on iOS, where the rate is
        // an AVSpeechUtterance rate rather than a multiplier; a touch above
        // it reads a cue at the pace a rider expects. Android's default is
        // already right, and changing it there makes the cue race.
        await _tts.setSpeechRate(0.52);
        // Hands the plugin the app's shared AVAudioSession and lets it
        // activate the session around an utterance, which is what makes
        // ducking work at all.
        await _tts.setSharedInstance(true);
        // `playback` is the category that keeps speaking with the screen
        // locked and the Ring/Silent switch on silent, which is why
        // `UIBackgroundModes` in Info.plist has `audio` in it. The options
        // are the set Apple names for turn-by-turn guidance: mix with (and
        // duck) music rather than being silenced by it, and pause a podcast
        // or an audiobook for the few seconds a cue takes rather than talking
        // over the top of it. `voicePrompt` tells the system this is spoken
        // guidance, not media.
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          const [
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions
                .interruptSpokenAudioAndMixWithOthers,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        );
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

/// Something the speaker has been asked to do, waiting its turn.
abstract class _Job {
  _Job({required this.at});

  /// When it was asked for; what [FlutterTtsSpeaker.staleAfter] measures.
  final DateTime at;

  final Completer<void> _done = Completer<void>();

  /// Done when the job has been carried out, or dropped.
  Future<void> get future => _done.future;

  void finish() {
    if (!_done.isCompleted) _done.complete();
  }
}

class _SpeakJob extends _Job {
  _SpeakJob(this.text, {required this.urgent, required super.at});

  final String text;
  final bool urgent;
}

class _VoiceJob extends _Job {
  _VoiceJob(this.id, {required super.at});

  final String? id;
}

/// The speaker the navigation feature uses.
///
/// Kept alive for the whole app (a plain [Provider] is not auto-disposed), so
/// the engine is configured once rather than on every guided ride. It speaks
/// the language the cues are written in: the one the app is shown in, when
/// the app has that translation, otherwise English, which is what the cue
/// text falls back to. Picking another language in Settings rebuilds the
/// speaker, so the next ride is spoken in it.
final turnSpeakerProvider = Provider<TurnSpeaker>((ref) {
  final speaker = FlutterTtsSpeaker(
    localeTag: cueLocaleTag(ref.watch(appLocaleProvider)),
  );
  ref.onDispose(speaker.dispose);
  return speaker;
});

/// The BCP-47 tag the cues are spoken in. See [turnSpeakerProvider].
///
/// [appLocale] is what the rider picked under Settings → Language, or `null`
/// while the app follows the phone. A picked language keeps the phone's
/// region when they speak the same language, so a German phone still asks
/// for `de-DE` rather than a bare `de`. English picked on a phone that is not
/// English has no region to borrow, and some engines refuse a bare `en`, so it
/// gets the same `en-US` as the untranslated fallback above.
String cueLocaleTag([Locale? appLocale]) {
  final system = WidgetsBinding.instance.platformDispatcher.locale;
  final wanted = appLocale ?? system;
  final translated = AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == wanted.languageCode,
  );
  if (!translated) return 'en-US';
  if (wanted.countryCode == null &&
      wanted.languageCode == system.languageCode) {
    return system.toLanguageTag();
  }
  if (wanted.countryCode == null && wanted.languageCode == 'en') {
    return 'en-US';
  }
  return wanted.toLanguageTag();
}

/// The voices the phone offers for the cues, best first. Auto-disposed so a
/// voice installed while the app runs shows up the next time the list is
/// opened.
final availableVoicesProvider = FutureProvider.autoDispose<List<VoiceOption>>(
  (ref) => ref.watch(turnSpeakerProvider).voices(),
);
