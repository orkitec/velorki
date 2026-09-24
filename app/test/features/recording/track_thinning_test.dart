import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/track_thinning.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// [count] fixes [stepM] apart, heading [bearingDeg] from [from].
List<TrackPoint> _leg(
  LatLng from,
  double bearingDeg,
  int count,
  double stepM,
) => <TrackPoint>[
  for (var i = 1; i <= count; i++)
    TrackPoint(destinationPoint(from, bearingDeg, i * stepM)),
];

/// A straight line of [lengthM] north, one fix every [stepM].
List<TrackPoint> _straight(double lengthM, {double stepM = 5}) => <TrackPoint>[
  const TrackPoint(LatLng(48, 11)),
  ..._leg(const LatLng(48, 11), 0, (lengthM / stepM).round(), stepM),
];

/// [legs] legs of 50 m, alternating north and east, ten fixes a leg.
List<TrackPoint> _zigzag(int legs) {
  var at = const LatLng(48, 11);
  final points = <TrackPoint>[TrackPoint(at)];
  for (var leg = 0; leg < legs; leg++) {
    final legPoints = _leg(at, leg.isEven ? 0 : 90, 10, 5);
    points.addAll(legPoints);
    at = legPoints.last.pos;
  }
  return points;
}

/// Whether [p] is within [m] metres of one of [points].
bool _near(List<LatLng> points, LatLng p, {double m = 8}) =>
    points.any((q) => haversineMeters(p, q) <= m);

void main() {
  test('an empty track thins to nothing, one or two fixes to themselves', () {
    expect(thinTrack(const <TrackPoint>[]), isEmpty);
    expect(thinTrack(const [TrackPoint(LatLng(48, 11))]), [
      const LatLng(48, 11),
    ]);
    expect(
      thinTrack(const [
        TrackPoint(LatLng(48, 11)),
        TrackPoint(LatLng(48.01, 11)),
      ]),
      [const LatLng(48, 11), const LatLng(48.01, 11)],
    );
  });

  test('a straight track keeps both ends and a point every 250 m', () {
    final points = _straight(3000);
    final thinned = thinTrack(points);

    expect(thinned.first, points.first.pos);
    expect(thinned.last, points.last.pos);
    // 11 spaced points between the ends, plus the ends.
    expect(thinned.length, 13);
    for (var i = 1; i < thinned.length - 1; i++) {
      expect(
        haversineMeters(thinned[i - 1], thinned[i]),
        inInclusiveRange(250, 256),
      );
    }
  });

  test('a corner between two spaced points is kept', () {
    // 100 m north, a right angle, 100 m east: neither leg is long enough for
    // a spaced point, the bend is kept all the same.
    const start = LatLng(48, 11);
    final north = _leg(start, 0, 20, 5);
    final corner = north.last.pos;
    final points = <TrackPoint>[
      const TrackPoint(start),
      ...north,
      ..._leg(corner, 90, 20, 5),
    ];

    final thinned = thinTrack(points);

    expect(thinned.length, 3);
    expect(_near(thinned, corner), isTrue);
  });

  test('a gentle bend is not a corner', () {
    const start = LatLng(48, 11);
    final first = _leg(start, 0, 20, 5);
    final points = <TrackPoint>[
      const TrackPoint(start),
      ...first,
      ..._leg(first.last.pos, 20, 20, 5),
    ];

    expect(thinTrack(points).length, 2);
  });

  test('a wiggle shorter than the turn span is not a corner', () {
    // A GPS blip: two fixes 5 m off the line and back. The headings over 30 m
    // on either side of it are still north.
    final points = _straight(200);
    final blip = points[20].pos;
    points[20] = TrackPoint(destinationPoint(blip, 90, 5));
    points[21] = TrackPoint(destinationPoint(points[21].pos, 90, 5));

    expect(thinTrack(points).length, 2);
  });

  test('more than maxPoints raises the spacing until the cap holds', () {
    final points = _straight(30000, stepM: 10);
    final thinned = thinTrack(points, maxPoints: 40);

    expect(thinned.length, lessThanOrEqualTo(40));
    expect(thinned.length, greaterThan(30));
    expect(thinned.first, points.first.pos);
    expect(thinned.last, points.last.pos);
  });

  test('every bend of a zigzag is one corner', () {
    // 150 legs of 50 m at right angles: 149 bends, no leg long enough for a
    // spaced point.
    final points = _zigzag(150);

    final thinned = thinTrack(points);

    expect(thinned.length, 151);
    expect(thinned.first, points.first.pos);
    expect(thinned.last, points.last.pos);
    // The apex of each bend, not a fix beside it.
    for (var leg = 1; leg < 150; leg++) {
      expect(_near(thinned, points[leg * 10].pos, m: 0.5), isTrue);
    }
  });

  test('the cap thins corners like any other point', () {
    final points = _zigzag(150);

    final capped = thinTrack(points, maxPoints: 30);

    expect(capped.length, lessThanOrEqualTo(30));
    // 7.5 km over 29 gaps is a point every 259 m, so nearly the cap.
    expect(capped.length, greaterThan(20));
    expect(capped.first, points.first.pos);
    expect(capped.last, points.last.pos);
  });
}
