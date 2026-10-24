import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// How long the library waits for the database before it says so.
const Duration databasePatience = Duration(seconds: 20);

/// True while the database has gone [databasePatience] without answering a
/// first query: in a browser, another tab can hold it, or a busy disk slow
/// its first open. Lists waiting on it show a note in place of a spinner
/// that would turn without end; they fill in whenever it answers.
class DatabaseStalled extends Notifier<bool> {
  @override
  bool build() {
    final db = ref.watch(velorkiDatabaseProvider);
    var answered = false;
    final timer = Timer(databasePatience, () {
      if (!answered && ref.mounted) state = true;
    });
    ref.onDispose(timer.cancel);
    unawaited(
      db.customSelect('SELECT 1').get().then<void>(
        (_) {
          answered = true;
          timer.cancel();
          if (ref.mounted) state = false;
        },
        // A database that fails says so through the lists' own errors.
        onError: (Object _) => timer.cancel(),
      ),
    );
    return false;
  }
}

/// See [DatabaseStalled].
final databaseStalledProvider = NotifierProvider<DatabaseStalled, bool>(
  DatabaseStalled.new,
);
