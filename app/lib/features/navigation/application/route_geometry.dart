import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

/// A waypoint nearer than this to the end of the route is the end of the
/// route, and is not asked for twice.
const double _sameSpotM = 10;

/// Where a point sits in relation to a route line.
class LineProjection {
  /// Creates a projection.
  const LineProjection({required this.distanceM, required this.alongM});

  /// How far the point is from the line, in metres.
  final double distanceM;

  /// How far along the line the nearest point of the line is, in metres.
  final double alongM;

  @override
  String toString() =>
      'LineProjection(${distanceM.toStringAsFixed(0)} m from the line, '
      '${alongM.toStringAsFixed(0)} m along)';
}

/// Distance from the start of [line] to each of its points.
List<double> cumulativeDistances(List<LatLng> line) {
  final out = List<double>.filled(line.length, 0);
  for (var i = 1; i < line.length; i++) {
    out[i] = out[i - 1] + haversineMeters(line[i - 1], line[i]);
  }
  return out;
}

/// Projects [point] onto [line], searching the whole line.
///
/// The same flat-earth segment maths the turn navigator snaps a fix with, but
/// without its window around the last match: this answers the odd question
/// about a route the rider is not currently being matched against, where there
/// is no last match to start from.
LineProjection projectOnLine(
  List<LatLng> line,
  LatLng point, {
  List<double>? cumulative,
}) {
  if (line.isEmpty) {
    return const LineProjection(distanceM: double.infinity, alongM: 0);
  }
  if (line.length == 1) {
    return LineProjection(
      distanceM: haversineMeters(point, line.first),
      alongM: 0,
    );
  }
  final cum = cumulative ?? cumulativeDistances(line);
  var bestDistance = double.infinity;
  var bestAlong = 0.0;
  for (var i = 0; i < line.length - 1; i++) {
    final a = line[i];
    final b = line[i + 1];
    final kx = math.cos(a.lat * math.pi / 180);
    final abx = (b.lon - a.lon) * kx;
    final aby = b.lat - a.lat;
    final apx = (point.lon - a.lon) * kx;
    final apy = point.lat - a.lat;
    final lengthSquared = abx * abx + aby * aby;
    final t = lengthSquared == 0
        ? 0.0
        : ((apx * abx + apy * aby) / lengthSquared).clamp(0.0, 1.0);
    final snapped = LatLng(
      a.lat + (b.lat - a.lat) * t,
      a.lon + (b.lon - a.lon) * t,
    );
    final distance = haversineMeters(point, snapped);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestAlong = cum[i] + (cum[i + 1] - cum[i]) * t;
    }
  }
  return LineProjection(distanceM: bestDistance, alongM: bestAlong);
}

/// The points a re-route still has to visit, given that the rider last stood
/// [alongM] metres along [line].
///
/// A waypoint counts as done once its place on the line is behind the rider,
/// so a detour heads for the rest of the plan rather than back to a corner
/// that was already ridden. The end of the line is always the last point: a
/// plan with no stored waypoints — a GPX import, say — is guided to its end
/// and nowhere else.
List<LatLng> remainingWaypoints(
  List<LatLng> line,
  List<LatLng> waypoints,
  double alongM,
) {
  if (line.isEmpty) return List<LatLng>.of(waypoints);
  final cumulative = cumulativeDistances(line);
  final ahead = <LatLng>[
    for (final waypoint in waypoints)
      if (projectOnLine(line, waypoint, cumulative: cumulative).alongM > alongM)
        waypoint,
  ];
  // The end of the plan is where the ride is going, whether or not it was
  // stored as a waypoint; a waypoint sitting on it is not asked for twice.
  if (ahead.isEmpty || haversineMeters(ahead.last, line.last) > _sameSpotM) {
    ahead.add(line.last);
  }
  return ahead;
}
