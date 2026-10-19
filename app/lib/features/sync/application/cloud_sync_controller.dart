import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderSubscription;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';
import '../../../app/router.dart';
import '../../../core/db/database.dart';
import '../../navigation/data/navigation_settings.dart';
import '../../settings/data/appearance_controller.dart';
import '../../settings/data/units.dart';
import '../../shared/application/active_tab.dart';
import '../data/cloud_sync_bridge.dart';
import '../data/google_drive_sync.dart';
import '../data/record_codec.dart';
import '../data/sync_backend.dart';
import '../domain/cloud_record.dart';
import '../domain/cloud_sync_status.dart';
import '../domain/sync_service.dart';
import 'library_sync.dart';
import 'settings_sync.dart';

part 'cloud_sync_controller.g.dart';

final Logger _log = Logger('velorki.sync');

/// Settings → Sync with: the service's name.
const String _prefsService = 'sync.service';

/// The switch the choice replaced (on: iCloud), read while no choice is
/// stored.
const String _prefsLegacyEnabled = 'sync.icloud';

/// The service the sync state in `sync_records` belongs to: switching to
/// another sends the library to it as new.
const String _prefsRecordsService = 'sync.records_service';

/// The least time between two fetches asked for by opening the Library tab.
const Duration _libraryFetchEvery = Duration(seconds: 30);

/// The time, a provider so tests can wind it forward.
@Riverpod(keepAlive: true)
DateTime Function() cloudSyncClock(Ref ref) => DateTime.now;

/// Whether this device can sync with iCloud at all: iOS 17 or later.
@Riverpod(keepAlive: true)
Future<bool> cloudSyncSupported(Ref ref) async {
  final bridge = ref.watch(cloudSyncBridgeProvider);
  return bridge != null && await bridge.isSupported();
}

/// The services this device can sync with, in the order Settings lists
/// them; empty where there is none, and Settings shows no section.
@Riverpod(keepAlive: true)
List<SyncService> offeredSyncServices(Ref ref) => [
  if (ref.watch(cloudSyncSupportedProvider).value ?? false) SyncService.icloud,
  if (ref.watch(googleSyncBackendProvider) != null) SyncService.google,
];

/// Where the body files of records to be sent are written.
@Riverpod(keepAlive: true)
Future<Directory> cloudSyncOutbox(Ref ref) async =>
    Directory(p.join((await getTemporaryDirectory()).path, 'cloud_sync_out'));

/// Settings → Sync with, as the rider chose it. Unset, it is iCloud where
/// the platform has it (iOS) and off everywhere else; before there was a
/// choice it was a switch, whose on is iCloud.
@Riverpod(keepAlive: true)
class SyncServiceChoice extends _$SyncServiceChoice {
  @override
  SyncService build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = SyncService.fromName(prefs.getString(_prefsService));
    if (stored != null) return stored;
    final legacy = prefs.getBool(_prefsLegacyEnabled);
    if (legacy != null) return legacy ? SyncService.icloud : SyncService.off;
    return ref.watch(cloudSyncBridgeProvider) != null
        ? SyncService.icloud
        : SyncService.off;
  }

  /// Syncs this device with [service] from now on.
  Future<void> select(SyncService service) async {
    state = service;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_prefsService, service.name);
    await prefs.remove(_prefsLegacyEnabled);
  }
}

/// The service sync runs with: the one chosen where this device offers
/// it, else off.
@Riverpod(keepAlive: true)
SyncService activeSyncService(Ref ref) {
  final chosen = ref.watch(syncServiceChoiceProvider);
  return ref.watch(offeredSyncServicesProvider).contains(chosen)
      ? chosen
      : SyncService.off;
}

/// The engine of the service sync runs with, or null while it is off.
@Riverpod(keepAlive: true)
SyncBackend? activeSyncBackend(Ref ref) =>
    switch (ref.watch(activeSyncServiceProvider)) {
      SyncService.icloud => ref.watch(cloudSyncBridgeProvider),
      SyncService.google => ref.watch(googleSyncBackendProvider),
      SyncService.off => null,
    };

/// Whether sync is running: a service is chosen that this device offers.
@Riverpod(keepAlive: true)
bool cloudSyncActive(Ref ref) =>
    ref.watch(activeSyncServiceProvider) != SyncService.off;

/// Runs sync with the chosen service while this device offers it, and
/// says where it stands.
///
/// Read once at launch (`bootstrap.dart`); an engine is started only from
/// here, so with sync off nothing touches a cloud. Choosing another
/// service stops the engine running and starts the other's, which gets
/// the whole library as new; nothing is deleted anywhere for it.
@Riverpod(keepAlive: true)
class CloudSyncController extends _$CloudSyncController
    implements CloudSyncHandler {
  LibrarySync? _library;
  SettingsSync? _settings;
  StreamSubscription<CloudSyncStatus>? _status;
  AppLifecycleListener? _lifecycle;
  ProviderSubscription<String>? _tabs;
  DateTime? _lastLibraryFetch;
  SyncBackend? _backend;
  bool _running = false;
  Future<void> _stopping = Future<void>.value();

  @override
  CloudSyncStatus build() {
    final service = ref.watch(activeSyncServiceProvider);
    final backend = ref.watch(activeSyncBackendProvider);
    ref.onDispose(() => _stopping = _stop());
    if (backend != null) {
      // After the first frame of this build: start reads state.
      Future.microtask(() => _start(backend, service));
    }
    return const CloudSyncStatus();
  }

  Future<void> _start(SyncBackend backend, SyncService service) async {
    if (_running) return;
    _running = true;
    _backend = backend;
    // An engine stopped just before (another service's, or this one's) is
    // let go of first.
    await _stopping;
    bool current() => _running && identical(_backend, backend);
    final db = ref.read(velorkiDatabaseProvider);
    final outbox = await ref.read(cloudSyncOutboxProvider.future);
    if (!current()) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final library = _library = LibrarySync(
      db: db,
      backend: backend,
      codec: RecordCodec(outbox),
    );
    final settings = _settings = SettingsSync(
      prefs: prefs,
      backend: backend,
      onApplied: _rereadSettings,
    );
    // What `sync_records` knows of a server is the service's it was last
    // synced with (iCloud's, from before there was a choice): another one
    // gets the library as new, and the settings merge as on a first start.
    final recordsService = prefs.getString(_prefsRecordsService);
    if (recordsService != service.name &&
        (recordsService != null || service != SyncService.icloud)) {
      _log.info('sync service ${recordsService ?? 'none'} -> ${service.name}');
      await library.reset();
      await settings.forget();
    }
    await prefs.setString(_prefsRecordsService, service.name);
    if (!current()) return;
    backend.setHandler(this);
    _status = backend.status.listen((s) => state = s);
    await backend.start();
    await settings.start();
    _listenToSettings();
    library.start();
    await library.push();
    // The engine fetches by itself only when a push notification tells it
    // to: at launch it is asked, as on every return to the app.
    unawaited(backend.fetchNow());
    // Opening the Library tab asks for what changed elsewhere, at most
    // every 30 seconds.
    _tabs = ref.listen(activeTabProvider, (_, tab) {
      if (tab != libraryRoute) return;
      final now = ref.read(cloudSyncClockProvider)();
      final last = _lastLibraryFetch;
      if (last != null && now.difference(last) < _libraryFetchEvery) return;
      _lastLibraryFetch = now;
      unawaited(backend.fetchNow());
    });
    _lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(backend.fetchNow());
        unawaited(_library?.push());
      },
    );
  }

  /// Fetches what changed in the cloud now (a pull to refresh), with no
  /// throttle. Completes when the fetch has, or after ten seconds; does
  /// nothing while sync is not running.
  Future<void> refresh() async {
    final backend = _backend;
    if (backend == null || !_running) return;
    await backend.fetchNow().timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
  }

  Future<void> _stop() async {
    final backend = _backend;
    if (!_running || backend == null) return;
    _running = false;
    _backend = null;
    // Taken off at once, so a start that follows sets up its own.
    final status = _status;
    final library = _library;
    _status = null;
    _library = null;
    _settings = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _tabs?.close();
    _tabs = null;
    _lastLibraryFetch = null;
    await status?.cancel();
    await library?.stop();
    backend.setHandler(null);
    await backend.stop();
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
    _log.info('account: ${change.name}');
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
      await ref
          .read(syncServiceChoiceProvider.notifier)
          .select(SyncService.off);
      return;
    }
    await _library?.push();
  }

  @override
  Future<void> settingsChanged(Map<String, Object?> values) async =>
      _settings?.remoteChanged(values);
}
