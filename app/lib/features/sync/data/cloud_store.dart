import 'dart:typed_data';

/// One record as a [CloudStore] keeps it: what `RecordCodec` makes of a
/// route or a ride (its fields and its gzip JSON body), and the version
/// the store gave it, which a write names to go over it.
class StoredRecord {
  /// Creates the record.
  const StoredRecord({
    required this.name,
    required this.type,
    required this.fields,
    required this.version,
    this.body,
  });

  /// The record name (`recordNameOf`).
  final String name;

  /// The record type (`SyncKind.recordType`).
  final String type;

  /// Strings, integers and doubles; no null values.
  final Map<String, Object?> fields;

  /// The gzip body, or null.
  final Uint8List? body;

  /// The store's version of the record (a Drive file's id and `version`,
  /// a CloudKit change tag), opaque here.
  final String version;
}

/// One write in a [CloudStore.push].
sealed class StoreWrite {
  const StoreWrite(this.name);

  /// The record name.
  final String name;
}

/// Writes a record whole.
class StoreSave extends StoreWrite {
  /// Creates the save. With [ifVersion] null the record must not be there
  /// yet; otherwise it must still be at that version.
  const StoreSave(
    super.name, {
    required this.type,
    required this.fields,
    required this.body,
    required this.ifVersion,
  });

  /// The record type.
  final String type;

  /// The fields, no null values.
  final Map<String, Object?> fields;

  /// The gzip body, or null.
  final Uint8List? body;

  /// The version the record must be at, or null for a new one.
  final String? ifVersion;
}

/// Deletes a record; one that is gone already is deleted too.
class StoreDelete extends StoreWrite {
  /// Creates the delete.
  const StoreDelete(super.name);
}

/// What became of one [StoreWrite].
sealed class StoreResult {
  const StoreResult();
}

/// Written; [version] is the record's new one (null for a delete).
class StoreDone extends StoreResult {
  /// Creates the result.
  const StoreDone([this.version]);

  /// The new version of a saved record.
  final String? version;
}

/// Refused: the record is not at the version named (or is there where
/// none was); the store's copy comes along.
class StoreConflict extends StoreResult {
  /// Creates the result.
  const StoreConflict(this.server);

  /// The record as the store has it.
  final StoredRecord server;
}

/// Refused: the version named is of a record the store no longer has.
class StoreMissing extends StoreResult {
  /// Creates the result.
  const StoreMissing();
}

/// Failed for [failure].
class StoreFailed extends StoreResult {
  /// Creates the result.
  const StoreFailed(this.failure);

  /// Why.
  final CloudStoreFailure failure;
}

/// What changed in a store, or everything in it.
class StoreChanges {
  /// Creates the page.
  const StoreChanges({
    required this.changed,
    required this.deleted,
    required this.cursor,
    this.more = false,
  });

  /// The records written since, as they are now.
  final List<StoredRecord> changed;

  /// The names of the records deleted since.
  final List<String> deleted;

  /// Where the next [CloudStore.pull] starts.
  final String cursor;

  /// Whether another page follows from [cursor] at once.
  final bool more;
}

/// Why a store call failed, as far as the sync cares.
enum CloudStoreFailure {
  /// No network, a busy or rate-limited server, a token being refreshed:
  /// tried again after a while.
  transient,

  /// The rider's storage is full.
  quotaExceeded,

  /// The account is still the rider's, but only they can let the app in
  /// again (a browser's Google token is gone after an hour or a reload, a
  /// CloudKit web session ran out): what waits stays until they sign in.
  signInNeeded,

  /// Anything else; tried again on the next launch or return to the app.
  other,
}

/// A store call that failed as a whole.
class CloudStoreException implements Exception {
  /// Creates the failure.
  const CloudStoreException(this.failure, [this.message, this.retryAfter]);

  /// Why.
  final CloudStoreFailure failure;

  /// What the store said, for the log.
  final String? message;

  /// How long the store asked to be left alone (a throttled CloudKit's
  /// `retryAfter`), or null: a retry waits at least this long.
  final Duration? retryAfter;

  @override
  String toString() => 'CloudStoreException(${failure.name}: $message)';
}

/// A cursor the store can no longer pull from: everything is listed again.
class StoreCursorExpired implements Exception {
  /// Creates the failure.
  const StoreCursorExpired();
}

/// A cloud that keeps records by name, for clouds without a sync engine of
/// their own (Google Drive's app data folder, CloudKit JS); what
/// `StoreSyncBackend` syncs through. Every call may throw
/// [CloudStoreException].
///
/// A [StoreSave]'s precondition need not be atomic: a store whose API has
/// no conditional write (Drive v3's `files.update`) reads the record's
/// version first and compares, and the small race that leaves is
/// accepted; the newer change still wins on the next round.
abstract interface class CloudStore {
  /// The signed-in account's stable id, or null when no one is signed in.
  Future<String?> accountId();

  /// The record [name], or null.
  Future<StoredRecord?> get(String name);

  /// Applies [writes]; one result per write, in their order.
  Future<List<StoreResult>> push(List<StoreWrite> writes);

  /// What changed since [cursor], a page at a time. Throws
  /// [StoreCursorExpired].
  Future<StoreChanges> pull(String cursor);

  /// Every record there is (no deletions), a page at a time from
  /// [cursor] when [StoreChanges.more] said so, and the cursor to [pull]
  /// from after it.
  Future<StoreChanges> fullList([String? cursor]);
}
