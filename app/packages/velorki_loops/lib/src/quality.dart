import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'loop_request.dart';

/// How much of a route is ridden more than once.
///
/// Consecutive geometry points are rounded to [precision] decimals — about
/// 11 m at four places, one OSM node's worth of jitter — and each pair is
/// keyed without direction, so riding a road back the other way counts as a
/// repeat. Pairs whose two ends round to the same coordinate carry no length
/// and are skipped.
///
/// It is measured in **metres, not in point pairs**: an on-device route is a
/// chain of OSM nodes, so a kilometre of open road can be two points while a
/// roundabout is thirty. Counting pairs let a doubled four-kilometre ferry leg
/// weigh the same as two metres of kerb, which is exactly how the doubled
/// out-and-back in the Funchal loop slipped past the scorer.
class RepeatedGeometry {
  /// Creates a measurement.
  const RepeatedGeometry({required this.repeatedM, required this.totalM});

  /// Nothing measured.
  static const RepeatedGeometry none = RepeatedGeometry(
    repeatedM: 0,
    totalM: 0,
  );

  /// Metres ridden for at least the second time.
  final double repeatedM;

  /// Metres measured in total.
  final double totalM;

  /// [repeatedM] over [totalM], 0..1. A pure out-and-back gives 0.5.
  double get ratio => totalM > 0 ? repeatedM / totalM : 0;

  /// Measures [points].
  factory RepeatedGeometry.of(List<LatLng> points, {int precision = 4}) {
    if (points.length < 2) return none;
    final seen = <String>{};
    var total = 0.0;
    var repeated = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = _key(points[i - 1], precision);
      final b = _key(points[i], precision);
      if (a == b) continue;
      final key = a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
      final d = haversineMeters(points[i - 1], points[i]);
      total += d;
      if (!seen.add(key)) repeated += d;
    }
    return RepeatedGeometry(repeatedM: repeated, totalM: total);
  }

  static String _key(LatLng p, int precision) {
    final r = p.round(precision);
    return '${r.lat.toStringAsFixed(precision)},'
        '${r.lon.toStringAsFixed(precision)}';
  }

  @override
  String toString() =>
      'RepeatedGeometry(${repeatedM.round()} m of ${totalM.round()} m, '
      '${(ratio * 100).toStringAsFixed(1)} %)';
}

/// The two things that disqualify a route from being shown as a loop at all,
/// whatever the rider's preferences are: it is not all on roads, or it is the
/// same road twice.
///
/// This is deliberately separate from [RouteScorer]: the scorer ranks loops
/// against taste, this says whether the thing is a loop.
class LoopQuality {
  /// Creates a quality measurement.
  const LoopQuality({
    required this.lengthM,
    required this.offRoadM,
    required this.repeated,
    this.waypointOffsetM = 0,
  });

  /// Measures [result].
  ///
  /// [waypoints] are the *synthetic* points the query asked for
  /// ([syntheticPoints]): how far the router had to go to find a way for one
  /// of them is [waypointOffsetM]. Pass none and it stays zero.
  factory LoopQuality.of(
    RouteResult result, {
    int precision = 4,
    List<LatLng> waypoints = const <LatLng>[],
  }) => LoopQuality(
    lengthM: result.lengthM,
    offRoadM: result.surfaceStats.offRoadShare * result.lengthM,
    repeated: RepeatedGeometry.of(result.positions, precision: precision),
    waypointOffsetM: _worstOffset(waypoints, result.positions),
  );

  static double _worstOffset(List<LatLng> waypoints, List<LatLng> route) {
    if (waypoints.isEmpty || route.isEmpty) return 0;
    var worst = 0.0;
    for (final wp in waypoints) {
      var nearest = double.infinity;
      for (final p in route) {
        final d = haversineMeters(wp, p);
        if (d < nearest) nearest = d;
      }
      if (nearest > worst) worst = nearest;
    }
    return worst;
  }

  /// The route's length in metres.
  final double lengthM;

  /// Metres not on a road: a ferry, or a beeline drawn straight from a
  /// waypoint that had no way near it. See [SurfaceStats.offRoadShare].
  final double offRoadM;

  /// How much of the geometry is ridden twice.
  final RepeatedGeometry repeated;

  /// How far the worst synthetic waypoint ended up from the route, in metres.
  ///
  /// A point invented on a circle around a coastal start lands in the water;
  /// the engine then snaps it to the nearest way, which can be kilometres
  /// inland or along the coast, and the "loop" runs nowhere near where the
  /// strategy meant it to. Zero when the query had no synthetic points.
  final double waypointOffsetM;

  /// [offRoadM] as a share of [lengthM], 0..1.
  double get offRoadShare => lengthM > 0 ? offRoadM / lengthM : 0;

  /// The share of the route ridden more than once, 0..1.
  double get repeatedShare => repeated.ratio;

  @override
  String toString() =>
      'LoopQuality(${(lengthM / 1000).toStringAsFixed(1)} km, '
      'offRoad ${offRoadM.round()} m, '
      'repeated ${(repeatedShare * 100).toStringAsFixed(1)} %, '
      'waypoint off by ${waypointOffsetM.round()} m)';
}

/// Throws away candidates that are not loops.
///
/// Two rules, both about geometry rather than taste:
///
/// * **no beelines.** A candidate with more than [maxOffRoadM] metres off the
///   road network is rejected outright. BRouter's round-trip mode invents its
///   waypoints on a circle, and a circle around a coastal town puts half of
///   them in the sea; the engine then snaps them to whatever way is nearest,
///   which in Funchal is the Porto Santo ferry line — a straight line over
///   open water, ridden out and back.
/// * **no riding it twice.** More than [maxRepeatedShare] of the length
///   ridden a second time is an out-and-back, not a loop — unless the rider
///   turned "different way back" off, which is them asking for exactly that.
///   A tenth of the length is the street the ride leaves and comes home on;
///   a fifth is a two-kilometre spur out to the next village and back, which
///   is what a coastal round trip keeps producing and what a rider looking at
///   the map calls "not a loop".
/// * **the invented points have to be real places.** A perimeter or detour
///   point more than [maxWaypointOffsetM] from the route it produced was in
///   the sea (or up a cliff): the engine snapped it somewhere else entirely,
///   so the loop is not the one the strategy proposed. The rider's own start
///   and vias are never judged this way — only [syntheticPoints].
///
/// [tooFarFromTarget] is a fourth rule and a softer one: it does not throw a
/// candidate away, it says the planner should ask again before showing it.
class LoopFilter {
  /// Creates a filter.
  const LoopFilter({
    this.maxOffRoadM = 100,
    this.maxRepeatedShare = 0.1,
    this.maxWaypointOffsetM = 500,
    this.maxLengthError = loopMaxLengthError,
  });

  /// Accepts everything, for a caller that wants to score the raw pool.
  static const LoopFilter none = LoopFilter(
    maxOffRoadM: double.infinity,
    maxRepeatedShare: double.infinity,
    maxWaypointOffsetM: double.infinity,
    maxLengthError: double.infinity,
  );

  /// How many metres off the road network a candidate may have. A hundred
  /// metres is the slack for a waypoint snapped across a car park, not enough
  /// for a ferry.
  final double maxOffRoadM;

  /// How much of the route may be ridden twice, 0..1. A tenth leaves room
  /// for the street it starts and ends on, and nothing more.
  final double maxRepeatedShare;

  /// How far an invented waypoint may be from the route it produced, in
  /// metres. Half a kilometre is a point snapped across a field; more than
  /// that and it was never on land.
  final double maxWaypointOffsetM;

  /// How far from the requested distance a candidate may be before the
  /// planner would rather ask again, as a share of the target. See
  /// [tooFarFromTarget].
  final double maxLengthError;

  /// Why [quality] is not a loop worth showing, or `null` when it is.
  ///
  /// [ridesBackTheSameWay] is the rider's own switch turned off: they asked
  /// to come home the way they went out, so [maxRepeatedShare] does not
  /// apply — but a beeline over water still does.
  ///
  /// The text is for the log and for test failures, not for the rider.
  String? reject(LoopQuality quality, {bool ridesBackTheSameWay = false}) {
    if (quality.offRoadM > maxOffRoadM) {
      return '${quality.offRoadM.round()} m off the road network '
          '(max ${maxOffRoadM.round()} m)';
    }
    if (!ridesBackTheSameWay && quality.repeatedShare > maxRepeatedShare) {
      return '${(quality.repeatedShare * 100).toStringAsFixed(0)} % ridden '
          'twice (max ${(maxRepeatedShare * 100).toStringAsFixed(0)} %)';
    }
    if (quality.waypointOffsetM > maxWaypointOffsetM) {
      return 'a waypoint ended up ${quality.waypointOffsetM.round()} m from '
          'the route (max ${maxWaypointOffsetM.round()} m)';
    }
    return null;
  }

  /// Why [quality] misses [targetM] by too much to be worth showing while
  /// there is retry budget left, or `null` when it is close enough.
  ///
  /// This is not a rejection. A 38 km answer to a 30 km request is a real
  /// loop — it is simply not the loop that was asked for, and the same query
  /// with the round-trip radius scaled by `target / length` usually comes
  /// back at the right distance ([retryQuery]). So the planner holds it back
  /// and asks again, and shows it only once the retries are spent: a loop
  /// that is too long beats no loop at all.
  ///
  /// The text is for the log and for test failures, not for the rider.
  String? tooFarFromTarget(LoopQuality quality, {required double targetM}) {
    if (targetM <= 0) return null;
    final error = (quality.lengthM - targetM).abs() / targetM;
    if (error <= maxLengthError) return null;
    return '${(quality.lengthM / 1000).toStringAsFixed(1)} km is '
        '${(error * 100).toStringAsFixed(0)} % off the '
        '${(targetM / 1000).toStringAsFixed(1)} km asked for '
        '(max ${(maxLengthError * 100).toStringAsFixed(0)} %)';
  }

  @override
  String toString() =>
      'LoopFilter(offRoad <= ${maxOffRoadM.round()} m, '
      'repeated <= ${(maxRepeatedShare * 100).toStringAsFixed(0)} %, '
      'waypoint <= ${maxWaypointOffsetM.round()} m, '
      'length within ${(maxLengthError * 100).toStringAsFixed(0)} %)';
}

/// The points in [query] that a strategy invented, rather than the rider.
///
/// [LoopRequest.start] and every [LoopRequest.via] are the rider's own and are
/// never moved, dropped or judged; everything else — a perimeter ring point, a
/// sideways detour point — is the algorithm's guess and may be wrong.
List<LatLng> syntheticPoints(LoopRequest request, RouteQuery query) {
  final rider = <LatLng>{request.start, ...request.via};
  return <LatLng>[
    for (final p in query.points)
      if (!rider.contains(p)) p,
  ];
}

/// How far off the requested distance a loop may be and still be shown
/// straight away, as a share of the target.
///
/// A quarter is the width of the band a rider reads as "about what I asked
/// for": 22.5 to 37.5 km for a 30 km request. Past that the planner spends
/// retry budget on a corrected radius before it offers the answer.
const double loopMaxLengthError = 0.25;

/// How far a retry rotates the direction it heads off in, in degrees.
const double loopRetryRotationDeg = 18;

/// The narrowest a retry may shrink a radius to, as a factor of the original.
const double loopRetryMinScale = 0.45;

/// The widest a retry may grow a radius to.
const double loopRetryMaxScale = 1.5;

/// A second attempt at [query], or `null` when there is nothing left to try.
///
/// Two levers, both cheap and both aimed at the same failure: a bearing that
/// pointed at water.
///
/// * The bearing is rotated by [loopRetryRotationDeg], so the invented
///   waypoints land somewhere else — on land, with luck.
/// * The radius is scaled by how far the first attempt missed the target
///   ([result] `null`, i.e. nothing routed at all, shrinks it by a quarter),
///   which is also what pulls an overlong mountain loop back towards the
///   distance the rider asked for.
///
/// For a query with explicit waypoints the same scaling and rotation move the
/// *synthetic* points — the ones the strategies invented — towards the start
/// and round it, which is how a perimeter point that landed in the sea gets a
/// second chance on land. Points the rider actually asked for
/// ([LoopRequest.start] and [LoopRequest.via]) are left exactly where they
/// are, so a retry never quietly drops a via.
RouteQuery? retryQuery(
  LoopRequest request,
  RouteQuery query, {
  RouteResult? result,
}) {
  final scale = _retryScale(request, result);
  if (query.roundTrip) {
    final radius = query.roundTripDistanceM;
    if (radius == null) return null;
    final direction = query.roundTripDirectionDeg ?? 0;
    return query.copyWith(
      roundTripDistanceM: radius * scale,
      roundTripDirectionDeg: direction + loopRetryRotationDeg,
    );
  }

  final synthetic = syntheticPoints(request, query).toSet();
  if (synthetic.isEmpty) return null;
  return query.copyWith(
    points: <LatLng>[
      for (final p in query.points)
        if (!synthetic.contains(p))
          p
        else
          destinationPoint(
            request.start,
            bearingDegrees(request.start, p) + loopRetryRotationDeg,
            haversineMeters(request.start, p) * scale,
          ),
    ],
  );
}

double _retryScale(LoopRequest request, RouteResult? result) {
  if (result == null || result.lengthM <= 0 || request.targetM <= 0) {
    return 0.75;
  }
  final wanted = request.targetM / result.lengthM;
  return math.min(loopRetryMaxScale, math.max(loopRetryMinScale, wanted));
}
