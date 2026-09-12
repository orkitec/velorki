import 'package:drift/drift.dart';

import '../database.dart';

part 'routes_dao.g.dart';

@DriftAccessor(tables: [Routes])
class RoutesDao extends DatabaseAccessor<VelorkiDatabase>
    with _$RoutesDaoMixin {
  RoutesDao(super.db);

  Future<List<RouteRow>> allRoutes() => _ordered().get();

  Stream<List<RouteRow>> watchRoutes() => _ordered().watch();

  Future<RouteRow?> routeById(String id) =>
      (select(routes)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<RouteRow?> watchRoute(String id) =>
      (select(routes)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<void> upsertRoute(RoutesCompanion route) =>
      into(routes).insertOnConflictUpdate(route);

  Future<bool> updateRoute(RouteRow route) => update(routes).replace(route);

  Future<int> deleteRoute(String id) =>
      (delete(routes)..where((t) => t.id.equals(id))).go();

  SimpleSelectStatement<$RoutesTable, RouteRow> _ordered() =>
      select(routes)..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
}
