import 'package:drift/drift.dart';

/// Where a route came from. Stored as the enum name, not its index.
enum RouteSource {
  planned,
  loop,
  importedGpx,
  importedFit,
  strava,
  rwgps,
  importedTcx,
}

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

  /// A web address the route came with or was given.
  TextColumn get link => text().nullable()();

  /// Who wrote the file the route came from.
  TextColumn get creator => text().nullable()();

  /// A route read from a file: the file's own markers, where each leg
  /// between them starts, and its cue sheet, as JSON, written once at the
  /// import and never by an edit; null for a route planned here and for one
  /// imported before it was kept.
  TextColumn get originalJson => text().nullable()();

  /// The file's own line, packed like [geometry], once an edit saved over
  /// it; null while [geometry] still is that line.
  BlobColumn get originalGeometry => blob().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
