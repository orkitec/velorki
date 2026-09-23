import 'package:drift/drift.dart';

import 'routes.dart';

@DataClassName('RideRow')
class Rides extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  RealColumn get distanceM => real()();
  IntColumn get movingTimeS => integer()();
  IntColumn get elapsedTimeS => integer()();
  RealColumn get ascentM => real()();
  RealColumn get descentM => real()();
  RealColumn get avgSpeedMps => real()();
  RealColumn get maxSpeedMps => real()();

  /// What the paired sensors averaged over the ride; null when none reported.
  IntColumn get avgHeartRateBpm => integer().nullable()();
  IntColumn get maxHeartRateBpm => integer().nullable()();
  IntColumn get avgCadenceRpm => integer().nullable()();
  IntColumn get avgPowerW => integer().nullable()();

  /// Deleting the followed route keeps the ride; the link is simply cleared.
  TextColumn get routeId =>
      text().nullable().references(Routes, #id, onDelete: KeyAction.setNull)();

  /// Packed track including timestamps; the recording journal uses the same
  /// layout so finalising a ride is a copy.
  BlobColumn get geometry => blob()();
  TextColumn get pausesJson => text()();
  TextColumn get uploadsJson => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// The surface breakdown matched from the routing tiles, as
  /// `SurfaceStats.toJson`, or `{"unavailable": true}` once matching failed
  /// for good; null until it was tried.
  TextColumn get surfaceStatsJson => text().nullable()();

  /// The laps the recording device cut, as JSON; null for a ride without.
  TextColumn get lapsJson => text().nullable()();

  /// The totals the recording device wrote for the ride, as JSON; null for
  /// a ride recorded here.
  TextColumn get deviceTotalsJson => text().nullable()();

  /// One signed 16-bit tenth of a degree per point of [geometry], the
  /// absent sentinel where a point had none; null for a ride without.
  BlobColumn get temperatures => blob().nullable()();

  /// The format of the file an imported ride came from (`gpx`, `fit`);
  /// null for a ride recorded here.
  TextColumn get sourceFormat => text().nullable()();

  /// Who wrote that file, its creator or the device's maker.
  TextColumn get creator => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
