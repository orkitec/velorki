import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../settings/data/appearance_controller.dart';
import '../application/recording_controller.dart';
import 'recording_settings.dart';

part 'battery_saver.g.dart';

/// Whether the ride running right now is being recorded in battery saver.
///
/// Everything the saver does to the screen hangs off this one flag, and it is
/// false again the moment the ride ends or the rider switches the saver off.
@Riverpod(keepAlive: true)
bool batterySaverActive(Ref ref) =>
    ref.watch(recordingSettingsProvider.select((s) => s.saver)) &&
    ref.watch(recordingControllerProvider.select((s) => s.isRecording));

/// The look a battery-saver ride forces on the app while it lasts.
@immutable
class AppearanceOverride {
  /// Creates the override.
  const AppearanceOverride({required this.mode, required this.mapLook});

  /// The theme mode to use instead of the rider's.
  final ThemeMode mode;

  /// The map style to use instead of the rider's.
  final MapLook mapLook;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppearanceOverride &&
          other.mode == mode &&
          other.mapLook == mapLook;

  @override
  int get hashCode => Object.hash(mode, mapLook);

  @override
  String toString() => 'AppearanceOverride(${mode.name}, map: ${mapLook.name})';
}

/// The dark theme and the black map a saver ride runs in, or `null` when the
/// rider's own choice stands.
///
/// An override rather than a write: on an OLED screen black pixels are pixels
/// that are off, which is the largest saving there is, but it is the ride's
/// doing and not the rider's. Nothing here touches the stored preferences, so
/// the app goes back to the look it had the second the ride ends.
@Riverpod(keepAlive: true)
AppearanceOverride? appearanceOverride(Ref ref) =>
    ref.watch(batterySaverActiveProvider)
    ? const AppearanceOverride(mode: ThemeMode.dark, mapLook: MapLook.black)
    : null;
