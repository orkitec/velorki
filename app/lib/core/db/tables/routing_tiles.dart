import 'package:drift/drift.dart';

enum RoutingTileState { absent, downloading, ready, stale }

@DataClassName('RoutingTileRow')
class RoutingTiles extends Table {
  /// BRouter rd5 segment name, e.g. `E10_N45`.
  TextColumn get name => text()();
  IntColumn get bytes => integer()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get formatVersion => text()();
  TextColumn get state => textEnum<RoutingTileState>()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}
