import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

/// How steep a stretch of road is, as the route on the map and the charts
/// colour it.
enum GradientClass {
  /// Down by more than 3 %.
  descent,

  /// Between 3 % down and 3 % up.
  flat,

  /// 3 to 6 % up.
  moderate,

  /// 6 to 10 % up.
  steep,

  /// More than 10 % up.
  verySteep,
}

/// The gradients, in percent, where one [GradientClass] gives way to the
/// next: what a key under the colours names.
const List<double> gradientClassBounds = <double>[-3, 3, 6, 10];

/// The colour (0xRRGGBB) the route is drawn in where it is as steep as
/// [gradient]: blue downhill, a neutral grey on the flat, and yellow,
/// orange and red the harder it climbs. The one place these colours live.
int gradientClassColour(GradientClass gradient) => switch (gradient) {
  GradientClass.descent => 0x3B82F6,
  GradientClass.flat => 0x9AA3AD,
  GradientClass.moderate => 0xF2C230,
  GradientClass.steep => 0xF08A24,
  GradientClass.verySteep => 0xD7352B,
};

/// The class of a gradient of [percent]; a bound itself belongs to the
/// steeper class.
GradientClass gradientClassOf(double percent) {
  if (percent <= gradientClassBounds[0]) return GradientClass.descent;
  if (percent < gradientClassBounds[1]) return GradientClass.flat;
  if (percent < gradientClassBounds[2]) return GradientClass.moderate;
  if (percent < gradientClassBounds[3]) return GradientClass.steep;
  return GradientClass.verySteep;
}

/// How long a stretch of road one gradient is measured over, in metres.
///
/// The heights of a planned route come from a terrain model and those of a
/// ride from a GPS or a barometer: from one point to the next they jump by
/// a metre or two either way, which over ten metres is a 20 % "climb". Over
/// two hundred metres that noise is gone and a real ramp still shows; at a
/// hundred, a road along a steep hillside, as on Madeira, still read as a
/// string of short climbs and dips the terrain model gave it.
const double gradientWindowM = 200;

/// How far apart the gradient is measured along the route, in metres: the
/// heights are read off the line this often, whatever the spacing of its
/// points, so a dense and a sparse geometry of the same road colour alike.
const double gradientStepM = 10;

/// A stretch of one class shorter than this, in metres, is folded into a
/// neighbour, so the line does not flicker between two colours where the
/// gradient sits on a bound, nor stripe the profile of a long climb with
/// the dips of a few dozen metres it has on the way.
const double gradientMinRunM = 200;

/// Where the heights are missing for longer than this, in metres, the
/// route is left uncoloured there rather than coloured by a straight line
/// between the heights on either side; a shorter gap is bridged.
const double gradientMaxGapM = 500;

/// One stretch of a route with the same [GradientClass], in metres from the
/// route's start.
typedef GradientRun = ({double startM, double endM, GradientClass gradient});

/// The gradient along [geometry], as [gradientRuns] cuts it.
List<GradientRun> gradientRunsOf(List<TrackPoint> geometry) {
  if (geometry.length < 2) return const <GradientRun>[];
  return gradientRuns(
    cumulativeDistancesMeters(
      geometry.map((p) => p.pos).toList(growable: false),
    ),
    <double?>[for (final p in geometry) p.ele],
  );
}

/// The gradient along a line whose points lie [distancesM] along it (never
/// decreasing) at the heights [elevationsM], cut into runs of the same
/// [GradientClass] that together cover the line from its first height to
/// its last.
///
/// The heights are read off the line every [gradientStepM], and the
/// gradient at each reading is the slope of the straight line that fits
/// the readings of the [gradientWindowM] around it best (least squares):
/// a single bad height moves it little, where the difference of the two
/// ends of the window would carry it whole. Runs shorter than
/// [gradientMinRunM] are then folded into a neighbour.
///
/// A point without a height ([elevationsM] `null` or not finite) is passed
/// over and the heights either side are joined by a straight line, unless
/// they are more than [gradientMaxGapM] apart: then the line has no runs
/// there, and the two sides are measured each on its own. Two heights far
/// apart with no point between them are simply a straight stretch. Nothing before
/// the first height nor after the last is coloured.
List<GradientRun> gradientRuns(
  List<double> distancesM,
  List<double?> elevationsM,
) {
  final n = distancesM.length < elevationsM.length
      ? distancesM.length
      : elevationsM.length;
  // The stretches with heights, each a list of (distance, height).
  final pieces = <List<(double, double)>>[];
  var piece = <(double, double)>[];
  // Whether points without a height lie between the last height and the
  // next: a long straight road has its points far apart, and that is no gap.
  var missing = false;
  for (var i = 0; i < n; i++) {
    final e = elevationsM[i];
    if (e == null || !e.isFinite) {
      missing = true;
      continue;
    }
    final d = distancesM[i];
    if (missing && piece.isNotEmpty && d - piece.last.$1 > gradientMaxGapM) {
      pieces.add(piece);
      piece = <(double, double)>[];
    }
    missing = false;
    piece.add((d, e));
  }
  pieces.add(piece);
  return <GradientRun>[
    for (final p in pieces) ..._mergeShortRuns(_classifiedRuns(p)),
  ];
}

/// The runs of one stretch with heights all along, before any merging.
List<GradientRun> _classifiedRuns(List<(double, double)> points) {
  if (points.length < 2) return const <GradientRun>[];
  final start = points.first.$1;
  final span = points.last.$1 - start;
  if (span <= 0) return const <GradientRun>[];
  final steps = (span / gradientStepM).ceil();
  final h = span / steps;
  // The heights read off the line every h metres, by straight lines
  // between its points.
  final heights = List<double>.filled(steps + 1, 0);
  var k = 0;
  for (var j = 0; j <= steps; j++) {
    final d = start + j * h;
    while (k + 2 < points.length && points[k + 1].$1 < d) {
      k++;
    }
    final (d0, e0) = points[k];
    final (d1, e1) = points[k + 1];
    final t = d1 > d0 ? ((d - d0) / (d1 - d0)).clamp(0.0, 1.0) : 0.0;
    heights[j] = e0 + (e1 - e0) * t;
  }
  // Readings either side of the one measured, at least one: a line shorter
  // than the window is measured whole.
  final half = math.max(1, (gradientWindowM / 2 / h).round());
  final runs = <GradientRun>[];
  for (var j = 0; j <= steps; j++) {
    final from = math.max(0, j - half);
    final to = math.min(steps, j + half);
    final gradient = gradientClassOf(_slope(heights, from, to) / h * 100);
    final runStart = j == 0 ? start : start + (j - 0.5) * h;
    final runEnd = j == steps ? start + span : start + (j + 0.5) * h;
    if (runs.isNotEmpty && runs.last.gradient == gradient) {
      runs.last = (startM: runs.last.startM, endM: runEnd, gradient: gradient);
    } else {
      runs.add((startM: runStart, endM: runEnd, gradient: gradient));
    }
  }
  return runs;
}

/// The least-squares slope of [heights] from index [from] to [to], in
/// metres per index.
double _slope(List<double> heights, int from, int to) {
  final count = to - from + 1;
  if (count < 2) return 0;
  final meanX = (from + to) / 2;
  var meanY = 0.0;
  for (var j = from; j <= to; j++) {
    meanY += heights[j];
  }
  meanY /= count;
  var sxy = 0.0;
  var sxx = 0.0;
  for (var j = from; j <= to; j++) {
    final dx = j - meanX;
    sxy += dx * (heights[j] - meanY);
    sxx += dx * dx;
  }
  return sxx > 0 ? sxy / sxx : 0;
}

/// [runs] with every run shorter than [gradientMinRunM] folded into a
/// neighbour, the shortest first: into the one whose class is nearer, and
/// between two as near into the longer. A line that is one short run stays
/// one.
List<GradientRun> _mergeShortRuns(List<GradientRun> runs) {
  final out = List<GradientRun>.of(runs);
  double length(GradientRun run) => run.endM - run.startM;
  while (out.length > 1) {
    var shortest = 0;
    for (var i = 1; i < out.length; i++) {
      if (length(out[i]) < length(out[shortest])) shortest = i;
    }
    final run = out[shortest];
    if (length(run) >= gradientMinRunM) break;
    final before = shortest > 0 ? out[shortest - 1] : null;
    final after = shortest + 1 < out.length ? out[shortest + 1] : null;
    int distance(GradientRun other) =>
        (other.gradient.index - run.gradient.index).abs();
    final intoBefore =
        after == null ||
        (before != null &&
            (distance(before) < distance(after) ||
                (distance(before) == distance(after) &&
                    length(before) >= length(after))));
    if (intoBefore) {
      out[shortest - 1] = (
        startM: before!.startM,
        endM: run.endM,
        gradient: before.gradient,
      );
      out.removeAt(shortest);
      _joinAt(out, shortest - 1);
    } else {
      out[shortest + 1] = (
        startM: run.startM,
        endM: after.endM,
        gradient: after.gradient,
      );
      out.removeAt(shortest);
      _joinAt(out, shortest);
    }
  }
  return out;
}

/// Joins the run at [i] with the one after it when the two are now of the
/// same class, and with the one before it likewise.
void _joinAt(List<GradientRun> runs, int i) {
  if (i + 1 < runs.length && runs[i + 1].gradient == runs[i].gradient) {
    runs[i] = (
      startM: runs[i].startM,
      endM: runs[i + 1].endM,
      gradient: runs[i].gradient,
    );
    runs.removeAt(i + 1);
  }
  if (i > 0 && runs[i - 1].gradient == runs[i].gradient) {
    runs[i - 1] = (
      startM: runs[i - 1].startM,
      endM: runs[i].endM,
      gradient: runs[i].gradient,
    );
    runs.removeAt(i);
  }
}
