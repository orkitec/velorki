import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

/// Index of the polyline segment of [points] that [p] lies closest to.
///
/// Returns the index `i` of the segment `points[i] → points[i + 1]`, so the
/// caller inserts a via point at `i + 1`. Returns `0` for fewer than two
/// points.
///
/// Distances are measured in a local equirectangular projection around [p],
/// which is exact enough over the few kilometres a drag or a long press can
/// span and costs no trigonometry per candidate segment.
int nearestSegmentIndex(List<LatLng> points, LatLng p) {
  if (points.length < 2) return 0;
  final cosLat = math.cos(p.latRad);
  double x(LatLng a) => a.lon * cosLat;
  double y(LatLng a) => a.lat;

  final px = x(p);
  final py = y(p);

  var best = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < points.length - 1; i++) {
    final ax = x(points[i]);
    final ay = y(points[i]);
    final bx = x(points[i + 1]);
    final by = y(points[i + 1]);
    final dx = bx - ax;
    final dy = by - ay;
    final lengthSq = dx * dx + dy * dy;
    double t;
    if (lengthSq <= 0) {
      t = 0;
    } else {
      t = ((px - ax) * dx + (py - ay) * dy) / lengthSq;
      t = t.clamp(0.0, 1.0);
    }
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    final distance = (px - cx) * (px - cx) + (py - cy) * (py - cy);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = i;
    }
  }
  return best;
}
