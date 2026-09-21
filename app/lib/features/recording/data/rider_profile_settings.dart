import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../domain/rider_profile.dart';

const String _prefsCalories = 'rider.calories';
const String _prefsZones = 'rider.zones';
const String _prefsWeightKg = 'rider.weightKg';
const String _prefsBirthYear = 'rider.birthYear';
const String _prefsSex = 'rider.sex';
const String _prefsMaxHeartRate = 'rider.maxHeartRateBpm';
const String _prefsEstimatePower = 'rider.estimatePower';
const String _prefsBikeWeightKg = 'rider.bikeWeightKg';
const String _prefsBike = 'rider.bike';

/// The lightest rider the weight field accepts, in kilograms.
const double minRiderWeightKg = 20;

/// The heaviest rider the weight field accepts, in kilograms.
const double maxRiderWeightKg = 250;

/// The earliest year of birth the field accepts.
const int minRiderBirthYear = 1900;

/// The lowest maximum heart rate the field accepts.
const int minRiderMaxHeartRateBpm = 100;

/// The highest maximum heart rate the field accepts.
const int maxRiderMaxHeartRateBpm = 230;

/// The lightest bike the weight field accepts, in kilograms.
const double minBikeWeightKg = 3;

/// The heaviest bike the weight field accepts, in kilograms.
const double maxBikeWeightKg = 40;

/// The rider profile, kept in shared_preferences.
///
/// A key is removed rather than written when it goes back to its default or
/// is cleared, so the stored preferences only ever hold what the rider
/// actually entered.
class RiderProfileController extends Notifier<RiderProfile> {
  @override
  RiderProfile build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return RiderProfile(
      calories: prefs.getBool(_prefsCalories) ?? false,
      zones: prefs.getBool(_prefsZones) ?? false,
      weightKg: prefs.getDouble(_prefsWeightKg),
      birthYear: prefs.getInt(_prefsBirthYear),
      sex: RiderSex.fromName(prefs.getString(_prefsSex)),
      maxHeartRateBpm: prefs.getInt(_prefsMaxHeartRate),
      estimatePower: prefs.getBool(_prefsEstimatePower) ?? false,
      bikeWeightKg: prefs.getDouble(_prefsBikeWeightKg) ?? defaultBikeWeightKg,
      bike: RiderBike.fromName(prefs.getString(_prefsBike)),
    );
  }

  /// Switches the calorie estimate on or off.
  Future<void> setCalories(bool value) async {
    await _setFlag(_prefsCalories, value);
    state = state.copyWith(calories: value);
  }

  /// Switches the heart-rate zones on or off.
  Future<void> setZones(bool value) async {
    await _setFlag(_prefsZones, value);
    state = state.copyWith(zones: value);
  }

  /// Stores the rider's weight, clamped to what a rider can weigh; `null`
  /// clears it.
  Future<void> setWeightKg(double? value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value == null || !value.isFinite) {
      await prefs.remove(_prefsWeightKg);
      state = state.copyWith(clearWeight: true);
      return;
    }
    final clamped = value.clamp(minRiderWeightKg, maxRiderWeightKg);
    await prefs.setDouble(_prefsWeightKg, clamped);
    state = state.copyWith(weightKg: clamped);
  }

  /// Stores the rider's year of birth, clamped between 1900 and this year;
  /// `null` clears it.
  Future<void> setBirthYear(int? value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value == null) {
      await prefs.remove(_prefsBirthYear);
      state = state.copyWith(clearBirthYear: true);
      return;
    }
    final clamped = value.clamp(minRiderBirthYear, DateTime.now().year);
    await prefs.setInt(_prefsBirthYear, clamped);
    state = state.copyWith(birthYear: clamped);
  }

  /// Stores the rider's sex.
  Future<void> setSex(RiderSex value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value == RiderSex.unspecified) {
      await prefs.remove(_prefsSex);
    } else {
      await prefs.setString(_prefsSex, value.name);
    }
    state = state.copyWith(sex: value);
  }

  /// Stores the rider's maximum heart rate, clamped to 100–230 bpm; `null`
  /// clears it and lets the age estimate one.
  Future<void> setMaxHeartRate(int? value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value == null) {
      await prefs.remove(_prefsMaxHeartRate);
      state = state.copyWith(clearMaxHeartRate: true);
      return;
    }
    final clamped = value.clamp(
      minRiderMaxHeartRateBpm,
      maxRiderMaxHeartRateBpm,
    );
    await prefs.setInt(_prefsMaxHeartRate, clamped);
    state = state.copyWith(maxHeartRateBpm: clamped);
  }

  /// Switches the power estimate on or off.
  Future<void> setEstimatePower(bool value) async {
    await _setFlag(_prefsEstimatePower, value);
    state = state.copyWith(estimatePower: value);
  }

  /// Stores the bike's weight, clamped to what a bike can weigh; `null` goes
  /// back to the default.
  Future<void> setBikeWeightKg(double? value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value == null || !value.isFinite) {
      await prefs.remove(_prefsBikeWeightKg);
      state = state.copyWith(bikeWeightKg: defaultBikeWeightKg);
      return;
    }
    final clamped = value.clamp(minBikeWeightKg, maxBikeWeightKg);
    if (clamped == defaultBikeWeightKg) {
      await prefs.remove(_prefsBikeWeightKg);
    } else {
      await prefs.setDouble(_prefsBikeWeightKg, clamped);
    }
    state = state.copyWith(bikeWeightKg: clamped);
  }

  /// Stores the kind of bike.
  Future<void> setBike(RiderBike value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value == RiderBike.road) {
      await prefs.remove(_prefsBike);
    } else {
      await prefs.setString(_prefsBike, value.name);
    }
    state = state.copyWith(bike: value);
  }

  Future<void> _setFlag(String key, bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value) {
      await prefs.setBool(key, true);
    } else {
      await prefs.remove(key);
    }
  }
}

/// The rider profile.
final riderProfileProvider =
    NotifierProvider<RiderProfileController, RiderProfile>(
      RiderProfileController.new,
    );
