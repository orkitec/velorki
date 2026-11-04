import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speak/speak.dart' as tts;

import '../../../l10n/generated/app_localizations.dart';
import '../../settings/data/language_controller.dart';
import '../domain/voice_option.dart';
import '../domain/voice_ranking.dart';
import 'navigation_settings.dart';

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

  /// Called when the cues start — guidance running, voice on, not muted —
  /// and matched by [endGuidance] when any of that stops being true.
  ///
  /// The phone's audio is not held in between: it is claimed for each cue
  /// and given back right after, so music comes back up and a paused podcast
  /// carries on between turns. See [SpeakTurnSpeaker].
  Future<void> beginGuidance();

  /// Stops the speaker; does nothing when no ride is being guided.
  Future<void> endGuidance();

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

/// Builds the `speak` speaker for an audio configuration; replaced in tests,
/// which have no text-to-speech engine.
typedef SpeakFactory = tts.Speak Function(tts.SpeakAudio audio);

/// The real speaker, on top of the `speak` package.
///
/// `speak` does the queueing (one cue at a time, an urgent one cutting in,
/// a cue that waited too long dropped), and claims the phone's audio only
/// while it speaks: right before a cue, with a short silent lead-in so a
/// Bluetooth headset is awake by the first word, and given back a moment
/// after the last, so music comes back up and a podcast resumes. On iOS that
/// is the `playback` category in `voicePrompt` mode; on Android navigation
/// guidance with transient audio focus.
///
/// Nothing touches the engine until the first cue (or the voice list), so a
/// rider who never starts a guided ride never starts text-to-speech.
///
/// Nothing here throws. A phone with no engine (or no voice data) is logged
/// once and then left alone; the rider still has the banner.
class SpeakTurnSpeaker implements TurnSpeaker {
  /// Creates a speaker that talks in [localeTag], e.g. `en-GB`, in the voice
  /// with [voiceId] (`null` for the best one), with other audio treated as
  /// [otherAudio] says.
  SpeakTurnSpeaker({
    this.localeTag = 'en-US',
    this._voiceId,
    InstructionAudio otherAudio = InstructionAudio.pausePodcasts,
    SpeakFactory? create,
    TargetPlatform? platform,
  }) : _speak = (create ?? _engine)(audioFor(otherAudio)),
       _platform = platform ?? defaultTargetPlatform {
    _speak
      ..language = localeTag
      ..rate = rateFor(_platform);
  }

  /// How long a cue may wait its turn before it is dropped unsaid.
  ///
  /// A distance callout is about where the rider was when it was worked out.
  /// Six seconds on is 30 m at 20 km/h: far enough for "in 200 metres" to be
  /// wrong, and long enough that a cue queued behind an ordinary one is still
  /// said.
  static const Duration staleAfter = Duration(seconds: 6);

  /// What [InstructionAudio] means for the phone's audio.
  static tts.SpeakAudio audioFor(InstructionAudio otherAudio) =>
      switch (otherAudio) {
        // Music lowered, a podcast paused and resumed after the cue.
        InstructionAudio.pausePodcasts => tts.SpeakAudio.navigation,
        InstructionAudio.lowerVolume => tts.SpeakAudio.navigation.copyWith(
          otherAudio: tts.OtherAudio.duck,
        ),
      }.copyWith(leadIn: leadIn);

  /// Silence before a cue that starts after a quiet stretch: a Bluetooth
  /// headset that has let its A2DP link go idle needs about a second to
  /// come back, and without it the first syllables are lost. 1.5 s is what
  /// the rides of September 2026 settled on.
  static const Duration leadIn = Duration(milliseconds: 1500);

  /// The speaking rate on [platform], relative to the platform's normal.
  ///
  /// iOS's everyday rate drawls for a cue of three or four words; a touch
  /// above it (0.52 where AVFoundation's normal is 0.5) reads it at the
  /// pace a rider expects. Android's normal is already right.
  static double rateFor(TargetPlatform platform) =>
      !kIsWeb && platform == TargetPlatform.iOS ? 1.04 : 1;

  /// The BCP-47 tag the cues are spoken in.
  final String localeTag;

  static tts.Speak _engine(tts.SpeakAudio audio) => tts.Speak(audio: audio);

  final tts.Speak _speak;
  final TargetPlatform _platform;

  /// The voice the rider chose, by [VoiceOption.id]; applied before the next
  /// cue.
  String? _voiceId;

  /// Applies [_voiceId]; every cue waits for it, so the cues stay in order.
  Future<void>? _voiceApplied;

  /// The engine's voices behind the last list handed out, by
  /// [VoiceOption.id].
  final Map<String, tts.Voice> _engineVoices = {};

  bool _broken = false;
  String? _defaultKey;
  VoiceOption? _defaultVoice;

  @override
  Future<void> speak(String text, {bool urgent = false}) async {
    if (text.isEmpty || _broken) return;
    await (_voiceApplied ??= _applyVoice());
    if (_broken) return;
    try {
      // Interrupted and expired cues simply end: neither is a failure.
      await _speak(
        text,
        queue: urgent ? tts.SpeakQueue.interrupt : tts.SpeakQueue.append,
        expireAfter: urgent ? null : staleAfter,
      );
    } on tts.SpeakException catch (error) {
      _fail(error, fatal: error.error == tts.SpeakError.engineUnavailable);
    } on UnsupportedError catch (error) {
      _fail(error, fatal: true);
    }
  }

  @override
  Future<void> selectVoice(String? id) {
    _voiceId = id;
    return _voiceApplied = _applyVoice();
  }

  Future<void> _applyVoice() async {
    if (_broken) return;
    final id = _voiceId;
    VoiceOption? chosen;
    if (id != null) {
      // A voice the rider chose is used as it is: it is never second-
      // guessed by the ranking, however thin it sounds.
      for (final option in await voices()) {
        if (option.id == id) chosen = option;
      }
    }
    // Nothing chosen, or the chosen voice has been deleted: the best voice
    // the phone actually has, or the engine's own for the language.
    chosen ??= await defaultVoice();
    _speak.voice = chosen == null ? null : _engineVoices[chosen.id];
  }

  @override
  Future<List<VoiceOption>> voices() async {
    if (_broken) return const <VoiceOption>[];
    try {
      final language = VoiceOption(
        id: '',
        name: '',
        localeTag: localeTag,
      ).language;
      final options = <VoiceOption>[];
      _engineVoices.clear();
      for (final voice in await _speak.voices(language: language)) {
        if (!voice.isInstalled) continue;
        final option = voiceOptionFrom(voice);
        if (option.language != language) continue;
        _engineVoices[option.id] = voice;
        options.add(option);
      }
      return options..sort(VoiceOption.compare);
    } on Object catch (error) {
      _fail(error, fatal: true);
      return const <VoiceOption>[];
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
  Future<void> beginGuidance() async {}

  @override
  Future<void> endGuidance() => stop();

  @override
  Future<void> stop() => _speak.stop();

  @override
  Future<void> dispose() => _speak.dispose();

  void _fail(Object error, {required bool fatal}) {
    if (_broken) return;
    _broken = fatal;
    debugPrint(
      fatal
          ? 'Voice directions are off: text-to-speech failed ($error)'
          : 'A voice direction was not spoken ($error)',
    );
  }
}

/// [voice] as the rest of the app knows it.
///
/// The id is the one the rider's choice was stored by before `speak`: the
/// iOS identifier, or name and locale together on Android, where the engine
/// names a voice by its name alone.
VoiceOption voiceOptionFrom(tts.Voice voice) => VoiceOption(
  id: voice.id == voice.name ? '${voice.name}|${voice.language}' : voice.id,
  name: voice.name,
  localeTag: voice.language,
  gender: switch (voice.gender) {
    tts.VoiceGender.female => VoiceGender.female,
    tts.VoiceGender.male => VoiceGender.male,
    tts.VoiceGender.unknown => VoiceGender.unknown,
  },
  quality: switch (voice.quality) {
    tts.VoiceQuality.premium => VoiceQuality.premium,
    tts.VoiceQuality.enhanced => VoiceQuality.enhanced,
    tts.VoiceQuality.normal => VoiceQuality.normal,
    tts.VoiceQuality.low => VoiceQuality.low,
    tts.VoiceQuality.unknown => VoiceQuality.unknown,
  },
  needsNetwork:
      voice.requiresNetwork ||
      // Google's online voices only differ from the ones on the phone by
      // this suffix, and a ride has no guaranteed signal.
      voice.name.toLowerCase().endsWith('-network'),
);

/// The speaker the navigation feature uses.
///
/// Kept alive for the whole app (a plain [Provider] is not auto-disposed), so
/// the engine is started once rather than on every guided ride. It speaks
/// the language the cues are written in: the one the app is shown in, when
/// the app has that translation, otherwise English, which is what the cue
/// text falls back to. Picking another language, or another treatment of
/// other audio, in Settings rebuilds the speaker, so the next cue uses it.
final turnSpeakerProvider = Provider<TurnSpeaker>((ref) {
  final speaker = SpeakTurnSpeaker(
    create: ref.watch(speakFactoryProvider),
    localeTag: cueLocaleTag(ref.watch(appLocaleProvider)),
    otherAudio: ref.watch(
      navigationSettingsProvider.select((settings) => settings.otherAudio),
    ),
    voiceId: ref.read(navigationSettingsProvider).voiceId,
  );
  ref.onDispose(speaker.dispose);
  return speaker;
});

/// How the speaker builds its `speak` engine: the real one, or a fake in
/// tests, which have no text-to-speech engine to drive.
final speakFactoryProvider = Provider<SpeakFactory>(
  (ref) => SpeakTurnSpeaker._engine,
);

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
