import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/track_stats.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A point at [lat]/[lon] with the given elevation and offset from [_epoch].
TrackPoint _p({
  double lat = 48.0,
  double lon = 11.0,
  double? ele,
  int? second,
  double? speedMps,
}) => TrackPoint(
  LatLng(lat, lon),
  ele: ele,
  time: second == null ? null : _epoch.add(Duration(seconds: second)),
  speedMps: speedMps,
);

final DateTime _epoch = DateTime.utc(2026, 9, 12, 8);

/// Length of a 0.001° step in latitude, the step every fixture below uses.
/// Computed rather than written out so the expectations stay exact.
final double _latStepM = haversineMeters(
  const LatLng(48.0, 11.0),
  const LatLng(48.001, 11.0),
);

void main() {
  group('elevationChange', () {
    test('ignores wobble below the hysteresis', () {
      // 500, 501, 500, 502, 499: nothing ever reaches 3 m from the reference.
      final points = [
        _p(ele: 500),
        _p(ele: 501),
        _p(ele: 500),
        _p(ele: 502),
        _p(ele: 499),
      ];
      final change = elevationChange(points);
      expect(change.ascentM, 0);
      expect(change.descentM, 0);
    });

    test('books a climb once it passes the hysteresis, from the reference', () {
      // 500 → 502 (2 m from the reference, ignored) → 504 (4 m, booked, the
      // reference moves to 504) → 505 (1 m, ignored) → 508 (4 m, booked).
      // Total 4 + 4 = 8, and the 502 and 505 that were skipped are picked up
      // by the step that follows them rather than lost.
      final change = elevationChange([
        _p(ele: 500),
        _p(ele: 502),
        _p(ele: 504),
        _p(ele: 505),
        _p(ele: 508),
      ]);
      expect(change.ascentM, closeTo(8, 1e-9));
      expect(change.descentM, 0);
    });

    test('a peak books the climb and then the fall from the new reference', () {
      // Up 500 → 510 in one step: 10 m ascent, reference 510.
      // Down to 508: 2 m, ignored. Down to 504: 6 m from 510, booked.
      final change = elevationChange([
        _p(ele: 500),
        _p(ele: 510),
        _p(ele: 508),
        _p(ele: 504),
      ]);
      expect(change.ascentM, closeTo(10, 1e-9));
      expect(change.descentM, closeTo(6, 1e-9));
    });

    test('the hysteresis is configurable', () {
      final points = [_p(ele: 500), _p(ele: 502)];
      expect(elevationChange(points).ascentM, 0);
      expect(elevationChange(points, hysteresisM: 1).ascentM, closeTo(2, 1e-9));
    });

    test('points without an elevation are skipped', () {
      final change = elevationChange([_p(ele: 500), _p(), _p(ele: 505), _p()]);
      expect(change.ascentM, closeTo(5, 1e-9));
    });

    test('a track without any elevation reports nothing', () {
      final change = elevationChange([_p(), _p(), _p()]);
      expect(change.ascentM, 0);
      expect(change.descentM, 0);
    });
  });

  group('movingTimeOf', () {
    test('drops the segments below 1 km/h', () {
      // Three 10 s segments: 111 m (40 km/h), 0 m (parked), 111 m again.
      final points = [
        _p(lat: 48.000, second: 0),
        _p(lat: 48.001, second: 10),
        _p(lat: 48.001, second: 20),
        _p(lat: 48.002, second: 30),
      ];
      expect(movingTimeOf(points), const Duration(seconds: 20));
      expect(elapsedTimeOf(points), const Duration(seconds: 30));
    });

    test('a crawl just under 1 km/h does not count, just over does', () {
      // 1 km/h is 0.2777… m/s. Over 100 s that is 27.78 m; 0.00024° of
      // latitude is 26.7 m (under) and 0.00026° is 28.9 m (over).
      final slow = [_p(lat: 48.0, second: 0), _p(lat: 48.00024, second: 100)];
      final quick = [_p(lat: 48.0, second: 0), _p(lat: 48.00026, second: 100)];
      expect(movingTimeOf(slow), Duration.zero);
      expect(movingTimeOf(quick), const Duration(seconds: 100));
    });

    test('a track without timestamps has no moving time', () {
      expect(movingTimeOf([_p(lat: 48.0), _p(lat: 48.1)]), Duration.zero);
    });

    test('a backwards or zero time step is skipped, not taken as instant', () {
      final points = [
        _p(lat: 48.0, second: 10),
        _p(lat: 48.001, second: 10),
        _p(lat: 48.002, second: 5),
        _p(lat: 48.003, second: 15),
      ];
      expect(movingTimeOf(points), const Duration(seconds: 10));
    });
  });

  group('maxSpeedOf', () {
    test('trusts the reported speed when the points carry one', () {
      final points = [
        _p(lat: 48.0, second: 0, speedMps: 5),
        _p(lat: 48.1, second: 1, speedMps: 9),
        _p(lat: 48.2, second: 2, speedMps: 7),
      ];
      expect(maxSpeedOf(points), 9);
    });

    test('falls back to the segment speeds', () {
      // 111.19 m in 10 s, then in 5 s.
      final points = [
        _p(lat: 48.000, second: 0),
        _p(lat: 48.001, second: 10),
        _p(lat: 48.002, second: 15),
      ];
      expect(maxSpeedOf(points), closeTo(_latStepM / 5, 1e-6));
    });
  });

  group('computeTrackStats', () {
    test('a recorded ride gets every number', () {
      // Four points 111.19 m apart: 10 s riding, 60 s parked, 10 s riding.
      final points = [
        _p(lat: 48.000, ele: 500, second: 0),
        _p(lat: 48.001, ele: 506, second: 10),
        _p(lat: 48.001, ele: 506, second: 70),
        _p(lat: 48.002, ele: 501, second: 80),
      ];
      final stats = computeTrackStats(points);

      expect(stats.distanceM, closeTo(2 * _latStepM, 1e-6));
      expect(stats.movingTime, const Duration(seconds: 20));
      expect(stats.elapsedTime, const Duration(seconds: 80));
      expect(stats.ascentM, closeTo(6, 1e-9));
      expect(stats.descentM, closeTo(5, 1e-9));
      expect(stats.avgSpeedMps, closeTo(2 * _latStepM / 20, 1e-6));
      expect(stats.maxSpeedMps, closeTo(_latStepM / 10, 1e-6));
      expect(stats.startedAt, _epoch);
      expect(stats.endedAt, _epoch.add(const Duration(seconds: 80)));
      expect(stats.hasTime, isTrue);
    });

    test('a planned route has distance and climb but no time', () {
      final stats = computeTrackStats([
        _p(lat: 48.000, ele: 500),
        _p(lat: 48.001, ele: 510),
      ]);
      expect(stats.distanceM, closeTo(_latStepM, 1e-6));
      expect(stats.ascentM, closeTo(10, 1e-9));
      expect(stats.movingTime, Duration.zero);
      expect(stats.elapsedTime, Duration.zero);
      expect(stats.avgSpeedMps, 0);
      expect(stats.hasTime, isFalse);
    });

    test('an empty track is all zeroes rather than a crash', () {
      expect(computeTrackStats(const []), same(TrackStats.empty));
    });
  });
}
