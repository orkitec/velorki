import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../application/turn_announcer.dart';
import '../domain/voice_option.dart';

const String _prefsTurns = 'navigation.turns';
const String _prefsVoice = 'navigation.voice';
const String _prefsReroute = 'navigation.reroute';
const String _prefsLead = 'navigation.leadSeconds';
const String _prefsVoiceId = 'navigation.voiceId';

/// The range the turn announcement lead can be set to, in seconds.
const int minLeadSeconds = 5;

/// See [minLeadSeconds].
const int maxLeadSeconds = 30;

/// Whether turn-by-turn guidance is shown and spoken while recording, how far
/// ahead a turn is announced, and whether a new way back onto the route is
/// planned when the rider leaves it.
class NavigationSettings {
  /// Creates the settings. All three switches are on and the lead is
  /// [defaultLeadSeconds] unless the rider says otherwise.
  const NavigationSettings({
    this.turns = true,
    this.voice = true,
    this.reroute = true,
    this.leadSeconds = defaultLeadSeconds,
    this.voiceId,
  });

  /// Whether the next turn is shown at all.
  final bool turns;

  /// Whether the turns are spoken. Only has an effect while [turns] is on.
  final bool voice;

  /// Whether leaving the route asks the router for a way back onto it. Only
  /// has an effect while [turns] is on.
  final bool reroute;

  /// How many seconds of travel before a turn it is announced, at the
  /// rider's current speed.
  final int leadSeconds;

  /// The voice the turns are said in, by its [VoiceOption.id]; `null` is
  /// the phone's own voice for the language.
  final String? voiceId;

  /// A copy with the named fields replaced. [voiceId] is only replaced when
  /// [setVoiceId] is true, so that it can be set back to `null`.
  NavigationSettings copyWith({
    bool? turns,
    bool? voice,
    bool? reroute,
    int? leadSeconds,
    String? voiceId,
    bool setVoiceId = false,
  }) => NavigationSettings(
    turns: turns ?? this.turns,
    voice: voice ?? this.voice,
    reroute: reroute ?? this.reroute,
    leadSeconds: leadSeconds ?? this.leadSeconds,
    voiceId: setVoiceId ? voiceId : this.voiceId,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavigationSettings &&
          other.turns == turns &&
          other.voice == voice &&
          other.reroute == reroute &&
          other.leadSeconds == leadSeconds &&
          other.voiceId == voiceId;

  @override
  int get hashCode => Object.hash(turns, voice, reroute, leadSeconds, voiceId);

  @override
  String toString() =>
      'NavigationSettings(turns: $turns, voice: $voice, reroute: $reroute, '
      'leadSeconds: $leadSeconds, voiceId: $voiceId)';
}

/// The navigation settings, kept in shared_preferences.
///
/// A key is removed rather than written when a setting goes back to its
/// default, so the stored preferences only ever hold the choices the rider
/// actually made.
class NavigationSettingsController extends Notifier<NavigationSettings> {
  @override
  NavigationSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return NavigationSettings(
      turns: prefs.getBool(_prefsTurns) ?? true,
      voice: prefs.getBool(_prefsVoice) ?? true,
      reroute: prefs.getBool(_prefsReroute) ?? true,
      leadSeconds: (prefs.getInt(_prefsLead) ?? defaultLeadSeconds).clamp(
        minLeadSeconds,
        maxLeadSeconds,
      ),
      voiceId: prefs.getString(_prefsVoiceId),
    );
  }

  /// Chooses the voice the turns are said in; `null` for the phone's own.
  Future<void> setVoiceId(String? id) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (id == null) {
      await prefs.remove(_prefsVoiceId);
    } else {
      await prefs.setString(_prefsVoiceId, id);
    }
    state = state.copyWith(voiceId: id, setVoiceId: true);
  }

  /// Sets how many seconds before a turn it is announced.
  Future<void> setLeadSeconds(int value) async {
    final seconds = value.clamp(minLeadSeconds, maxLeadSeconds);
    final prefs = ref.read(sharedPreferencesProvider);
    if (seconds == defaultLeadSeconds) {
      await prefs.remove(_prefsLead);
    } else {
      await prefs.setInt(_prefsLead, seconds);
    }
    state = state.copyWith(leadSeconds: seconds);
  }

  /// Shows or hides the turn directions.
  Future<void> setTurns(bool value) async {
    await _write(_prefsTurns, value);
    state = state.copyWith(turns: value);
  }

  /// Switches the voice on or off.
  Future<void> setVoice(bool value) async {
    await _write(_prefsVoice, value);
    state = state.copyWith(voice: value);
  }

  /// Switches re-routing on or off.
  Future<void> setReroute(bool value) async {
    await _write(_prefsReroute, value);
    state = state.copyWith(reroute: value);
  }

  Future<void> _write(String key, bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    // On is the default, so it is stored as "no key at all".
    if (value) {
      await prefs.remove(key);
    } else {
      await prefs.setBool(key, value);
    }
  }
}

/// The navigation settings.
final navigationSettingsProvider =
    NotifierProvider<NavigationSettingsController, NavigationSettings>(
      NavigationSettingsController.new,
    );
