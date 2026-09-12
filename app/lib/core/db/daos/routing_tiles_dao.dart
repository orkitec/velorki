import 'package:drift/drift.dart';

import '../database.dart';

part 'routing_tiles_dao.g.dart';

/// The rd5 segment tiles downloaded for on-device routing.
///
/// One row per BRouter tile, keyed by its name (`E10_N45`). The row is the
/// record of what is on disk under `<appSupport>/brouter/segments/`; the file
/// itself is written by `TileDownloader`.
@DriftAccessor(tables: [RoutingTiles])
class RoutingTilesDao extends DatabaseAccessor<VelorkiDatabase>
    with _$RoutingTilesDaoMixin {
  /// Creates the accessor.
  RoutingTilesDao(super.db);

  /// Every known tile, by name.
  Future<List<RoutingTileRow>> allTiles() => _ordered().get();

  /// Every known tile, updated as rows change.
  Stream<List<RoutingTileRow>> watchTiles() => _ordered().watch();

  /// One tile, or `null` when it was never downloaded.
  Future<RoutingTileRow?> tileByName(String name) => (select(
    routingTiles,
  )..where((t) => t.name.equals(name))).getSingleOrNull();

  /// Writes [tile], replacing an existing row with the same name.
  Future<void> upsertTile(RoutingTilesCompanion tile) =>
      into(routingTiles).insertOnConflictUpdate(tile);

  /// Records that [name] is being downloaded, with the size the manifest
  /// promises so the list can show it before the file exists.
  Future<void> markDownloading(
    String name, {
    required int bytes,
    required DateTime updatedAt,
    required String formatVersion,
  }) => upsertTile(
    RoutingTilesCompanion.insert(
      name: name,
      bytes: bytes,
      updatedAt: updatedAt,
      formatVersion: formatVersion,
      state: RoutingTileState.downloading,
    ),
  );

  /// Records a finished download: the real size on disk and the manifest's
  /// date and format version.
  Future<void> markReady(
    String name, {
    required int bytes,
    required DateTime updatedAt,
    required String formatVersion,
  }) => upsertTile(
    RoutingTilesCompanion.insert(
      name: name,
      bytes: bytes,
      updatedAt: updatedAt,
      formatVersion: formatVersion,
      state: RoutingTileState.ready,
    ),
  );

  /// Moves [name] to [state] without touching its size or date.
  Future<int> setState(String name, RoutingTileState state) =>
      (update(routingTiles)..where((t) => t.name.equals(name))).write(
        RoutingTilesCompanion(state: Value(state)),
      );

  /// Drops the row for [name].
  Future<int> deleteTile(String name) =>
      (delete(routingTiles)..where((t) => t.name.equals(name))).go();

  SimpleSelectStatement<$RoutingTilesTable, RoutingTileRow> _ordered() =>
      select(routingTiles)..orderBy([(t) => OrderingTerm.asc(t.name)]);
}
