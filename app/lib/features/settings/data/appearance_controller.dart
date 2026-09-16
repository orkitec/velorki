import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';
import '../../../app/theme.dart';

part 'appearance_controller.g.dart';

const String _prefsThemeMode = 'appearance.mode';
const String _prefsAccent = 'appearance.accent';
const String _prefsMapLook = 'appearance.map';
const String _prefsOverlayDark = 'appearance.overlay_dark';

/// Which map style is drawn, independently of the app theme.
enum MapLook {
  /// The light map in light mode, the night map in dark mode.
  auto,

  /// Always the light map.
  light,

  /// Always the blue-grey night map.
  night,

  /// Always the black map.
  black;

  /// The look named [name], or [auto] when the name is unknown.
  static MapLook fromName(String? name) =>
      MapLook.values.firstWhere((l) => l.name == name, orElse: () => auto);
}

/// What the CyclOSM cycling overlay does on the night and the black map.
///
/// The overlay is one set of raster tiles drawn for a light background, so on
/// a dark map it has to be treated. Riders disagree about how: inverting reads
/// as a dark map but turns the colours around, dimming keeps the colours as
/// CyclOSM drew them. The light map is never touched.
enum OverlayDarkMode {
  /// Inverted and hue-corrected, so the overlay reads as part of a dark map.
  inverted,

  /// Darkened and desaturated, keeping CyclOSM's own colours.
  dimmed,

  /// Drawn as it comes, bright on a dark map.
  unchanged;

  /// The mode named [name], or [inverted] when the name is unknown.
  static OverlayDarkMode fromName(String? name) => OverlayDarkMode.values
      .firstWhere((m) => m.name == name, orElse: () => inverted);
}

/// What the rider chose under Settings → Appearance.
@immutable
class Appearance {
  /// Creates the choice.
  const Appearance({
    this.mode = ThemeMode.system,
    this.accent = AccentPreset.volt,
    this.mapLook = MapLook.auto,
    this.overlayDark = OverlayDarkMode.inverted,
  });

  /// Light, dark or whatever the system says.
  final ThemeMode mode;

  /// The accent colour.
  final AccentPreset accent;

  /// The map style.
  final MapLook mapLook;

  /// How the cycling overlay is treated on the dark map styles.
  final OverlayDarkMode overlayDark;

  /// A copy with the given fields replaced.
  Appearance copyWith({
    ThemeMode? mode,
    AccentPreset? accent,
    MapLook? mapLook,
    OverlayDarkMode? overlayDark,
  }) => Appearance(
    mode: mode ?? this.mode,
    accent: accent ?? this.accent,
    mapLook: mapLook ?? this.mapLook,
    overlayDark: overlayDark ?? this.overlayDark,
  );

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.mode == mode &&
      other.accent == accent &&
      other.mapLook == mapLook &&
      other.overlayDark == overlayDark;

  @override
  int get hashCode => Object.hash(mode, accent, mapLook, overlayDark);
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
      mapLook: MapLook.fromName(prefs.getString(_prefsMapLook)),
      overlayDark: OverlayDarkMode.fromName(prefs.getString(_prefsOverlayDark)),
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

  /// Picks the map style.
  Future<void> setMapLook(MapLook look) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (look == MapLook.auto) {
      await prefs.remove(_prefsMapLook);
    } else {
      await prefs.setString(_prefsMapLook, look.name);
    }
    state = state.copyWith(mapLook: look);
  }

  /// Picks how the cycling overlay is treated on the dark maps.
  Future<void> setOverlayDark(OverlayDarkMode mode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (mode == OverlayDarkMode.inverted) {
      await prefs.remove(_prefsOverlayDark);
    } else {
      await prefs.setString(_prefsOverlayDark, mode.name);
    }
    state = state.copyWith(overlayDark: mode);
  }
}
