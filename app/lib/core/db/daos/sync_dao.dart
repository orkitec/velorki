import 'package:drift/drift.dart';

import '../database.dart';
import '../sync_triggers.dart';

part 'sync_dao.g.dart';

/// The `sync_records` outbox; see [SyncRecords].
@DriftAccessor(tables: [SyncRecords, Routes, Rides])
class SyncDao extends DatabaseAccessor<VelorkiDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  /// Every record with a change iCloud has not confirmed.
  Future<List<SyncRecordRow>> dirtyRecords() =>
      (select(syncRecords)..where((t) => t.dirty.equals(true))).get();

  /// How many records wait to be sent, as a stream.
  Stream<int> watchDirtyCount() {
    final count = syncRecords.recordId.count();
    final query = selectOnly(syncRecords)
      ..addColumns([count])
      ..where(syncRecords.dirty.equals(true));
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// The record of [kind] with [id], or null.
  Future<SyncRecordRow?> record(String kind, String id) =>
      (select(syncRecords)
            ..where((t) => t.kind.equals(kind) & t.recordId.equals(id)))
          .getSingleOrNull();

  /// The ids of every route that is Strava data and so never leaves the
  /// phone: the same rule as [RoutesDao.deleteStravaRoutes].
  Future<Set<String>> stravaRouteIds() async {
    final query = selectOnly(routes)
      ..addColumns([routes.id])
      ..where(
        routes.source.equalsValue(RouteSource.strava) |
            routes.externalIdsJson.like('%"strava_route_id"%'),
      );
    return {for (final row in await query.get()) row.read(routes.id)!};
  }

  /// iCloud saved the record: keep its [systemFields], and clear the change
  /// when it is still the one that was sent ([version]; null when not
  /// known, which leaves the record to be sent again).
  Future<void> markSaved(
    String kind,
    String id, {
    required Uint8List systemFields,
    int? version,
  }) => customUpdate(
    'UPDATE sync_records SET system_fields = ?, '
    'dirty = CASE WHEN version = ? AND deleted = 0 THEN 0 ELSE dirty END '
    'WHERE kind = ? AND record_id = ?',
    variables: [
      Variable.withBlob(systemFields),
      Variable<int>(version ?? -1),
      Variable.withString(kind),
      Variable.withString(id),
    ],
    updates: {syncRecords},
  );

  /// iCloud deleted the record: a tombstone goes, a row that is still here
  /// (written again since, or sent as a delete because it may not be
  /// synced) loses its server copy.
  Future<void> markDeleted(String kind, String id) => transaction(() async {
    await (delete(syncRecords)..where(
          (t) =>
              t.kind.equals(kind) &
              t.recordId.equals(id) &
              t.deleted.equals(true),
        ))
        .go();
    await clearSystemFields(kind, id);
  });

  /// Leaves the record as it is but clean: nothing to send.
  Future<void> markClean(String kind, String id) =>
      (update(syncRecords)
            ..where((t) => t.kind.equals(kind) & t.recordId.equals(id)))
          .write(const SyncRecordsCompanion(dirty: Value(false)));

  /// Forgets the record altogether: a tombstone never sent, or a row iCloud
  /// deleted.
  Future<void> forget(String kind, String id) => (delete(
    syncRecords,
  )..where((t) => t.kind.equals(kind) & t.recordId.equals(id))).go();

  /// Forgets what the server had of the record, so it is sent as new.
  Future<void> clearSystemFields(String kind, String id) =>
      (update(syncRecords)
            ..where((t) => t.kind.equals(kind) & t.recordId.equals(id)))
          .write(const SyncRecordsCompanion(systemFields: Value(null)));

  /// Keeps the server's [systemFields] for a record whose local change won,
  /// so the next save goes over the server's copy.
  Future<void> setSystemFields(
    String kind,
    String id,
    Uint8List systemFields,
  ) =>
      (update(syncRecords)
            ..where((t) => t.kind.equals(kind) & t.recordId.equals(id)))
          .write(SyncRecordsCompanion(systemFields: Value(systemFields)));

  /// After a record from iCloud was written: it is what the server has, so
  /// nothing to send, changed when the server's copy was.
  Future<void> markApplied(
    String kind,
    String id, {
    required int changedAtMs,
    required Uint8List? systemFields,
    String? pendingRouteId,
  }) => into(syncRecords).insertOnConflictUpdate(
    SyncRecordsCompanion.insert(
      kind: kind,
      recordId: id,
      changedAtMs: changedAtMs,
      dirty: const Value(false),
      deleted: const Value(false),
      systemFields: Value(systemFields),
      pendingRouteId: Value(pendingRouteId),
    ),
  );

  /// The rides from iCloud still waiting for the route with [routeId].
  Future<List<SyncRecordRow>> waitingFor(String routeId) =>
      (select(syncRecords)..where(
            (t) => t.kind.equals('ride') & t.pendingRouteId.equals(routeId),
          ))
          .get();

  /// The ride [rideId] has its route now.
  Future<void> clearPendingRoute(String rideId) =>
      (update(syncRecords)
            ..where((t) => t.kind.equals('ride') & t.recordId.equals(rideId)))
          .write(const SyncRecordsCompanion(pendingRouteId: Value(null)));

  /// Starts over as if nothing had ever been synced: tombstones go, and
  /// every route and ride is to be sent as new. What signing out of iCloud,
  /// a different account or a reset zone needs.
  Future<void> resetAll() => transaction(() async {
    await (delete(syncRecords)..where((t) => t.deleted.equals(true))).go();
    await markLibraryUnsynced(this);
  });
}
