import 'dart:math' as math;

/// The shortest stretch a gradient is taken over, in metres: the tiles'
/// heights come from a terrain model, which over a few metres is noise.
const double climbWindowMetres = 30;

/// A link shorter than this is too short to say anything about its slope.
const double climbMinimumMetres = 20;

/// The grade class of a slope: 1 from 6 %, 2 from 10 %, 3 from 15 %, else 0.
int gradeClass(double grade) {
  final g = grade.abs();
  return g >= 0.15
      ? 3
      : g >= 0.10
      ? 2
      : g >= 0.06
      ? 1
      : 0;
}

/// The steep pieces along a line through [coords] (BRouter's integer
/// longitude and latitude in turn) with heights [elevations] in quarter
/// metres, one per point: each handed to [emit] with its points from the
/// foot uphill and its grade class.
///
/// The slope is taken over stretches of at least [climbWindowMetres]; one
/// shorter left at the end joins the stretch before it. Stretches next to
/// each other with the same class and the same sense make one piece.
void findClimbs(
  List<int> coords,
  List<int> elevations,
  void Function(List<int> coords, int grade) emit,
) {
  final n = elevations.length;
  if (n < 2 || coords.length != n * 2) return;
  final lat = (coords[1] / 1e6 - 90) * math.pi / 180;
  final mPerLon = 0.11132 * math.cos(lat);
  const mPerLat = 0.110574;
  final along = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    final dx = (coords[i * 2] - coords[i * 2 - 2]) * mPerLon;
    final dy = (coords[i * 2 + 1] - coords[i * 2 - 1]) * mPerLat;
    along[i] = along[i - 1] + math.sqrt(dx * dx + dy * dy);
  }
  if (along[n - 1] < climbMinimumMetres) return;

  // The stretches, as indices of their first and last point.
  final ends = <int>[0];
  var from = 0;
  for (var i = 1; i < n; i++) {
    if (along[i] - along[from] >= climbWindowMetres - 0.5) {
      ends.add(i);
      from = i;
    }
  }
  if (ends.last != n - 1) {
    if (ends.length > 1) {
      ends[ends.length - 1] = n - 1; // the short rest joins the one before
    } else {
      ends.add(n - 1);
    }
  }

  var pieceStart = -1;
  var pieceClass = 0;
  var pieceUp = true;
  void flush(int end) {
    if (pieceStart < 0 || pieceClass == 0) return;
    final points = <int>[];
    if (pieceUp) {
      for (var i = pieceStart; i <= end; i++) {
        points
          ..add(coords[i * 2])
          ..add(coords[i * 2 + 1]);
      }
    } else {
      for (var i = end; i >= pieceStart; i--) {
        points
          ..add(coords[i * 2])
          ..add(coords[i * 2 + 1]);
      }
    }
    emit(points, pieceClass);
  }

  for (var w = 1; w < ends.length; w++) {
    final a = ends[w - 1];
    final b = ends[w];
    final rise = (elevations[b] - elevations[a]) / 4;
    final grade = rise / math.max(along[b] - along[a], 1e-6);
    final cls = gradeClass(grade);
    final up = rise >= 0;
    if (cls == pieceClass && up == pieceUp && pieceStart >= 0) continue;
    flush(a);
    pieceStart = a;
    pieceClass = cls;
    pieceUp = up;
  }
  flush(n - 1);
}
