import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/app_config.dart';
import 'cloud_store.dart';
import 'store_sync_backend.dart';
import 'sync_backend.dart';

part 'google_drive_sync.g.dart';

/// The hidden app data folder of the rider's Google Drive as a
/// [CloudStore], or null where Google sync is not offered. Null everywhere
/// until the Drive store lands: Settings offers Google only where this is
/// there, so nothing unfinished ships, while the choice, the engine and
/// the controller's path for it are in place (and tested with an
/// in-memory store).
@Riverpod(keepAlive: true)
CloudStore? googleDriveStore(Ref ref) => null;

/// Where a [StoreSyncBackend] writes the bodies it fetched, for the codec
/// to read and delete.
@Riverpod(keepAlive: true)
Future<Directory> cloudSyncInbox(Ref ref) async =>
    Directory(p.join((await getTemporaryDirectory()).path, 'cloud_sync_in'));

/// The sync engine over [googleDriveStore], or null without one.
@Riverpod(keepAlive: true)
SyncBackend? googleSyncBackend(Ref ref) {
  final store = ref.watch(googleDriveStoreProvider);
  if (store == null) return null;
  final backend = StoreSyncBackend(
    store: store,
    state: PrefsSyncEngineState(
      ref.watch(sharedPreferencesProvider),
      prefix: 'sync.google.',
    ),
    inbox: () => ref.read(cloudSyncInboxProvider.future),
  );
  ref.onDispose(() => unawaited(backend.stop()));
  return backend;
}

/// [SyncEngineState] in the shared preferences, under [prefix].
class PrefsSyncEngineState implements SyncEngineState {
  /// Creates the state over [prefs].
  PrefsSyncEngineState(this._prefs, {required this.prefix});

  final SharedPreferences _prefs;

  /// What every key starts with.
  final String prefix;

  @override
  String? read(String key) => _prefs.getString('$prefix$key');

  @override
  Future<void> write(String key, String? value) => value == null
      ? _prefs.remove('$prefix$key')
      : _prefs.setString('$prefix$key', value);
}
