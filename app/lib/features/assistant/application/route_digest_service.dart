import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/geo/track_surface.dart';
import '../../planner/application/track_surface_service.dart';
import '../../planner/domain/saved_route.dart';
import '../../search/data/gazetteer_store.dart';
import '../../search/domain/search_result.dart';
import '../domain/route_digest_builder.dart';

/// Builds the digest of a route on the phone, for "Describe this route"
/// and for a question about the route on the planner's map.
///
/// A saved route keeps its line and its surface shares, not the router's
/// per-way messages, so the line is matched against the routing tiles again
/// — the same on-device match an imported route's surface comes from, which
/// follows the line as it was saved rather than whatever the router would
/// plan between its waypoints today. The settlements and the places to stop
/// come out of the offline gazetteer. Nothing here touches the network.
class RouteDigestService {
  /// Creates the service.
  RouteDigestService({required this.surfaces, required this.gazetteer});

  /// The on-device track matcher.
  final TrackSurfaceService surfaces;

  /// The offline gazetteer, or `null` when there is none.
  final Future<GazetteerStore?> Function() gazetteer;

  /// The digest of [route], or `null` when there is nothing to tell: no tile
  /// to match it on, no heights and nothing from the gazetteer.
  Future<RouteDigest?> digestOf(SavedRoute route) => digestOfTrack(
    geometry: route.geometry,
    distanceM: route.distanceM,
    profile: route.profile.brouterName,
  );

  /// The digest of the line [geometry], [distanceM] long, planned with
  /// [profile].
  ///
  /// [messages] are the router's own messages along the line, when it drew
  /// all of it — the planner's route as it came back. With them nothing is
  /// matched again; without them the line is matched against the tiles.
  ///
  /// `null` when there is nothing to tell, unless [keepEmpty] asks for the
  /// bare digest (the loop flag and the profile) even then.
  Future<RouteDigest?> digestOfTrack({
    required List<TrackPoint> geometry,
    required double distanceM,
    String? profile,
    List<SegmentMessage> messages = const <SegmentMessage>[],
    bool keepEmpty = false,
  }) async {
    if (geometry.length < 2) return null;

    var ways = messages;
    if (ways.isEmpty) {
      final matched = await surfaces.matchWays(
        points: geometry,
        distanceM: distanceM,
      );
      if (matched.state == TrackSurfaceState.matched) ways = matched.messages;
    }

    var candidates = const <DigestCandidate>[];
    try {
      final store = await gazetteer();
      if (store != null) candidates = await corridorCandidates(store, geometry);
    } on Object catch (e) {
      debugPrint('velorki: no gazetteer for the route digest: $e');
    }

    // A long route is a few thousand samples and as many gazetteer rows;
    // measuring them is kept off the frame.
    final digest = await Isolate.run(
      () => buildRouteDigest(
        geometry: geometry,
        messages: ways,
        candidates: candidates,
        profile: profile,
      ),
    );
    final empty =
        digest.stretches.isEmpty &&
        digest.climbs.isEmpty &&
        digest.towns.isEmpty &&
        digest.places.isEmpty;
    return empty && !keepEmpty ? null : digest;
  }
}

/// The gazetteer rows a route along [geometry] might pass: settlements and
/// places to stop in boxes around consecutive pieces of the line, each box
/// as wide as the furthest a row of its kind still counts from.
Future<List<DigestCandidate>> corridorCandidates(
  GazetteerStore store,
  List<TrackPoint> geometry, {
  double pieceM = 5000,
}) async {
  final positions = [for (final p in geometry) p.pos];
  final along = cumulativeDistancesMeters(positions);
  final townReach = digestTownReachM.values.reduce(math.max);
  final seen = <String>{};
  final found = <DigestCandidate>[];

  var start = 0;
  while (start < positions.length - 1) {
    var end = start + 1;
    while (end < positions.length - 1 && along[end] - along[start] < pieceM) {
      end++;
    }
    final piece = BoundingBox.fromPoints(positions.sublist(start, end + 1));
    final rows = [
      ...await store.inBox(
        _grown(piece, townReach),
        placeKinds: digestTownReachM.keys.toList(),
      ),
      ...await store.inBox(
        _grown(piece, digestPlaceReachM),
        poiKinds: digestPlaceKinds,
      ),
    ];
    for (final SearchResult row in rows) {
      final kind = row.detail;
      if (kind == null) continue;
      final key = '$kind|${row.name}|${row.position.lat}|${row.position.lon}';
      if (!seen.add(key)) continue;
      found.add(
        DigestCandidate(name: row.name, kind: kind, position: row.position),
      );
    }
    start = end;
  }
  return found;
}

BoundingBox _grown(BoundingBox box, double meters) {
  const perDegree = 111320.0;
  final dLat = meters / perDegree;
  final mid = (box.south + box.north) / 2;
  final dLon =
      meters /
      (perDegree * math.max(math.cos(mid * math.pi / 180).abs(), 0.01));
  return BoundingBox(
    south: box.south - dLat,
    west: box.west - dLon,
    north: box.north + dLat,
    east: box.east + dLon,
  );
}

/// The app's [RouteDigestService].
final routeDigestServiceProvider = Provider<RouteDigestService>((ref) {
  return RouteDigestService(
    surfaces: ref.watch(trackSurfaceServiceProvider),
    gazetteer: () => ref.read(gazetteerStoreProvider.future),
  );
});
