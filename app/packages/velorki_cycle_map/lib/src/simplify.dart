import 'dart:math' as math;
import 'dart:typed_data';

/// The points of a line to keep so that it strays no more than [tolerance]
/// micro-degrees (of latitude) from the original: Douglas-Peucker over the
/// points [from] to [to] (exclusive) of [coords], longitude and latitude in
/// turn. Longitudes are scaled by [lonScale], the cosine of the latitude,
/// so the tolerance is the same distance both ways.
///
/// Writes the kept point indices into [keep] and returns how many; the
/// first and the last point are always kept.
int simplifyLine(
  Int32List coords,
  int from,
  int to,
  double tolerance,
  double lonScale,
  Int32List keep,
  List<int> stack,
) {
  final count = to - from;
  if (count <= 2 || tolerance <= 0) {
    for (var i = 0; i < count; i++) {
      keep[i] = from + i;
    }
    return count;
  }
  final marked = Uint8List(count);
  marked[0] = 1;
  marked[count - 1] = 1;
  final tol2 = tolerance * tolerance;
  stack
    ..clear()
    ..add(from)
    ..add(to - 1);
  while (stack.isNotEmpty) {
    final last = stack.removeLast();
    final first = stack.removeLast();
    final ax = coords[first * 2] * lonScale;
    final ay = coords[first * 2 + 1].toDouble();
    final dx = coords[last * 2] * lonScale - ax;
    final dy = coords[last * 2 + 1] - ay;
    final len2 = dx * dx + dy * dy;
    var worst = -1.0;
    var worstAt = -1;
    for (var i = first + 1; i < last; i++) {
      final px = coords[i * 2] * lonScale - ax;
      final py = coords[i * 2 + 1] - ay;
      double d2;
      if (len2 == 0) {
        d2 = px * px + py * py;
      } else {
        final t = math.max(0.0, math.min(1.0, (px * dx + py * dy) / len2));
        final ex = px - t * dx;
        final ey = py - t * dy;
        d2 = ex * ex + ey * ey;
      }
      if (d2 > worst) {
        worst = d2;
        worstAt = i;
      }
    }
    if (worst > tol2) {
      marked[worstAt - from] = 1;
      stack
        ..add(first)
        ..add(worstAt)
        ..add(worstAt)
        ..add(last);
    }
  }
  var k = 0;
  for (var i = 0; i < count; i++) {
    if (marked[i] != 0) keep[k++] = from + i;
  }
  return k;
}

/// The simplification tolerance at [zoom], in micro-degrees of latitude:
/// half a screen pixel of a 512-pixel tile, none from zoom 16 on, where a
/// way's every bend shows.
double toleranceAtZoom(int zoom, double latitude) {
  if (zoom >= 16) return 0;
  final metresPerPixel =
      40075016.686 * math.cos(latitude * math.pi / 180) / (512 << zoom);
  return 0.5 * metresPerPixel / 0.111195;
}
