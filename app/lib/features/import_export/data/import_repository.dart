import 'package:drift/drift.dart' show Value;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/db/daos/rides_dao.dart';
import '../../../core/db/database.dart';
import '../../../core/geo/ride_stats.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/domain/saved_route.dart';
import '../domain/imported_track.dart';

part 'import_repository.g.dart';

/// Writes an [ImportedTrack] into the library, as a route or as a ride.
///
/// This is the only place that turns an import into a database row, so the
/// preview screen does not have to know about either table.
class ImportRepository {
  /// Creates a repository over the two stores an import can land in.
  ImportRepository(
    this._routes,
    this._rides, {
    Uuid? uuid,
    DateTime Function()? clock,
  }) : _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now;

  final RouteRepository _routes;
  final RidesDao _rides;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Saves [track] as a `routes` row called [name].
  ///
  /// Without a [source] the format decides it, so the library can tell a GPX
  /// import from a FIT one. A route that came out of a partner service passes
  /// [RouteSource.strava] or [RouteSource.rwgps] instead, which is what later
  /// rules key off — AI descriptions are disabled for Strava-sourced routes,
  /// and Strava's seven-day cache rule applies to them.
  ///
  /// [externalIds] and [externalFetchedAt] record where it came from; they are
  /// written after the row exists, so an import without them is unchanged.
  Future<SavedRoute> saveAsRoute({
    required String name,
    required ImportedTrack track,
    RouteSource? source,
    Map<String, Object?>? externalIds,
    DateTime? externalFetchedAt,
  }) async {
    final saved = await _routes.saveImportedRoute(
      name: name,
      points: track.points,
      source: source ?? sourceForFormat(track.format),
      description: track.description,
      pois: track.pois,
    );
    if (externalIds != null && externalIds.isNotEmpty) {
      await _routes.markExternal(
        saved.id,
        externalIds: externalIds,
        fetchedAt: externalFetchedAt ?? _clock(),
      );
    }
    return saved;
  }

  /// The source a plain file import gets.
  static RouteSource sourceForFormat(ImportFormat format) => switch (format) {
    ImportFormat.gpx => RouteSource.importedGpx,
    ImportFormat.fit => RouteSource.importedFit,
  };

  /// Saves [track] as a `rides` row called [name] and returns it.
  ///
  /// Every statistic comes from [computeImportedStats], so an imported ride is
  /// measured with the very same rules as a recorded one — pause gaps and
  /// implausible jumps included. A file without timestamps still imports: it
  /// keeps its distance and its climb but gets a zero moving time and the
  /// current instant as its start, which is the honest answer for a track that
  /// never said when it happened.
  Future<RideRow> saveAsRide({
    required String name,
    required ImportedTrack track,
  }) async {
    if (track.points.isEmpty) {
      throw ArgumentError.value(track, 'track', 'an imported ride is empty');
    }
    final stats = computeImportedStats(track.points);
    final startedAt = stats.startedAt ?? _clock();
    final row = RideRow(
      id: _uuid.v4(),
      name: name,
      startedAt: startedAt,
      endedAt: stats.endedAt ?? startedAt.add(stats.elapsedTime),
      distanceM: stats.distanceM,
      movingTimeS: stats.movingTime.inSeconds,
      elapsedTimeS: stats.elapsedTime.inSeconds,
      ascentM: stats.ascentM,
      descentM: stats.descentM,
      avgSpeedMps: stats.avgSpeedMps,
      maxSpeedMps: stats.maxSpeedMps,
      geometry: PackedTrack.encode(track.points),
      pausesJson: '[]',
      notes: track.description,
    );
    await _rides.upsertRide(
      RidesCompanion.insert(
        id: row.id,
        name: row.name,
        startedAt: row.startedAt,
        endedAt: row.endedAt,
        distanceM: row.distanceM,
        movingTimeS: row.movingTimeS,
        elapsedTimeS: row.elapsedTimeS,
        ascentM: row.ascentM,
        descentM: row.descentM,
        avgSpeedMps: row.avgSpeedMps,
        maxSpeedMps: row.maxSpeedMps,
        geometry: row.geometry,
        pausesJson: row.pausesJson,
        notes: Value(row.notes),
      ),
    );
    return row;
  }
}

/// The import repository over the app database.
@Riverpod(keepAlive: true)
ImportRepository importRepository(Ref ref) => ImportRepository(
  ref.watch(routeRepositoryProvider),
  ref.watch(ridesDaoProvider),
);
