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

  /// Content digest of the rd5 as the mirror published it, or the one worked
  /// out on the device; null while unknown.
  TextColumn get contentSha256 => text().nullable()();

  /// The same for the tile's `.gaz`; null while unknown or without one.
  TextColumn get gazetteerContentSha256 => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}
