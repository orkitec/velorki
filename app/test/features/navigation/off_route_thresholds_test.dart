import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/application/off_route_thresholds.dart';

void main() {
  group('the stray threshold', () {
    test('a good fix leaves the base distance standing', () {
      expect(strayThresholdM(5), offRouteMeters);
      expect(strayThresholdM(30), offRouteMeters, reason: '2 × 30 is under 75');
    });

    test('a shaky fix has to be twice its own error circle out', () {
      expect(strayThresholdM(50), 100);
      expect(strayThresholdM(80), 160);
    });

    test('an unknown or zero accuracy is the base distance', () {
      expect(strayThresholdM(null), offRouteMeters);
      expect(strayThresholdM(0), offRouteMeters);
      expect(strayThresholdM(-5), offRouteMeters, reason: 'nonsense is none');
      expect(strayThresholdM(double.nan), offRouteMeters);
      expect(strayThresholdM(double.infinity), offRouteMeters);
    });

    test('a phone with no fix at all does not switch detection off', () {
      // Capped, so an accuracy of kilometres cannot leave a rider riding a
      // wrong turn to its end without being told.
      expect(strayThresholdM(500), 2 * accuracyCapMeters);
      expect(strayThresholdM(5000), 2 * accuracyCapMeters);
    });

    test('a rejoin is a shorter leash than the plan', () {
      expect(strayThresholdM(null, baseM: detourDriftMeters), 50);
      expect(strayThresholdM(10, baseM: detourDriftMeters), 50);
      expect(strayThresholdM(40, baseM: detourDriftMeters), 80);
      expect(strayThresholdM(5000, baseM: detourDriftMeters), 200);
    });
  });

  group('the snap threshold', () {
    test('a good fix leaves the base distance standing', () {
      expect(snapThresholdM(5), routeSnapMeters);
      expect(snapThresholdM(30), routeSnapMeters);
    });

    test('a shaky fix widens it by one error circle, not two', () {
      expect(snapThresholdM(50), 50);
      expect(snapThresholdM(90), 90);
    });

    test('an unknown or zero accuracy is the base distance', () {
      expect(snapThresholdM(null), routeSnapMeters);
      expect(snapThresholdM(0), routeSnapMeters);
      expect(snapThresholdM(double.nan), routeSnapMeters);
    });

    test('and it is capped too', () {
      expect(snapThresholdM(5000), accuracyCapMeters);
    });

    test('coming back is always easier than leaving', () {
      for (final accuracy in <double?>[null, 0, 5, 30, 50, 100, 1000]) {
        expect(
          snapThresholdM(accuracy),
          lessThan(strayThresholdM(accuracy)),
          reason: 'accuracy $accuracy',
        );
      }
    });
  });

  group('the effective accuracy', () {
    test('is what the formulas are built on', () {
      expect(effectiveAccuracyM(null), 0);
      expect(effectiveAccuracyM(0), 0);
      expect(effectiveAccuracyM(12), 12);
      expect(effectiveAccuracyM(accuracyCapMeters), accuracyCapMeters);
      expect(effectiveAccuracyM(1e6), accuracyCapMeters);
    });
  });
}
