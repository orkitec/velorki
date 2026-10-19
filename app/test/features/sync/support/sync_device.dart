import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/sync/application/library_sync.dart';
import 'package:velorki/features/sync/data/cloud_store.dart';
import 'package:velorki/features/sync/data/record_codec.dart';
import 'package:velorki/features/sync/data/store_sync_backend.dart';
import 'package:velorki/features/sync/data/sync_backend.dart';
import 'package:velorki/features/sync/domain/cloud_record.dart';
import 'package:velorki/features/sync/domain/cloud_sync_status.dart';

/// [SyncEngineState] in a map that outlives the engine, as the shared
/// preferences outlive a restart.
class MapSyncState implements SyncEngineState {
  final Map<String, String> values = <String, String>{};

  @override
  String? read(String key) => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
}

/// One phone or tablet: its own database, engine state and engine over the
/// shared store, and a handler that does what the controller does.
class SyncDevice implements CloudSyncHandler {
  SyncDevice(
    this.store,
    Directory dir,
    String name, {
    this.batchSize = 20,
    this.syncsSettings = true,
  }) : db = VelorkiDatabase.memory(),
       _dir = Directory('${dir.path}/$name');

  final VelorkiDatabase db;
  final CloudStore store;
  final Directory _dir;
  final int batchSize;
  final bool syncsSettings;
  final MapSyncState state = MapSyncState();
  late StoreSyncBackend engine;
  late LibrarySync sync;
  CloudSyncStatus status = const CloudSyncStatus();
  final List<Map<String, Object?>> settingsHeard = <Map<String, Object?>>[];
  final List<AccountChange> accountChanges = <AccountChange>[];
  StreamSubscription<CloudSyncStatus>? _statusSub;

  /// The app opened: a new engine over the state kept, a new library sync,
  /// and what waits handed over, as the controller's start does.
  Future<void> open() async {
    engine = StoreSyncBackend(
      store: store,
      state: state,
      inbox: () async => Directory('${_dir.path}/in'),
      batchSize: batchSize,
      syncsSettings: syncsSettings,
      scheduling: false,
    );
    sync = LibrarySync(
      db: db,
      backend: engine,
      codec: RecordCodec(Directory('${_dir.path}/out')),
    );
    engine.setHandler(this);
    _statusSub = engine.status.listen((s) => status = s);
    await engine.start();
    await sync.push();
  }

  /// The app killed: the database and the engine state stay.
  Future<void> close() async {
    await _statusSub?.cancel();
    await sync.stop();
    engine.setHandler(null);
    await engine.stop();
  }

  /// The status the engine sent last, once its stream has delivered it.
  Future<CloudSyncStatus> statusNow() async {
    await pumpEventQueue();
    return status;
  }

  Future<void> restart() async {
    await close();
    await open();
  }

  /// Hands the waiting changes over, sends them and fetches.
  Future<void> syncNow() async {
    await sync.push();
    await engine.sendNow();
    await engine.fetchNow();
  }

  Future<void> renameRoute(String id, String name) =>
      RouteRepository(db.routesDao).rename(id, name);

  Future<String?> routeName(String id) async =>
      (await db.routesDao.routeById(id))?.name;

  Future<List<String>> routeNames() async =>
      [for (final r in await db.routesDao.allRoutes()) r.name]..sort();

  Future<List<String>> rideNames() async =>
      [for (final r in await db.ridesDao.allRides()) r.name]..sort();

  Future<void> setChangedAt(String kind, String id, int ms) =>
      db.customStatement(
        'UPDATE sync_records SET changed_at_ms = ? WHERE kind = ? AND record_id = ?',
        [ms, kind, id],
      );

  @override
  Future<List<CloudRecord>> recordsToSave(List<String> names) =>
      sync.recordsToSave(names);

  @override
  Future<void> applyRemote(
    List<CloudRecord> modifications,
    List<String> deletions,
  ) => sync.applyRemote(modifications, deletions);

  @override
  Future<void> sent(SentChanges changes) => sync.sent(changes);

  @override
  Future<void> accountChanged(AccountChange change) async {
    accountChanges.add(change);
    await sync.reset();
    if (change != AccountChange.signOut) await sync.push();
  }

  @override
  Future<void> zoneDeleted(ZoneDeletion reason) async {}

  @override
  Future<void> settingsChanged(Map<String, Object?> values) async =>
      settingsHeard.add(values);
}
