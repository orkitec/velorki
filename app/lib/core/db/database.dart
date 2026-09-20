import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'daos/offline_regions_dao.dart';
import 'daos/rides_dao.dart';
import 'daos/routes_dao.dart';
import 'daos/routing_tiles_dao.dart';
import 'tables/offline_regions.dart';
import 'tables/rides.dart';
import 'tables/routes.dart';
import 'tables/routing_tiles.dart';

export 'tables/offline_regions.dart';
export 'tables/rides.dart';
export 'tables/routes.dart';
export 'tables/routing_tiles.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Routes, Rides, OfflineRegions, RoutingTiles],
  daos: [RoutesDao, RidesDao, OfflineRegionsDao, RoutingTilesDao],
)
class VelorkiDatabase extends _$VelorkiDatabase {
  VelorkiDatabase(super.e);

  /// In-memory instance for tests.
  VelorkiDatabase.memory() : super(NativeDatabase.memory());

  /// The on-device database, opened on a background isolate.
  factory VelorkiDatabase.open() => VelorkiDatabase(_openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      // 2 added the turn instructions of a saved route; older rows keep null
      // and come back with an empty list.
      if (from < 2) await m.addColumn(routes, routes.turnsJson);
      // 3 added when an offline map area was downloaded; older areas keep
      // null and count as due for a refresh.
      if (from < 3) {
        await m.addColumn(offlineRegions, offlineRegions.downloadedAt);
      }
      // 4 added what the paired sensors averaged over a ride; rides recorded
      // without one keep null.
      if (from < 4) {
        await m.addColumn(rides, rides.avgHeartRateBpm);
        await m.addColumn(rides, rides.maxHeartRateBpm);
        await m.addColumn(rides, rides.avgCadenceRpm);
        await m.addColumn(rides, rides.avgPowerW);
      }
      // 5 added the points of interest a route was imported with; older
      // routes keep null and come back with an empty list.
      if (from < 5) await m.addColumn(routes, routes.poisJson);
    },
    beforeOpen: (_) async {
      // SQLite needs this per connection for the rides → routes foreign key.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

QueryExecutor _openConnection() => LazyDatabase(() async {
  final dir = await getApplicationDocumentsDirectory();
  return NativeDatabase.createInBackground(
    File(p.join(dir.path, 'velorki.sqlite')),
  );
});

@Riverpod(keepAlive: true)
VelorkiDatabase velorkiDatabase(Ref ref) {
  final db = VelorkiDatabase.open();
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
RoutesDao routesDao(Ref ref) => ref.watch(velorkiDatabaseProvider).routesDao;

@Riverpod(keepAlive: true)
RidesDao ridesDao(Ref ref) => ref.watch(velorkiDatabaseProvider).ridesDao;

@Riverpod(keepAlive: true)
OfflineRegionsDao offlineRegionsDao(Ref ref) =>
    ref.watch(velorkiDatabaseProvider).offlineRegionsDao;

@Riverpod(keepAlive: true)
RoutingTilesDao routingTilesDao(Ref ref) =>
    ref.watch(velorkiDatabaseProvider).routingTilesDao;
