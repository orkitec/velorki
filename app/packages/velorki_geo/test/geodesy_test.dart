import 'package:test/test.dart';
import 'package:velorki_geo/velorki_geo.dart';

const munich = LatLng(48.1372, 11.5756);
const berlin = LatLng(52.5200, 13.4050);
const hamburg = LatLng(53.5511, 9.9937);

void main() {
  group('haversineMeters', () {
    test('Munich to Berlin is about 504 km', () {
      final d = haversineMeters(munich, berlin);
      expect(d, closeTo(504000, 504000 * 0.01));
    });

    test('is symmetric and zero for identical points', () {
      expect(
        haversineMeters(munich, berlin),
        closeTo(haversineMeters(berlin, munich), 1e-6),
      );
      expect(haversineMeters(munich, munich), 0);
    });

    test('one degree of latitude is about 111.2 km', () {
      final d = haversineMeters(const LatLng(0, 0), const LatLng(1, 0));
      expect(d, closeTo(111195, 100));
    });
  });

  group('bearingDegrees', () {
    test('cardinal directions', () {
      expect(
        bearingDegrees(const LatLng(0, 0), const LatLng(1, 0)),
        closeTo(0, 1e-6),
      );
      expect(
        bearingDegrees(const LatLng(0, 0), const LatLng(0, 1)),
        closeTo(90, 1e-6),
      );
      expect(
        bearingDegrees(const LatLng(0, 0), const LatLng(-1, 0)),
        closeTo(180, 1e-6),
      );
      expect(
        bearingDegrees(const LatLng(0, 0), const LatLng(0, -1)),
        closeTo(270, 1e-6),
      );
    });

    test('quadrants', () {
      final ne = bearingDegrees(munich, const LatLng(49.0, 12.5));
      final se = bearingDegrees(munich, const LatLng(47.0, 12.5));
      final sw = bearingDegrees(munich, const LatLng(47.0, 10.5));
      final nw = bearingDegrees(munich, const LatLng(49.0, 10.5));
      expect(ne, inExclusiveRange(0, 90));
      expect(se, inExclusiveRange(90, 180));
      expect(sw, inExclusiveRange(180, 270));
      expect(nw, inExclusiveRange(270, 360));
    });

    test('Munich to Berlin heads north-north-east', () {
      expect(bearingDegrees(munich, berlin), closeTo(14.2, 0.5));
    });

    test('is always normalised into [0, 360)', () {
      for (var b = 0; b < 360; b += 17) {
        final target = destinationPoint(munich, b.toDouble(), 25000);
        final back = bearingDegrees(munich, target);
        expect(back, greaterThanOrEqualTo(0));
        expect(back, lessThan(360));
      }
    });
  });

  group('destinationPoint', () {
    test('round trips through haversine and bearing', () {
      for (final bearing in [0.0, 37.5, 90.0, 175.0, 233.3, 359.9]) {
        for (final meters in [10.0, 1500.0, 42000.0, 300000.0]) {
          final target = destinationPoint(munich, bearing, meters);
          expect(
            haversineMeters(munich, target),
            closeTo(meters, meters * 1e-9 + 1e-5),
          );
          expect(bearingDegrees(munich, target), closeTo(bearing % 360, 1e-6));
        }
      }
    });

    test('zero distance returns the origin', () {
      final p = destinationPoint(hamburg, 123, 0);
      expect(p.lat, closeTo(hamburg.lat, 1e-12));
      expect(p.lon, closeTo(hamburg.lon, 1e-12));
    });

    test('normalises longitude across the antimeridian', () {
      final p = destinationPoint(const LatLng(0, 179.9), 90, 50000);
      expect(p.lon, lessThan(0));
      expect(p.lon, greaterThan(-180));
    });
  });

  group('polyline', () {
    final line = <LatLng>[
      const LatLng(48.0, 11.0),
      const LatLng(48.1, 11.0),
      const LatLng(48.1, 11.1),
    ];

    test('length is the sum of the legs', () {
      final expected =
          haversineMeters(line[0], line[1]) + haversineMeters(line[1], line[2]);
      expect(polylineLengthMeters(line), closeTo(expected, 1e-9));
    });

    test('degenerate inputs are zero', () {
      expect(polylineLengthMeters(const []), 0);
      expect(polylineLengthMeters([munich]), 0);
    });

    test('cumulative distances start at zero and end at the total', () {
      final cum = cumulativeDistancesMeters(line);
      expect(cum, hasLength(3));
      expect(cum.first, 0);
      expect(cum.last, closeTo(polylineLengthMeters(line), 1e-9));
      expect(cum[1], lessThan(cum[2]));
    });
  });

  group('LatLng', () {
    test('value equality and hashCode', () {
      expect(const LatLng(1.5, 2.5), const LatLng(1.5, 2.5));
      expect(const LatLng(1.5, 2.5).hashCode, const LatLng(1.5, 2.5).hashCode);
      expect(const LatLng(1.5, 2.5), isNot(const LatLng(2.5, 1.5)));
    });

    test('toString names the class', () {
      expect(const LatLng(1.5, 2.5).toString(), 'LatLng(1.5, 2.5)');
    });

    test('round trims to the requested precision', () {
      expect(
        const LatLng(48.137213, 11.575612).round(2),
        const LatLng(48.14, 11.58),
      );
      expect(
        const LatLng(-0.123456, 0.987654).round(4),
        const LatLng(-0.1235, 0.9877),
      );
      expect(const LatLng(48.6, -11.4).round(0), const LatLng(49.0, -11.0));
    });
  });
}
