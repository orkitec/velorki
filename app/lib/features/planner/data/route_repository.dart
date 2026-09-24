import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/db/daos/routes_dao.dart';
import '../../../core/geo/track_surface.dart';
import '../../../core/db/database.dart';
import '../../../core/geo/ride_stats.dart';
import '../domain/route_legs.dart';
import '../domain/route_profile.dart';
import '../domain/route_waypoints.dart';
import '../domain/routing_options.dart';
import '../domain/route_poi.dart';
import '../domain/saved_route.dart';
import '../domain/waypoint.dart';

part 'route_repository.g.dart';

/// Reads and writes the `routes` table in the planner's terms.
///
/// One row holds everything needed to put a route back on the map without
/// asking the routing server again: the packed geometry, the waypoints, the
/// routing options and the surface statistics.
class RouteRepository {
  /// Creates a repository over [dao].
  RouteRepository(this._dao, {Uuid? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? const Uuid(),
      _clock = clock ?? DateTime.now;

  final RoutesDao _dao;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Every saved route, newest first, as a stream that follows the database.
  Stream<List<SavedRoute>> watchRoutes() =>
      _dao.watchRoutes().map((rows) => rows.map(toDomain).toList());

  /// One saved route, or `null` when the id is unknown.
  Future<SavedRoute?> routeById(String id) async {
    final row = await _dao.routeById(id);
    return row == null ? null : toDomain(row);
  }

  /// One saved route as a stream, `null` once it is deleted.
  Stream<SavedRoute?> watchRoute(String id) =>
      _dao.watchRoute(id).map((row) => row == null ? null : toDomain(row));

  /// Writes a planned route to the library.
  ///
  /// Passing the [id] of an existing row updates it and keeps its creation
  /// date; without one a new row is created.
  ///
  /// A [PlannedRoute] has its legs written with it, so it opens with the
  /// same kept and routed stretches. [surfaceStats] are the figures the
  /// planner showed; without them, the router's own, when it has them for
  /// the whole route.
  Future<SavedRoute> savePlannedRoute({
    required String name,
    required RouteResult route,
    required List<Waypoint> waypoints,
    required RoutingOptions options,
    List<RoutePoi> pois = const <RoutePoi>[],
    String? id,
    String? description,
    RouteSource source = RouteSource.planned,
    SurfaceStats? surfaceStats,
    RouteOriginal? original,
  }) async {
    final now = _clock();
    final existing = id == null ? null : await _dao.routeById(id);
    // Saving over a route keeps what the planner does not carry: its
    // description, its link and who wrote the file it came from. The points
    // of interest it does carry — the plan's points beside the route — are
    // written as they stand, so one that was removed there goes here too.
    final kept = existing == null ? null : toDomain(existing);
    final geometryLine = route.geometry
        .map((p) => p.pos)
        .toList(growable: false);
    final saved = SavedRoute(
      id: id ?? _uuid.v4(),
      name: name,
      description: description ?? kept?.description,
      link: kept?.link,
      creator: kept?.creator,
      source: source,
      profile: options.profile,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      distanceM: route.lengthM,
      ascentM: route.ascentM,
      descentM: route.descentM,
      bounds: route.bounds ?? _boundsOf(waypoints),
      geometryBlob: PackedTrack.encode(route.geometry),
      waypoints: waypoints,
      options: options,
      surfaceStats:
          surfaceStats ?? (route.messages.isEmpty ? null : route.surfaceStats),
      legs: route is PlannedRoute && route.legs.length == waypoints.length - 1
          ? route.savedLegs
          : null,
      // The file's own line outlives every save over it: the row's own when
      // it has one, else what the planner took for it.
      original: kept?.original ?? original,
      // The rider's own turns, from the waypoints of the turn kind, beside
      // the router's: what the cue sheet and the navigator read.
      turns: mergeWaypointTurns(route.turns, waypoints, geometryLine),
      pois: pois,
    );
    await _dao.upsertRoute(toCompanion(saved));
    return saved;
  }

  /// Writes a route that came out of a file rather than out of the router.
  ///
  /// [profile] is the bike the file names; `null` leaves the bike to the
  /// planner, which opens the route with the one the rider rode last. The
  /// line and the markers it opens with are kept as its original.
  ///
  /// There is no [RouteResult] here — nobody asked BRouter — so the distance
  /// and the elevation gain are computed from the geometry itself, and the
  /// surface statistics stay empty. [waypoints] defaults to the first and the
  /// last point, which is what the planner needs to re-route the import later.
  ///
  /// [source] says which decoder produced it, so the library can tell a GPX
  /// import from a FIT one.
  Future<SavedRoute> saveImportedRoute({
    required String name,
    required List<TrackPoint> points,
    required RouteSource source,
    String? id,
    String? description,
    List<Waypoint>? waypoints,
    List<RoutePoi> pois = const <RoutePoi>[],
    List<TurnHint> turns = const <TurnHint>[],
    RoutingOptions options = const RoutingOptions(),
    RouteProfile? profile,
    String? link,
    String? creator,
  }) async {
    if (points.isEmpty) {
      throw ArgumentError.value(points, 'points', 'an imported route is empty');
    }
    final now = _clock();
    final existing = id == null ? null : await _dao.routeById(id);
    final geometry = computeRouteGeometryStats(points);
    final ends = normalizeWaypointKinds([
      Waypoint(pos: points.first.pos),
      if (points.length > 1) Waypoint(pos: points.last.pos),
    ]);
    final blob = PackedTrack.encode(points);
    final markers = trackMarkers(
      track: points.map((p) => p.pos).toList(growable: false),
      saved: waypoints ?? ends,
      pois: pois,
      turns: turns,
    );
    final saved = SavedRoute(
      id: id ?? _uuid.v4(),
      name: name,
      description: description,
      source: source,
      profile: profile ?? options.profile,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      distanceM: geometry.distanceM,
      ascentM: geometry.ascentM,
      descentM: geometry.descentM,
      bounds: BoundingBox.fromPoints(points.map((p) => p.pos)),
      geometryBlob: blob,
      waypoints: waypoints ?? ends,
      options: profile == null ? options : options.copyWith(profile: profile),
      profileKnown: profile != null,
      pois: pois,
      turns: turns,
      link: link,
      creator: creator,
      original: markers.length < 2
          ? null
          : RouteOriginal(
              geometryBlob: blob,
              waypoints: normalizeWaypointKinds([
                for (final m in markers) m.$2,
              ]),
              legs: [
                for (final m in markers.take(markers.length - 1))
                  SavedLeg(start: m.$1, kept: true),
              ],
              turns: turns,
            ),
    );
    await _dao.upsertRoute(toCompanion(saved));
    return saved;
  }

  /// Records which partner service a route came from, and when it was read.
  ///
  /// `external_fetched_at` exists for Strava's seven-day cache rule: data read
  /// from Strava may be kept for a week, after which it has to be fetched
  /// again or dropped. Writing the two columns separately keeps the geometry
  /// out of the statement and leaves [saveImportedRoute] unaware of partner
  /// services.
  ///
  /// An unknown id changes nothing.
  Future<void> markExternal(
    String routeId, {
    required Map<String, Object?> externalIds,
    DateTime? fetchedAt,
  }) async {
    final row = await _dao.routeById(routeId);
    if (row == null) return;
    await _dao.updateRoute(
      row.copyWith(
        externalIdsJson: Value(jsonEncode(externalIds)),
        externalFetchedAt: Value(fetchedAt ?? _clock()),
      ),
    );
  }

  /// Writes [route] back exactly as it is, which is what the undo of a delete
  /// needs.
  Future<void> restore(SavedRoute route) =>
      _dao.upsertRoute(toCompanion(route));

  /// Deletes the route with [id].
  Future<void> delete(String id) => _dao.deleteRoute(id);

  /// Writes the route's description.
  ///
  /// [aiGenerated] records that the model wrote it, which the detail screen
  /// shows and which keeps the column honest for anyone auditing what was
  /// generated. An unknown id changes nothing.
  Future<void> setDescription(
    String id,
    String description, {
    bool aiGenerated = false,
  }) async {
    final row = await _dao.routeById(id);
    if (row == null) return;
    await _dao.updateRoute(
      row.copyWith(
        description: Value(description),
        aiDescriptionGenerated: aiGenerated,
        updatedAt: _clock(),
      ),
    );
  }

  /// Replaces the waypoints of the route with [id], everything else as it
  /// is: what a change to a point's name, kind or note needs, since it
  /// leaves the geometry alone. An unknown id changes nothing.
  Future<void> setWaypoints(String id, List<Waypoint> waypoints) async {
    final row = await _dao.routeById(id);
    if (row == null) return;
    final route = toDomain(row);
    final legs = route.legs;
    await _dao.updateRoute(
      row.copyWith(
        // Details move no point, so the legs stay where they were.
        waypointsJson: encodeWaypoints(
          waypoints,
          legs: legs != null && legs.length == waypoints.length - 1
              ? legs
              : null,
        ),
        turnsJson: Value(
          encodeTurns(
            mergeWaypointTurns(
              route.turns,
              waypoints,
              route.geometry.map((p) => p.pos).toList(growable: false),
            ),
          ),
        ),
        updatedAt: _clock(),
      ),
    );
  }

  /// Writes the surface breakdown worked out for the route with [id], or,
  /// with no [stats], the marker for a track the router could not follow.
  ///
  /// A route planned here arrives with its surfaces from the router; one
  /// read from a file has none until its track is matched, which the card
  /// does once and keeps. An unknown id changes nothing.
  Future<void> setSurfaceStats(String id, SurfaceStats? stats) async {
    final row = await _dao.routeById(id);
    if (row == null) return;
    await _dao.updateRoute(
      row.copyWith(
        surfaceStatsJson: Value(
          encodeTrackSurface(
            stats == null
                ? TrackSurfaceCache.unmatched
                : TrackSurfaceCache(stats: stats),
          ),
        ),
        // Not a change to the route itself: the figures describe the track
        // that was always there, so the card's "edited" date stays put.
        updatedAt: row.updatedAt,
      ),
    );
  }

  /// Replaces the points of interest of the route with [id], everything
  /// else as it is: what a change to a point beside the route needs, since
  /// it leaves the geometry and the waypoints alone. An unknown id changes
  /// nothing.
  Future<void> setPois(String id, List<RoutePoi> pois) async {
    final row = await _dao.routeById(id);
    if (row == null) return;
    await _dao.updateRoute(
      row.copyWith(poisJson: Value(encodePois(pois)), updatedAt: _clock()),
    );
  }

  /// Writes the route's link, `null` to take it away. An unknown id changes
  /// nothing.
  Future<void> setLink(String id, String? link) async {
    final row = await _dao.routeById(id);
    if (row == null) return;
    final trimmed = link?.trim();
    await _dao.updateRoute(
      row.copyWith(
        link: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
        updatedAt: _clock(),
      ),
    );
  }

  /// Gives the route with [id] a new [name].
  Future<void> rename(String id, String name) async {
    final row = await _dao.routeById(id);
    if (row == null) return;
    await _dao.updateRoute(row.copyWith(name: name, updatedAt: _clock()));
  }

  /// Maps a database row into the domain model.
  SavedRoute toDomain(RouteRow row) => SavedRoute(
    id: row.id,
    name: row.name,
    description: row.description,
    source: row.source,
    profile: RouteProfile.fromName(row.profile),
    profileKnown: decodeProfileKnown(row.routingOptionsJson),
    original: decodeOriginal(row.originalJson, row.originalGeometry, row),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    distanceM: row.distanceM,
    ascentM: row.ascentM,
    descentM: row.descentM,
    bounds: BoundingBox(
      south: row.bboxMinLat,
      west: row.bboxMinLon,
      north: row.bboxMaxLat,
      east: row.bboxMaxLon,
    ),
    geometryBlob: Uint8List.fromList(row.geometry),
    waypoints: decodeWaypoints(row.waypointsJson),
    legs: decodeLegs(row.waypointsJson),
    options: decodeOptions(row.routingOptionsJson),
    // One read of the column for both: the marker for a track that could
    // not be followed lives in it beside the figures, and parsing it as
    // figures would give a route a breakdown of nothing but zeroes.
    surfaceStats: decodeTrackSurface(row.surfaceStatsJson)?.stats,
    surfaceUnavailable:
        decodeTrackSurface(row.surfaceStatsJson)?.unavailable ?? false,
    turns: decodeTurns(row.turnsJson),
    aiDescriptionGenerated: row.aiDescriptionGenerated,
    pois: decodePois(row.poisJson),
    link: row.link,
    creator: row.creator,
  );

  /// Maps the domain model into a row for `INSERT OR REPLACE`.
  RoutesCompanion toCompanion(SavedRoute route) => RoutesCompanion.insert(
    id: route.id,
    name: route.name,
    description: Value(route.description),
    source: route.source,
    profile: route.profile.brouterName,
    createdAt: route.createdAt,
    updatedAt: route.updatedAt,
    distanceM: route.distanceM,
    ascentM: route.ascentM,
    descentM: route.descentM,
    bboxMinLat: route.bounds.south,
    bboxMinLon: route.bounds.west,
    bboxMaxLat: route.bounds.north,
    bboxMaxLon: route.bounds.east,
    geometry: route.geometryBlob,
    waypointsJson: encodeWaypoints(route.waypoints, legs: route.legs),
    routingOptionsJson: jsonEncode(
      <String, dynamic>{...route.options.toMap()}
        ..removeWhere((key, _) => key == 'profile' && !route.profileKnown),
    ),
    surfaceStatsJson: Value(
      route.surfaceStats == null
          ? null
          : jsonEncode(encodeSurfaceStats(route.surfaceStats!)),
    ),
    turnsJson: Value(encodeTurns(route.turns)),
    aiDescriptionGenerated: Value(route.aiDescriptionGenerated),
    poisJson: Value(encodePois(route.pois)),
    link: Value(route.link),
    creator: Value(route.creator),
    originalJson: Value(encodeOriginal(route.original)),
    // The file's line is stored apart only once it is not the line any
    // more.
    originalGeometry: Value(
      route.original == null ||
              _sameBytes(route.original!.geometryBlob, route.geometryBlob)
          ? null
          : route.original!.geometryBlob,
    ),
  );

  BoundingBox _boundsOf(List<Waypoint> waypoints) => waypoints.isEmpty
      ? const BoundingBox(south: 0, west: 0, north: 0, east: 0)
      : BoundingBox.fromPoints(waypoints.map((w) => w.pos));
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether the `routing_options_json` column names a bike; a file that
/// named none was saved without one.
bool decodeProfileKnown(String json) {
  final decoded = _tryDecode(json);
  return decoded is! Map<String, dynamic> || decoded.containsKey('profile');
}

/// The `original_json` column: the markers with their legs, and the turns.
String? encodeOriginal(RouteOriginal? original) => original == null
    ? null
    : jsonEncode(<String, dynamic>{
        'waypoints': jsonDecode(
          encodeWaypoints(original.waypoints, legs: original.legs),
        ),
        if (original.turns.isNotEmpty)
          'turns': [for (final t in original.turns) t.toMap()],
      });

/// Reads the original of [row] back: [json] from `original_json`, the line
/// from [geometry] (`original_geometry`) or, while that is empty, the row's
/// own. `null` when there is none or it cannot be read.
RouteOriginal? decodeOriginal(String? json, Uint8List? geometry, RouteRow row) {
  if (json == null || json.isEmpty) return null;
  final decoded = _tryDecode(json);
  if (decoded is! Map<String, dynamic>) return null;
  final points = jsonEncode(decoded['waypoints']);
  final legs = decodeLegs(points);
  if (legs == null) return null;
  final turns = decoded['turns'];
  return RouteOriginal(
    geometryBlob: Uint8List.fromList(geometry ?? row.geometry),
    waypoints: decodeWaypoints(points),
    legs: legs,
    turns: turns is List ? decodeTurns(jsonEncode(turns)) : const <TurnHint>[],
  );
}

/// The `waypoints_json` column.
///
/// With [legs], every waypoint but the last also says where the leg from it
/// starts in the geometry (`leg`) and whether that leg is a file's own line
/// (`kept`): keys an older build does not read and a row without them does
/// not have.
String encodeWaypoints(List<Waypoint> waypoints, {List<SavedLeg>? legs}) {
  final withLegs = legs != null && legs.length == waypoints.length - 1;
  return jsonEncode(<Map<String, dynamic>>[
    for (var i = 0; i < waypoints.length; i++)
      <String, dynamic>{
        ...waypoints[i].toMap(),
        if (withLegs && i < legs.length) 'leg': legs[i].start,
        if (withLegs && i < legs.length && legs[i].kept) 'kept': true,
      },
  ]);
}

/// The legs stored in the `waypoints_json` column, or `null` when the row
/// has none — saved before legs were, or without them.
List<SavedLeg>? decodeLegs(String json) {
  final decoded = _tryDecode(json);
  if (decoded is! List || decoded.length < 2) return null;
  final legs = <SavedLeg>[];
  for (var i = 0; i < decoded.length - 1; i++) {
    final entry = decoded[i];
    if (entry is! Map<String, dynamic>) return null;
    final start = entry['leg'];
    if (start is! int) return null;
    legs.add(SavedLeg(start: start, kept: entry['kept'] == true));
  }
  return legs;
}

/// Parses the `waypoints_json` column; anything unreadable yields an empty
/// list rather than breaking the library.
List<Waypoint> decodeWaypoints(String json) {
  final decoded = _tryDecode(json);
  if (decoded is! List) return const <Waypoint>[];
  final out = <Waypoint>[];
  for (final entry in decoded) {
    if (entry is Map<String, dynamic>) out.add(Waypoint.fromMap(entry));
  }
  return normalizeWaypointKinds(out);
}

/// Parses the `routing_options_json` column.
RoutingOptions decodeOptions(String json) {
  final decoded = _tryDecode(json);
  if (decoded is! Map<String, dynamic>) return const RoutingOptions();
  return RoutingOptions.fromMap(decoded);
}

/// The `surface_stats_json` column, as [SurfaceStats.toJson] writes it. The
/// rides table stores its matched surface in the same shape.
Map<String, dynamic> encodeSurfaceStats(SurfaceStats stats) => stats.toJson();

/// The `pois_json` column: null rather than `[]` for a route without any.
String? encodePois(List<RoutePoi> pois) =>
    pois.isEmpty ? null : jsonEncode(pois.map((p) => p.toMap()).toList());

/// Parses the `pois_json` column; anything unreadable yields an empty list
/// rather than breaking the library.
List<RoutePoi> decodePois(String? json) {
  if (json == null || json.isEmpty) return const <RoutePoi>[];
  final decoded = _tryDecode(json);
  if (decoded is! List) return const <RoutePoi>[];
  return <RoutePoi>[
    for (final entry in decoded)
      if (entry is Map<String, dynamic>) RoutePoi.fromMap(entry),
  ];
}

/// The `turns_json` column: null rather than `[]` for a route without turn
/// instructions, so the column stays empty for everything that never went
/// through the router.
String? encodeTurns(List<TurnHint> turns) =>
    turns.isEmpty ? null : jsonEncode(turns.map((t) => t.toMap()).toList());

/// Parses the `turns_json` column; anything unreadable yields an empty list
/// rather than breaking the library.
List<TurnHint> decodeTurns(String? json) {
  if (json == null || json.isEmpty) return const <TurnHint>[];
  final decoded = _tryDecode(json);
  if (decoded is! List) return const <TurnHint>[];
  final out = <TurnHint>[];
  for (final entry in decoded) {
    if (entry is! Map) continue;
    final hint = TurnHint.fromMap(entry);
    if (hint != null) out.add(hint);
  }
  return out;
}

/// Parses the `surface_stats_json` column.
SurfaceStats? decodeSurfaceStats(String? json) {
  if (json == null || json.isEmpty) return null;
  final decoded = _tryDecode(json);
  if (decoded is! Map<String, dynamic>) return null;
  return SurfaceStats.fromJson(decoded);
}

Object? _tryDecode(String json) {
  try {
    return jsonDecode(json);
  } on FormatException {
    return null;
  }
}

/// The repository over the app database.
@Riverpod(keepAlive: true)
RouteRepository routeRepository(Ref ref) =>
    RouteRepository(ref.watch(routesDaoProvider));

/// Every saved route, newest first.
@riverpod
Stream<List<SavedRoute>> savedRoutes(Ref ref) =>
    ref.watch(routeRepositoryProvider).watchRoutes();

/// One saved route, `null` once it is deleted.
@riverpod
Stream<SavedRoute?> savedRoute(Ref ref, String id) =>
    ref.watch(routeRepositoryProvider).watchRoute(id);
