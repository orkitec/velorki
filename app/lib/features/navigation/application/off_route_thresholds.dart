import 'dart:math' as math;

/// How far from the plan a fix has to be, at best, to count as a stray one.
///
/// Seventy-five metres is what a rider on a parallel service road, a cycle
/// path beside the carriageway or the other side of a dual carriageway sits
/// at, and none of those is a wrong turn.
const double offRouteMeters = 75;

/// How near the plan a fix has to be, at best, for the rider to count as on
/// it again.
///
/// One fix inside this is enough to be back on the route, and it is also the
/// gap the record screen is willing to draw the puck across: the matched
/// point is the honest answer only while the rider is really on the line.
const double routeSnapMeters = 30;

/// How far from a rejoin the rider has to drift, at best, before another one
/// is worth asking for.
const double detourDriftMeters = 50;

/// The largest reported accuracy the thresholds will scale with.
///
/// A phone that has lost the sky reports accuracies of hundreds or thousands
/// of metres, and an unbounded threshold would switch off-route detection off
/// for as long as that lasts — the rider would ride a wrong turn to its end
/// and never be told. Past this the fix says nothing useful about where the
/// rider is, so the threshold stops growing and the two-fix hysteresis is
/// left to absorb the noise.
const double accuracyCapMeters = 100;

/// How much of a reported accuracy the thresholds actually use.
///
/// An unknown, zero or nonsensical accuracy counts as none at all, which
/// leaves the base distances standing; anything above [accuracyCapMeters] is
/// taken as [accuracyCapMeters].
double effectiveAccuracyM(double? accuracyM) {
  if (accuracyM == null || !accuracyM.isFinite || accuracyM <= 0) return 0;
  return math.min(accuracyM, accuracyCapMeters);
}

/// How far from the plan a fix counts as a stray one, for a fix reported with
/// [accuracyM] metres of horizontal accuracy.
///
/// `max(baseM, 2 × accuracy)`, the shape OsmAnd uses: a fix that could be
/// anywhere inside its own error circle must be twice that circle out before
/// it is evidence of a detour, or a rider standing still under trees would be
/// re-routed round the corner they are on.
///
/// [baseM] is [offRouteMeters] for the plan itself and [detourDriftMeters]
/// for a rejoin being followed, which is a shorter leash because the rider
/// asked for that route a moment ago.
double strayThresholdM(double? accuracyM, {double baseM = offRouteMeters}) =>
    math.max(baseM, 2 * effectiveAccuracyM(accuracyM));

/// How near the plan a fix puts the rider back on it, for a fix reported with
/// [accuracyM] metres of horizontal accuracy.
///
/// `max([routeSnapMeters], accuracy)`, the shape Organic Maps uses: one
/// circle, not two, because coming back is the cheap direction — a rider
/// wrongly called back on is told about the next turn, a rider wrongly kept
/// off route is nagged and re-routed.
double snapThresholdM(double? accuracyM) =>
    math.max(routeSnapMeters, effectiveAccuracyM(accuracyM));
