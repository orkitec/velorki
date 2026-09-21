import '../../../core/geo/ride_analysis.dart';
import 'rider_profile.dart';

/// Which figure a calorie estimate was made from.
enum CalorieSource {
  /// The work a power meter measured, the most trustworthy source.
  power,

  /// The heart rate over the ride, through Keytel et al. (2005).
  heartRate,

  /// The riding speed alone, through the ACSM cycling table.
  speed,
}

/// A calorie estimate and where it came from.
class CalorieEstimate {
  /// Creates the estimate.
  const CalorieEstimate({required this.kcal, required this.source});

  /// Kilocalories burned, rounded.
  final int kcal;

  /// Which figure it was made from.
  final CalorieSource source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalorieEstimate && other.kcal == kcal && other.source == source;

  @override
  int get hashCode => Object.hash(kcal, source);

  @override
  String toString() => 'CalorieEstimate($kcal kcal from ${source.name})';
}

/// How much of the moving time a sensor must have covered for its figure to
/// stand for the whole ride.
const double calorieCoverage = 0.9;

/// Estimates the calories a ride burned, or `null` when nothing is known
/// about the rider or nothing was ridden.
///
/// The best source available wins: a power meter that reported for most of
/// the ride gives the work done, and a kilojoule of work is very nearly a
/// kilocalorie burned at the body's roughly 24 % efficiency, which is what
/// Strava and Garmin do too. Else a heart rate over most of the ride, with the
/// rider's weight, age and sex, goes through the Keytel formula, integrated
/// over time. Else the speed alone, through the ACSM table of metabolic
/// equivalents times the rider's weight.
CalorieEstimate? estimateCalories(
  RiderProfile profile,
  RideEffort effort, {
  required int year,
}) {
  final weightKg = profile.weightKg;
  if (weightKg == null || effort.movingTime <= Duration.zero) return null;
  final movingMicros = effort.movingTime.inMicroseconds;

  if (effort.powerTime.inMicroseconds >= calorieCoverage * movingMicros) {
    return CalorieEstimate(
      kcal: effort.energyKj.round(),
      source: CalorieSource.power,
    );
  }

  final age = profile.ageIn(year);
  if (profile.sex != RiderSex.unspecified &&
      age != null &&
      effort.heartRateTime.inMicroseconds >= calorieCoverage * movingMicros) {
    return CalorieEstimate(
      kcal: _keytel(
        profile.sex,
        weightKg: weightKg,
        age: age,
        minutes: effort.heartRateTime.inMicroseconds / 60e6,
        beatMinutes: effort.heartRateBeatSeconds / 60,
      ).round(),
      source: CalorieSource.heartRate,
    );
  }

  return CalorieEstimate(
    kcal: (effort.metHours * weightKg).round(),
    source: CalorieSource.speed,
  );
}

/// Keytel et al. 2005: kilojoules per minute as a straight line in heart
/// rate, weight and age, with one set of coefficients per sex.
///
/// Being linear in the heart rate it integrates exactly: the constant part
/// times the minutes plus the heart-rate coefficient times the beat-minutes,
/// which is what the analysis summed. Divided by 4.184 for kilocalories, and
/// never below zero, which a very low heart rate could otherwise give.
double _keytel(
  RiderSex sex, {
  required double weightKg,
  required int age,
  required double minutes,
  required double beatMinutes,
}) {
  final (constant, perBeat) = switch (sex) {
    RiderSex.male => (-55.0969 + 0.1988 * weightKg + 0.2017 * age, 0.6309),
    RiderSex.female => (-20.4022 - 0.1263 * weightKg + 0.074 * age, 0.4472),
    RiderSex.unspecified => throw ArgumentError.value(sex, 'sex'),
  };
  final kj = constant * minutes + perBeat * beatMinutes;
  return kj < 0 ? 0 : kj / 4.184;
}
