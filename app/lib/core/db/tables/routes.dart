import 'package:drift/drift.dart';

/// Where a route came from. Stored as the enum name, not its index.
enum RouteSource { planned, loop, importedGpx, importedFit, strava, rwgps }

@DataClassName('RouteRow')
class Routes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get source => textEnum<RouteSource>()();
  TextColumn get profile => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  RealColumn get distanceM => real()();
  RealColumn get ascentM => real()();
  RealColumn get descentM => real()();
  RealColumn get bboxMinLat => real()();
  RealColumn get bboxMinLon => real()();
  RealColumn get bboxMaxLat => real()();
  RealColumn get bboxMaxLon => real()();

  /// `velorki_geo` packed track, 32 bytes per point.
  BlobColumn get geometry => blob()();
  TextColumn get waypointsJson => text()();
  TextColumn get routingOptionsJson => text()();
  TextColumn get surfaceStatsJson => text().nullable()();

  /// The turn instructions as a JSON list of `TurnHint.toMap()`; null when the
  /// route has none.
  TextColumn get turnsJson => text().nullable()();

  /// The route's points of interest as a JSON list; null for a route without
  /// any and for rows saved before the app stored them.
  TextColumn get poisJson => text().nullable()();
  TextColumn get externalIdsJson => text().nullable()();

  /// Drives Strava's 7-day cache rule for imported routes.
  DateTimeColumn get externalFetchedAt => dateTime().nullable()();
  BoolColumn get aiDescriptionGenerated =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
