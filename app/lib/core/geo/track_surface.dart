import 'dart:convert';
import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'track_thinning.dart';

/// Reading the surface off a track the router never drew.
///
/// A route the app planned comes back from the router with a message per way,
/// and the surface breakdown falls out of those. Two kinds of track have no
/// such messages: a ride, which was measured rather than routed, and a route
/// read from a file, which somebody else drew. Both are answered the same
/// way — route through the track's own points on the device and read the
/// surface off that answer — so both use what is here.

/// Why a track has, or has not, a surface breakdown.
enum TrackSurfaceState {
  /// The track was matched and [TrackSurface.stats] describes it.
  matched,

  /// There is no on-device routing at all in this build or setting.
  noRouting,

  /// On-device routing exists, but the tiles for the track's area are not
  /// downloaded. Not cached: it is tried again once they are.
  noTiles,

  /// The router could not follow the track: no route, a route of another
  /// length, a timeout, or a track too short to say anything about.
  unmatched,
}

/// The outcome of matching one track.
class TrackSurface {
  const TrackSurface._(this.state, this.stats);

  /// A matched track with its breakdown.
  const TrackSurface.matched(SurfaceStats stats)
    : this._(TrackSurfaceState.matched, stats);

  /// No on-device routing.
  static const TrackSurface noRouting = TrackSurface._(
    TrackSurfaceState.noRouting,
    null,
  );

  /// Tiles missing.
  static const TrackSurface noTiles = TrackSurface._(
    TrackSurfaceState.noTiles,
    null,
  );

  /// The track could not be matched.
  static const TrackSurface unmatched = TrackSurface._(
    TrackSurfaceState.unmatched,
    null,
  );

  /// What happened.
  final TrackSurfaceState state;

  /// The breakdown, only for [TrackSurfaceState.matched].
  final SurfaceStats? stats;

  @override
  String toString() =>
      'TrackSurface(${state.name}${stats == null ? '' : ', $stats'})';
}

/// Told to a profile so its messages carry every tag of a way, not only the
/// ones it reads: `surface` for one, which `shortest` never looks at.
const Map<String, String> keepAllTags = <String, String>{
  // A profile variable, so a number: the parser reads no `true`.
  'processUnusedTags': '1',
};

/// Matches a track to the roads it lies on, by routing through its thinned
/// points on the device, and reads the surface off the result.
///
/// The track never leaves the phone: only [local], the on-device engine, is
/// ever asked, and only when [decide] says every tile the route needs is on
/// disk. BRouter reads a missing tile as empty land and would quietly route
/// around it, so partial coverage is "no tiles", not a guess.
///
/// The router is asked for the `shortest` way through the points, which is
/// the way that sticks to the track rather than the way a profile prefers.
/// The answer is trusted only when its length is within [tolerance] of the
/// track's own distance: a detour around a park path, a ferry or a cut
/// through a field would describe roads nobody took.
class TrackSurfaceService {
  /// Creates the service.
  ///
  /// [local] is the on-device backend, or `null` when there is none; [decide]
  /// is `CompositeRoutingBackend.decide`, the coverage rule. A query is cut
  /// into chunks of at most [maxPointsPerQuery] waypoints, each with its own
  /// [timeout], so a long track is many short searches rather than one the
  /// deadline cuts off.
  TrackSurfaceService({
    required this.local,
    required this.decide,
    this.maxPointsPerQuery = 50,
    this.timeout = const Duration(seconds: 60),
    this.tolerance = 0.15,
    this.minDistanceM = 500,
  }) : assert(maxPointsPerQuery >= 2, 'a chunk needs two waypoints');

  /// The on-device engine, or `null` when routing is server-only or off.
  final RoutingBackend? local;

  /// Whether the tiles for a query are on disk.
  final RoutingDecision Function(RouteQuery query) decide;

  /// The most waypoints in one routing request.
  final int maxPointsPerQuery;

  /// The deadline per request.
  final Duration timeout;

  /// How far the routed length may differ from the track's distance, as a
  /// fraction of the latter.
  final double tolerance;

  /// Tracks shorter than this are not matched: a few hundred metres is one
  /// or two ways, and the router's snapping decides the shares.
  final double minDistanceM;

  /// The profile: the way that follows the points most closely.
  static const String profile = 'shortest';

  /// Matches the track of [points], [distanceM] long, and says what came of
  /// it.
  Future<TrackSurface> match({
    required List<TrackPoint> points,
    required double distanceM,
  }) async {
    final backend = local;
    if (backend == null) return TrackSurface.noRouting;
    if (points.length < 2 || distanceM < minDistanceM) {
      return TrackSurface.unmatched;
    }

    final waypoints = thinTrack(points);
    if (waypoints.length < 2) return TrackSurface.unmatched;
    final coverage = decide(RouteQuery(points: waypoints, profile: profile));
    if (!coverage.hasLocalCoverage) return TrackSurface.noTiles;

    var lengthM = 0.0;
    final messages = <SegmentMessage>[];
    for (final chunk in _chunks(waypoints)) {
      final RouteResult result;
      try {
        result = await backend.route(
          RouteQuery(
            points: chunk,
            profile: profile,
            alternativeIdx: 0,
            timeout: timeout,
            // The shortest profile never reads the surface, and a profile
            // drops the tags it does not read from its messages; this keeps
            // every tag, which is what the statistics are made of.
            profileParams: keepAllTags,
          ),
        );
      } on RoutingException {
        return TrackSurface.unmatched;
      }
      lengthM += result.lengthM;
      messages.addAll(result.messages);
    }

    if ((lengthM - distanceM).abs() > tolerance * distanceM) {
      return TrackSurface.unmatched;
    }
    final stats = SurfaceStats.fromMessages(messages, lengthM);
    if (stats.totalLengthM <= 0) return TrackSurface.unmatched;
    return TrackSurface.matched(stats);
  }

  /// Consecutive runs of at most [maxPointsPerQuery] waypoints, each starting
  /// where the previous one ended, so the routed legs join up.
  Iterable<List<LatLng>> _chunks(List<LatLng> waypoints) sync* {
    var start = 0;
    while (start < waypoints.length - 1) {
      final end = math.min(start + maxPointsPerQuery, waypoints.length);
      yield waypoints.sublist(start, end);
      start = end - 1;
    }
  }
}

/// What a `surface_stats_json` column holds for a track that had to be
/// matched.
///
/// Null until the track was ever matched against the routing tiles; [stats]
/// once it was; [unavailable] once matching failed for a reason a retry
/// would not change, so the page does not route the track again on every
/// open. A track whose area had no tiles is not recorded at all: it is tried
/// again once they are there.
class TrackSurfaceCache {
  /// Creates the cache entry.
  const TrackSurfaceCache({this.stats, this.unavailable = false});

  /// The marker for a track the map could not follow.
  static const TrackSurfaceCache unmatched = TrackSurfaceCache(
    unavailable: true,
  );

  /// The matched surface breakdown, when there is one.
  final SurfaceStats? stats;

  /// Whether matching failed for good.
  final bool unavailable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackSurfaceCache &&
          other.stats == stats &&
          other.unavailable == unavailable;

  @override
  int get hashCode => Object.hash(stats, unavailable);

  @override
  String toString() => unavailable ? 'TrackSurfaceCache.unmatched' : '$stats';
}

/// The `surface_stats_json` column: the statistics as `SurfaceStats.toJson`,
/// or `{"unavailable": true}` for a track that could not be matched.
String encodeTrackSurface(TrackSurfaceCache cache) => jsonEncode(
  cache.unavailable
      ? const <String, Object?>{'unavailable': true}
      : cache.stats?.toJson() ?? const <String, Object?>{},
);

/// Parses the `surface_stats_json` column; null or anything unreadable
/// means "not matched yet", which is safe: the page then matches again.
TrackSurfaceCache? decodeTrackSurface(String? json) {
  if (json == null || json.isEmpty) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  if (decoded['unavailable'] == true) return TrackSurfaceCache.unmatched;
  final stats = SurfaceStats.fromJson(decoded);
  return stats.totalLengthM > 0 ? TrackSurfaceCache(stats: stats) : null;
}
