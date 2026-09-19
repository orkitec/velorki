import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';

const String _prefsHealth = 'sensors.health';
const String _prefsHealthWrite = 'sensors.health.write';
const String _prefsWatch = 'sensors.watch';

/// Whether Velorki talks to the platform's health store at all, whether
/// finished rides are saved there as workouts, and whether the rider's watch
/// is part of the ride.
class SensorSettings {
  /// Creates the settings. Health and the watch are off until the rider
  /// switches them on; once Health is on, rides are saved unless they say
  /// otherwise.
  const SensorSettings({
    this.health = false,
    this.healthWrite = true,
    this.watch = false,
  });

  /// Nothing is switched on: no permission has been asked for, nothing reads
  /// or writes the health store, and no watch is spoken to.
  static const SensorSettings off = SensorSettings();

  /// Whether heart rate is read from Apple Health or Health Connect.
  final bool health;

  /// Whether a finished ride is written back as a cycling workout. Only has
  /// an effect while [health] is on.
  final bool healthWrite;

  /// Whether the paired Apple Watch measures and steers the ride.
  final bool watch;

  /// A copy with the named fields replaced.
  SensorSettings copyWith({bool? health, bool? healthWrite, bool? watch}) =>
      SensorSettings(
        health: health ?? this.health,
        healthWrite: healthWrite ?? this.healthWrite,
        watch: watch ?? this.watch,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorSettings &&
          other.health == health &&
          other.healthWrite == healthWrite &&
          other.watch == watch;

  @override
  int get hashCode => Object.hash(health, healthWrite, watch);

  @override
  String toString() =>
      'SensorSettings(health: $health, healthWrite: $healthWrite, '
      'watch: $watch)';
}

/// The sensor settings, kept in shared_preferences.
///
/// A key is removed rather than written when a setting goes back to its
/// default, so the stored preferences only ever hold the choices the rider
/// actually made — and an app that has never been to this section holds
/// nothing at all, which is what "everything optional" means here.
class SensorSettingsController extends Notifier<SensorSettings> {
  @override
  SensorSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return SensorSettings(
      health: prefs.getBool(_prefsHealth) ?? false,
      healthWrite: prefs.getBool(_prefsHealthWrite) ?? true,
      watch: prefs.getBool(_prefsWatch) ?? false,
    );
  }

  /// Switches the health store on or off.
  ///
  /// Switching it on is the rider's consent to the OS prompt, and nothing
  /// else asks for one: the caller has already been told by the store whether
  /// access was granted.
  Future<void> setHealth(bool value) async {
    await _write(_prefsHealth, value, defaultValue: false);
    state = state.copyWith(health: value);
  }

  /// Switches saving finished rides as workouts on or off.
  Future<void> setHealthWrite(bool value) async {
    await _write(_prefsHealthWrite, value, defaultValue: true);
    state = state.copyWith(healthWrite: value);
  }

  /// Switches the watch on or off.
  ///
  /// Switching it on is what registers the watch with the hub and lets the
  /// two apps talk; until then nothing reaches the wrist, and the watch app
  /// asks the OS on the watch for nothing.
  Future<void> setWatch(bool value) async {
    await _write(_prefsWatch, value, defaultValue: false);
    state = state.copyWith(watch: value);
  }

  Future<void> _write(
    String key,
    bool value, {
    required bool defaultValue,
  }) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value == defaultValue) {
      await prefs.remove(key);
    } else {
      await prefs.setBool(key, value);
    }
  }
}

/// The sensor settings.
final sensorSettingsProvider =
    NotifierProvider<SensorSettingsController, SensorSettings>(
      SensorSettingsController.new,
    );
