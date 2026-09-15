import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:velorki/features/map/data/compass_heading.dart';

/// A phone lying flat on its back: the accelerometer reads one g straight up
/// through the screen.
const flat = <double>[0, 0, 9.81];

/// The earth's field in the northern hemisphere as a flat phone pointing
/// north reads it: twenty microtesla along the ground out of the top of the
/// phone, forty down into it.
const northwards = <double>[0, 20, -40];

void main() {
  group('azimuthDegrees', () {
    test('a phone lying flat and pointing north reads zero', () {
      expect(
        azimuthDegrees(accelerometer: flat, magnetometer: northwards),
        closeTo(0, 0.5),
      );
    });

    test('pointing east reads ninety', () {
      // Top to the east: the field's horizontal part now runs out of the
      // phone's left edge.
      expect(
        azimuthDegrees(
          accelerometer: flat,
          magnetometer: const <double>[-20, 0, -40],
        ),
        closeTo(90, 0.5),
      );
    });

    test('pointing south reads a hundred and eighty', () {
      expect(
        azimuthDegrees(
          accelerometer: flat,
          magnetometer: const <double>[0, -20, -40],
        ),
        closeTo(180, 0.5),
      );
    });

    test('pointing west reads two hundred and seventy', () {
      expect(
        azimuthDegrees(
          accelerometer: flat,
          magnetometer: const <double>[20, 0, -40],
        ),
        closeTo(270, 0.5),
      );
    });

    test('a phone tilted in the hand still reads the right way', () {
      // The same phone pointing east, tilted thirty degrees back towards the
      // rider: gravity has moved into the y axis and the field with it, and
      // the tilt compensation has to take both out again.
      expect(
        azimuthDegrees(
          accelerometer: const <double>[0, 4.905, 8.496],
          magnetometer: const <double>[-20, -20, -34.64],
        ),
        closeTo(90, 3),
      );
    });

    test('no magnetic field is no heading', () {
      expect(
        azimuthDegrees(
          accelerometer: flat,
          magnetometer: const <double>[0, 0, 0],
        ),
        isNull,
      );
    });

    test('no gravity is no heading either', () {
      expect(
        azimuthDegrees(
          accelerometer: const <double>[0, 0, 0],
          magnetometer: northwards,
        ),
        isNull,
      );
    });

    test('a field parallel to gravity leaves no east to point at', () {
      expect(
        azimuthDegrees(
          accelerometer: flat,
          magnetometer: const <double>[0, 0, -40],
        ),
        isNull,
      );
    });

    test('a broken sample is no heading', () {
      expect(
        azimuthDegrees(
          accelerometer: const <double>[0, 0, double.nan],
          magnetometer: northwards,
        ),
        isNull,
      );
    });
  });

  group('SensorsCompassSource', () {
    AccelerometerEvent accel(List<double> v) =>
        AccelerometerEvent(v[0], v[1], v[2], DateTime.utc(2026));
    MagnetometerEvent mag(List<double> v) =>
        MagnetometerEvent(v[0], v[1], v[2], DateTime.utc(2026));

    test('pairs the latest of each sensor and smooths the result', () {
      fakeAsync((async) {
        final gravity = StreamController<AccelerometerEvent>.broadcast();
        final field = StreamController<MagnetometerEvent>.broadcast();
        final source = SensorsCompassSource(
          accelerometer: () => gravity.stream,
          magnetometer: () => field.stream,
        );
        final seen = <double>[];
        final sub = source.headings.listen(seen.add);
        async.flushMicrotasks();

        // One sensor alone says nothing.
        gravity.add(accel(flat));
        async.elapse(compassSampleInterval * 3);
        expect(seen, isEmpty);

        // Both, and the first heading is taken as it stands.
        field.add(mag(northwards));
        async.elapse(compassSampleInterval);
        expect(seen.single, closeTo(0, 0.5));

        // The phone swings to the east: a quarter of the difference per
        // sample, so the needle walks there instead of jumping.
        field.add(mag(const <double>[-20, 0, -40]));
        async.elapse(compassSampleInterval);
        expect(seen.last, closeTo(22.5, 0.5));
        async.elapse(compassSampleInterval);
        expect(seen.last, closeTo(39.4, 0.5));

        sub.cancel();
        async.flushMicrotasks();
        expect(gravity.hasListener, isFalse, reason: 'the sensors stop');
        expect(field.hasListener, isFalse);
        gravity.close();
        field.close();
      });
    });

    test('a needle that has not moved is not reported again', () {
      fakeAsync((async) {
        final gravity = StreamController<AccelerometerEvent>.broadcast();
        final field = StreamController<MagnetometerEvent>.broadcast();
        final source = SensorsCompassSource(
          accelerometer: () => gravity.stream,
          magnetometer: () => field.stream,
        );
        final seen = <double>[];
        final sub = source.headings.listen(seen.add);
        async.flushMicrotasks();

        gravity.add(accel(flat));
        field.add(mag(northwards));
        async.elapse(compassSampleInterval * 20);
        expect(seen, hasLength(1), reason: 'twenty samples, one heading');

        sub.cancel();
        gravity.close();
        field.close();
        async.flushMicrotasks();
      });
    });
  });
}
