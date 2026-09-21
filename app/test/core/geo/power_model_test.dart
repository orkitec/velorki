import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/power_model.dart';

/// A 75 kg rider on a 9 kg road bike: the defaults the estimate ships with.
const PowerModel _road = PowerModel(massKg: 84, cdA: 0.32, crr: 0.005);

void main() {
  group('airDensityAt', () {
    test('is the sea level standard at sea level', () {
      expect(airDensityAt(0), 1.225);
    });

    test('thins with altitude', () {
      expect(airDensityAt(1000), closeTo(1.088, 0.001));
    });
  });

  group('pedalPowerW', () {
    test('flat at 30 km/h is about 151 W on the road defaults', () {
      // Aero 0.5 · 1.225 · 0.32 · 8.333³ = 113.4 W, rolling
      // 0.005 · 84 · 9.8067 · 8.333 = 34.3 W, over the 0.975 drivetrain.
      final watts = pedalPowerW(
        _road,
        vMps: 30 / 3.6,
        grade: 0,
        aMps2: 0,
        elevationM: 0,
      );

      expect(watts, closeTo(151, 2));
    });

    test('an 8 % climb at 10 km/h is about 203 W', () {
      final watts = pedalPowerW(
        _road,
        vMps: 10 / 3.6,
        grade: 0.08,
        aMps2: 0,
        elevationM: 0,
      );

      expect(watts, closeTo(203, 3));
    });

    test('a descent is no work for the rider', () {
      final watts = pedalPowerW(
        _road,
        vMps: 40 / 3.6,
        grade: -0.08,
        aMps2: 0,
        elevationM: 0,
      );

      expect(watts, 0);
    });

    test('thinner air costs less at the same speed', () {
      final low = pedalPowerW(
        _road,
        vMps: 30 / 3.6,
        grade: 0,
        aMps2: 0,
        elevationM: 0,
      );
      final high = pedalPowerW(
        _road,
        vMps: 30 / 3.6,
        grade: 0,
        aMps2: 0,
        elevationM: 2000,
      );

      expect(high, lessThan(low));
    });
  });

  test('two models of the same figures are equal', () {
    expect(_road, const PowerModel(massKg: 84, cdA: 0.32, crr: 0.005));
    expect(
      _road.hashCode,
      const PowerModel(massKg: 84, cdA: 0.32, crr: 0.005).hashCode,
    );
    expect(_road, isNot(const PowerModel(massKg: 85, cdA: 0.32, crr: 0.005)));
    expect(_road.toString(), contains('84.0 kg'));
  });
}
