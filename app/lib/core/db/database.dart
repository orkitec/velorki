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
  int get schemaVersion => 9;

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
      // 6 added the surface breakdown matched from the routing tiles; older
      // rides keep null and are matched when their page is next opened.
      if (from < 6) await m.addColumn(rides, rides.surfaceStatsJson);
      // 7 added what an imported activity file brought beyond the track:
      // the device's laps, its totals and a temperature per point.
      if (from < 7) {
        await m.addColumn(rides, rides.lapsJson);
        await m.addColumn(rides, rides.deviceTotalsJson);
        await m.addColumn(rides, rides.temperatures);
      }
      // 8 added where a route or ride came from: a link and a creator on a
      // route, the file format and the creator on a ride.
      if (from < 8) {
        await m.addColumn(routes, routes.link);
        await m.addColumn(routes, routes.creator);
        await m.addColumn(rides, rides.sourceFormat);
        await m.addColumn(rides, rides.creator);
      }
      // 9 kept the line and the markers a route was imported with, so it
      // can be put back after an edit; older routes keep null and take the
      // line they have as theirs.
      if (from < 9) {
        await m.addColumn(routes, routes.originalJson);
        await m.addColumn(routes, routes.originalGeometry);
      }
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
