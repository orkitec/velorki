import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/ride_stats.dart';
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

/// The same fixture without a timestamp, i.e. a route rather than a ride.
TrackPoint _plain(int index, {double? ele}) =>
    TrackPoint(LatLng(48 + index * 0.0001, 11), ele: ele);

/// A timed fix at [lat], for the fixtures that need their own spacing.
TrackPoint _at(double lat, int second, {double? ele}) => TrackPoint(
  LatLng(lat, 11),
  ele: ele,
  time: DateTime.utc(2026, 9, 12, 10, 0, second),
);

/// Length of a 0.001° step in latitude, computed rather than written out so
/// the expectations below stay exact.
final double longStepMeters = haversineMeters(
  const LatLng(48, 11),
  const LatLng(48.001, 11),
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

    test('a crawl just under 1 km/h does not count, just over does', () {
      // 1 km/h is 0.2777… m/s, so 6.94 m in 25 s. 0.00006° of latitude is
      // 6.67 m (under) and 0.00007° is 7.78 m (over); 25 s keeps both inside
      // the 30 s break.
      final slow = computeRideStats([_at(48, 0), _at(48.00006, 25)]);
      final quick = computeRideStats([_at(48, 0), _at(48.00007, 25)]);
      expect(slow.movingTime, Duration.zero);
      expect(quick.movingTime, const Duration(seconds: 25));
      expect(
        slow.distanceM,
        closeTo(0.6 * stepMeters, 0.01),
        reason: 'a crawl is still distance travelled',
      );
    });

    test('a ride with a short stop gets every number', () {
      // 111.19 m in 10 s, 10 s parked — shorter than the 30 s break, so it
      // stays part of the ride — then 111.19 m in 10 s again, 6 m up and 5 m
      // back down.
      final stats = computeRideStats([
        _at(48, 0, ele: 500),
        _at(48.001, 10, ele: 506),
        _at(48.001, 20, ele: 506),
        _at(48.002, 30, ele: 501),
      ]);
      expect(stats.distanceM, closeTo(2 * longStepMeters, 1e-6));
      expect(stats.movingTime, const Duration(seconds: 20));
      expect(stats.elapsedTime, const Duration(seconds: 30));
      expect(stats.ascentM, closeTo(6, 1e-9));
      expect(stats.descentM, closeTo(5, 1e-9));
      expect(stats.avgSpeedMps, closeTo(2 * longStepMeters / 20, 1e-6));
      expect(stats.maxSpeedMps, closeTo(longStepMeters / 10, 1e-6));
      expect(stats.startedAt, DateTime.utc(2026, 9, 12, 10));
      expect(stats.endedAt, DateTime.utc(2026, 9, 12, 10, 0, 30));
      expect(stats.hasTime, isTrue);
    });

    test('fixes without an elevation are skipped, not read as zero', () {
      final stats = computeRideStats(<TrackPoint>[
        _point(0, ele: 500),
        _point(1),
        _point(2, ele: 505),
        _point(3),
      ]);
      expect(stats.ascentM, closeTo(5, 1e-9));
      expect(stats.descentM, 0);
    });

    test('a ride without any elevation reports no climb', () {
      final stats = computeRideStats(
        List<TrackPoint>.generate(3, (i) => _point(i)),
      );
      expect(stats.ascentM, 0);
      expect(stats.descentM, 0);
      expect(stats.hasTime, isTrue);
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

  group('computeRouteGeometryStats', () {
    test('a route has distance and climb but no time at all', () {
      final stats = computeRouteGeometryStats([
        _plain(0, ele: 500),
        _plain(10, ele: 510),
      ]);
      expect(stats.distanceM, closeTo(longStepMeters, 1e-6));
      expect(stats.ascentM, closeTo(10, 1e-9));
      expect(stats.descentM, 0);
    });

    test('wobble below the hysteresis is ignored', () {
      // 500, 501, 500, 502, 499: nothing ever reaches 3 m from the anchor.
      final elevations = <double>[500, 501, 500, 502, 499];
      final stats = computeRouteGeometryStats([
        for (var i = 0; i < elevations.length; i++)
          _plain(i, ele: elevations[i]),
      ]);
      expect(stats.ascentM, 0);
      expect(stats.descentM, 0);
    });

    test('the hysteresis is configurable', () {
      final points = [_plain(0, ele: 500), _plain(1, ele: 502)];
      expect(computeRouteGeometryStats(points).ascentM, 0);
      expect(
        computeRouteGeometryStats(points, hysteresisM: 1).ascentM,
        closeTo(2, 1e-9),
      );
    });

    test('points without an elevation are skipped', () {
      final stats = computeRouteGeometryStats([
        _plain(0, ele: 500),
        _plain(1),
        _plain(2, ele: 505),
        _plain(3),
      ]);
      expect(stats.ascentM, closeTo(5, 1e-9));
      expect(stats.distanceM, closeTo(3 * stepMeters, 0.01));
    });

    test('an empty route is all zeroes rather than a crash', () {
      final stats = computeRouteGeometryStats(const <TrackPoint>[]);
      expect(stats.distanceM, 0);
      expect(stats.ascentM, 0);
      expect(stats.descentM, 0);
    });
  });

  group('computeImportedStats', () {
    test('a timed file is measured exactly like a recorded ride', () {
      // Two one-second segments with a five-minute break between them: the
      // 543 m across the break are not a ridden distance.
      final stats = computeImportedStats(<TrackPoint>[
        _at(48, 0),
        _at(48.0001, 1),
        _at(48.005, 300),
        _at(48.0051, 301),
      ]);
      expect(stats.distanceM, closeTo(2 * stepMeters, 0.01));
      expect(stats.movingTime, const Duration(seconds: 2));
      expect(stats.hasTime, isTrue);
    });

    test('a file without timestamps keeps its distance and its climb', () {
      final stats = computeImportedStats([
        _plain(0, ele: 500),
        _plain(1, ele: 504),
        _plain(2, ele: 500),
      ]);
      expect(stats.distanceM, closeTo(2 * stepMeters, 0.01));
      expect(stats.ascentM, closeTo(4, 1e-9));
      expect(stats.descentM, closeTo(4, 1e-9));
      expect(stats.movingTime, Duration.zero);
      expect(stats.elapsedTime, Duration.zero);
      expect(stats.avgSpeedMps, 0);
      expect(stats.pointCount, 3);
      expect(stats.hasTime, isFalse);
    });

    test('an empty file is all zeroes rather than a crash', () {
      expect(computeImportedStats(const <TrackPoint>[]), RideStats.empty);
    });
  });
}
