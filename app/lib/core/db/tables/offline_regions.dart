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

  @override
  Set<Column<Object>> get primaryKey => {id};
}
