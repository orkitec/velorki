import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'loop_request.dart';
import 'quality.dart';

/// The raw, preference-independent measurements a loop is judged on.
///
/// Exposed so the UI can explain a ranking ("12 % too long, 38 % gravel")
/// instead of showing a bare number.
class LoopFeatures {
  /// Creates a feature vector.
  const LoopFeatures({
    required this.lengthM,
    required this.targetM,
    required this.lengthError,
    required this.ascentPerKm,
    required this.unpavedShare,
    required this.cyclewayShare,
    required this.busyShare,
    required this.repeatedSegmentRatio,
  });

  /// Actual route length in metres.
  final double lengthM;

  /// Requested route length in metres.
  final double targetM;

  /// `|length - target| / target`, so 0.1 is "10 % off".
  final double lengthError;

  /// Filtered ascent divided by the length in kilometres.
  final double ascentPerKm;

  /// Share of the route on an unpaved surface, 0..1.
  final double unpavedShare;

  /// Share of the route on cycle infrastructure, 0..1.
  final double cyclewayShare;

  /// Share of the route on primary or trunk roads, 0..1.
  final double busyShare;

  /// Share of the route's **length** ridden more than once, 0..1.
  /// A pure out-and-back scores 0.5.
  final double repeatedSegmentRatio;

  /// The feature vector as a map, for charts and debug output.
  Map<String, double> toMap() => <String, double>{
    'lengthM': lengthM,
    'targetM': targetM,
    'lengthError': lengthError,
    'ascentPerKm': ascentPerKm,
    'unpavedShare': unpavedShare,
    'cyclewayShare': cyclewayShare,
    'busyShare': busyShare,
    'repeatedSegmentRatio': repeatedSegmentRatio,
  };

  @override
  String toString() => 'LoopFeatures(${toMap()})';
}

/// A scored loop. **Lower [total] is better.**
class LoopScore {
  /// Creates a score.
  const LoopScore({
    required this.total,
    required this.features,
    required this.contributions,
  });

  /// The weighted sum. Lower is better; it can go negative when the rewards
  /// (cycleways, wanted gravel, wanted hills) outweigh the penalties.
  final double total;

  /// The raw measurements behind the score.
  final LoopFeatures features;

  /// Each term's signed contribution to [total], keyed by feature name.
  final Map<String, double> contributions;

  @override
  String toString() => 'LoopScore(${total.toStringAsFixed(3)}, $contributions)';
}

/// Scores loop candidates against one rider's [LoopPrefs].
///
/// The weights are deliberately plain constants rather than a learned model:
/// they are readable, adjustable and testable, and the ordering they produce
/// is what the user actually sees.
class RouteScorer {
  /// Creates a scorer for [prefs].
  const RouteScorer(this.prefs);

  /// The preferences being scored against.
  final LoopPrefs prefs;

  /// Weight of the relative length error.
  static const double lengthWeight = 3.0;

  /// Weight of the hills term.
  static const double hillsWeight = 1.5;

  /// Weight of the surface term.
  static const double surfaceWeight = 1.0;

  /// Weight of the cycleway reward.
  static const double cyclewayWeight = 1.0;

  /// Weight of the busy-road penalty; doubled when
  /// [LoopPrefs.avoidTraffic] is set.
  static const double busyWeight = 2.0;

  /// Weight of the repeated-segment penalty.
  ///
  /// High on purpose, and higher than the length term: among the candidates
  /// that survive [LoopFilter] the least doubled one should win even when it
  /// is a few kilometres further from the target. At this weight a tenth of
  /// the route ridden twice costs as much as being 27 % off the distance.
  static const double repeatWeight = 8.0;

  /// Decimal places used to hash a coordinate when detecting repeats.
  /// Four places is about 11 m, one OSM node's worth of jitter.
  static const int repeatPrecision = 4;

  /// Measures [result] against a [targetM] metre target.
  LoopFeatures features(RouteResult result, {required double targetM}) {
    final stats = result.surfaceStats;
    final lengthM = result.lengthM;
    final km = lengthM / 1000;
    return LoopFeatures(
      lengthM: lengthM,
      targetM: targetM,
      lengthError: targetM > 0 ? (lengthM - targetM).abs() / targetM : 0,
      ascentPerKm: km > 0 ? result.ascentM / km : 0,
      unpavedShare: stats.unpavedShare,
      cyclewayShare: stats.cyclewayShare,
      busyShare: stats.busyShare,
      repeatedSegmentRatio: repeatedSegmentRatio(result.positions),
    );
  }

  /// Scores [result] against a [targetM] metre target.
  LoopScore score(RouteResult result, {required double targetM}) =>
      scoreFeatures(features(result, targetM: targetM));

  /// Scores an already measured [LoopFeatures].
  LoopScore scoreFeatures(LoopFeatures f) {
    final contributions = <String, double>{
      'lengthError': lengthWeight * f.lengthError,
      'hills': hillsWeight * hillsTerm(f.ascentPerKm),
      'surface': surfaceWeight * surfaceTerm(f.unpavedShare),
      'cycleway': -cyclewayWeight * f.cyclewayShare,
      'busy': (prefs.avoidTraffic ? busyWeight * 2 : busyWeight) * f.busyShare,
      'repeated': repeatWeight * f.repeatedSegmentRatio,
    };
    var total = 0.0;
    for (final v in contributions.values) {
      total += v;
    }
    return LoopScore(total: total, features: f, contributions: contributions);
  }

  /// The hills term, normalised to roughly -1..1. Negative is a reward.
  ///
  /// * [Hills.avoid]: nothing below 8 m/km, then linear.
  /// * [Hills.neutral]: nothing below 15 m/km, then linear.
  /// * [Hills.seek]: -1 inside the 10–25 m/km band, rising penalties outside.
  double hillsTerm(double ascentPerKm) {
    switch (prefs.hills) {
      case Hills.avoid:
        return math.max(0.0, (ascentPerKm - 8) / 20);
      case Hills.neutral:
        return math.max(0.0, (ascentPerKm - 15) / 20);
      case Hills.seek:
        if (ascentPerKm < 10) return (10 - ascentPerKm) / 10;
        if (ascentPerKm <= 25) return -1.0;
        return (ascentPerKm - 25) / 20;
    }
  }

  /// The surface term. Negative is a reward.
  ///
  /// * [Surface.paved]: every unpaved metre counts.
  /// * [Surface.mixed]: only the share above 40 % counts.
  /// * [Surface.gravel]: unpaved is what was asked for, so it is rewarded.
  double surfaceTerm(double unpavedShare) {
    switch (prefs.surface) {
      case Surface.paved:
        return unpavedShare;
      case Surface.mixed:
        return math.max(0.0, unpavedShare - 0.4);
      case Surface.gravel:
        return -unpavedShare;
    }
  }

  /// The share of the route's length that it rides more than once.
  ///
  /// See [RepeatedGeometry], which does the measuring: metres rather than
  /// point pairs, because a route's points are OSM nodes and are nowhere near
  /// evenly spaced.
  static double repeatedSegmentRatio(List<LatLng> points) =>
      RepeatedGeometry.of(points, precision: repeatPrecision).ratio;
}
