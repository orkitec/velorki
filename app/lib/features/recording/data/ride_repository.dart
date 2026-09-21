import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:velorki_brouter/velorki_brouter.dart' show SurfaceStats;
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/db/daos/rides_dao.dart';
import '../../../core/db/database.dart';
import '../../../core/geo/ride_stats.dart';
import '../domain/ride.dart';
import '../domain/ride_upload.dart';

/// Reads and writes the `rides` table in the recorder's terms.
class RideRepository {
  /// Creates a repository over [dao].
  RideRepository(this._dao);

  final RidesDao _dao;

  /// Every ride, newest first, as a stream that follows the database.
  Stream<List<Ride>> watchRides() =>
      _dao.watchRides().map((rows) => rows.map(toDomain).toList());

  /// The [limit] newest rides.
  Stream<List<Ride>> watchRecentRides({int limit = 5}) =>
      _dao.watchRecentRides(limit: limit).map((r) => r.map(toDomain).toList());

  /// One ride as a stream, `null` once it is deleted.
  Stream<Ride?> watchRide(String id) =>
      _dao.watchRide(id).map((row) => row == null ? null : toDomain(row));

  /// One ride, or `null` when the id is unknown.
  Future<Ride?> rideById(String id) async {
    final row = await _dao.rideById(id);
    return row == null ? null : toDomain(row);
  }

  /// Gives the ride with [id] a new [name].
  Future<void> rename(String id, String name) => _dao.renameRide(id, name);

  /// Deletes the ride with [id].
  Future<void> delete(String id) => _dao.deleteRide(id);

  /// Writes [ride] exactly as it is, which is what undoing a delete needs.
  Future<void> save(Ride ride) => _insert(ride);

  /// Turns a recorded track into a `rides` row.
  ///
  /// The statistics are computed from [points] with the very same rules the
  /// recorder used live, so the finished ride shows the numbers the rider saw
  /// — the seams among [pauses] included, which is what keeps a continued
  /// ride from counting the hand-over as riding.
  Future<Ride> finalizeRide({
    required String rideId,
    required String name,
    required List<TrackPoint> points,
    required DateTime startedAt,
    required DateTime endedAt,
    String? routeId,
    List<RidePause> pauses = const <RidePause>[],
    String? notes,
  }) async {
    final stats = computeRideStats(points, breaks: statsBreaksOf(pauses));
    final ride = Ride(
      id: rideId,
      name: name,
      startedAt: stats.startedAt ?? startedAt,
      endedAt: stats.endedAt ?? endedAt,
      stats: stats,
      geometry: PackedTrack.encode(points),
      routeId: routeId,
      pauses: pauses,
      notes: notes,
    );
    await _insert(ride);
    return ride;
  }

  /// Remembers where the ride with [rideId] was uploaded to.
  ///
  /// One entry per service, merged into whatever is already there, so a Strava
  /// upload does not forget a Ride with GPS one. Writing the column rather
  /// than the whole row keeps the geometry out of the statement.
  ///
  /// An unknown id changes nothing.
  Future<void> recordUpload(
    String rideId, {
    required String serviceId,
    required RideUpload upload,
  }) async {
    final row = await _dao.rideById(rideId);
    if (row == null) return;
    final merged = <String, RideUpload>{
      ...decodeRideUploads(row.uploadsJson),
      serviceId: upload,
    };
    await _dao.setRideUploads(rideId, encodeRideUploads(merged));
  }

  /// Forgets every upload record of [rideId].
  ///
  /// A continued ride is not the ride that was sent any more: it has to be
  /// sent again, and the detail screen has to offer that rather than "View on
  /// Strava".
  Future<void> clearUploads(String rideId) => _dao.setRideUploads(rideId, null);

  /// Forgets the upload record of [serviceId], which is what a failed retry
  /// of a ride that was never accepted should leave behind.
  Future<void> clearUpload(String rideId, {required String serviceId}) async {
    final row = await _dao.rideById(rideId);
    if (row == null) return;
    final remaining = <String, RideUpload>{
      ...decodeRideUploads(row.uploadsJson),
    }..remove(serviceId);
    await _dao.setRideUploads(
      rideId,
      remaining.isEmpty ? null : encodeRideUploads(remaining),
    );
  }

  /// Keeps the surface breakdown matched for [rideId], so the page never
  /// routes the track twice. An unknown id changes nothing.
  Future<void> setSurface(String rideId, SurfaceStats stats) =>
      _dao.setRideSurface(
        rideId,
        encodeRideSurface(RideSurfaceCache(stats: stats)),
      );

  /// Remembers that the track of [rideId] could not be matched, so it is not
  /// tried again on every open. A new tile clears the marker.
  Future<void> markSurfaceUnavailable(String rideId) => _dao.setRideSurface(
    rideId,
    encodeRideSurface(RideSurfaceCache.unmatched),
  );

  /// Maps a database row into the domain model.
  Ride toDomain(RideRow row) => Ride(
    id: row.id,
    name: row.name,
    startedAt: row.startedAt,
    endedAt: row.endedAt,
    stats: RideStats(
      distanceM: row.distanceM,
      movingTime: Duration(seconds: row.movingTimeS),
      elapsedTime: Duration(seconds: row.elapsedTimeS),
      ascentM: row.ascentM,
      descentM: row.descentM,
      maxSpeedMps: row.maxSpeedMps,
      pointCount: PackedTrack.pointCount(Uint8List.fromList(row.geometry)),
      startedAt: row.startedAt,
      endedAt: row.endedAt,
      avgHeartRateBpm: row.avgHeartRateBpm,
      maxHeartRateBpm: row.maxHeartRateBpm,
      avgCadenceRpm: row.avgCadenceRpm,
      avgPowerW: row.avgPowerW,
    ),
    geometry: Uint8List.fromList(row.geometry),
    routeId: row.routeId,
    pauses: decodeRidePauses(row.pausesJson),
    uploads: decodeRideUploads(row.uploadsJson),
    notes: row.notes,
    surface: decodeRideSurface(row.surfaceStatsJson),
  );

  /// Maps the domain model into a row for `INSERT OR REPLACE`.
  RidesCompanion toCompanion(Ride ride) => RidesCompanion.insert(
    id: ride.id,
    name: ride.name,
    startedAt: ride.startedAt,
    endedAt: ride.endedAt,
    distanceM: ride.stats.distanceM,
    movingTimeS: ride.stats.movingTime.inSeconds,
    elapsedTimeS: ride.stats.elapsedTime.inSeconds,
    ascentM: ride.stats.ascentM,
    descentM: ride.stats.descentM,
    avgSpeedMps: ride.stats.avgSpeedMps,
    maxSpeedMps: ride.stats.maxSpeedMps,
    avgHeartRateBpm: Value(ride.stats.avgHeartRateBpm),
    maxHeartRateBpm: Value(ride.stats.maxHeartRateBpm),
    avgCadenceRpm: Value(ride.stats.avgCadenceRpm),
    avgPowerW: Value(ride.stats.avgPowerW),
    routeId: Value(ride.routeId),
    geometry: ride.geometry,
    pausesJson: encodeRidePauses(ride.pauses),
    uploadsJson: Value(
      ride.uploads.isEmpty ? null : encodeRideUploads(ride.uploads),
    ),
    notes: Value(ride.notes),
    surfaceStatsJson: Value(
      ride.surface == null ? null : encodeRideSurface(ride.surface!),
    ),
  );

  /// Writes the row, dropping the route link when the followed route was
  /// deleted while the ride was still being recorded.
  Future<void> _insert(Ride ride) async {
    try {
      await _dao.upsertRide(toCompanion(ride));
    } on SqliteException {
      if (ride.routeId == null) rethrow;
      await _dao.upsertRide(
        toCompanion(ride).copyWith(routeId: const Value<String?>(null)),
      );
    }
  }
}

/// The repository over the app database.
final rideRepositoryProvider = Provider<RideRepository>(
  (ref) => RideRepository(ref.watch(ridesDaoProvider)),
);

/// Every recorded ride, newest first.
final ridesProvider = StreamProvider.autoDispose<List<Ride>>(
  (ref) => ref.watch(rideRepositoryProvider).watchRides(),
);

/// One ride, `null` once it is deleted.
final rideProvider = StreamProvider.autoDispose.family<Ride?, String>(
  (ref, id) => ref.watch(rideRepositoryProvider).watchRide(id),
);
