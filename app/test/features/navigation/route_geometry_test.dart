import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/application/route_geometry.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// One degree of latitude, the same figure the recording fakes use.
const double _metresPerDegree = 111194.9266;

/// One degree of longitude at 48°.
final double _metresPerDegreeEast =
    _metresPerDegree * math.cos(48 * math.pi / 180);

/// A point [alongM] north of 48°/11° and [asideM] east of it.
LatLng _at(double alongM, {double asideM = 0}) =>
    LatLng(48 + alongM / _metresPerDegree, 11 + asideM / _metresPerDegreeEast);

/// A straight kilometre north, a point every 100 m.
List<LatLng> _line() => <LatLng>[for (var i = 0; i <= 10; i++) _at(i * 100.0)];

void main() {
  test('the cumulative distances follow the line', () {
    final cumulative = cumulativeDistances(_line());

    expect(cumulative.first, 0);
    expect(cumulative[5], closeTo(500, 2));
    expect(cumulative.last, closeTo(1000, 2));
  });

  test('a point beside the line projects onto it', () {
    final projection = projectOnLine(_line(), _at(450, asideM: 40));

    expect(projection.distanceM, closeTo(40, 2));
    expect(projection.alongM, closeTo(450, 2));
  });

  test('a point on the line is on the line', () {
    final projection = projectOnLine(_line(), _at(300));

    expect(projection.distanceM, lessThan(1));
    expect(projection.alongM, closeTo(300, 2));
  });

  test('an empty line is infinitely far away', () {
    final projection = projectOnLine(const <LatLng>[], _at(0));

    expect(projection.distanceM, double.infinity);
    expect(projection.alongM, 0);
  });

  test('only the waypoints ahead of the rider are still to be visited', () {
    final waypoints = <LatLng>[_at(0), _at(300), _at(700), _at(1000)];

    final remaining = remainingWaypoints(_line(), waypoints, 400);

    expect(remaining, <LatLng>[_at(700), _at(1000)]);
  });

  test('a rider past every waypoint is still sent to the end', () {
    final waypoints = <LatLng>[_at(0), _at(300)];

    final remaining = remainingWaypoints(_line(), waypoints, 900);

    expect(remaining, <LatLng>[_at(1000)]);
  });

  test('a plan with no waypoints is guided to its end alone', () {
    final remaining = remainingWaypoints(_line(), const <LatLng>[], 0);

    expect(remaining, <LatLng>[_at(1000)]);
  });

  test('the last waypoint is not asked for twice', () {
    final waypoints = <LatLng>[_at(0), _at(600), _at(1000)];

    final remaining = remainingWaypoints(_line(), waypoints, 100);

    expect(remaining, <LatLng>[_at(600), _at(1000)]);
  });

  test('a waypoint beside the line counts by where it projects', () {
    final waypoints = <LatLng>[_at(200, asideM: 60), _at(1000)];

    expect(remainingWaypoints(_line(), waypoints, 100), <LatLng>[
      _at(200, asideM: 60),
      _at(1000),
    ]);
    expect(remainingWaypoints(_line(), waypoints, 300), <LatLng>[_at(1000)]);
  });
}
