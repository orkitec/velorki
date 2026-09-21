import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/recording/application/threshold_power_suggestion.dart';

void main() {
  group('suggestThresholdPower', () {
    test('is 95 % of the best twenty minutes, rounded to 5 W', () {
      // 250 × 0.95 = 237.5, which rounds to 240; 247 × 0.95 = 234.65 → 235.
      expect(suggestThresholdPower(<int?>[250]), 240);
      expect(suggestThresholdPower(<int?>[247]), 235);
      expect(suggestThresholdPower(<int?>[300]), 285);
      expect(suggestThresholdPower(<int?>[200]), 190);
    });

    test('takes the best ride, skipping those without twenty minutes', () {
      expect(suggestThresholdPower(<int?>[null, 210, 300, null, 247]), 285);
    });

    test('is nothing without a ride that had twenty minutes of power', () {
      expect(suggestThresholdPower(const <int?>[]), isNull);
      expect(suggestThresholdPower(<int?>[null, null]), isNull);
    });
  });
}
