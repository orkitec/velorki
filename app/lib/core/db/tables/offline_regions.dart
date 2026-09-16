import 'package:drift/drift.dart';

@DataClassName('OfflineRegionRow')
class OfflineRegions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get bboxMinLat => real()();
  RealColumn get bboxMinLon => real()();
  RealColumn get bboxMaxLat => real()();
  RealColumn get bboxMaxLon => real()();

  /// Id handed out by MapLibre's OfflineManager, null until the download runs.
  IntColumn get maplibreRegionId => integer().nullable()();
  IntColumn get sizeBytes => integer()();

  /// When the tiles were fetched; null for areas from before this was kept,
  /// which count as due for a refresh.
  DateTimeColumn get downloadedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
