import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as pp;
import 'package:velorki_io/io.dart';

import '../../../app/app_config.dart';
import '../../../core/db/database.dart';
import '../../../core/files/app_directories.dart';
import '../../map/data/offline_regions_repository.dart';

/// Whether this build offers "Reset app": debug and profile builds only.
///
/// A provider because `kReleaseMode` cannot be changed under test; tests
/// override it.
final devToolsAvailableProvider = Provider<bool>(
  (ref) => !kReleaseMode && !kIsWeb,
);

/// Puts the device back to a fresh install, for testing the first start
/// without reinstalling. Development builds only.
///
/// Everything is injected so the order and the reach can be tested with
/// fakes. A step that fails is logged and the rest still run: half a reset
/// is worse than a reset with a note in the log.
class AppReset {
  /// Creates the reset over the stores it clears.
  const AppReset({
    required this.clearPreferences,
    required this.deleteOfflineMaps,
    required this.closeDatabase,
    required this.clearSecureStorage,
    required this.directories,
    required this.endApp,
  });

  /// Removes every key from shared preferences.
  final Future<void> Function() clearPreferences;

  /// Removes MapLibre's offline packs and its tile cache.
  final Future<void> Function() deleteOfflineMaps;

  /// Closes the Drift connection so its files can go.
  final Future<void> Function() closeDatabase;

  /// Removes everything in the keychain or keystore.
  final Future<void> Function() clearSecureStorage;

  /// The directories whose contents go: the database, the routing tiles, the
  /// gazetteers, the recording journal, caches and temporary files.
  final Future<List<Directory>> Function() directories;

  /// Ends the process.
  final void Function() endApp;

  /// Clears everything on the device, then ends the app.
  Future<void> run() async {
    await _step('offline maps', deleteOfflineMaps);
    await _step('database', closeDatabase);
    await _step('preferences', clearPreferences);
    await _step('secure storage', clearSecureStorage);
    await _step('files', () async {
      final seen = <String>{};
      for (final dir in await directories()) {
        if (!seen.add(p.normalize(dir.path)) || !dir.existsSync()) continue;
        for (final entry in dir.listSync()) {
          try {
            entry.deleteSync(recursive: true);
          } on FileSystemException catch (e) {
            debugPrint('App reset: ${entry.path}: $e');
          }
        }
      }
    });
    endApp();
  }

  Future<void> _step(String name, Future<void> Function() step) async {
    try {
      await step();
    } on Object catch (e) {
      debugPrint('App reset: $name failed: $e');
    }
  }
}

/// The reset of the running app.
///
/// The database file lives in the documents directory, the routing tiles and
/// gazetteers under the support directory (`brouter/`), the recording
/// journal beside them, and the cycle map and cloud caches under the cache
/// and temporary directories; each directory is emptied, not removed.
final appResetProvider = Provider<AppReset>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  final database = ref.read(velorkiDatabaseProvider);
  final maps = ref.read(offlineMapApiProvider);
  return AppReset(
    clearPreferences: prefs.clear,
    deleteOfflineMaps: () async {
      for (final id in await maps.regionIds()) {
        await maps.delete(id);
      }
      await clearMapAmbientCache();
    },
    closeDatabase: database.close,
    clearSecureStorage: const FlutterSecureStorage().deleteAll,
    directories: () async => [
      await pp.getApplicationDocumentsDirectory(),
      await appSupportDirectory(),
      await appCacheDirectory(),
      await appTemporaryDirectory(),
    ],
    endApp: () {
      unawaited(SystemNavigator.pop());
      exit(0);
    },
  );
});
