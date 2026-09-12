import 'package:drift/drift.dart';

import '../database.dart';

part 'rides_dao.g.dart';

@DriftAccessor(tables: [Rides])
class RidesDao extends DatabaseAccessor<VelorkiDatabase> with _$RidesDaoMixin {
  RidesDao(super.db);

  Future<List<RideRow>> allRides() => _ordered().get();

  Stream<List<RideRow>> watchRides() => _ordered().watch();

  /// The [limit] newest rides, for the "recent rides" block of the record tab.
  Stream<List<RideRow>> watchRecentRides({int limit = 5}) =>
      (_ordered()..limit(limit)).watch();

  Future<RideRow?> rideById(String id) =>
      (select(rides)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<RideRow?> watchRide(String id) =>
      (select(rides)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<void> upsertRide(RidesCompanion ride) =>
      into(rides).insertOnConflictUpdate(ride);

  Future<bool> updateRide(RideRow ride) => update(rides).replace(ride);

  /// Gives the ride with [id] a new [name]; unknown ids change nothing.
  Future<int> renameRide(String id, String name) => (update(
    rides,
  )..where((t) => t.id.equals(id))).write(RidesCompanion(name: Value(name)));

  /// Replaces the `uploads_json` column of [id]; `null` clears it.
  Future<int> setRideUploads(String id, String? uploadsJson) =>
      (update(rides)..where((t) => t.id.equals(id))).write(
        RidesCompanion(uploadsJson: Value(uploadsJson)),
      );

  Future<int> deleteRide(String id) =>
      (delete(rides)..where((t) => t.id.equals(id))).go();

  SimpleSelectStatement<$RidesTable, RideRow> _ordered() =>
      select(rides)..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
}
