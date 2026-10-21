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
/// kept in the origin private file system, or in IndexedDB where the browser
/// gives a worker no OPFS. `sqlite3.wasm` and `drift_worker.js` are served
/// from `web/`, next to `index.html` (`tool/web_assets.sh`).
///
/// An open or a statement that takes seconds is logged with the Web Locks
/// the page sees: drift on OPFS takes one lock per statement for every tab
/// of the origin, so a tab that holds it stalls every other.
QueryExecutor openVelorkiDatabase() => DatabaseConnection.delayed(
  Future(() async {
    final clock = Stopwatch()..start();
    final slow = Timer.periodic(_slow, (_) {
      unawaited(_logLocks('still opening after ${clock.elapsed.inSeconds} s'));
    });
    try {
      final result = await WasmDatabase.open(
        databaseName: 'velorki',
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.js'),
      );
      final missing = result.missingFeatures.map((f) => f.name).join(', ');
      debugPrint(
        'velorki: database in ${result.chosenImplementation.name} '
        'after ${clock.elapsedMilliseconds} ms'
        '${missing.isEmpty ? '' : ' (missing: $missing)'}',
      );
      return result.resolvedExecutor.interceptWith(_SlowStatements());
    } finally {
      slow.cancel();
    }
  }),
);

/// Run on every connection before anything else. Each transaction in OPFS
/// otherwise creates and deletes its journal file and flushes it to disk
/// three times; on a busy disk every flush takes milliseconds. A persisted
/// journal is kept and zeroed instead, and NORMAL flushes once per commit:
/// a power cut may lose the last commit, never the file.
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
