import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/db/daos/routes_dao.dart';
import '../../../core/db/database.dart';
import '../../../core/geo/ride_stats.dart';
import '../domain/route_profile.dart';
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
  Future<SavedRoute> savePlannedRoute({
    required String name,
    required RouteResult route,
    required List<Waypoint> waypoints,
    required RoutingOptions options,
    String? id,
    String? description,
    RouteSource source = RouteSource.planned,
  }) async {
    final now = _clock();
    final existing = id == null ? null : await _dao.routeById(id);
    final saved = SavedRoute(
      id: id ?? _uuid.v4(),
      name: name,
      description: description,
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
      surfaceStats: route.messages.isEmpty ? null : route.surfaceStats,
      turns: route.turns,
    );
    await _dao.upsertRoute(toCompanion(saved));
    return saved;
  }

  /// Writes a route that came out of a file rather than out of the router.
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
    final saved = SavedRoute(
      id: id ?? _uuid.v4(),
      name: name,
      description: description,
      source: source,
      profile: options.profile,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      distanceM: geometry.distanceM,
      ascentM: geometry.ascentM,
      descentM: geometry.descentM,
      bounds: BoundingBox.fromPoints(points.map((p) => p.pos)),
      geometryBlob: PackedTrack.encode(points),
      waypoints: waypoints ?? ends,
      options: options,
      pois: pois,
      turns: turns,
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
    options: decodeOptions(row.routingOptionsJson),
    surfaceStats: decodeSurfaceStats(row.surfaceStatsJson),
    turns: decodeTurns(row.turnsJson),
    aiDescriptionGenerated: row.aiDescriptionGenerated,
    pois: decodePois(row.poisJson),
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
    waypointsJson: encodeWaypoints(route.waypoints),
    routingOptionsJson: jsonEncode(route.options.toMap()),
    surfaceStatsJson: Value(
      route.surfaceStats == null
          ? null
          : jsonEncode(encodeSurfaceStats(route.surfaceStats!)),
    ),
    turnsJson: Value(encodeTurns(route.turns)),
    aiDescriptionGenerated: Value(route.aiDescriptionGenerated),
    poisJson: Value(encodePois(route.pois)),
  );

  BoundingBox _boundsOf(List<Waypoint> waypoints) => waypoints.isEmpty
      ? const BoundingBox(south: 0, west: 0, north: 0, east: 0)
      : BoundingBox.fromPoints(waypoints.map((w) => w.pos));
}

/// The `waypoints_json` column.
String encodeWaypoints(List<Waypoint> waypoints) =>
    jsonEncode(waypoints.map((w) => w.toMap()).toList());

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

/// The `surface_stats_json` column.
Map<String, dynamic> encodeSurfaceStats(SurfaceStats stats) =>
    <String, dynamic>{
      'paved': stats.pavedShare,
      'unpaved': stats.unpavedShare,
      'unknown': stats.unknownShare,
      'cycleway': stats.cyclewayShare,
      'busy': stats.busyShare,
      'coveredLengthM': stats.coveredLengthM,
      'totalLengthM': stats.totalLengthM,
    };

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
  double at(String key) => (decoded[key] as num? ?? 0).toDouble();
  return SurfaceStats(
    pavedShare: at('paved'),
    unpavedShare: at('unpaved'),
    unknownShare: at('unknown'),
    cyclewayShare: at('cycleway'),
    busyShare: at('busy'),
    coveredLengthM: at('coveredLengthM'),
    totalLengthM: at('totalLengthM'),
  );
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
