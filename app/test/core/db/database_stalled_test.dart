import 'dart:async';

import 'package:drift/drift.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/core/db/database_stalled.dart';

void main() {
  bool stalledAfter(VelorkiDatabase db, Duration wait) {
    late bool stalled;
    fakeAsync((async) {
      final container = ProviderContainer(
        overrides: [velorkiDatabaseProvider.overrideWithValue(db)],
      );
      final sub = container.listen(databaseStalledProvider, (_, _) {});
      async.elapse(wait);
      stalled = sub.read();
      container.dispose();
      async.flushTimers();
    });
    return stalled;
  }

  test('a database that answers is never stalled', () {
    final db = VelorkiDatabase.memory();
    addTearDown(db.close);
    expect(stalledAfter(db, databasePatience * 2), isFalse);
  });

  test('a database that does not answer is stalled after the patience', () {
    // Opens never: as a browser tab waits on a lock another tab holds.
    final db = VelorkiDatabase(
      LazyDatabase(() => Completer<QueryExecutor>().future),
    );
    expect(
      stalledAfter(db, databasePatience - const Duration(seconds: 1)),
      isFalse,
    );
    expect(stalledAfter(db, databasePatience), isTrue);
  });
}
