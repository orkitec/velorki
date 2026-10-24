import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// `<documents>/velorki.sqlite`, opened on a background isolate.
QueryExecutor openVelorkiDatabase() => LazyDatabase(() async {
  final dir = await getApplicationDocumentsDirectory();
  return NativeDatabase.createInBackground(
    File(p.join(dir.path, 'velorki.sqlite')),
  );
});

/// Run on every connection before anything else; the phone's defaults
/// suit it.
const List<String> connectionPragmas = [];

/// A database that lives as long as the executor, for tests.
QueryExecutor inMemoryDatabase() => NativeDatabase.memory();
