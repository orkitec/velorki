import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../planner/data/routing_backend_provider.dart';
import '../data/ride_repository.dart';
import '../domain/ride.dart';
import '../domain/track_thinning.dart';

/// Why a ride has, or has not, a surface breakdown.
enum RideSurfaceState {
  /// The track was matched and [RideSurface.stats] describes it.
  matched,

  /// There is no on-device routing at all in this build or setting.
  noRouting,

  /// On-device routing exists, but the tiles for the ride's area are not
  /// downloaded. Not cached: it is tried again once they are.
  noTiles,

  /// The router could not follow the track: no route, a route of another
  /// length, a timeout, or a ride too short to say anything about.
  unmatched,
}

/// The outcome of matching one ride.
class RideSurface {
  const RideSurface._(this.state, this.stats);

  /// A matched ride with its breakdown.
  const RideSurface.matched(SurfaceStats stats)
    : this._(RideSurfaceState.matched, stats);

  /// No on-device routing.
  static const RideSurface noRouting = RideSurface._(
    RideSurfaceState.noRouting,
    null,
  );

  /// Tiles missing.
  static const RideSurface noTiles = RideSurface._(
    RideSurfaceState.noTiles,
    null,
  );

  /// The track could not be matched.
  static const RideSurface unmatched = RideSurface._(
    RideSurfaceState.unmatched,
    null,
  );

  /// What happened.
  final RideSurfaceState state;

  /// The breakdown, only for [RideSurfaceState.matched].
  final SurfaceStats? stats;

  @override
  String toString() =>
      'RideSurface(${state.name}${stats == null ? '' : ', $stats'})';
}

/// Matches a recorded ride to the roads it was ridden on, by routing through
/// its thinned track on the device, and reads the surface off the result.
///
/// The track never leaves the phone: only [local], the on-device engine, is
/// ever asked, and only when [decide] says every tile the route needs is on
/// disk. BRouter reads a missing tile as empty land and would quietly route
/// around it, so partial coverage is "no tiles", not a guess.
///
/// The router is asked for the `shortest` way through the waypoints, which is
/// the way that sticks to the track rather than the way a profile prefers.
/// The answer is trusted only when its length is within [tolerance] of the
/// recorded distance: a detour around a park path, a ferry or a cut through a
/// field would describe roads the rider never took.
/// Told to a profile so its messages carry every tag of a way, not only the
/// ones it reads: `surface` for one, which `shortest` never looks at.
const Map<String, String> keepAllTags = <String, String>{
  // A profile variable, so a number: the parser reads no `true`.
  'processUnusedTags': '1',
};

class RideSurfaceService {
  /// Creates the service.
  ///
  /// [local] is the on-device backend, or `null` when there is none; [decide]
  /// is `CompositeRoutingBackend.decide`, the coverage rule. A query is cut
  /// into chunks of at most [maxPointsPerQuery] waypoints, each with its own
  /// [timeout], so a long ride is many short searches rather than one the
  /// deadline cuts off.
  RideSurfaceService({
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

  /// How far the routed length may differ from the recorded distance, as a
  /// fraction of the latter.
  final double tolerance;

  /// Rides shorter than this are not matched: a few hundred metres is one or
  /// two ways, and the router's snapping decides the shares.
  final double minDistanceM;

  /// The profile: the way that follows the waypoints most closely.
  static const String profile = 'shortest';

  /// The surface breakdown of [ride], or `null` when it cannot be had; see
  /// [match] for why.
  Future<SurfaceStats?> compute(Ride ride) async => (await match(ride)).stats;

  /// Matches [ride] and says what came of it.
  Future<RideSurface> match(Ride ride) async {
    final backend = local;
    if (backend == null) return RideSurface.noRouting;
    final points = ride.points;
    final distanceM = ride.stats.distanceM;
    if (points.length < 2 || distanceM < minDistanceM) {
      return RideSurface.unmatched;
    }

    final waypoints = thinTrack(points);
    if (waypoints.length < 2) return RideSurface.unmatched;
    final coverage = decide(RouteQuery(points: waypoints, profile: profile));
    if (!coverage.hasLocalCoverage) return RideSurface.noTiles;

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
        return RideSurface.unmatched;
      }
      lengthM += result.lengthM;
      messages.addAll(result.messages);
    }

    if ((lengthM - distanceM).abs() > tolerance * distanceM) {
      return RideSurface.unmatched;
    }
    final stats = SurfaceStats.fromMessages(messages, lengthM);
    if (stats.totalLengthM <= 0) return RideSurface.unmatched;
    return RideSurface.matched(stats);
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

/// The service over the app's routing backend.
///
/// Only the on-device half of the composite backend is handed over; the
/// server, when there is one, is never asked about a ride.
final rideSurfaceServiceProvider = Provider<RideSurfaceService>((ref) {
  final backend = ref.watch(routingBackendProvider);
  final composite = backend is CompositeRoutingBackend ? backend : null;
  return RideSurfaceService(
    local: composite?.local,
    decide:
        composite?.decide ??
        (q) => const RoutingDecision(
          source: null,
          requiredTiles: <TileName>[],
          missingTiles: <TileName>[],
        ),
  );
});

/// The surface breakdown of one ride: from the row when it was matched
/// before, otherwise matched now and written back.
///
/// A ride the map could not follow is written back too, as a marker, so it
/// is not routed again on every open; the marker goes when a new tile is
/// downloaded. A ride whose area has no tiles is not written at all, so it is
/// matched as soon as they are there. Rebuilds when the tiles change, since
/// the backend does.
final rideSurfaceProvider = FutureProvider.autoDispose
    .family<RideSurface, String>((ref, rideId) async {
      final repository = ref.watch(rideRepositoryProvider);
      final service = ref.watch(rideSurfaceServiceProvider);
      final ride = await ref.watch(rideProvider(rideId).future);
      if (ride == null) return RideSurface.unmatched;

      final cached = ride.surface;
      if (cached != null) {
        final stats = cached.stats;
        if (stats != null) return RideSurface.matched(stats);
        if (cached.unavailable) return RideSurface.unmatched;
      }

      final outcome = await service.match(ride);
      switch (outcome.state) {
        case RideSurfaceState.matched:
          await repository.setSurface(rideId, outcome.stats!);
        case RideSurfaceState.unmatched:
          await repository.markSurfaceUnavailable(rideId);
        case RideSurfaceState.noRouting:
        case RideSurfaceState.noTiles:
          break;
      }
      return outcome;
    });
