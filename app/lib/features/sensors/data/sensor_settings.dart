import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../domain/ble_profiles.dart';

const String _prefsHealth = 'sensors.health';
const String _prefsHealthWrite = 'sensors.health.write';
const String _prefsWatch = 'sensors.watch';
const String _prefsWatchRest = 'sensors.watch.rest';

/// Whether Velorki talks to the platform's health store at all, whether
/// finished rides are saved there as workouts, whether the rider's watch is
/// part of the ride, and what a wheel sensor is measuring.
class SensorSettings {
  /// Creates the settings. Health and the watch are off until the rider
  /// switches them on; once Health is on, rides are saved unless they say
  /// otherwise.
  const SensorSettings({
    this.health = false,
    this.healthWrite = true,
    this.watch = false,
    this.watchRest = false,
    this.wheelCircumferenceMm = defaultWheelCircumferenceMm,
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

  /// Whether the watch ends its workout at every pause and is woken again
  /// when the ride goes on, so the sensor rests at every stop. Off, the
  /// workout pauses with the ride and the sensor keeps its cadence. Only
  /// has an effect while [watch] is on.
  final bool watchRest;

  /// How far the bike rolls in one wheel turn, in millimetres. A wheel sensor
  /// counts revolutions and nothing else, so this is the whole difference
  /// between its count and a speed.
  final int wheelCircumferenceMm;

  /// [wheelCircumferenceMm] in metres, which is the unit a speed is derived
  /// in.
  double get wheelCircumferenceM => wheelCircumferenceMm / 1000;

  /// A copy with the named fields replaced.
  SensorSettings copyWith({
    bool? health,
    bool? healthWrite,
    bool? watch,
    bool? watchRest,
    int? wheelCircumferenceMm,
  }) => SensorSettings(
    health: health ?? this.health,
    healthWrite: healthWrite ?? this.healthWrite,
    watch: watch ?? this.watch,
    watchRest: watchRest ?? this.watchRest,
    wheelCircumferenceMm: wheelCircumferenceMm ?? this.wheelCircumferenceMm,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorSettings &&
          other.health == health &&
          other.healthWrite == healthWrite &&
          other.watch == watch &&
          other.watchRest == watchRest &&
          other.wheelCircumferenceMm == wheelCircumferenceMm;

  @override
  int get hashCode =>
      Object.hash(health, healthWrite, watch, watchRest, wheelCircumferenceMm);

  @override
  String toString() =>
      'SensorSettings(health: $health, healthWrite: $healthWrite, '
      'watch: $watch, watchRest: $watchRest, '
      'wheel: $wheelCircumferenceMm mm)';
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
      watchRest: prefs.getBool(_prefsWatchRest) ?? false,
      wheelCircumferenceMm:
          prefs.getInt(prefsWheelCircumferenceMm) ??
          defaultWheelCircumferenceMm,
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

  /// Switches resting the watch's sensor at every pause on or off.
  Future<void> setWatchRest(bool value) async {
    await _write(_prefsWatchRest, value, defaultValue: false);
    state = state.copyWith(watchRest: value);
  }

  /// Sets the wheel a speed sensor is on, in millimetres.
  ///
  /// Clamped to something a bicycle could actually have, because the number is
  /// typed by hand and a stray digit would turn a ride into a flight.
  Future<void> setWheelCircumferenceMm(int value) async {
    final wheel = value.clamp(minWheelCircumferenceMm, maxWheelCircumferenceMm);
    final prefs = ref.read(sharedPreferencesProvider);
    if (wheel == defaultWheelCircumferenceMm) {
      await prefs.remove(prefsWheelCircumferenceMm);
    } else {
      await prefs.setInt(prefsWheelCircumferenceMm, wheel);
    }
    state = state.copyWith(wheelCircumferenceMm: wheel);
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
