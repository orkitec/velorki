import 'package:test/test.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  const box = BoundingBox(south: 48.0, west: 11.0, north: 48.2, east: 11.4);

  group('fromPoints', () {
    test('spans every point', () {
      final b = BoundingBox.fromPoints(const [
        LatLng(48.1, 11.3),
        LatLng(47.9, 11.5),
        LatLng(48.4, 11.1),
      ]);
      expect(b.south, 47.9);
      expect(b.north, 48.4);
      expect(b.west, 11.1);
      expect(b.east, 11.5);
    });

    test('a single point gives a degenerate box that contains it', () {
      const p = LatLng(48.1, 11.3);
      final b = BoundingBox.fromPoints(const [p]);
      expect(b.latSpan, 0);
      expect(b.lonSpan, 0);
      expect(b.contains(p), isTrue);
    });

    test('rejects an empty list', () {
      expect(() => BoundingBox.fromPoints(const []), throwsArgumentError);
    });
  });

  group('contains', () {
    test('inside, on the edge, outside', () {
      expect(box.contains(const LatLng(48.1, 11.2)), isTrue);
      expect(box.contains(const LatLng(48.0, 11.0)), isTrue);
      expect(box.contains(const LatLng(48.2, 11.4)), isTrue);
      expect(box.contains(const LatLng(47.9, 11.2)), isFalse);
      expect(box.contains(const LatLng(48.1, 11.5)), isFalse);
    });
  });

  group('intersects', () {
    test('overlapping, touching, disjoint', () {
      expect(
        box.intersects(
          const BoundingBox(south: 48.1, west: 11.3, north: 49.0, east: 12.0),
        ),
        isTrue,
      );
      expect(
        box.intersects(
          const BoundingBox(south: 48.2, west: 11.4, north: 49.0, east: 12.0),
        ),
        isTrue,
      );
      expect(
        box.intersects(
          const BoundingBox(south: 49.0, west: 11.0, north: 50.0, east: 12.0),
        ),
        isFalse,
      );
    });

    test('is symmetric and reflexive', () {
      const other = BoundingBox(
        south: 48.1,
        west: 10.0,
        north: 48.15,
        east: 11.1,
      );
      expect(box.intersects(other), other.intersects(box));
      expect(box.intersects(box), isTrue);
    });
  });

  group('expandMeters', () {
    test('grows by roughly the requested distance', () {
      final grown = box.expandMeters(1000);
      final southShift = haversineMeters(
        LatLng(box.south, box.west),
        LatLng(grown.south, box.west),
      );
      expect(southShift, closeTo(1000, 1));
      final westShift = haversineMeters(
        LatLng(box.south, box.west),
        LatLng(box.south, grown.west),
      );
      expect(westShift, greaterThan(900));
    });

    test('the original box stays inside the grown one', () {
      final grown = box.expandMeters(500);
      expect(grown.contains(box.southWest), isTrue);
      expect(grown.contains(box.northEast), isTrue);
    });

    test('clamps at the poles and the antimeridian', () {
      const polar = BoundingBox(
        south: 89.9,
        west: 179.9,
        north: 89.95,
        east: 179.95,
      );
      final grown = polar.expandMeters(100000);
      expect(grown.north, lessThanOrEqualTo(90.0));
      expect(grown.east, lessThanOrEqualTo(180.0));
    });
  });

  group('expandFraction', () {
    test('adds a fraction of the span on each side', () {
      final grown = box.expandFraction(0.5);
      expect(grown.south, closeTo(48.0 - 0.1, 1e-12));
      expect(grown.north, closeTo(48.2 + 0.1, 1e-12));
      expect(grown.west, closeTo(11.0 - 0.2, 1e-12));
      expect(grown.east, closeTo(11.4 + 0.2, 1e-12));
    });

    test('a degenerate box still gains area', () {
      const point = BoundingBox(
        south: 48.0,
        west: 11.0,
        north: 48.0,
        east: 11.0,
      );
      final grown = point.expandFraction(0.25);
      expect(grown.latSpan, closeTo(0.5, 1e-12));
      expect(grown.lonSpan, closeTo(0.5, 1e-12));
    });
  });

  test('union, centre and value equality', () {
    const other = BoundingBox(south: 47.0, west: 12.0, north: 48.1, east: 12.5);
    final u = box.union(other);
    expect(
      u,
      const BoundingBox(south: 47.0, west: 11.0, north: 48.2, east: 12.5),
    );
    expect(box.center.lat, closeTo(48.1, 1e-12));
    expect(box.center.lon, closeTo(11.2, 1e-12));
    expect(
      box,
      const BoundingBox(south: 48.0, west: 11.0, north: 48.2, east: 11.4),
    );
    expect(
      box.hashCode,
      const BoundingBox(
        south: 48.0,
        west: 11.0,
        north: 48.2,
        east: 11.4,
      ).hashCode,
    );
    expect(box.toString(), contains('48.2'));
  });
}
