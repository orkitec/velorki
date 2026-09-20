import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/units/units.dart';
import 'package:velorki/features/recording/domain/split_length.dart';

void main() {
  group('the automatic split length', () {
    test('is a kilometre up to thirty of them', () {
      expect(splitUnits(SplitLength.auto, UnitSystem.metric, 3000), 1);
      expect(splitUnits(SplitLength.auto, UnitSystem.metric, 30000), 1);
    });

    test('is five kilometres up to a hundred and fifty', () {
      expect(splitUnits(SplitLength.auto, UnitSystem.metric, 30001), 5);
      expect(splitUnits(SplitLength.auto, UnitSystem.metric, 41000), 5);
      expect(splitUnits(SplitLength.auto, UnitSystem.metric, 150000), 5);
    });

    test('is ten kilometres beyond', () {
      expect(splitUnits(SplitLength.auto, UnitSystem.metric, 200000), 10);
    });

    test('counts in miles under imperial', () {
      // 48 km is under thirty miles, still one-mile splits; 50 km is not.
      expect(splitUnits(SplitLength.auto, UnitSystem.imperial, 48000), 1);
      expect(splitUnits(SplitLength.auto, UnitSystem.imperial, 50000), 5);
      expect(
        splitLengthMetres(SplitLength.auto, UnitSystem.imperial, 50000),
        5 * metersPerMile,
      );
    });
  });

  test('a fixed choice is what it says whatever the ride', () {
    expect(splitLengthMetres(SplitLength.one, UnitSystem.metric, 200000), 1000);
    expect(splitLengthMetres(SplitLength.ten, UnitSystem.metric, 3000), 10000);
    expect(
      splitLengthMetres(SplitLength.five, UnitSystem.imperial, 3000),
      5 * metersPerMile,
    );
  });

  test('an unknown stored name is automatic', () {
    expect(SplitLength.fromName('five'), SplitLength.five);
    expect(SplitLength.fromName('furlong'), SplitLength.auto);
    expect(SplitLength.fromName(null), SplitLength.auto);
  });
}
