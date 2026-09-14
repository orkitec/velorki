import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';

const String _prefsTurns = 'navigation.turns';
const String _prefsVoice = 'navigation.voice';
const String _prefsReroute = 'navigation.reroute';

/// Whether turn-by-turn guidance is shown and spoken while recording, and
/// whether a new way back onto the route is planned when the rider leaves it.
class NavigationSettings {
  /// Creates the settings. All three are on unless the rider says otherwise.
  const NavigationSettings({
    this.turns = true,
    this.voice = true,
    this.reroute = true,
  });

  /// Whether the next turn is shown at all.
  final bool turns;

  /// Whether the turns are spoken. Only has an effect while [turns] is on.
  final bool voice;

  /// Whether leaving the route asks the router for a way back onto it. Only
  /// has an effect while [turns] is on.
  final bool reroute;

  /// A copy with the named fields replaced.
  NavigationSettings copyWith({bool? turns, bool? voice, bool? reroute}) =>
      NavigationSettings(
        turns: turns ?? this.turns,
        voice: voice ?? this.voice,
        reroute: reroute ?? this.reroute,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavigationSettings &&
          other.turns == turns &&
          other.voice == voice &&
          other.reroute == reroute;

  @override
  int get hashCode => Object.hash(turns, voice, reroute);

  @override
  String toString() =>
      'NavigationSettings(turns: $turns, voice: $voice, reroute: $reroute)';
}

/// The navigation settings, kept in shared_preferences.
///
/// All three default to on, and a key is removed rather than written when it
/// goes back to its default, so the stored preferences only ever hold the
/// choices the rider actually made.
class NavigationSettingsController extends Notifier<NavigationSettings> {
  @override
  NavigationSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return NavigationSettings(
      turns: prefs.getBool(_prefsTurns) ?? true,
      voice: prefs.getBool(_prefsVoice) ?? true,
      reroute: prefs.getBool(_prefsReroute) ?? true,
    );
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
