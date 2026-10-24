import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:velorki_io/io.dart';

import '../domain/cloud_record.dart';
import '../domain/cloud_sync_status.dart';
import 'cloud_store.dart';
import 'sync_backend.dart';

/// Logs record names and decisions only, never their content.
final Logger _log = Logger('velorki.sync.store');

/// The record that holds the synced settings: a name `parseRecordName`
/// does not know, so the library never sees it.
const String _settingsRecord = 'settings';

/// How a store's version is kept in `sync_records.system_fields`, told
/// apart from CloudKit's archived system fields.
const String _versionPrefix = 'store:';

/// The few values [StoreSyncBackend] keeps between runs (the account, the
/// cursor, the settings last seen), by key.
abstract interface class SyncEngineState {
  /// The value of [key], or null.
  String? read(String key);

  /// Writes [value] for [key]; null removes it.
  Future<void> write(String key, String? value);
}

/// The wait before trying again after the [failures]th transient failure
/// in a row: 2 s doubling to at most 5 min, give or take a fifth so
/// devices that failed together do not retry together.
Duration syncBackoff(int failures, math.Random random) {
  final base = math.min(300, 1 << math.min(failures, 9)) * 1000;
  return Duration(
    milliseconds: (base * (0.8 + 0.4 * random.nextDouble())).round(),
  );
}

/// A sync engine for clouds without one of their own: what CKSyncEngine
/// does for iCloud, in Dart over a [CloudStore], so `LibrarySync` and
/// `SettingsSync` run over it unchanged.
///
/// `sync_records` stays the one outbox: the names enqueued wait in memory
/// only, and `LibrarySync.push` hands over everything marked again at
/// every start. A record's store version rides in its system fields;
/// [SyncEngineState] keeps the account, the cursor and the settings. A
/// send asks the library for a batch of records by name, pushes them over
/// the versions they last had and reports what became of each, a refused
/// save with the store's copy, which the library settles newer change
/// wins. A name enqueued again while on its way stays waiting. Transient
/// failures are tried again after [syncBackoff], and a store that needs
/// the rider to sign in again keeps what waits until they have; an expired
/// cursor lists the whole store again. Another account than last time clears what was
/// kept for the old one and tells the handler, which resends the library
/// as new and deletes nothing.
class StoreSyncBackend implements SyncBackend {
  /// Creates the engine over [store]. Incoming bodies are written to
  /// [inbox] for the codec, which deletes them. A run of transient
  /// failures waits [backoff] ([syncBackoff] unless given) before trying
  /// again. With [scheduling] off nothing is sent or retried by itself:
  /// tests call [sendNow]. With [syncsSettings] off the settings stay on
  /// the device (a store whose other devices keep theirs elsewhere, as
  /// iCloud's apps keep them in its key-value store).
  StoreSyncBackend({
    required this._store,
    required this._state,
    required this._inbox,
    this.batchSize = 20,
    this.syncsSettings = true,
    this.sendDelay = const Duration(milliseconds: 500),
    this.scheduling = true,
    Duration Function(int failures)? backoff,
    this._clock = DateTime.now,
  }) : _backoff = backoff ?? ((f) => syncBackoff(f, _jitter));

  static final math.Random _jitter = math.Random();

  final CloudStore _store;
  final SyncEngineState _state;
  final Future<Directory> Function() _inbox;
  final Duration Function(int failures) _backoff;
  final DateTime Function() _clock;

  /// The most records sent in one push.
  final int batchSize;

  /// How long after an enqueue the changes are sent.
  final Duration sendDelay;

  /// Whether sends and retries start by themselves.
  final bool scheduling;

  /// Whether the settings go through the store's `settings` record.
  final bool syncsSettings;

  CloudSyncHandler? _handler;
  bool _running = false;
  final Set<String> _saves = <String>{};
  final Set<String> _deletes = <String>{};

  /// Bumped per name on every enqueue: a send lets go only of a name not
  /// enqueued again while it was on its way.
  final Map<String, int> _generation = <String, int>{};
  int _generations = 0;
  int _files = 0;

  Future<void>? _sending;
  bool _sendAgain = false;
  Future<void>? _fetching;
  bool _fetchAgain = false;
  Future<bool>? _accountCheck;
  bool _accountOk = false;
  bool _quotaFull = false;
  Timer? _sendTimer;

  /// Transient failures in a row and the retry waiting, of sends and of
  /// fetches apart: one going through says nothing of the other.
  final List<int> _failures = [0, 0];
  final List<Timer?> _retries = [null, null];

  /// How long the store last asked to be left alone, for the next retry.
  Duration? _retryAfter;

  /// Where a full listing cut short in this run goes on.
  String? _listingCursor;

  /// The last page fetched and not yet handed over, with where it was
  /// fetched from: a round that failed after the download hands it over
  /// again without downloading it again.
  ({String? from, bool listing, StoreChanges changes})? _undelivered;

  CloudSyncStatus _now = const CloudSyncStatus();
  final StreamController<CloudSyncStatus> _status =
      StreamController<CloudSyncStatus>.broadcast();

  @override
  Future<bool> isSupported() async => true;

  @override
  void setHandler(CloudSyncHandler? handler) => _handler = handler;

  @override
  Stream<CloudSyncStatus> get status => _status.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _emit();
    if (await _checkAccount()) _scheduleSend(Duration.zero);
  }

  @override
  Future<void> stop() async {
    _running = false;
    _accountOk = false;
    _sendTimer?.cancel();
    _sendTimer = null;
    for (var i = 0; i < _retries.length; i++) {
      _retries[i]?.cancel();
      _retries[i] = null;
    }
  }

  @override
  Future<void> enqueue({
    List<String> saves = const <String>[],
    List<String> deletes = const <String>[],
  }) async {
    for (final name in saves) {
      _deletes.remove(name);
      _saves.add(name);
      _generation[name] = ++_generations;
    }
    for (final name in deletes) {
      _saves.remove(name);
      _deletes.add(name);
      _generation[name] = ++_generations;
    }
    if (saves.isNotEmpty || deletes.isNotEmpty) _scheduleSend(sendDelay);
  }

  /// Sends everything waiting; completes when nothing is left or a failure
  /// stopped it.
  Future<void> sendNow() => _sending ??= () async {
    do {
      _sendAgain = false;
      await _send();
    } while (_sendAgain && _running);
  }().whenComplete(() => _sending = null);

  @override
  Future<void> fetchNow() {
    if (_fetching != null) {
      _fetchAgain = true;
      return _fetching!;
    }
    return _fetching = () async {
      do {
        _fetchAgain = false;
        await _fetch();
      } while (_fetchAgain && _running);
    }().whenComplete(() => _fetching = null);
  }

  // --- Sending --------------------------------------------------------------

  void _scheduleSend(Duration delay) {
    if (_sending != null) _sendAgain = true;
    if (!scheduling || !_running || _sendTimer != null) return;
    _sendTimer = Timer(delay, () {
      _sendTimer = null;
      unawaited(sendNow());
    });
  }

  Future<void> _send() async {
    if (!_running || _handler == null || !await _checkAccount()) return;
    final error = <CloudSyncError>{};
    var anySaved = false;
    try {
      await _flushSettings();
      anySaved = await _sendRounds(error);
    } on Object catch (e, st) {
      // As for a fetch: the round ends with an error, never left syncing.
      _log.warning('send failed: $e', e, st);
      error.add(CloudSyncError.other);
    }
    if (anySaved) _quotaFull = false;
    if (error.contains(CloudSyncError.quotaExceeded)) _quotaFull = true;
    _finish(
      error.contains(CloudSyncError.quotaExceeded)
          ? CloudSyncError.quotaExceeded
          : error.firstOrNull,
      sending: true,
    );
  }

  /// Sends what waits, a batch at a time; returns whether anything was
  /// saved, and puts what went wrong into [error].
  Future<bool> _sendRounds(Set<CloudSyncError> error) async {
    var anySaved = false;
    for (var round = 0; round < 100; round++) {
      final handler = _handler;
      if (!_running || handler == null) break;
      if (_saves.isEmpty && _deletes.isEmpty) break;
      _emit(syncing: true);
      final saveNames = _saves.take(batchSize).toList();
      final deleteNames = _deletes.take(batchSize).toList();
      final generations = <String, int?>{
        for (final n in [...saveNames, ...deleteNames]) n: _generation[n],
      };
      void done(String name) {
        if (_generation[name] != generations[name]) return;
        _saves.remove(name);
        _deletes.remove(name);
      }

      final records = saveNames.isEmpty
          ? const <CloudRecord>[]
          : await handler.recordsToSave(saveNames);
      final provided = {for (final r in records) r.name};
      // What the library left out is not to be saved.
      saveNames.where((n) => !provided.contains(n)).forEach(done);
      final writes = <StoreWrite>[
        for (final r in records) await _saveOf(r),
        for (final n in deleteNames) StoreDelete(n),
      ];
      List<StoreResult> results;
      try {
        results = writes.isEmpty ? const [] : await _store.push(writes);
      } on CloudStoreException catch (e) {
        _log.info('push failed: $e');
        _retryAfter = e.retryAfter;
        results = [for (final _ in writes) StoreFailed(e.failure)];
      }
      for (final r in records) {
        if (r.assetPath != null) await _delete(File(r.assetPath!));
      }
      final sent = await _sentOf(writes, results, done, error);
      anySaved |= sent.saved.isNotEmpty;
      _log.info(
        'sent ${sent.saved.keys.toList()} deleted ${sent.deleted} failed '
        '${[for (final f in sent.failedSaves) '${f.name}:${f.failure.name}']}',
      );
      await handler.sent(sent);
      if (error.contains(CloudSyncError.network) ||
          error.contains(CloudSyncError.signInNeeded)) {
        break;
      }
    }
    return anySaved;
  }

  Future<StoreSave> _saveOf(CloudRecord record) async {
    Uint8List? body;
    try {
      if (record.assetPath != null) {
        body = await File(record.assetPath!).readAsBytes();
      }
    } on FileSystemException catch (e) {
      _log.warning('no body for ${record.name}', e);
    }
    return StoreSave(
      record.name,
      type: record.type,
      fields: {
        for (final MapEntry(:key, :value) in record.fields.entries) key: ?value,
      },
      body: body,
      ifVersion: _versionOf(record.systemFields),
    );
  }

  /// What the library hears of a push; marks the names done with, and
  /// what went wrong into [error].
  Future<SentChanges> _sentOf(
    List<StoreWrite> writes,
    List<StoreResult> results,
    void Function(String) done,
    Set<CloudSyncError> error,
  ) async {
    final saved = <String, Uint8List>{};
    final failedSaves = <FailedSave>[];
    final deleted = <String>[];
    final failedDeletes = <String>[];
    for (var i = 0; i < writes.length; i++) {
      final write = writes[i];
      final result = i < results.length
          ? results[i]
          : const StoreFailed(CloudStoreFailure.transient);
      // Kept waiting only for a transient failure, tried again after the
      // backoff as CKSyncEngine does, and until the rider signs in again.
      if (result is! StoreFailed || !_keepsWaiting(result.failure)) {
        done(write.name);
      }
      if (write is StoreDelete) {
        switch (result) {
          case StoreDone() || StoreMissing():
            deleted.add(write.name);
          case StoreFailed(:final failure):
            failedDeletes.add(write.name);
            error.add(_errorOf(failure));
          case StoreConflict():
            failedDeletes.add(write.name);
        }
        continue;
      }
      switch (result) {
        case StoreDone(:final version):
          saved[write.name] = _systemFieldsOf(version ?? '');
        case StoreConflict(:final server):
          failedSaves.add(
            FailedSave(
              write.name,
              SaveFailure.conflict,
              serverRecord: await _incoming(server),
            ),
          );
        case StoreMissing():
          failedSaves.add(FailedSave(write.name, SaveFailure.unknownItem));
        case StoreFailed(:final failure):
          error.add(_errorOf(failure));
          failedSaves.add(
            FailedSave(write.name, switch (failure) {
              CloudStoreFailure.transient ||
              CloudStoreFailure.signInNeeded => SaveFailure.retrying,
              CloudStoreFailure.quotaExceeded => SaveFailure.quotaExceeded,
              CloudStoreFailure.other => SaveFailure.other,
            }),
          );
      }
    }
    return SentChanges(
      saved: saved,
      failedSaves: failedSaves,
      deleted: deleted,
      failedDeletes: failedDeletes,
    );
  }

  // --- Fetching -------------------------------------------------------------

  Future<void> _fetch() async {
    if (!_running || _handler == null) return;
    if (!await _checkAccount(force: true)) return;
    CloudSyncError? error;
    var failed = false;
    _emit(syncing: true);
    try {
      var cursor = _state.read(_Keys.cursor);
      var listing = cursor == null;
      // A listing cut short earlier in this run goes on from its page.
      if (listing) cursor = _listingCursor;
      for (var page = 0; page < 10000; page++) {
        final changes = await _page(cursor, listing: listing);
        if (changes == null) {
          (cursor, listing) = (null, true);
          continue;
        }
        final handler = _handler;
        if (!_running || handler == null) return;
        StoredRecord? settings;
        final modifications = <CloudRecord>[];
        for (final record in changes.changed) {
          if (record.name == _settingsRecord) {
            settings = record;
          } else {
            modifications.add(await _incoming(record));
          }
        }
        final deletions = [
          for (final name in changes.deleted)
            if (name != _settingsRecord) name,
        ];
        if (modifications.isNotEmpty || deletions.isNotEmpty) {
          _log.info(
            'fetched ${[for (final r in modifications) r.name]} '
            'deleted $deletions',
          );
          try {
            await handler.applyRemote(modifications, deletions);
          } on Object catch (e) {
            // The page stays kept: the next round hands it over again
            // without downloading it again.
            _log.info('the fetched changes were not taken: $e');
            rethrow;
          }
          _log.info(
            'applied ${modifications.length} changes and '
            '${deletions.length} deletions',
          );
        }
        if (settings != null && syncsSettings) {
          await _settingsArrived(settings);
        }
        _undelivered = null;
        cursor = changes.cursor;
        if (listing && changes.more) {
          // A listing's own page tokens are kept for this run only: one
          // cut short goes on from here, a restart lists again.
          _listingCursor = cursor;
        } else {
          await _state.write(_Keys.cursor, cursor);
          _listingCursor = null;
          listing = false;
        }
        if (!changes.more) break;
      }
    } on CloudStoreException catch (e) {
      _log.info('fetch failed: $e');
      error = _errorOf(e.failure);
      _retryAfter = e.retryAfter;
      if (e.failure != CloudStoreFailure.transient) _forgetProgress();
    } on Object catch (e, st) {
      // Whatever it was, the round ends here and says so: nothing may
      // leave the status at syncing. The cursor stays where it was, so the
      // next round brings the same changes again, from the page kept.
      _log.warning('fetch failed: $e', e, st);
      error = CloudSyncError.other;
      failed = true;
    } finally {
      _emit(syncing: false);
    }
    _finish(error);
    // Tried again after the backoff too: a database slow to open the
    // first time catches up by itself.
    if (failed) _retryLater(sending: false);
  }

  /// The page of changes from [cursor]: the one fetched before and not
  /// handed over when it is the same, else the store's. Null when the
  /// cursor ran out and everything is to be listed again.
  Future<StoreChanges?> _page(String? cursor, {required bool listing}) async {
    final kept = _undelivered;
    if (kept != null && kept.listing == listing && kept.from == cursor) {
      _log.info('the page fetched before again, not downloaded again');
      return kept.changes;
    }
    _undelivered = null;
    final StoreChanges changes;
    try {
      changes = listing
          ? await _store.fullList(cursor)
          : await _store.pull(cursor!);
    } on StoreCursorExpired {
      _log.info('cursor expired: everything again');
      _forgetProgress();
      return null;
    }
    _undelivered = (from: cursor, listing: listing, changes: changes);
    return changes;
  }

  /// Forgets the listing under way and the page kept.
  void _forgetProgress() {
    _listingCursor = null;
    _undelivered = null;
  }

  /// [record] as the library reads it: its body in a file of its own.
  Future<CloudRecord> _incoming(StoredRecord record) async {
    String? path;
    if (record.body case final body?) {
      final dir = await _inbox();
      await dir.create(recursive: true);
      path = p.join(dir.path, 'in_${_files++}_${record.name}.json.gz');
      await File(path).writeAsBytes(body, flush: true);
    }
    return CloudRecord(
      name: record.name,
      type: record.type,
      fields: record.fields,
      assetPath: path,
      systemFields: _systemFieldsOf(record.version),
    );
  }

  // --- Settings -------------------------------------------------------------

  @override
  Future<Map<String, Object?>> readSettings(List<String> keys) async {
    if (!syncsSettings) return const <String, Object?>{};
    try {
      final record = await _store.get(_settingsRecord);
      await _keepSettings(record?.fields ?? const {}, record?.version);
    } on CloudStoreException catch (e) {
      // What was last seen stands in until the store answers.
      _log.info('settings not read: $e');
    }
    final values = _merged();
    return {
      for (final key in keys)
        if (values[key] != null) key: values[key],
    };
  }

  @override
  Future<void> writeSettings(Map<String, Object?> values) async {
    if (!syncsSettings) return;
    final out = {..._map(_Keys.settingsOut), ...values};
    await _state.write(_Keys.settingsOut, jsonEncode(out));
    if (_running && await _checkAccount()) await _flushSettings();
  }

  /// The settings last seen with those not yet written over them.
  Map<String, Object?> _merged() {
    final values = _map(_Keys.settings);
    for (final MapEntry(:key, :value) in _map(_Keys.settingsOut).entries) {
      value == null ? values.remove(key) : values[key] = value;
    }
    return values;
  }

  /// Writes the settings changed here; a conflict takes the store's copy
  /// (its other changes reach the handler) and goes again.
  Future<void> _flushSettings() async {
    if (!syncsSettings) return;
    for (var attempt = 0; attempt < 5; attempt++) {
      if (_map(_Keys.settingsOut).isEmpty) return;
      final merged = _merged();
      final results = await _push([
        StoreSave(
          _settingsRecord,
          type: 'Settings',
          fields: merged,
          body: null,
          ifVersion: _state.read(_Keys.settingsVersion),
        ),
      ]);
      switch (results.single) {
        case StoreDone(:final version):
          await _keepSettings(merged, version);
          await _state.write(_Keys.settingsOut, null);
          return;
        case StoreConflict(:final server):
          await _settingsArrived(server);
        case StoreMissing():
          await _keepSettings(const {}, null);
        case StoreFailed(:final failure):
          _log.info('settings not written: ${failure.name}');
          if (failure == CloudStoreFailure.transient) {
            _retryLater(sending: true);
          }
          return;
      }
    }
  }

  Future<List<StoreResult>> _push(List<StoreWrite> writes) async {
    try {
      return await _store.push(writes);
    } on CloudStoreException catch (e) {
      return [for (final _ in writes) StoreFailed(e.failure)];
    }
  }

  /// The store's settings arrived: the keys it changed, but not those
  /// about to be written from here, go to the handler.
  Future<void> _settingsArrived(StoredRecord record) async {
    if (record.version == _state.read(_Keys.settingsVersion)) return;
    final before = _map(_Keys.settings);
    final out = _map(_Keys.settingsOut);
    final changed = {
      for (final key in {...before.keys, ...record.fields.keys})
        if (before[key] != record.fields[key] && !out.containsKey(key))
          key: record.fields[key],
    };
    await _keepSettings(record.fields, record.version);
    if (changed.isNotEmpty) await _handler?.settingsChanged(changed);
  }

  Future<void> _keepSettings(Map<String, Object?> fields, String? version) =>
      Future.wait([
        _state.write(_Keys.settings, jsonEncode(fields)),
        _state.write(_Keys.settingsVersion, version),
      ]);

  Map<String, Object?> _map(String key) {
    final json = _state.read(key);
    if (json == null) return <String, Object?>{};
    final decoded = jsonDecode(json);
    return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
  }

  // --- Account --------------------------------------------------------------

  /// Whether there is an account to sync with; tells the handler when it
  /// is another than last time. Asks the store when [force]d or not known
  /// yet this run.
  Future<bool> _checkAccount({bool force = false}) {
    if (!force && _accountOk) return Future<bool>.value(true);
    return _accountCheck ??= _askAccount().whenComplete(
      () => _accountCheck = null,
    );
  }

  Future<bool> _askAccount() async {
    final String? id;
    try {
      id = await _store.accountId();
    } on CloudStoreException catch (e) {
      _log.info('account unknown: $e');
      _accountOk = false;
      _finish(_errorOf(e.failure));
      return false;
    }
    final previous = _state.read(_Keys.account);
    final signedOut = _state.read(_Keys.signedOut) != null;
    _accountOk = id != null;
    _emit(
      account: id == null ? CloudAccount.noAccount : CloudAccount.available,
    );
    if (id == previous) return id != null;
    if (id == null && previous == null) return false;
    await _state.write(_Keys.account, id);
    await _state.write(_Keys.signedOut, id == null ? '1' : null);
    // The first account this device syncs with is no change.
    if (previous == null && !signedOut) return true;
    final change = id == null
        ? AccountChange.signOut
        : previous != null
        ? AccountChange.switchAccounts
        : AccountChange.signIn;
    for (final key in _Keys.perAccount) {
      await _state.write(key, null);
    }
    _saves.clear();
    _deletes.clear();
    _forgetProgress();
    _log.info('account: ${change.name}');
    await _handler?.accountChanged(change);
    return id != null;
  }

  // --- Status and retries ---------------------------------------------------

  void _finish(CloudSyncError? error, {bool sending = false}) {
    final shown = error ?? (_quotaFull ? CloudSyncError.quotaExceeded : null);
    if (error == null) _failures[sending ? 0 : 1] = 0;
    _emit(
      syncing: false,
      lastSyncedAt: error == null ? _clock() : null,
      error: shown,
      clearError: shown == null,
    );
    if (error == CloudSyncError.network) _retryLater(sending: sending);
  }

  /// Tries the send, or the fetch (and then a send), again after the
  /// backoff.
  void _retryLater({required bool sending}) {
    if (!scheduling || !_running) return;
    final i = sending ? 0 : 1;
    _retries[i]?.cancel();
    var wait = _backoff(++_failures[i]);
    // A throttled store said how long to leave it alone.
    if (_retryAfter case final asked? when asked > wait) wait = asked;
    _retryAfter = null;
    _log.info(
      '${sending ? 'send' : 'fetch'} again in ${wait.inSeconds} s '
      '(failure ${_failures[i]} in a row)',
    );
    _retries[i] = Timer(wait, () async {
      _retries[i] = null;
      if (!sending) await fetchNow();
      await sendNow();
    });
  }

  static CloudSyncError _errorOf(CloudStoreFailure failure) =>
      switch (failure) {
        CloudStoreFailure.transient => CloudSyncError.network,
        CloudStoreFailure.quotaExceeded => CloudSyncError.quotaExceeded,
        CloudStoreFailure.signInNeeded => CloudSyncError.signInNeeded,
        CloudStoreFailure.other => CloudSyncError.other,
      };

  static bool _keepsWaiting(CloudStoreFailure failure) =>
      failure == CloudStoreFailure.transient ||
      failure == CloudStoreFailure.signInNeeded;

  void _emit({
    CloudAccount? account,
    bool? syncing,
    DateTime? lastSyncedAt,
    CloudSyncError? error,
    bool clearError = false,
  }) {
    _now = CloudSyncStatus(
      account: account ?? _now.account,
      syncing: syncing ?? _now.syncing,
      lastSyncedAt: lastSyncedAt ?? _now.lastSyncedAt,
      error: clearError ? null : error ?? _now.error,
    );
    _status.add(_now);
  }

  static Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Gone already.
    }
  }

  static Uint8List _systemFieldsOf(String version) =>
      Uint8List.fromList(utf8.encode('$_versionPrefix$version'));

  static String? _versionOf(Uint8List? systemFields) {
    if (systemFields == null) return null;
    final text = utf8.decode(systemFields, allowMalformed: true);
    return text.startsWith(_versionPrefix)
        ? text.substring(_versionPrefix.length)
        : null;
  }
}

/// The keys of [SyncEngineState].
abstract final class _Keys {
  static const String account = 'account';
  static const String signedOut = 'signed_out';
  static const String cursor = 'cursor';
  static const String settings = 'settings';
  static const String settingsVersion = 'settings_version';
  static const String settingsOut = 'settings_out';

  /// What belongs to the account last synced with.
  static const List<String> perAccount = [
    cursor,
    settings,
    settingsVersion,
    settingsOut,
  ];
}
