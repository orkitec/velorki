import 'package:drift/drift.dart';

import '../database.dart';

part 'rides_dao.g.dart';

@DriftAccessor(tables: [Rides])
class RidesDao extends DatabaseAccessor<VelorkiDatabase> with _$RidesDaoMixin {
  RidesDao(super.db);

  Future<List<RideRow>> allRides() => _ordered().get();

  Stream<List<RideRow>> watchRides() => _ordered().watch();

  Future<RideRow?> rideById(String id) =>
      (select(rides)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<RideRow?> watchRide(String id) =>
      (select(rides)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<void> upsertRide(RidesCompanion ride) =>
      into(rides).insertOnConflictUpdate(ride);

  Future<bool> updateRide(RideRow ride) => update(rides).replace(ride);

  Future<int> deleteRide(String id) =>
      (delete(rides)..where((t) => t.id.equals(id))).go();

  SimpleSelectStatement<$RidesTable, RideRow> _ordered() =>
      select(rides)..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
}
