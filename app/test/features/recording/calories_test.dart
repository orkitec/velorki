import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/ride_analysis.dart';
import 'package:velorki/features/recording/domain/calories.dart';
import 'package:velorki/features/recording/domain/rider_profile.dart';

const Duration _hour = Duration(hours: 1);

/// An hour of riding at 20 km/h (8 MET), with whatever the sensors gave.
RideEffort _effort({
  Duration powerTime = Duration.zero,
  double energyKj = 0,
  Duration heartRateTime = Duration.zero,
  int meanHeartRate = 0,
  Duration movingTime = _hour,
}) => RideEffort(
  movingTime: movingTime,
  maxCadenceRpm: null,
  maxPowerW: null,
  energyKj: energyKj,
  powerTime: powerTime,
  heartRateTime: heartRateTime,
  heartRateBeatSeconds: meanHeartRate * heartRateTime.inSeconds.toDouble(),
  metHours: 8.0 * movingTime.inSeconds / 3600,
  heartRateZones: RideEffort.zero.heartRateZones,
);

const RiderProfile _rider = RiderProfile(
  weightKg: 75,
  birthYear: 1986,
  sex: RiderSex.male,
);

void main() {
  test('nothing is estimated without a weight', () {
    expect(
      estimateCalories(
        const RiderProfile(birthYear: 1986, sex: RiderSex.male),
        _effort(),
        year: 2026,
      ),
      isNull,
    );
  });

  test('nothing is estimated when nothing was ridden', () {
    expect(
      estimateCalories(_rider, _effort(movingTime: Duration.zero), year: 2026),
      isNull,
    );
  });

  test('a power meter over the ride gives the work done, kJ as kcal', () {
    final estimate = estimateCalories(
      _rider,
      _effort(powerTime: _hour, energyKj: 720.4),
      year: 2026,
    );

    expect(
      estimate,
      const CalorieEstimate(kcal: 720, source: CalorieSource.power),
    );
  });

  test('a power meter over only part of the ride does not count', () {
    final estimate = estimateCalories(
      _rider,
      _effort(
        powerTime: const Duration(minutes: 30),
        energyKj: 360,
        heartRateTime: _hour,
        meanHeartRate: 150,
      ),
      year: 2026,
    );

    expect(estimate!.source, CalorieSource.heartRate);
  });

  test('a heart rate over the ride goes through Keytel for a man', () {
    final estimate = estimateCalories(
      _rider,
      _effort(heartRateTime: _hour, meanHeartRate: 150),
      year: 2026,
    );

    // 40 years old, 75 kg, 150 bpm: (-55.0969 + 0.6309·150 + 0.1988·75 +
    // 0.2017·40) / 4.184 = 14.86 kcal/min, 891 kcal an hour.
    final perMinute =
        (-55.0969 + 0.6309 * 150 + 0.1988 * 75 + 0.2017 * 40) / 4.184;
    expect(estimate!.source, CalorieSource.heartRate);
    expect(estimate.kcal, (perMinute * 60).round());
  });

  test('and for a woman with her own coefficients', () {
    final estimate = estimateCalories(
      _rider.copyWith(sex: RiderSex.female, weightKg: 60),
      _effort(heartRateTime: _hour, meanHeartRate: 150),
      year: 2026,
    );

    final perMinute =
        (-20.4022 + 0.4472 * 150 - 0.1263 * 60 + 0.074 * 40) / 4.184;
    expect(estimate!.source, CalorieSource.heartRate);
    expect(estimate.kcal, (perMinute * 60).round());
  });

  test('a heart rate too low for the formula is not a negative figure', () {
    final estimate = estimateCalories(
      _rider.copyWith(weightKg: 20, birthYear: 2010),
      _effort(heartRateTime: _hour, meanHeartRate: 60),
      year: 2026,
    );

    expect(estimate!.source, CalorieSource.heartRate);
    expect(estimate.kcal, 0);
  });

  test('without sex or age the heart rate is skipped for the speed', () {
    final noSex = estimateCalories(
      _rider.copyWith(sex: RiderSex.unspecified),
      _effort(heartRateTime: _hour, meanHeartRate: 150),
      year: 2026,
    );
    final noAge = estimateCalories(
      _rider.copyWith(clearBirthYear: true),
      _effort(heartRateTime: _hour, meanHeartRate: 150),
      year: 2026,
    );

    expect(noSex!.source, CalorieSource.speed);
    expect(noAge!.source, CalorieSource.speed);
  });

  test('the speed alone is MET-hours times the weight', () {
    final estimate = estimateCalories(_rider, _effort(), year: 2026);

    // An hour at 8 MET for 75 kg.
    expect(
      estimate,
      const CalorieEstimate(kcal: 600, source: CalorieSource.speed),
    );
  });
}
