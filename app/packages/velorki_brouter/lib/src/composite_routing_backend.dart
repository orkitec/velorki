import 'dart:math' as math;

import 'local_routing_backend.dart';
import 'route_query.dart';
import 'route_result.dart';
import 'routing_backend.dart';
import 'routing_exception.dart';
import 'segments_manifest.dart';
import 'tiles.dart';

/// Where a route came from, or would come from.
enum RoutingSource {
  /// The on-device engine, from downloaded rd5 tiles.
  local,

  /// A BRouter server over the network.
  remote,
}

/// What [CompositeRoutingBackend.decide] worked out for one query: which
/// backend would serve it, and which tiles are missing for the on-device path.
///
/// The route detail screen shows exactly this: "needed for offline routing:
/// 2 tiles, 640 MB".
class RoutingDecision {
  /// Creates a decision.
  const RoutingDecision({
    required this.source,
    required this.requiredTiles,
    required this.missingTiles,
  });

  /// The backend that would run the query, or `null` when neither can:
  /// tiles are missing and there is no server.
  final RoutingSource? source;

  /// Every tile the on-device engine would need for this query.
  final List<TileName> requiredTiles;

  /// The subset of [requiredTiles] that is not on disk, or is on disk with the
  /// wrong format version. Empty when the device has full coverage.
  final List<TileName> missingTiles;

  /// Whether some backend can answer the query.
  bool get canRoute => source != null;

  /// Whether the on-device engine has full coverage for the query.
  bool get hasLocalCoverage => missingTiles.isEmpty;

  /// The download size of [missingTiles] according to [manifest], in bytes.
  ///
  /// Tiles the manifest does not list count as zero, so treat this as "at
  /// least this much".
  int missingBytes(SegmentsManifest manifest) =>
      manifest.bytesFor(missingTiles);

  /// The exception [CompositeRoutingBackend.route] throws for this decision,
  /// or `null` when the query can be routed.
  RoutingException? get failure => canRoute
      ? null
      : RoutingException(
          kind: RoutingErrorKind.missingTiles,
          message:
              'on-device routing needs ${missingTiles.length} '
              '${missingTiles.length == 1 ? 'tile' : 'tiles'} that '
              '${missingTiles.length == 1 ? 'is' : 'are'} not downloaded: '
              '${missingTiles.join(', ')}',
          missingTiles: missingTiles,
        );

  @override
  String toString() =>
      'RoutingDecision(${source?.name ?? 'none'}, '
      '${requiredTiles.length} tiles, ${missingTiles.length} missing)';
}

/// Routes on the device when the tiles are there, over the network otherwise.
///
/// The rule of the plan, in one place:
///
/// 1. take the bounding box of the waypoints, expand it by
///    `max(10 km, 20 %)` and collect the intersecting 5° tiles
///    ([tilesForRoute]);
/// 2. all of them present locally, with a matching format version → the
///    [LocalRoutingBackend];
/// 3. otherwise the server, when one is configured;
/// 4. otherwise a [RoutingErrorKind.missingTiles] failure naming the tiles,
///    which the UI turns into "download N tiles (X MB)".
///
/// It never routes locally on partial coverage: BRouter reads a missing tile
/// as empty land and would silently return a detour, or nothing.
class CompositeRoutingBackend implements RoutingBackend {
  /// Creates a composite backend.
  ///
  /// [localTiles] is called for every decision (it is cheap — a `Set` the app
  /// keeps in memory, or [LocalRoutingBackend.availableTiles] as a tear-off),
  /// so downloading a tile takes effect on the next query without rebuilding
  /// anything.
  ///
  /// When [requiredFormatVersion] is set, a tile counts as present only if
  /// [localFormatVersions] maps it to that exact version — an unknown version
  /// counts as a mismatch, because a tile BRouter would refuse to read is no
  /// better than a missing one.
  ///
  /// At least one of [local] and [remote] must be given.
  CompositeRoutingBackend({
    this.local,
    this.remote,
    required this.localTiles,
    this.requiredFormatVersion,
    this.localFormatVersions,
    this.expandFraction = 0.2,
    this.minExpandMeters = 10000,
  }) {
    if (local == null && remote == null) {
      throw ArgumentError(
        'CompositeRoutingBackend needs a local or a remote backend',
      );
    }
  }

  /// The on-device backend, or `null` when on-device routing is off.
  final LocalRoutingBackend? local;

  /// The server backend, or `null` in a device-only build.
  final RoutingBackend? remote;

  /// The tiles currently on disk. Called once per decision.
  final Set<TileName> Function() localTiles;

  /// The rd5 format version this app build can read (the `lookups.dat`
  /// version pair, e.g. `11.2`), or `null` to skip the check.
  final String? requiredFormatVersion;

  /// The format version of each downloaded tile, as recorded in
  /// `routing_tiles`. Only consulted when [requiredFormatVersion] is set.
  final Map<TileName, String>? localFormatVersions;

  /// The bounding-box expansion of the tile rule; see [tilesForRoute].
  final double expandFraction;

  /// The minimum bounding-box expansion in metres; see [tilesForRoute].
  final double minExpandMeters;

  RoutingSource? _lastSource;

  /// Where the most recent successful [route] came from, or `null` before the
  /// first one. The planner shows an "offline" badge from this.
  RoutingSource? get lastSource => _lastSource;

  /// The tiles the on-device engine needs for [q].
  ///
  /// A round trip only has a start point, so the box is expanded by the
  /// round-trip radius as well — BRouter puts its generated waypoints on that
  /// circle, and they must be covered too.
  List<TileName> requiredTiles(RouteQuery q) {
    if (q.points.isEmpty) return const <TileName>[];
    var minExpand = minExpandMeters;
    if (q.roundTrip && q.roundTripDistanceM != null) {
      minExpand = math.max(minExpand, q.roundTripDistanceM! * 1.5);
    }
    return tilesForRoute(
      q.points,
      expandFraction: expandFraction,
      minExpandMeters: minExpand,
    );
  }

  /// Which backend would run [q], and what is missing for the on-device one.
  ///
  /// Pure: it answers the UI's "can this be routed offline?" without routing.
  RoutingDecision decide(RouteQuery q) {
    final required = requiredTiles(q);
    final missing = <TileName>[];
    if (local == null) {
      missing.addAll(required);
    } else {
      final present = localTiles();
      final versions = localFormatVersions;
      for (final tile in required) {
        if (!present.contains(tile)) {
          missing.add(tile);
        } else if (requiredFormatVersion != null &&
            versions?[tile] != requiredFormatVersion) {
          missing.add(tile);
        }
      }
    }

    final RoutingSource? source;
    if (local != null && missing.isEmpty) {
      source = RoutingSource.local;
    } else if (remote != null) {
      source = RoutingSource.remote;
    } else {
      source = null;
    }
    return RoutingDecision(
      source: source,
      requiredTiles: required,
      missingTiles: missing,
    );
  }

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    final decision = decide(q);
    final failure = decision.failure;
    if (failure != null) throw failure;

    final backend = decision.source == RoutingSource.local ? local! : remote!;
    final result = await backend.route(q, cancel: cancel);
    _lastSource = decision.source;
    return result;
  }

  @override
  String toString() =>
      'CompositeRoutingBackend(local: ${local != null}, '
      'remote: ${remote != null}, last: ${_lastSource?.name})';
}
