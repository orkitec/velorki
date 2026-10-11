import 'dart:math' as math;

/// How steep pieces are found in a profile of heights: the tiles' heights
/// come from a terrain model which, in cities, has the buildings in it, so
/// a profile is smoothed along the way first and a climb has to keep going
/// for a while to count.
final class ClimbRule {
  /// A rule.
  const ClimbRule({
    this.smoothMetres = 150,
    this.measureSmoothMetres = 25,
    this.windowMetres = 40,
    this.minLengthMetres = 150,
    this.minRiseMetres = 10,
    this.detectGrade = 0.05,
  });

  /// The spread of the smoothing a climb is found with (a Gaussian's
  /// sigma along the way), in metres: wide enough to flatten a block's
  /// buildings; 0 for none.
  final double smoothMetres;

  /// The lighter smoothing a found climb is measured with, so its grade is
  /// the street's and not the wide average's.
  final double measureSmoothMetres;

  /// The grade a stretch of the widely smoothed profile needs to belong to
  /// a climb.
  final double detectGrade;

  /// The shortest stretch a gradient is taken over.
  final double windowMetres;

  /// The shortest run of steep stretches that counts as a climb.
  final double minLengthMetres;

  /// The least height a run has to gain or lose to count.
  final double minRiseMetres;

  /// What the map uses.
  static const ClimbRule standard = ClimbRule();
}

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
/// Climbs are found on the heights smoothed widely along the line
/// ([ClimbRule.smoothMetres]): stretches of at least
/// [ClimbRule.windowMetres] (one shorter left at the end joins the one
/// before) at [ClimbRule.detectGrade] or more, in runs going the same way
/// that are long enough and gain or lose enough height. A run is then
/// measured on the lightly smoothed heights: its stretches next to each
/// other with the same grade class make one piece.
void findClimbs(
  List<int> coords,
  List<int> elevations,
  void Function(List<int> coords, int grade) emit, {
  ClimbRule rule = ClimbRule.standard,
}) {
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
  if (along[n - 1] < rule.minLengthMetres) return;

  final heights = _smoothed(along, elevations, rule.smoothMetres);
  final measured = _smoothed(along, elevations, rule.measureSmoothMetres);

  // The stretches, as indices of their first and last point.
  final ends = <int>[0];
  var from = 0;
  for (var i = 1; i < n; i++) {
    if (along[i] - along[from] >= rule.windowMetres - 0.5) {
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
  final stretches = ends.length - 1;
  final steep = List<bool>.filled(stretches, false);
  final classes = List<int>.filled(stretches, 0);
  final up = List<bool>.filled(stretches, true);
  for (var w = 0; w < stretches; w++) {
    final a = ends[w];
    final b = ends[w + 1];
    final length = math.max(along[b] - along[a], 1e-6);
    final rise = heights[b] - heights[a];
    steep[w] = rise.abs() / length >= rule.detectGrade;
    up[w] = rise >= 0;
    final measuredRise = measured[b] - measured[a];
    // A stretch measured against the run's way counts as flat in it.
    classes[w] = (measuredRise >= 0) == up[w]
        ? gradeClass(measuredRise / length)
        : 0;
  }

  void emitPiece(int a, int b, int cls, bool goingUp) {
    final points = <int>[];
    if (goingUp) {
      for (var i = a; i <= b; i++) {
        points
          ..add(coords[i * 2])
          ..add(coords[i * 2 + 1]);
      }
    } else {
      for (var i = b; i >= a; i--) {
        points
          ..add(coords[i * 2])
          ..add(coords[i * 2 + 1]);
      }
    }
    emit(points, cls);
  }

  // The runs: steep stretches going the same way, long enough and gaining
  // or losing enough height.
  final runs = <(int, int, bool, double)>[]; // first, last stretch, up, rise
  var w = 0;
  while (w < stretches) {
    if (!steep[w]) {
      w++;
      continue;
    }
    var end = w;
    while (end + 1 < stretches && steep[end + 1] && up[end + 1] == up[w]) {
      end++;
    }
    final a = ends[w];
    final b = ends[end + 1];
    final rise = (heights[b] - heights[a]).abs();
    if (along[b] - along[a] >= rule.minLengthMetres &&
        rise >= rule.minRiseMetres) {
      runs.add((w, end, up[w], rise));
    }
    w = end + 1;
  }

  for (final (first, last, goingUp, _) in runs) {
    var start = first;
    for (var k = first + 1; k <= last + 1; k++) {
      if (k == last + 1 || classes[k] != classes[start]) {
        if (classes[start] > 0) {
          emitPiece(ends[start], ends[k], classes[start], goingUp);
        }
        start = k;
      }
    }
  }
}

/// [elevations] (quarter metres) in metres, smoothed along the line: two
/// passes of a running mean over [sigma] metres either side, close to a
/// Gaussian and one sweep each instead of a weight per pair of points.
List<double> _smoothed(List<double> along, List<int> elevations, double sigma) {
  final metres = [for (final e in elevations) e / 4];
  if (sigma <= 0 || metres.length < 3) return metres;
  return _runningMean(along, _runningMean(along, metres, sigma), sigma);
}

/// The mean of the piecewise-linear profile [values] over [half] metres
/// either side of each point, the line's ends cutting the span short.
List<double> _runningMean(
  List<double> along,
  List<double> values,
  double half,
) {
  final n = values.length;
  // The integral of the profile up to each point.
  final integral = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    integral[i] =
        integral[i - 1] +
        (values[i] + values[i - 1]) / 2 * (along[i] - along[i - 1]);
  }
  double integralAt(double d, int hint) {
    // The segment holding [d], searched from [hint].
    var i = hint;
    while (i > 0 && along[i] > d) {
      i--;
    }
    while (i < n - 1 && along[i + 1] < d) {
      i++;
    }
    if (i >= n - 1) return integral[n - 1];
    final span = along[i + 1] - along[i];
    final t = span <= 0 ? 0.0 : ((d - along[i]) / span).clamp(0.0, 1.0);
    final v = values[i] + (values[i + 1] - values[i]) * t;
    return integral[i] + (values[i] + v) / 2 * (d - along[i]);
  }

  final out = List<double>.filled(n, 0);
  var lo = 0;
  var hi = 0;
  for (var i = 0; i < n; i++) {
    final from = math.max(0.0, along[i] - half);
    final to = math.min(along[n - 1], along[i] + half);
    if (to - from <= 0) {
      out[i] = values[i];
      continue;
    }
    while (lo < n - 1 && along[lo + 1] <= from) {
      lo++;
    }
    while (hi < n - 1 && along[hi + 1] <= to) {
      hi++;
    }
    out[i] = (integralAt(to, hi) - integralAt(from, lo)) / (to - from);
  }
  return out;
}
