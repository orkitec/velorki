// The web side of a conditional import: what uses it is the same import
// on the phone side, which is the side dart_code_linter follows.
// ignore_for_file: unused-code

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';

/// The browser's database: drift's WebAssembly SQLite in `drift_worker.js`,
/// kept in the origin private file system, or in IndexedDB where the browser
/// gives a worker no OPFS. `sqlite3.wasm` and `drift_worker.js` are served
/// from `web/`, next to `index.html`.
QueryExecutor openVelorkiDatabase() => DatabaseConnection.delayed(
  Future(() async {
    final result = await WasmDatabase.open(
      databaseName: 'velorki',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    final missing = result.missingFeatures.map((f) => f.name).join(', ');
    debugPrint(
      'velorki: database in ${result.chosenImplementation.name}'
      '${missing.isEmpty ? '' : ' (missing: $missing)'}',
    );
    return result.resolvedExecutor;
  }),
);

/// Tests run on the VM; a browser build has no in-memory database.
QueryExecutor inMemoryDatabase() =>
    throw UnsupportedError('inMemoryDatabase() in a browser');
