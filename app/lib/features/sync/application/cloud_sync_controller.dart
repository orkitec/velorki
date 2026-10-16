import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';
import '../../../core/db/database.dart';
import '../../navigation/data/navigation_settings.dart';
import '../../settings/data/appearance_controller.dart';
import '../../settings/data/units.dart';
import '../data/cloud_sync_bridge.dart';
import '../data/record_codec.dart';
import '../domain/cloud_record.dart';
import '../domain/cloud_sync_status.dart';
import 'library_sync.dart';
import 'settings_sync.dart';

part 'cloud_sync_controller.g.dart';

final Logger _log = Logger('velorki.sync');

const String _prefsEnabled = 'sync.icloud';
const String _prefsNoticeDone = 'sync.icloud.notice_done';

/// Whether this device can sync with iCloud at all: iOS 17 or later. The
/// setting is not shown anywhere else.
@Riverpod(keepAlive: true)
Future<bool> cloudSyncSupported(Ref ref) async {
  final bridge = ref.watch(cloudSyncBridgeProvider);
  return bridge != null && await bridge.isSupported();
}

/// Where the body files of records to be sent are written.
@Riverpod(keepAlive: true)
Future<Directory> cloudSyncOutbox(Ref ref) async =>
    Directory(p.join((await getTemporaryDirectory()).path, 'cloud_sync_out'));

/// Settings → Sync with iCloud: on unless the rider switched it off.
@Riverpod(keepAlive: true)
class CloudSyncEnabled extends _$CloudSyncEnabled {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_prefsEnabled) ?? true;

  /// Switches the sync on or off on this device.
  Future<void> set({required bool enabled}) async {
    state = enabled;
    await ref.read(sharedPreferencesProvider).setBool(_prefsEnabled, enabled);
  }
}

/// The one-time note for a rider whose library was there before sync
/// came: true while it is to be shown.
@Riverpod(keepAlive: true)
class CloudSyncNotice extends _$CloudSyncNotice {
  @override
  bool build() => false;

  /// Shown, never again.
  void dismiss() => state = false;

  void _show() => state = true;
}

/// Runs iCloud sync while it is supported and switched on, and says where
/// it stands.
///
/// Read once at launch (`bootstrap.dart`); the engine is started on the
/// native side only from here, so with the switch off nothing touches
/// iCloud.
@Riverpod(keepAlive: true)
class CloudSyncController extends _$CloudSyncController
    implements CloudSyncHandler {
  LibrarySync? _library;
  SettingsSync? _settings;
  StreamSubscription<CloudSyncStatus>? _status;
  AppLifecycleListener? _lifecycle;
  bool _running = false;

  @override
  CloudSyncStatus build() {
    final bridge = ref.watch(cloudSyncBridgeProvider);
    if (bridge == null) return const CloudSyncStatus();
    final supported = ref.watch(cloudSyncSupportedProvider).value ?? false;
    final enabled = ref.watch(cloudSyncEnabledProvider);
    ref.onDispose(() => unawaited(_stop(bridge)));
    if (supported && enabled) {
      // After the first frame of this build: start reads state.
      Future.microtask(() => _start(bridge));
    }
    return const CloudSyncStatus();
  }

  Future<void> _start(CloudSyncBridge bridge) async {
    if (_running) return;
    _running = true;
    final db = ref.read(velorkiDatabaseProvider);
    final outbox = await ref.read(cloudSyncOutboxProvider.future);
    if (!_running) return;
    final library = _library = LibrarySync(
      db: db,
      bridge: bridge,
      codec: RecordCodec(outbox),
    );
    final settings = _settings = SettingsSync(
      prefs: ref.read(sharedPreferencesProvider),
      bridge: bridge,
      onApplied: _rereadSettings,
    );
    bridge.setHandler(this);
    _status = bridge.status.listen((s) => state = s);
    await bridge.start();
    await _maybeShowNotice(db);
    await settings.start();
    _listenToSettings();
    library.start();
    await library.push();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(bridge.fetchNow());
        unawaited(_library?.push());
      },
    );
  }

  Future<void> _stop(CloudSyncBridge bridge) async {
    if (!_running) return;
    _running = false;
    _lifecycle?.dispose();
    _lifecycle = null;
    await _status?.cancel();
    _status = null;
    await _library?.stop();
    _library = null;
    _settings = null;
    bridge.setHandler(null);
    await bridge.stop();
  }

  /// A rider who had routes or rides before this version is told once that
  /// they sync now; a new rider simply finds it on.
  Future<void> _maybeShowNotice(VelorkiDatabase db) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(_prefsNoticeDone) ?? false) return;
    await prefs.setBool(_prefsNoticeDone, true);
    final routes = await db.routesDao.allRoutes();
    final hasLibrary =
        routes.isNotEmpty || (await db.ridesDao.allRides()).isNotEmpty;
    if (hasLibrary) ref.read(cloudSyncNoticeProvider.notifier)._show();
  }

  void _listenToSettings() {
    void changed() => unawaited(_settings?.localChanged());
    ref
      ..listen(appearanceSettingProvider, (_, _) => changed())
      ..listen(unitSystemProvider, (_, _) => changed())
      ..listen(navigationSettingsProvider, (_, _) => changed());
  }

  void _rereadSettings() {
    ref
      ..invalidate(appearanceSettingProvider)
      ..invalidate(unitSystemProvider)
      ..invalidate(navigationSettingsProvider);
  }

  @override
  Future<List<CloudRecord>> recordsToSave(List<String> names) async =>
      await _library?.recordsToSave(names) ?? const <CloudRecord>[];

  @override
  Future<void> applyRemote(
    List<CloudRecord> modifications,
    List<String> deletions,
  ) async => _library?.applyRemote(modifications, deletions);

  @override
  Future<void> sent(SentChanges changes) async => _library?.sent(changes);

  @override
  Future<void> accountChanged(AccountChange change) async {
    _log.info('iCloud account: ${change.name}');
    // Whatever the account was, this library is sent to the one there is
    // now as new; it is never deleted for an account change.
    await _library?.reset();
    await _settings?.forget();
    if (change != AccountChange.signOut) {
      await _settings?.start();
      await _library?.push();
    }
  }

  @override
  Future<void> zoneDeleted(ZoneDeletion reason) async {
    _log.info('iCloud zone deleted: ${reason.name}');
    await _library?.reset();
    if (reason == ZoneDeletion.purged) {
      // The rider deleted Velorki's data from iCloud: it is not put back
      // there behind their back. The library here stays as it is.
      await ref.read(cloudSyncEnabledProvider.notifier).set(enabled: false);
      return;
    }
    await _library?.push();
  }

  @override
  Future<void> settingsChanged(Map<String, Object?> values) async =>
      _settings?.remoteChanged(values);
}
