import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';
import '../../../app/theme.dart';

part 'appearance_controller.g.dart';

const String _prefsThemeMode = 'appearance.mode';
const String _prefsAccent = 'appearance.accent';

/// What the rider chose under Settings → Appearance.
@immutable
class Appearance {
  /// Creates the choice.
  const Appearance({
    this.mode = ThemeMode.system,
    this.accent = AccentPreset.volt,
  });

  /// Light, dark or whatever the system says.
  final ThemeMode mode;

  /// The accent colour.
  final AccentPreset accent;

  /// A copy with the given fields replaced.
  Appearance copyWith({ThemeMode? mode, AccentPreset? accent}) =>
      Appearance(mode: mode ?? this.mode, accent: accent ?? this.accent);

  @override
  bool operator ==(Object other) =>
      other is Appearance && other.mode == mode && other.accent == accent;

  @override
  int get hashCode => Object.hash(mode, accent);
}

/// Settings → Appearance, persisted in shared_preferences.
@Riverpod(keepAlive: true)
class AppearanceSetting extends _$AppearanceSetting {
  @override
  Appearance build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final modeName = prefs.getString(_prefsThemeMode);
    return Appearance(
      mode: ThemeMode.values.firstWhere(
        (mode) => mode.name == modeName,
        orElse: () => ThemeMode.system,
      ),
      accent: AccentPreset.fromName(prefs.getString(_prefsAccent)),
    );
  }

  /// Switches between light, dark and system.
  Future<void> setMode(ThemeMode mode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (mode == ThemeMode.system) {
      await prefs.remove(_prefsThemeMode);
    } else {
      await prefs.setString(_prefsThemeMode, mode.name);
    }
    state = state.copyWith(mode: mode);
  }

  /// Picks the accent colour.
  Future<void> setAccent(AccentPreset accent) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (accent == AccentPreset.volt) {
      await prefs.remove(_prefsAccent);
    } else {
      await prefs.setString(_prefsAccent, accent.name);
    }
    state = state.copyWith(accent: accent);
  }
}
