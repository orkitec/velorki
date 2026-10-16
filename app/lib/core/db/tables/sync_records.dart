import 'package:drift/drift.dart';

/// What iCloud sync knows about one route or ride: the outbox of local
/// changes and what the server last said about the record.
///
/// Rows are written by SQLite triggers on `routes` and `rides`
/// (`sync_triggers.dart`), so every way a row is written or deleted is
/// covered, and by the sync layer when it applies a change from iCloud or
/// hears that one was saved.
@DataClassName('SyncRecordRow')
class SyncRecords extends Table {
  /// `route` or `ride`.
  TextColumn get kind => text()();

  /// The id of the route or ride.
  TextColumn get recordId => text()();

  /// When the record was last changed, in milliseconds since the epoch: the
  /// local change, or the modification an applied iCloud record carried.
  /// The newer of two changes wins a conflict.
  IntColumn get changedAtMs => integer()();

  /// Counts the local changes, so a save iCloud confirms only clears
  /// [dirty] when nothing changed while it was on its way.
  IntColumn get version => integer().withDefault(const Constant(0))();

  /// Whether there is a local change iCloud has not confirmed yet.
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  /// A tombstone: the row was deleted here and the delete is still to be
  /// sent.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// The CloudKit record's system fields (its change tag) as the server
  /// last returned them; null while the record was never on the server.
  BlobColumn get systemFields => blob().nullable()();

  /// A ride from iCloud whose route had not arrived yet: the route's id,
  /// linked once that route is applied.
  TextColumn get pendingRouteId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {kind, recordId};
}
