import 'package:drift/drift.dart';

import '../database.dart';

part 'offline_regions_dao.g.dart';

@DriftAccessor(tables: [OfflineRegions])
class OfflineRegionsDao extends DatabaseAccessor<VelorkiDatabase>
    with _$OfflineRegionsDaoMixin {
  OfflineRegionsDao(super.db);

  Future<List<OfflineRegionRow>> allRegions() => _ordered().get();

  Stream<List<OfflineRegionRow>> watchRegions() => _ordered().watch();

  Future<OfflineRegionRow?> regionById(String id) =>
      (select(offlineRegions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertRegion(OfflineRegionsCompanion region) =>
      into(offlineRegions).insertOnConflictUpdate(region);

  /// Records what MapLibre handed back once a download finished.
  Future<int> setDownloadResult(
    String id, {
    required int maplibreRegionId,
    required int sizeBytes,
    required DateTime downloadedAt,
  }) => (update(offlineRegions)..where((t) => t.id.equals(id))).write(
    OfflineRegionsCompanion(
      maplibreRegionId: Value(maplibreRegionId),
      sizeBytes: Value(sizeBytes),
      downloadedAt: Value(downloadedAt),
    ),
  );

  Future<int> deleteRegion(String id) =>
      (delete(offlineRegions)..where((t) => t.id.equals(id))).go();

  SimpleSelectStatement<$OfflineRegionsTable, OfflineRegionRow> _ordered() =>
      select(offlineRegions)..orderBy([(t) => OrderingTerm.asc(t.name)]);
}
