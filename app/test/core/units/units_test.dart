import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/units/units.dart';

void main() {
  group('distance', () {
    test('metric stays in metres up to the kilometre', () {
      expect(
        formatDistance(UnitSystem.metric, 999),
        const Measure(999, MeasureUnit.meters),
      );
      expect(
        formatDistance(UnitSystem.metric, 1000),
        const Measure(1, MeasureUnit.kilometers, decimals: 1),
      );
      expect(
        formatDistance(UnitSystem.metric, 12345).value,
        closeTo(12.345, 1e-9),
      );
    });

    test('imperial reads in feet below a tenth of a mile', () {
      // 0.09 mi, still feet.
      final short = formatDistance(UnitSystem.imperial, 0.09 * metersPerMile);
      expect(short.unit, MeasureUnit.feet);
      expect(short.value, 480);
      expect(short.decimals, 0);

      // 0.1 mi exactly, already miles.
      final long = formatDistance(UnitSystem.imperial, 0.1 * metersPerMile);
      expect(long.unit, MeasureUnit.miles);
      expect(long.value, closeTo(0.1, 1e-9));
      expect(long.decimals, 1);
    });

    test('feet are rounded to ten', () {
      // 98.4 ft, 101.7 ft, 105.0 ft and 108.3 ft: the first three land on a
      // hundred, the last steps up to a hundred and ten.
      expect(formatDistance(UnitSystem.imperial, 30).value, 100);
      expect(formatDistance(UnitSystem.imperial, 31).value, 100);
      expect(formatDistance(UnitSystem.imperial, 32).value, 100);
      expect(formatDistance(UnitSystem.imperial, 33).value, 110);
    });

    test('a long imperial distance is miles with one decimal', () {
      final measure = formatDistance(UnitSystem.imperial, 12345);
      expect(measure.unit, MeasureUnit.miles);
      expect(measure.value, closeTo(7.6708, 1e-4));
      expect(measure.decimals, 1);
    });

    test('a negative distance keeps its sign and its unit', () {
      expect(
        formatDistance(UnitSystem.metric, -500),
        const Measure(-500, MeasureUnit.meters),
      );
      expect(formatDistance(UnitSystem.imperial, -30).value, -100);
    });
  });

  group('speed', () {
    test('metric counts kilometres per hour', () {
      final measure = formatSpeed(UnitSystem.metric, 10);
      expect(measure.unit, MeasureUnit.kilometersPerHour);
      expect(measure.value, closeTo(36, 1e-9));
      expect(measure.decimals, 1);
    });

    test('imperial counts miles per hour', () {
      final measure = formatSpeed(UnitSystem.imperial, 10);
      expect(measure.unit, MeasureUnit.milesPerHour);
      expect(measure.value, closeTo(22.3694, 1e-4));
      expect(measure.decimals, 1);
    });
  });

  group('elevation', () {
    test('metric is whole metres', () {
      expect(
        formatElevation(UnitSystem.metric, 210),
        const Measure(210, MeasureUnit.meters),
      );
    });

    test('imperial is whole feet', () {
      expect(
        formatElevation(UnitSystem.imperial, 210),
        const Measure(689, MeasureUnit.feet),
      );
      expect(
        formatElevation(UnitSystem.imperial, 500),
        const Measure(1640, MeasureUnit.feet),
      );
    });
  });

  group('slider helpers', () {
    test('metres go out to kilometres or miles and come back', () {
      expect(distanceToDisplay(UnitSystem.metric, 30000), 30);
      expect(
        distanceToDisplay(UnitSystem.imperial, 30000),
        closeTo(18.64, 0.01),
      );
      expect(displayToMeters(UnitSystem.metric, 30), 30000);
      expect(displayToMeters(UnitSystem.imperial, 20), closeTo(32186.9, 0.1));
      for (final system in UnitSystem.values) {
        expect(
          displayToMeters(system, distanceToDisplay(system, 4321)),
          closeTo(4321, 1e-9),
        );
      }
    });

    test('heights go out to metres or feet', () {
      expect(elevationToDisplay(UnitSystem.metric, 100), 100);
      expect(
        elevationToDisplay(UnitSystem.imperial, 100),
        closeTo(328.08, 0.01),
      );
    });
  });

  test('a name that means nothing falls back to metric', () {
    expect(UnitSystem.fromName('imperial'), UnitSystem.imperial);
    expect(UnitSystem.fromName('furlongs'), UnitSystem.metric);
    expect(UnitSystem.fromName(null), UnitSystem.metric);
  });

  test('feet round to a hundred for the spoken cue', () {
    expect(roundToHundredFeet(152), 500);
    expect(roundToHundredFeet(300), 1000);
    expect(roundToTenFeet(160), 520);
  });
}
