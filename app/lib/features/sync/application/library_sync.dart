import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:logging/logging.dart';

import '../../../core/db/database.dart';
import '../../../core/db/daos/sync_dao.dart';
import '../data/record_codec.dart';
import '../data/sync_backend.dart';
import '../domain/cloud_record.dart';

/// Logs record names and decisions only, never a route's or ride's
/// content; `initLogging` sends it to the device log in release builds.
final Logger _log = Logger('velorki.sync.library');

/// What became of one record from iCloud.
enum _Applied {
  /// Written here.
  written,

  /// The very change this device has; only the server's tag was kept.
  sameChange,

  /// The change here is newer and goes over the server's copy.
  localWins,

  /// The record could not be read (no body, no line, a name not known).
  unreadable,
}

/// Keeps the routes and rides in step with the rider's cloud through a
/// [SyncBackend] ("iCloud" below stands for whichever one it is).
///
/// Local changes are found in `sync_records` (the triggers write it) and
/// handed to the engine by record name; the engine asks for the records
/// when it sends, and brings back what other devices changed, which is
/// written here record by record. A conflict goes to the newer change: the
/// local one's time is its `changed_at_ms`, the remote one's the record's
/// `modifiedAt`; on a tie the server's copy wins, which every device
/// decides alike. A record deleted elsewhere goes here too, unless it has a
/// change here iCloud has not had yet, which brings it back.
///
/// Strava routes never leave the phone: they are never sent, and one that
/// was on iCloud before it became Strava's (which no path does today) is
/// deleted there.
class LibrarySync {
  /// Creates the sync over [db], sending through [backend].
  LibrarySync({
    required this._db,
    required this._backend,
    required this._codec,
    this.recordTimeout = const Duration(seconds: 60),
    this.openTimeout = const Duration(minutes: 3),
  });

  /// The longest the database may take to answer at all before the first
  /// record: a browser's first visit creates it in the origin private file
  /// system, which on a busy machine took over a minute.
  final Duration openTimeout;

  /// The longest one record from the cloud may take to be read and
  /// written. One that takes longer (a database that does not answer)
  /// ends the round with [RemoteApplyStalled]: the engine says so, and the
  /// next round brings what was left again.
  final Duration recordTimeout;

  final VelorkiDatabase _db;
  final SyncBackend _backend;
  final RecordCodec _codec;

  SyncDao get _sync => _db.syncDao;

  /// The version of each record handed out to be saved, by name: the save
  /// iCloud confirms only clears a change still at that version.
  final Map<String, int> _handedOut = <String, int>{};

  StreamSubscription<int>? _dirtyWatch;
  Timer? _debounce;
  Future<void>? _pushing;
  bool _pushAgain = false;

  /// Starts watching for local changes, and sends what is waiting.
  void start() {
    _dirtyWatch ??= _sync.watchDirtyCount().listen(
      (count) {
        if (count == 0) return;
        // A burst of writes (an import, a save with its legs) is sent once.
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 2), () => _pushQuietly());
      },
      onError: (Object e, StackTrace st) {
        _log.warning('no watch on the changes here: $e', e, st);
      },
    );
  }

  /// Stops watching. What is waiting stays marked for the next [start].
  Future<void> stop() async {
    _debounce?.cancel();
    _debounce = null;
    await _dirtyWatch?.cancel();
    _dirtyWatch = null;
  }

  /// Hands every waiting change to the engine. Runs one at a time; a call
  /// while one runs runs again after it.
  Future<void> push() {
    if (_pushing != null) {
      _pushAgain = true;
      return _pushing!;
    }
    return _pushing = _push().whenComplete(() {
      _pushing = null;
      if (_pushAgain) {
        _pushAgain = false;
        _pushQuietly();
      }
    });
  }

  /// [push] on its own: a failure (a database that does not answer) is
  /// logged, and what waits goes with the next push.
  void _pushQuietly() => unawaited(
    push().catchError((Object e, StackTrace st) {
      _log.warning('push failed: $e', e, st);
    }),
  );

  Future<void> _push() async {
    final dirty = await _sync.dirtyRecords();
    if (dirty.isEmpty) return;
    final strava = await _sync.stravaRouteIds();
    final saves = <String>[];
    final deletes = <String>[];
    for (final record in dirty) {
      final kind = SyncKind.fromColumn(record.kind);
      if (kind == null) continue;
      final name = recordNameOf(kind, record.recordId);
      final excluded =
          kind == SyncKind.route && strava.contains(record.recordId);
      if (record.deleted || excluded) {
        if (record.systemFields != null) {
          deletes.add(name);
        } else if (record.deleted) {
          // Never on iCloud: nothing to delete there.
          await _sync.forget(record.kind, record.recordId);
        } else {
          await _sync.markClean(record.kind, record.recordId);
        }
      } else {
        saves.add(name);
      }
    }
    if (saves.isNotEmpty || deletes.isNotEmpty) {
      _log.info('enqueue saves=$saves deletes=$deletes');
    }
    await _backend.enqueue(saves: saves, deletes: deletes);
  }

  /// The records named [names], ready to be saved.
  Future<List<CloudRecord>> recordsToSave(List<String> names) async {
    final strava = await _sync.stravaRouteIds();
    final out = <CloudRecord>[];
    for (final name in names) {
      final parsed = parseRecordName(name);
      if (parsed == null) continue;
      final (kind, id) = parsed;
      final sync = await _sync.record(kind.column, id);
      if (sync == null || sync.deleted) {
        _log.info(
          'not handed out $name: ${sync == null ? 'no row' : 'deleted'}',
        );
        continue;
      }
      try {
        final record = switch (kind) {
          SyncKind.route => await _routeRecord(id, sync, strava),
          SyncKind.ride => await _rideRecord(id, sync, strava),
        };
        if (record == null) {
          _log.info('not handed out $name: gone or Strava');
          continue;
        }
        _handedOut[name] = sync.version;
        out.add(record);
      } on Object catch (e, st) {
        _log.warning('could not encode $name', e, st);
      }
    }
    _log.info(
      'handed out ${[for (final r in out) '${r.name}@${_handedOut[r.name]}']}',
    );
    return out;
  }

  Future<CloudRecord?> _routeRecord(
    String id,
    SyncRecordRow sync,
    Set<String> strava,
  ) async {
    if (strava.contains(id)) return null;
    final row = await _db.routesDao.routeById(id);
    if (row == null) return null;
    return _codec.encodeRoute(
      row,
      changedAtMs: sync.changedAtMs,
      systemFields: sync.systemFields,
    );
  }

  Future<CloudRecord?> _rideRecord(
    String id,
    SyncRecordRow sync,
    Set<String> strava,
  ) async {
    final row = await _db.ridesDao.rideById(id);
    if (row == null) return null;
    final routeId = row.routeId ?? sync.pendingRouteId;
    return _codec.encodeRide(
      row,
      changedAtMs: sync.changedAtMs,
      // A ride keeps a route that stays on the phone to itself.
      routeId: routeId == null || strava.contains(routeId) ? null : routeId,
      systemFields: sync.systemFields,
    );
  }

  /// Writes what other devices changed: routes first, so the rides that
  /// follow them find them.
  Future<void> applyRemote(
    List<CloudRecord> modifications,
    List<String> deletions,
  ) async {
    final routes = modifications.where(
      (r) => parseRecordName(r.name)?.$1 == SyncKind.route,
    );
    final rides = modifications.where(
      (r) => parseRecordName(r.name)?.$1 == SyncKind.ride,
    );
    final open = Stopwatch()..start();
    try {
      await _sync.record('', '').timeout(openTimeout);
    } on TimeoutException {
      _log.warning(
        'the database did not answer in ${openTimeout.inSeconds} s: '
        'nothing applied, the round stops',
      );
      throw const RemoteApplyStalled('database');
    }
    if (open.elapsed > const Duration(seconds: 2)) {
      _log.info('the database answered after ${open.elapsed.inSeconds} s');
    }
    for (final record in [...routes, ...rides]) {
      final _Applied applied;
      try {
        applied = await _applyRecord(record).timeout(recordTimeout);
      } on TimeoutException {
        _log.warning(
          'could not apply ${record.name}: no answer after '
          '${recordTimeout.inSeconds} s, the round stops',
        );
        throw RemoteApplyStalled(record.name);
      } on Object catch (e, st) {
        _log.warning('could not apply ${record.name}: $e', e, st);
        continue;
      }
      _log.info('remote ${record.name}: ${applied.name}');
    }
    for (final name in deletions) {
      try {
        await _applyDeletion(name);
      } on Object catch (e, st) {
        _log.warning('could not apply the deletion of $name', e, st);
      }
    }
  }

  /// Whether the local change of [sync] beats a remote one made at
  /// [remoteMs]: only a newer one does.
  static bool _localWins(SyncRecordRow? sync, int remoteMs) =>
      sync != null && sync.dirty && sync.changedAtMs > remoteMs;

  /// Applies one record from iCloud.
  Future<_Applied> _applyRecord(CloudRecord record) async {
    final parsed = parseRecordName(record.name);
    if (parsed == null) return _Applied.unreadable;
    final (kind, id) = parsed;
    final remoteMs = RecordCodec.modifiedAtOf(record);
    final sync = await _sync.record(kind.column, id);
    if (sync != null &&
        !sync.dirty &&
        !sync.deleted &&
        sync.systemFields != null &&
        sync.changedAtMs == remoteMs) {
      // The very change this device has (its own save coming back, most
      // often): only the server's newer tag is news.
      if (record.systemFields != null) {
        await _sync.setSystemFields(kind.column, id, record.systemFields!);
      }
      return _Applied.sameChange;
    }
    if (_localWins(sync, remoteMs)) {
      // Ours is newer and goes over the server's copy on the next save.
      if (record.systemFields != null) {
        await _sync.setSystemFields(kind.column, id, record.systemFields!);
      }
      return _Applied.localWins;
    }
    switch (kind) {
      case SyncKind.route:
        _log.info('apply ${record.name}: decoding');
        final decoded = await _codec.decodeRoute(record);
        if (decoded == null) return _Applied.unreadable;
        _log.info('apply ${record.name}: writing');
        await _db.transaction(() async {
          await _writeRoute(decoded.row);
          await _sync.markApplied(
            kind.column,
            id,
            changedAtMs: decoded.modifiedAtMs,
            systemFields: record.systemFields,
          );
          await _linkWaitingRides(id);
        });
      case SyncKind.ride:
        _log.info('apply ${record.name}: decoding');
        final decoded = await _codec.decodeRide(record);
        if (decoded == null) return _Applied.unreadable;
        _log.info('apply ${record.name}: writing');
        await _db.transaction(() async {
          final pending = await _writeRide(decoded.row);
          await _sync.markApplied(
            kind.column,
            id,
            changedAtMs: decoded.modifiedAtMs,
            systemFields: record.systemFields,
            pendingRouteId: pending,
          );
        });
    }
    return _Applied.written;
  }

  Future<void> _writeRoute(RoutesCompanion row) async {
    final existing = await _db.routesDao.routeById(row.id.value);
    var write = row;
    // A breakdown matched here for the same line stays when the record has
    // none; each device can match its own.
    if (existing != null &&
        row.surfaceStatsJson.value == null &&
        existing.surfaceStatsJson != null &&
        _sameBytes(existing.geometry, row.geometry.value)) {
      write = write.copyWith(
        surfaceStatsJson: Value(existing.surfaceStatsJson),
      );
    }
    await _db.routesDao.upsertRoute(write);
  }

  /// Writes a ride; returns the route it waits for when that route is not
  /// here yet.
  Future<String?> _writeRide(RidesCompanion row) async {
    final existing = await _db.ridesDao.rideById(row.id.value);
    var write = row;
    String? pending;
    final routeId = row.routeId.value;
    if (routeId != null && await _db.routesDao.routeById(routeId) == null) {
      pending = routeId;
      write = write.copyWith(routeId: const Value(null));
    }
    if (existing != null &&
        row.surfaceStatsJson.value == null &&
        existing.surfaceStatsJson != null &&
        _sameBytes(existing.geometry, row.geometry.value)) {
      write = write.copyWith(
        surfaceStatsJson: Value(existing.surfaceStatsJson),
      );
    }
    await _db.ridesDao.upsertRide(write);
    return pending;
  }

  /// Links the rides that arrived before the route with [routeId], without
  /// making that a change of theirs.
  Future<void> _linkWaitingRides(String routeId) async {
    for (final waiting in await _sync.waitingFor(routeId)) {
      final ride = await _db.ridesDao.rideById(waiting.recordId);
      if (ride == null) continue;
      await _db.ridesDao.updateRide(ride.copyWith(routeId: Value(routeId)));
      if (waiting.dirty) {
        // A change of its own is still to be sent, now with the link.
        await _sync.clearPendingRoute(waiting.recordId);
      } else {
        await _sync.markApplied(
          SyncKind.ride.column,
          waiting.recordId,
          changedAtMs: waiting.changedAtMs,
          systemFields: waiting.systemFields,
        );
      }
    }
  }

  Future<void> _applyDeletion(String name) async {
    final parsed = parseRecordName(name);
    if (parsed == null) return;
    final (kind, id) = parsed;
    if (kind == SyncKind.route && (await _sync.stravaRouteIds()).contains(id)) {
      // Taken off iCloud because it is Strava's (this device's own delete
      // coming back): it stays here.
      _log.info('remote delete $name: kept, Strava');
      await _sync.clearSystemFields(kind.column, id);
      return;
    }
    final sync = await _sync.record(kind.column, id);
    if (sync != null && sync.dirty && !sync.deleted) {
      // Changed here since: it comes back, as a new record.
      _log.info('remote delete $name: kept, changed here');
      await _sync.clearSystemFields(kind.column, id);
      return;
    }
    _log.info('remote delete $name: deleted');
    await _db.transaction(() async {
      switch (kind) {
        case SyncKind.route:
          await _db.routesDao.deleteRoute(id);
        case SyncKind.ride:
          await _db.ridesDao.deleteRide(id);
      }
      // The delete came from iCloud: nothing to send back.
      await _sync.forget(kind.column, id);
    });
  }

  /// What the engine reports of a round of sending.
  Future<void> sent(SentChanges changes) async {
    final again = <String>[];
    var fetch = false;
    for (final MapEntry(key: name, value: systemFields)
        in changes.saved.entries) {
      final parsed = parseRecordName(name);
      if (parsed == null) continue;
      final (kind, id) = parsed;
      final version = _handedOut.remove(name);
      await _sync.markSaved(
        kind.column,
        id,
        systemFields: systemFields,
        version: version,
      );
      final after = await _sync.record(kind.column, id);
      if (after != null && after.dirty && !after.deleted) {
        // Changed again while it was on its way (or handed out before a
        // restart): the engine has let go of the name, so it is asked for
        // once more, now over the tag just saved.
        _log.info('saved $name@$version, changed since: again');
        again.add(name);
      } else {
        _log.info('saved $name@$version');
      }
    }
    for (final failed in changes.failedSaves) {
      final parsed = parseRecordName(failed.name);
      _handedOut.remove(failed.name);
      if (parsed == null) continue;
      final (kind, id) = parsed;
      switch (failed.failure) {
        case SaveFailure.conflict:
          final server = failed.serverRecord;
          // The newer of the two stays: the server's is written here, or
          // ours goes again over the server's change tag.
          final applied = server == null
              ? _Applied.unreadable
              : await _applyRecord(server);
          _log.info('conflict on ${failed.name}: ${applied.name}');
          switch (applied) {
            case _Applied.written:
            case _Applied.sameChange:
              break;
            case _Applied.localWins:
              again.add(failed.name);
            case _Applied.unreadable:
              // Without the server's copy whole there is no telling which
              // change is newer, and ours sent again over the same stale
              // tag would only be refused again: the fetch brings the
              // server's copy and decides, and what is left marked here is
              // sent on the next push.
              fetch = true;
          }
        case SaveFailure.unknownItem:
          _log.info('save of ${failed.name} failed: not on the server, as new');
          await _sync.clearSystemFields(kind.column, id);
          again.add(failed.name);
        case SaveFailure.retrying:
        case SaveFailure.quotaExceeded:
        case SaveFailure.other:
          // Still marked: sent again on the next launch or return to the
          // app, or by the engine itself.
          _log.info('save of ${failed.name} failed: ${failed.failure.name}');
      }
    }
    final strava = await _sync.stravaRouteIds();
    for (final name in changes.deleted) {
      final parsed = parseRecordName(name);
      if (parsed == null) continue;
      final (kind, id) = parsed;
      _log.info('deleted $name');
      await _sync.markDeleted(kind.column, id);
      if (kind == SyncKind.route && strava.contains(id)) {
        await _sync.markClean(kind.column, id);
      }
    }
    for (final name in changes.failedDeletes) {
      _log.info('delete of $name failed');
    }
    if (again.isNotEmpty) {
      _log.info('enqueue again saves=$again');
      await _backend.enqueue(saves: again);
    }
    if (fetch) await _backend.fetchNow();
  }

  /// Starts over: everything here is sent as new, tombstones forgotten.
  /// What another account, a sign-out or a deleted zone leaves behind; the
  /// library itself is never touched.
  Future<void> reset() async {
    _handedOut.clear();
    await _sync.resetAll();
  }
}

/// A record from the cloud that was not written in
/// [LibrarySync.recordTimeout], or a database that did not answer in
/// [LibrarySync.openTimeout].
class RemoteApplyStalled implements Exception {
  /// Creates the failure.
  const RemoteApplyStalled(this.name);

  /// The record's name, or `database`.
  final String name;

  @override
  String toString() => 'RemoteApplyStalled($name)';
}

bool _sameBytes(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
