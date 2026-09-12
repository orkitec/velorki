import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/recording/domain/ride_stats.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// One ten-thousandth of a degree of latitude, the step the fixtures use.
///
/// 2π · 6371008.8 m / 360 / 10000 = 11.1195 m, so a step per second is
/// 11.1195 m/s — well above the 1 km/h moving threshold and well below the
/// 30 m/s jump filter.
const double stepMeters = 11.11949;

TrackPoint _point(int index, {double? ele, int seconds = 1, double? speed}) =>
    TrackPoint(
      LatLng(48 + index * 0.0001, 11),
      ele: ele,
      time: DateTime.utc(2026, 9, 12, 10, 0, index * seconds),
      speedMps: speed,
    );

void main() {
  group('computeRideStats', () {
    test('no points is all zeroes', () {
      final stats = computeRideStats(const <TrackPoint>[]);
      expect(stats.distanceM, 0);
      expect(stats.elapsedTime, Duration.zero);
      expect(stats.movingTime, Duration.zero);
      expect(stats.avgSpeedMps, 0);
      expect(stats.pointCount, 0);
    });

    test('adds up distance, moving time and average speed', () {
      final stats = computeRideStats(
        List<TrackPoint>.generate(4, (i) => _point(i)),
      );
      expect(stats.pointCount, 4);
      expect(stats.distanceM, closeTo(3 * stepMeters, 0.01));
      expect(stats.movingTime, const Duration(seconds: 3));
      expect(stats.elapsedTime, const Duration(seconds: 3));
      expect(stats.avgSpeedMps, closeTo(stepMeters, 0.01));
      expect(stats.maxSpeedMps, closeTo(stepMeters, 0.01));
      expect(stats.startedAt, DateTime.utc(2026, 9, 12, 10));
      expect(stats.endedAt, DateTime.utc(2026, 9, 12, 10, 0, 3));
    });

    test('standing still counts as elapsed but not as moving', () {
      final stats = computeRideStats(<TrackPoint>[
        TrackPoint(const LatLng(48, 11), time: DateTime.utc(2026, 9, 12, 10)),
        TrackPoint(
          const LatLng(48, 11),
          time: DateTime.utc(2026, 9, 12, 10, 0, 5),
        ),
      ]);
      expect(stats.distanceM, 0);
      expect(stats.movingTime, Duration.zero);
      expect(stats.elapsedTime, const Duration(seconds: 5));
    });

    test('a jump faster than 30 m/s is dropped, not recorded', () {
      final stats = computeRideStats(<TrackPoint>[
        TrackPoint(const LatLng(48, 11), time: DateTime.utc(2026, 9, 12, 10)),
        // 0.01° is 1111.9 m, in one second: 1111 m/s.
        TrackPoint(
          const LatLng(48.01, 11),
          time: DateTime.utc(2026, 9, 12, 10, 0, 1),
        ),
        TrackPoint(
          const LatLng(48.0001, 11),
          time: DateTime.utc(2026, 9, 12, 10, 0, 2),
        ),
      ]);
      expect(
        stats.pointCount,
        2,
        reason: 'the jump is not a point of the ride',
      );
      expect(stats.distanceM, closeTo(stepMeters, 0.01));
      expect(stats.maxSpeedMps, lessThan(maxPlausibleSpeedMps));
    });

    test('out-of-order and duplicate timestamps are dropped', () {
      final stats = computeRideStats(<TrackPoint>[
        _point(0),
        _point(1),
        TrackPoint(
          const LatLng(48.0005, 11),
          time: DateTime.utc(2026, 9, 12, 10, 0, 1),
        ),
      ]);
      expect(stats.pointCount, 2);
    });

    test('a gap longer than 30 s adds neither distance nor moving time', () {
      final stats = computeRideStats(<TrackPoint>[
        TrackPoint(const LatLng(48, 11), time: DateTime.utc(2026, 9, 12, 10)),
        TrackPoint(
          const LatLng(48, 11),
          time: DateTime.utc(2026, 9, 12, 10, 0, 1),
        ),
        // Five minutes later and half a kilometre on: a pause, not a sprint.
        TrackPoint(
          const LatLng(48.005, 11),
          time: DateTime.utc(2026, 9, 12, 10, 5),
        ),
        TrackPoint(
          const LatLng(48.0051, 11),
          time: DateTime.utc(2026, 9, 12, 10, 5, 1),
        ),
      ]);
      expect(stats.distanceM, closeTo(stepMeters, 0.01));
      expect(stats.movingTime, const Duration(seconds: 1));
      expect(stats.elapsedTime, const Duration(minutes: 5, seconds: 1));
    });

    test('ascent and descent use 3 m of hysteresis', () {
      // 100 → 101 (noise) → 104 (+4) → 103 (noise) → 100 (-4) → 96 (-4).
      final elevations = <double>[100, 101, 104, 103, 100, 96];
      final stats = computeRideStats(<TrackPoint>[
        for (var i = 0; i < elevations.length; i++)
          _point(i, ele: elevations[i]),
      ]);
      expect(stats.ascentM, closeTo(4, 0.001));
      expect(stats.descentM, closeTo(8, 0.001));
    });

    test('a steady climb loses at most one hysteresis band', () {
      final stats = computeRideStats(<TrackPoint>[
        for (var i = 0; i <= 10; i++) _point(i, ele: 100 + i.toDouble()),
      ]);
      // 100 → 110 in steps of one metre: 9 m counted, the open 1 m is not.
      expect(stats.ascentM, closeTo(9, 0.001));
      expect(stats.descentM, 0);
    });

    test('a reported speed wins over the computed one for the maximum', () {
      final stats = computeRideStats(<TrackPoint>[
        _point(0, speed: 0),
        _point(1, speed: 25),
      ]);
      expect(stats.maxSpeedMps, 25);
    });
  });

  group('RideStatsAccumulator', () {
    test('reports the last segment speed and the last movement', () {
      final accumulator = RideStatsAccumulator()
        ..add(_point(0))
        ..add(_point(1));
      expect(accumulator.lastSegmentSpeedMps, closeTo(stepMeters, 0.01));
      expect(accumulator.lastMovingAt, DateTime.utc(2026, 9, 12, 10, 0, 1));

      accumulator.add(
        TrackPoint(
          const LatLng(48.0001, 11),
          time: DateTime.utc(2026, 9, 12, 10, 0, 2),
        ),
      );
      expect(accumulator.lastSegmentSpeedMps, 0);
      expect(accumulator.lastMovingAt, DateTime.utc(2026, 9, 12, 10, 0, 1));
    });

    test('rejects a fix without changing anything', () {
      final accumulator = RideStatsAccumulator()..add(_point(0));
      final accepted = accumulator.add(
        TrackPoint(
          const LatLng(49, 11),
          time: DateTime.utc(2026, 9, 12, 10, 0, 1),
        ),
      );
      expect(accepted, isFalse);
      expect(accumulator.pointCount, 1);
      expect(accumulator.stats.distanceM, 0);
    });
  });
}
