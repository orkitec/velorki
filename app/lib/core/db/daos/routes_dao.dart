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

  /// The id, external ids and dates of every route read from Strava or
  /// edited from one, oldest check first, without the geometry.
  Future<List<StravaRouteCheck>> stravaRouteChecks() async {
    final query = selectOnly(routes)
      ..addColumns([
        routes.id,
        routes.externalIdsJson,
        routes.externalFetchedAt,
        routes.createdAt,
      ])
      ..where(_fromStrava(routes))
      ..orderBy([OrderingTerm.asc(routes.externalFetchedAt)]);
    return [
      for (final row in await query.get())
        StravaRouteCheck(
          id: row.read(routes.id)!,
          externalIdsJson: row.read(routes.externalIdsJson),
          checkedAt:
              row.read(routes.externalFetchedAt) ?? row.read(routes.createdAt)!,
        ),
    ];
  }

  /// Records that route [id] was found on its service at [at], and nothing
  /// else: the rider's edits and the card's date stay.
  Future<int> setExternalFetchedAt(String id, DateTime at) =>
      (update(routes)..where((t) => t.id.equals(id))).write(
        RoutesCompanion(externalFetchedAt: Value(at)),
      );

  /// Deletes every route read from Strava, or edited from one: the rows
  /// with the Strava source and the rows that carry a Strava route id.
  /// Returns how many went.
  Future<int> deleteStravaRoutes() => (delete(routes)..where(_fromStrava)).go();

  /// How many routes the rider keeps in the library, as a stream that
  /// follows the table: the planned, the generated and the imported ones,
  /// not the routes read from Strava, which are a cache of the account.
  Stream<int> watchKeptRouteCount() {
    final count = routes.id.count();
    final query = selectOnly(routes)
      ..addColumns([count])
      ..where(routes.source.equalsValue(RouteSource.strava).not());
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  static Expression<bool> _fromStrava($RoutesTable t) =>
      t.source.equalsValue(RouteSource.strava) |
      t.externalIdsJson.like('%"strava_route_id"%');

  SimpleSelectStatement<$RoutesTable, RouteRow> _ordered() =>
      select(routes)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
}

/// What the Strava route check needs of one row.
class StravaRouteCheck {
  /// Creates the record.
  const StravaRouteCheck({
    required this.id,
    required this.externalIdsJson,
    required this.checkedAt,
  });

  /// The row's id.
  final String id;

  /// The `external_ids_json` column.
  final String? externalIdsJson;

  /// When the route was last read from or found on Strava; its creation for
  /// a row that never was.
  final DateTime checkedAt;
}
