import 'package:flutter/foundation.dart';

import '../domain/cloud_record.dart';
import '../domain/cloud_sync_status.dart';

/// How a save the cloud refused failed, as far as the library cares.
enum SaveFailure {
  /// The server's copy changed since this device last saw it; the server's
  /// record comes along.
  conflict,

  /// The record is not on the server any more.
  unknownItem,

  /// The rider's cloud storage is full.
  quotaExceeded,

  /// The engine tries again by itself (no network, busy, rate limited).
  retrying,

  /// Anything else.
  other;

  /// The failure named [name], [other] for anything unknown.
  static SaveFailure fromName(Object? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => other);
}

/// One save the cloud refused.
@immutable
class FailedSave {
  /// Creates the failure.
  const FailedSave(this.name, this.failure, {this.serverRecord});

  /// The record name.
  final String name;

  /// Why.
  final SaveFailure failure;

  /// The server's record, for a [SaveFailure.conflict].
  final CloudRecord? serverRecord;
}

/// What one round of sending brought back.
@immutable
class SentChanges {
  /// Creates the result.
  const SentChanges({
    this.saved = const <String, Uint8List>{},
    this.failedSaves = const <FailedSave>[],
    this.deleted = const <String>[],
    this.failedDeletes = const <String>[],
  });

  /// The records saved, by name, with their new system fields.
  final Map<String, Uint8List> saved;

  /// The saves refused.
  final List<FailedSave> failedSaves;

  /// The names of the records deleted.
  final List<String> deleted;

  /// The names of the records whose delete failed.
  final List<String> failedDeletes;
}

/// What happened to the cloud account under the running sync.
enum AccountChange {
  /// An account appeared.
  signIn,

  /// The account went.
  signOut,

  /// A different account is signed in.
  switchAccounts;

  /// The change named [name], or null.
  static AccountChange? fromName(Object? name) {
    for (final change in values) {
      if (change.name == name) return change;
    }
    return null;
  }
}

/// Why the iCloud zone went (CKSyncEngine only).
enum ZoneDeletion {
  /// Deleted by the app (another device's own reset).
  deleted,

  /// The rider deleted the app's data from iCloud in Settings.
  purged,

  /// The rider reset Advanced Data Protection keys; the data is gone.
  encryptedDataReset;

  /// The reason named [name], [deleted] for anything unknown.
  static ZoneDeletion fromName(Object? name) =>
      values.firstWhere((z) => z.name == name, orElse: () => deleted);
}

/// What the engine asks of the library and tells it.
abstract interface class CloudSyncHandler {
  /// The records with [names] as they are to be saved; a name without a
  /// record (deleted meanwhile, or never to be synced) is left out, and the
  /// engine drops its save.
  Future<List<CloudRecord>> recordsToSave(List<String> names);

  /// Writes what changed in the cloud. The engine waits for it, so the
  /// sync only moves on once the changes are in the database.
  Future<void> applyRemote(
    List<CloudRecord> modifications,
    List<String> deletions,
  );

  /// What happened to the records sent.
  Future<void> sent(SentChanges changes);

  /// The cloud account changed.
  Future<void> accountChanged(AccountChange change);

  /// The iCloud zone was deleted.
  Future<void> zoneDeleted(ZoneDeletion reason);

  /// Settings keys another device changed, with their new values (null:
  /// removed).
  Future<void> settingsChanged(Map<String, Object?> values);
}

/// A sync engine the library and the settings run over: CloudKit's
/// CKSyncEngine on iOS (`MethodChannelCloudSyncBridge`), or
/// `StoreSyncBackend` over a `CloudStore` for clouds without one (Google
/// Drive). Either asks for records by name as it sends, hands every
/// fetched change over and waits for it to be written, and reports what
/// became of each save, so `LibrarySync` is the same over both.
abstract interface class SyncBackend {
  /// Whether this device can sync with it at all.
  Future<bool> isSupported();

  /// Attaches the library's side. One handler at a time.
  void setHandler(CloudSyncHandler? handler);

  /// Starts the engine; it fetches and sends by itself from then on.
  Future<void> start();

  /// Stops the engine. What is pending stays for the next [start].
  Future<void> stop();

  /// Asks for the records named [saves] to be saved and [deletes] to be
  /// deleted.
  Future<void> enqueue({
    List<String> saves = const <String>[],
    List<String> deletes = const <String>[],
  });

  /// Fetches what changed in the cloud now, rather than when the engine
  /// would. Completes when the fetch has.
  Future<void> fetchNow();

  /// Where the sync stands, as it changes.
  Stream<CloudSyncStatus> get status;

  /// The cloud's synced settings (iCloud's key-value store) for [keys];
  /// missing keys are left out.
  Future<Map<String, Object?>> readSettings(List<String> keys);

  /// Writes [values] to the cloud's synced settings; a null value removes
  /// the key. Keys whose value is already there are not written again.
  Future<void> writeSettings(Map<String, Object?> values);
}
