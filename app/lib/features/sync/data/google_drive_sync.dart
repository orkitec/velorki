import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki_io/io.dart';

import '../../../app/app_config.dart';
import '../../../core/files/app_directories.dart';
import 'cloud_store.dart';
import 'drive_cloud_store.dart';
import 'google_account.dart';
import 'store_sync_backend.dart';
import 'sync_backend.dart';

part 'google_drive_sync.g.dart';

/// The hidden app data folder of the rider's Google Drive as a
/// [CloudStore], or null where Google sync is not offered (no sign-in on
/// the platform). The store outlives the account: signed out, its
/// account id is null and the engine syncs nothing.
@Riverpod(keepAlive: true)
CloudStore? googleDriveStore(Ref ref) {
  final service = ref.watch(googleSignInServiceProvider);
  if (service == null) return null;
  return DriveCloudStore(
    auth: GoogleDriveAuth(
      account: () => ref.read(googleAccountControllerProvider),
      service: service,
      onLost: () => ref.read(googleAccountControllerProvider.notifier).lost(),
    ),
    state: PrefsSyncEngineState(
      ref.watch(sharedPreferencesProvider),
      prefix: 'sync.google.drive.',
    ),
  );
}

/// Where a [StoreSyncBackend] writes the bodies it fetched, for the codec
/// to read and delete.
@Riverpod(keepAlive: true)
Future<Directory> cloudSyncInbox(Ref ref) async =>
    Directory(p.join((await appTemporaryDirectory()).path, 'cloud_sync_in'));

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
