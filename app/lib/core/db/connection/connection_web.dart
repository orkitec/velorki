// The web side of a conditional import: what uses it is the same import
// on the phone side, which is the side dart_code_linter follows.
// ignore_for_file: unused-code

import 'dart:async';
import 'dart:js_interop';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// The browser's database: drift's WebAssembly SQLite in `drift_worker.js`,
/// served with `sqlite3.wasm` from `web/`, next to `index.html`
/// (`tool/web_assets.sh`).
///
/// Where a shared worker can hold it, the database lives in that worker and
/// is kept in IndexedDB: one copy for every tab, each statement one message
/// away. Drift would pick OPFS in Chrome (`opfsLocks`), but there each
/// statement takes a Web Lock and every file operation is a synchronous
/// round trip between two more workers; on a busy page the first open took
/// three times as long and held the lock all the while, so the Library and
/// the sync waited behind it. A database an earlier build kept in OPFS is
/// copied over on the first open, and stays in OPFS should the copy fail.
///
/// An open or a statement that takes seconds is logged with the Web Locks
/// the page sees, so a stall names what holds it.
QueryExecutor openVelorkiDatabase() => DatabaseConnection.delayed(
  Future(() async {
    if (++_opens > 1) {
      // One connection per page: a second would queue behind the first's
      // locks, or keep its own copy of the database.
      debugPrint(
        'velorki: database opened again ($_opens times in this page) '
        'from ${StackTrace.current}',
      );
    }
    final clock = Stopwatch()..start();
    final slow = Timer.periodic(_slow, (_) {
      unawaited(_logLocks('still opening after ${clock.elapsed.inSeconds} s'));
    });
    try {
      final probed = await WasmDatabase.probe(
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.js'),
        databaseName: _name,
      );
      final (storage, initial) = await _choose(probed);
      final connection = await probed.open(
        storage,
        _name,
        initializeDatabase: initial == null ? null : () => initial,
      );
      final missing = probed.missingFeatures.map((f) => f.name).join(', ');
      debugPrint(
        'velorki: database in ${storage.name} '
        '${initial == null ? '' : '(copied from OPFS) '}'
        'after ${clock.elapsedMilliseconds} ms'
        '${missing.isEmpty ? '' : ' (missing: $missing)'}',
      );
      return connection.interceptWith(_SlowStatements());
    } finally {
      slow.cancel();
    }
  }),
);

const String _name = 'velorki';

var _opens = 0;

/// The implementations in the order they are wanted.
const List<WasmStorageImplementation> _preferred = [
  WasmStorageImplementation.opfsShared,
  WasmStorageImplementation.sharedIndexedDb,
  WasmStorageImplementation.opfsLocks,
  WasmStorageImplementation.unsafeIndexedDb,
];

/// Which storage to open, and the bytes of an OPFS database to start an
/// IndexedDB one from.
Future<(WasmStorageImplementation, Uint8List?)> _choose(
  WasmProbeResult probed,
) async {
  final available = probed.availableStorages;
  final storage = _preferred.firstWhere(
    available.contains,
    orElse: () => WasmStorageImplementation.inMemory,
  );
  bool exists(WebStorageApi api) =>
      probed.existingDatabases.any((e) => e.$1 == api && e.$2 == _name);
  if (storage.storageApi != WebStorageApi.indexedDb ||
      exists(WebStorageApi.indexedDb) ||
      !exists(WebStorageApi.opfs)) {
    return (storage, null);
  }
  final copy = await _readOpfsDatabase();
  if (copy != null) return (storage, copy);
  // Unreadable, or mid-transaction when it was last closed: it stays where
  // it is, and SQLite there rolls the transaction back.
  const fallback = WasmStorageImplementation.opfsLocks;
  return (available.contains(fallback) ? fallback : storage, null);
}

/// The file of the OPFS database drift keeps at `drift_db/velorki`, or null
/// when it cannot be read or its journal holds a transaction to roll back.
Future<Uint8List?> _readOpfsDatabase() async {
  try {
    final root = await web.window.navigator.storage.getDirectory().toDart;
    final dir = await (await root.getDirectoryHandle('drift_db').toDart)
        .getDirectoryHandle(_name)
        .toDart;
    Future<Uint8List?> read(String file) async {
      try {
        final handle = await dir.getFileHandle(file).toDart;
        final blob = await handle.getFile().toDart;
        return (await blob.arrayBuffer().toDart).toDart.asUint8List();
      } on Object {
        return null;
      }
    }

    // A persisted journal is zeroed at every commit; a header that is not
    // zero is a transaction that did not finish.
    final journal = await read('database-journal');
    if (journal != null && journal.take(28).any((b) => b != 0)) return null;
    final database = await read('database');
    return database == null || database.isEmpty ? null : database;
  } on Object catch (e) {
    debugPrint('velorki: the OPFS database could not be read: $e');
    return null;
  }
}

/// Run on every connection before anything else. Each transaction
/// otherwise creates and deletes its journal file and flushes it three
/// times, each a trip to the browser's storage. A persisted journal is kept
/// and zeroed instead, and NORMAL flushes once per commit: a power cut may
/// lose the last commit, never the file.
const List<String> connectionPragmas = [
  'PRAGMA journal_mode = PERSIST',
  'PRAGMA synchronous = NORMAL',
];

/// Tests run on the VM; a browser build has no in-memory database.
QueryExecutor inMemoryDatabase() =>
    throw UnsupportedError('inMemoryDatabase() in a browser');

const Duration _slow = Duration(seconds: 5);

/// Logs a statement (or an open) that took longer than [_slow], with the
/// locks held at that moment.
class _SlowStatements extends QueryInterceptor {
  Future<T> _timed<T>(String what, Future<T> Function() run) async {
    final clock = Stopwatch()..start();
    final timer = Timer(_slow, () {
      unawaited(_logLocks('waiting ${_slow.inSeconds} s for $what'));
    });
    try {
      return await run();
    } finally {
      timer.cancel();
      if (clock.elapsed > _slow) {
        debugPrint('velorki: $what took ${clock.elapsedMilliseconds} ms');
      }
    }
  }

  static String _short(String sql) =>
      sql.length > 80 ? '${sql.substring(0, 80)}…' : sql;

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      _timed('the database to open', () => executor.ensureOpen(user));

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _timed(_short(statement), () => executor.runSelect(statement, args));

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _timed(_short(statement), () => executor.runInsert(statement, args));

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _timed(_short(statement), () => executor.runUpdate(statement, args));

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _timed(_short(statement), () => executor.runDelete(statement, args));

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _timed(_short(statement), () => executor.runCustom(statement, args));

  @override
  Future<void> runBatched(QueryExecutor executor, BatchedStatements batch) =>
      _timed('a batch', () => executor.runBatched(batch));
}

/// Logs [what] with the Web Locks held and waited for in this origin.
Future<void> _logLocks(String what) async {
  try {
    final snapshot = await web.window.navigator.locks.query().toDart;
    String names(JSArray<web.LockInfo> locks) =>
        locks.toDart.map((l) => '${l.name} (${l.clientId})').join(', ');
    debugPrint(
      'velorki: database $what; '
      'locks held: [${names(snapshot.held)}], '
      'waiting: [${names(snapshot.pending)}]',
    );
  } on Object catch (e) {
    debugPrint('velorki: database $what (no lock list: $e)');
  }
}
