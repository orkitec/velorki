import 'package:drift/drift.dart';

/// The columns of `routes` whose change is a change iCloud has to hear of.
/// Left out: `external_fetched_at`, the time a Strava route was last found
/// on Strava, and `surface_stats_json`, a breakdown every device can match
/// from its own tiles.
const List<String> _routeColumns = [
  'name',
  'description',
  'source',
  'profile',
  'created_at',
  'updated_at',
  'distance_m',
  'ascent_m',
  'descent_m',
  'bbox_min_lat',
  'bbox_min_lon',
  'bbox_max_lat',
  'bbox_max_lon',
  'geometry',
  'waypoints_json',
  'routing_options_json',
  'turns_json',
  'pois_json',
  'external_ids_json',
  'ai_description_generated',
  'link',
  'creator',
  'original_json',
  'original_geometry',
  'turns_generated',
];

/// The same for `rides`. Left out: `uploads_json`, where the ride was
/// uploaded to, which never leaves the phone, and `surface_stats_json`.
const List<String> _rideColumns = [
  'name',
  'started_at',
  'ended_at',
  'distance_m',
  'moving_time_s',
  'elapsed_time_s',
  'ascent_m',
  'descent_m',
  'avg_speed_mps',
  'max_speed_mps',
  'avg_heart_rate_bpm',
  'max_heart_rate_bpm',
  'avg_cadence_rpm',
  'avg_power_w',
  'route_id',
  'geometry',
  'pauses_json',
  'notes',
  'laps_json',
  'device_totals_json',
  'temperatures',
  'source_format',
  'creator',
];

/// Milliseconds since the epoch, in SQL.
const String _nowMs =
    "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)";

/// Marks the row of [kind] with id [id] (an SQL expression) changed, or
/// deleted with [deleted].
String _mark(String kind, String id, {required bool deleted}) =>
    '''
INSERT INTO sync_records (kind, record_id, changed_at_ms, version, dirty, deleted)
VALUES ('$kind', $id, $_nowMs, 1, 1, ${deleted ? 1 : 0})
ON CONFLICT (kind, record_id) DO UPDATE SET
  changed_at_ms = excluded.changed_at_ms,
  version = sync_records.version + 1,
  dirty = 1,
  deleted = ${deleted ? 1 : 0};''';

List<String> _triggersFor(String table, String kind, List<String> columns) {
  final changed = [
    'OLD.id IS NOT NEW.id',
    for (final c in columns) 'OLD.$c IS NOT NEW.$c',
  ].join(' OR ');
  return [
    'CREATE TRIGGER IF NOT EXISTS sync_${table}_insert AFTER INSERT ON $table '
        "BEGIN ${_mark(kind, 'NEW.id', deleted: false)} END",
    'CREATE TRIGGER IF NOT EXISTS sync_${table}_update AFTER UPDATE ON $table '
        "WHEN $changed BEGIN ${_mark(kind, 'NEW.id', deleted: false)} END",
    'CREATE TRIGGER IF NOT EXISTS sync_${table}_delete AFTER DELETE ON $table '
        "BEGIN ${_mark(kind, 'OLD.id', deleted: true)} END",
  ];
}

/// The triggers that keep `sync_records` in step with `routes` and `rides`:
/// every insert, every change that matters and every delete marks the row.
List<String> get syncTriggerStatements => [
  ..._triggersFor('routes', 'route', _routeColumns),
  ..._triggersFor('rides', 'ride', _rideColumns),
];

/// Creates the triggers on [db].
Future<void> createSyncTriggers(DatabaseConnectionUser db) async {
  for (final statement in syncTriggerStatements) {
    await db.customStatement(statement);
  }
}

/// Marks every route and ride there is as changed and never sent: what the
/// first sync of a library that existed before needs.
Future<void> markLibraryUnsynced(DatabaseConnectionUser db) async {
  for (final (table, kind) in const [('routes', 'route'), ('rides', 'ride')]) {
    await db.customStatement(
      '''
INSERT INTO sync_records (kind, record_id, changed_at_ms, version, dirty, deleted)
SELECT '$kind', id, $_nowMs, 1, 1, 0 FROM $table WHERE true
ON CONFLICT (kind, record_id) DO UPDATE SET
  dirty = 1, deleted = 0, system_fields = NULL, version = sync_records.version + 1''',
    );
  }
}
