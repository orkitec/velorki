import 'package:velorki_geo/velorki_geo.dart';

/// A circular area the route must avoid.
///
/// BRouter takes these as `nogos=lon,lat,radius[,weight]|...`, the radius in
/// metres. Without a [weight] the area is forbidden outright; with one it is
/// merely expensive, which is what "avoid if you reasonably can" means.
class NoGo {
  /// Creates a no-go area.
  const NoGo({required this.center, required this.radiusM, this.weight});

  /// Centre of the circle.
  final LatLng center;

  /// Radius in metres.
  final double radiusM;

  /// Optional cost multiplier; `null` forbids the area entirely.
  final double? weight;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoGo &&
          other.center == center &&
          other.radiusM == radiusM &&
          other.weight == weight;

  @override
  int get hashCode => Object.hash(center, radiusM, weight);

  @override
  String toString() => 'NoGo($center, r: $radiusM, w: $weight)';
}

/// Everything a [RoutingBackend] needs to compute one route.
///
/// A plain route uses [points] (at least two, in order). A round trip uses a
/// single start point plus [roundTripDistanceM] and [roundTripDirectionDeg];
/// BRouter then builds the intermediate points itself.
class RouteQuery {
  /// Creates a routing query.
  const RouteQuery({
    required this.points,
    this.profile = 'trekking',
    this.alternativeIdx = 0,
    this.roundTrip = false,
    this.roundTripDistanceM,
    this.roundTripDirectionDeg,
    this.allowSameWayBack = true,
    this.nogos = const <NoGo>[],
    this.timeout,
  });

  /// The waypoints, start first. In round-trip mode only the first is used.
  final List<LatLng> points;

  /// BRouter profile name without the `.brf` suffix, e.g. `trekking`.
  final String profile;

  /// Which of BRouter's alternatives to return, `0`..`3`.
  final int alternativeIdx;

  /// Whether to ask BRouter for a round trip (`engineMode=4`).
  final bool roundTrip;

  /// Round-trip search **radius** in metres.
  ///
  /// This is BRouter's `roundTripDistance`, which is the radius of the circle
  /// the intermediate points are placed on — not the length of the resulting
  /// route. See the README for the conversion `velorki_loops` uses.
  final double? roundTripDistanceM;

  /// Direction the round trip should head off in, degrees clockwise from
  /// north. `null` lets BRouter choose.
  final double? roundTripDirectionDeg;

  /// Whether the route may return along the way it came.
  final bool allowSameWayBack;

  /// Areas to avoid.
  final List<NoGo> nogos;

  /// Client-side deadline for the whole request.
  ///
  /// BRouter's HTTP server has no `timeout` query parameter — its limit is the
  /// JVM system property `maxRunningTime` — so this is enforced by the client.
  final Duration? timeout;

  /// The start point of the query.
  LatLng get start => points.first;

  /// A copy with the given fields replaced.
  RouteQuery copyWith({
    List<LatLng>? points,
    String? profile,
    int? alternativeIdx,
    bool? roundTrip,
    double? roundTripDistanceM,
    double? roundTripDirectionDeg,
    bool? allowSameWayBack,
    List<NoGo>? nogos,
    Duration? timeout,
  }) => RouteQuery(
    points: points ?? this.points,
    profile: profile ?? this.profile,
    alternativeIdx: alternativeIdx ?? this.alternativeIdx,
    roundTrip: roundTrip ?? this.roundTrip,
    roundTripDistanceM: roundTripDistanceM ?? this.roundTripDistanceM,
    roundTripDirectionDeg: roundTripDirectionDeg ?? this.roundTripDirectionDeg,
    allowSameWayBack: allowSameWayBack ?? this.allowSameWayBack,
    nogos: nogos ?? this.nogos,
    timeout: timeout ?? this.timeout,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteQuery &&
          _listEquals(other.points, points) &&
          other.profile == profile &&
          other.alternativeIdx == alternativeIdx &&
          other.roundTrip == roundTrip &&
          other.roundTripDistanceM == roundTripDistanceM &&
          other.roundTripDirectionDeg == roundTripDirectionDeg &&
          other.allowSameWayBack == allowSameWayBack &&
          _listEquals(other.nogos, nogos) &&
          other.timeout == timeout;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(points),
    profile,
    alternativeIdx,
    roundTrip,
    roundTripDistanceM,
    roundTripDirectionDeg,
    allowSameWayBack,
    Object.hashAll(nogos),
    timeout,
  );

  @override
  String toString() =>
      'RouteQuery(${points.length} pts, profile: $profile, '
      'alt: $alternativeIdx, roundTrip: $roundTrip, '
      'dist: $roundTripDistanceM, dir: $roundTripDirectionDeg, '
      'sameWayBack: $allowSameWayBack, nogos: ${nogos.length})';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
