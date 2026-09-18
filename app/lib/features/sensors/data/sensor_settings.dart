import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';

const String _prefsHealth = 'sensors.health';
const String _prefsHealthWrite = 'sensors.health.write';

/// Whether Velorki talks to the platform's health store at all, and whether
/// finished rides are saved there as workouts.
class SensorSettings {
  /// Creates the settings. Health is off until the rider switches it on;
  /// once it is on, rides are saved unless they say otherwise.
  const SensorSettings({this.health = false, this.healthWrite = true});

  /// Nothing is switched on: no permission has been asked for, and nothing
  /// reads or writes the health store.
  static const SensorSettings off = SensorSettings();

  /// Whether heart rate is read from Apple Health or Health Connect.
  final bool health;

  /// Whether a finished ride is written back as a cycling workout. Only has
  /// an effect while [health] is on.
  final bool healthWrite;

  /// A copy with the named fields replaced.
  SensorSettings copyWith({bool? health, bool? healthWrite}) => SensorSettings(
    health: health ?? this.health,
    healthWrite: healthWrite ?? this.healthWrite,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorSettings &&
          other.health == health &&
          other.healthWrite == healthWrite;

  @override
  int get hashCode => Object.hash(health, healthWrite);

  @override
  String toString() =>
      'SensorSettings(health: $health, healthWrite: $healthWrite)';
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
