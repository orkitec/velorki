import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/domain/shape_points.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A wiggly track of [n] points heading north over about [n] * 50 m, with a
/// zigzag of [amplitude] degrees of longitude.
List<LatLng> _track(int n, {double amplitude = 0.002}) => <LatLng>[
  for (var i = 0; i < n; i++)
    LatLng(48 + i * 0.00045, 11 + (i.isEven ? 0 : amplitude) * (i % 3)),
];

void main() {
  group('shapePoints', () {
    test('keeps both ends and stays within the cap on a long track', () {
      final track = _track(400);
      final shape = shapePoints(track);
      expect(shape.first, track.first);
      expect(shape.last, track.last);
      expect(shape.length, lessThanOrEqualTo(maxShapePoints + 2));
      expect(shape.length, greaterThan(2));
      // Every point is one of the track's own.
      for (final p in shape) {
        expect(track, contains(p));
      }
      // In track order.
      var last = -1;
      for (final p in shape) {
        final i = track.indexOf(p);
        expect(i, greaterThan(last));
        last = i;
      }
    });

    test('a short track gets fewer points, about one per 500 m', () {
      final track = _track(40, amplitude: 0.0002);
      final lengthM = polylineLengthMeters(track);
      expect(lengthM, lessThan(3000), reason: 'a short track');
      final shape = shapePoints(track);
      expect(shape.first, track.first);
      expect(shape.last, track.last);
      expect(shape.length, lessThanOrEqualTo((lengthM / 500).round() + 2));
      expect(shape.length, greaterThan(2));
    });

    test('two points or fewer come back as they are', () {
      const two = [LatLng(48, 11), LatLng(48.1, 11.1)];
      expect(shapePoints(two), two);
      expect(shapePoints(const <LatLng>[]), isEmpty);
    });

    test('a straight track needs no points between its ends', () {
      final straight = <LatLng>[
        for (var i = 0; i < 100; i++) LatLng(48 + i * 0.001, 11),
      ];
      expect(shapePoints(straight), [straight.first, straight.last]);
    });
  });
}
