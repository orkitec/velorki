import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/heading_smoother.dart';

void main() {
  group('visibility hysteresis', () {
    test('stays hidden until the rider is clearly moving', () {
      final smoother = HeadingSmoother();

      expect(smoother.update(headingDeg: 90, speedMps: 0), isNull);
      expect(smoother.update(headingDeg: 90, speedMps: 1.4), isNull);
      expect(smoother.isVisible, isFalse);

      expect(smoother.update(headingDeg: 90, speedMps: 1.5), 90);
      expect(smoother.isVisible, isTrue);
    });

    test('holds the cone through the gap between the thresholds', () {
      final smoother = HeadingSmoother()..update(headingDeg: 90, speedMps: 3.0);

      // Rolling out: below the on-threshold but above the off-threshold, so
      // the cone must not blink away and back on the next fix.
      expect(smoother.update(headingDeg: 90, speedMps: 1.0), 90);
      expect(smoother.update(headingDeg: 90, speedMps: 0.7), 90);
      expect(smoother.isVisible, isTrue);

      expect(smoother.update(headingDeg: 90, speedMps: 0.59), isNull);
      expect(smoother.isVisible, isFalse);
    });

    test('a missing or broken speed hides the cone', () {
      final smoother = HeadingSmoother()..update(headingDeg: 90, speedMps: 3.0);

      expect(smoother.update(headingDeg: 90), isNull);
      expect(smoother.isVisible, isFalse);

      smoother.update(headingDeg: 90, speedMps: 3.0);
      expect(smoother.update(headingDeg: 90, speedMps: double.nan), isNull);
    });
  });

  group('smoothing', () {
    test('the first course is taken as it is', () {
      final smoother = HeadingSmoother();

      expect(smoother.update(headingDeg: 120, speedMps: 5), 120);
    });

    test('later courses move the heading by alpha of the difference', () {
      final smoother = HeadingSmoother()..update(headingDeg: 0, speedMps: 5);

      // Riding speed, so alpha is 0.5: 0 + 0.5 * 100, then 50 + 0.5 * 50.
      expect(smoother.update(headingDeg: 100, speedMps: 5), closeTo(50, 1e-9));
      expect(smoother.update(headingDeg: 100, speedMps: 5), closeTo(75, 1e-9));
    });

    test('a slower fix is blended in more carefully', () {
      final smoother = HeadingSmoother()..update(headingDeg: 0, speedMps: 2);

      // Below 4 m/s the course is half noise, so only 0.3 of it counts.
      expect(smoother.update(headingDeg: 100, speedMps: 2), closeTo(30, 1e-9));
      // And back at riding speed the cone catches up faster again.
      expect(smoother.update(headingDeg: 100, speedMps: 5), closeTo(65, 1e-9));
    });

    test('a raw course is normalised before it is blended', () {
      final smoother = HeadingSmoother();

      expect(smoother.update(headingDeg: 450, speedMps: 5), 90);
      expect(smoother.update(headingDeg: -270, speedMps: 5), 90);
    });

    test('averages the short way around 0 degrees', () {
      final smoother = HeadingSmoother()..update(headingDeg: 359, speedMps: 5);

      // Half of the two degrees between 359 and 1, not half of the 358 the
      // long way round, which would land on 180.
      expect(smoother.update(headingDeg: 1, speedMps: 5), closeTo(0, 1e-9));
      expect(smoother.update(headingDeg: 1, speedMps: 5), closeTo(0.5, 1e-9));
      expect(smoother.heading, inInclusiveRange(0, 360));
    });

    test('crossing 0 downwards stays in 0-360', () {
      final smoother = HeadingSmoother()..update(headingDeg: 1, speedMps: 5);

      final heading = smoother.update(headingDeg: 350, speedMps: 5)!;
      expect(heading, closeTo(355.5, 1e-9));
      expect(heading, inInclusiveRange(0, 360));
    });

    test('a fix without a course keeps the last heading', () {
      final smoother = HeadingSmoother()..update(headingDeg: 90, speedMps: 5);

      expect(smoother.update(speedMps: 5), 90);
      expect(smoother.update(headingDeg: double.nan, speedMps: 5), 90);
      expect(smoother.update(headingDeg: double.infinity, speedMps: 5), 90);
    });

    test('a course too slow to mean anything does not move the heading', () {
      final smoother = HeadingSmoother()..update(headingDeg: 90, speedMps: 5);

      // Above the off-threshold, so the cone stays, but a course at half a
      // walking pace is noise and must not drag the arrow around.
      expect(smoother.update(headingDeg: 270, speedMps: 0.7), 90);
    });
  });

  group('reset', () {
    test('forgets the average, so the next course is taken as it is', () {
      final smoother = HeadingSmoother()..update(headingDeg: 90, speedMps: 5);

      smoother.reset();

      expect(smoother.isVisible, isFalse);
      expect(smoother.heading, isNull);
      expect(smoother.update(headingDeg: 270, speedMps: 5), 270);
    });

    test('hiding the cone resets it as well', () {
      final smoother = HeadingSmoother()..update(headingDeg: 90, speedMps: 5);

      expect(smoother.update(headingDeg: 90, speedMps: 0), isNull);
      expect(smoother.heading, isNull);

      // No drift from the forgotten 90 towards the new course.
      expect(smoother.update(headingDeg: 270, speedMps: 5), 270);
    });
  });

  test('the thresholds are configurable', () {
    final smoother = HeadingSmoother(
      onSpeedMps: 10,
      offSpeedMps: 5,
      alpha: 1.0,
    );

    expect(smoother.update(headingDeg: 0, speedMps: 9), isNull);
    expect(smoother.update(headingDeg: 0, speedMps: 10), 0);
    // alpha 1 takes the newest course whole.
    expect(smoother.update(headingDeg: 100, speedMps: 10), 100);
    expect(smoother.update(headingDeg: 100, speedMps: 4.9), isNull);
  });
}
