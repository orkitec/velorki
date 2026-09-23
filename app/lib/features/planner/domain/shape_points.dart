import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

/// How many via points a shaped route gets at most.
const int maxShapePoints = 20;

/// Points along [track] that hold its shape when the planner routes through
/// them: the two ends and at most [maxVia] points between, fewer on a short
/// track (one per 500 m), the ones Douglas-Peucker ranks as holding the
/// shape best.
///
/// For a route that was imported rather than planned, whose saved
/// waypoints are only its ends: opened in the planner as they are, the
/// first edit would route start to end and lose the course the file came
/// with.
List<LatLng> shapePoints(List<LatLng> track, {int maxVia = maxShapePoints}) {
  if (track.length <= 2) return List<LatLng>.of(track);
  final lengthM = polylineLengthMeters(track);
  final cap = math.min(maxVia, math.max(1, (lengthM / 500).round()));
  // Every point ranked by how far the track would stray without it, and
  // the highest-ranked ones kept, in track order: a tolerance searched
  // for instead could drop a whole zigzag at once.
  final rank = _douglasPeuckerRank(_project(track));
  final ranked = <int>[
    for (final entry in rank.entries)
      if (entry.value >= minShapeDeviationM) entry.key,
  ]..sort((a, b) => rank[b]!.compareTo(rank[a]!));
  final keep = <int>{0, track.length - 1, ...ranked.take(cap)}.toList()..sort();
  return <LatLng>[for (final i in keep) track[i]];
}

/// A point that keeps the track from straying less than this is noise.
const double minShapeDeviationM = 5;

/// The indices of [track] that Douglas-Peucker keeps at [toleranceM]
/// metres, in track order, both ends always among them.
List<int> douglasPeuckerIndices(List<LatLng> track, double toleranceM) {
  if (track.length <= 2) return [for (var i = 0; i < track.length; i++) i];
  final keep = <int>[
    0,
    for (final entry in _douglasPeuckerRank(_project(track)).entries)
      if (entry.value > toleranceM) entry.key,
    track.length - 1,
  ]..sort();
  return keep;
}

/// Metres in a local equirectangular projection around the track's first
/// point, exact enough over the tens of kilometres a route spans.
List<_XY> _project(List<LatLng> track) {
  final cosLat = math.cos(track.first.latRad);
  return <_XY>[
    for (final p in track) _XY(p.lon * 111320 * cosLat, p.lat * 110540),
  ];
}

class _XY {
  const _XY(this.x, this.y);

  final double x;
  final double y;
}

/// Douglas-Peucker run to the end: for every inner point, how far the
/// track strays from the line between its neighbours in the simplification
/// at the moment the point is picked. The larger, the more the point holds
/// the shape; a point is picked after every point that ranks above it.
Map<int, double> _douglasPeuckerRank(List<_XY> points) {
  final rank = <int, double>{};
  void split(int first, int last) {
    var farthest = -1;
    var farthestDistance = 0.0;
    for (var i = first + 1; i < last; i++) {
      final d = _distanceToSegment(points[i], points[first], points[last]);
      if (d > farthestDistance) {
        farthestDistance = d;
        farthest = i;
      }
    }
    if (farthest < 0) return;
    rank[farthest] = farthestDistance;
    split(first, farthest);
    split(farthest, last);
  }

  split(0, points.length - 1);
  return rank;
}

double _distanceToSegment(_XY p, _XY a, _XY b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final lengthSq = dx * dx + dy * dy;
  var t = 0.0;
  if (lengthSq > 0) {
    t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq).clamp(0.0, 1.0);
  }
  final cx = a.x + t * dx;
  final cy = a.y + t * dy;
  return math.sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy));
}
