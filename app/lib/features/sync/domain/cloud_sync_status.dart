import 'package:flutter/foundation.dart';

/// The iCloud account on this device, as CloudKit reports it.
enum CloudAccount {
  /// Signed in, iCloud Drive on: sync can run.
  available,

  /// No account, or iCloud is switched off for the app.
  noAccount,

  /// Parental controls or a device profile keep the app out of iCloud.
  restricted,

  /// Signed in but not usable for a moment (a sign-in still finishing).
  temporarilyUnavailable,

  /// Not asked yet, or CloudKit could not say.
  unknown;

  /// The account named [name], [unknown] for anything else.
  static CloudAccount fromName(Object? name) =>
      values.firstWhere((a) => a.name == name, orElse: () => unknown);
}

/// What last went wrong, if anything.
enum CloudSyncError {
  /// The rider's iCloud storage is full.
  quotaExceeded,

  /// No network; CloudKit tries again by itself.
  network,

  /// Only the rider can let the app in again: Settings shows a sign-in.
  signInNeeded,

  /// Anything else; tried again on the next launch or return to the app.
  other;

  /// The error named [name], or null.
  static CloudSyncError? fromName(Object? name) {
    for (final error in values) {
      if (error.name == name) return error;
    }
    return null;
  }
}

/// Where iCloud sync stands on this device.
@immutable
class CloudSyncStatus {
  /// Creates the status.
  const CloudSyncStatus({
    this.account = CloudAccount.unknown,
    this.syncing = false,
    this.lastSyncedAt,
    this.error,
  });

  /// Reads the map the status channel carries.
  factory CloudSyncStatus.fromMap(Map<Object?, Object?> map) {
    final last = map['lastSyncedAt'];
    return CloudSyncStatus(
      account: CloudAccount.fromName(map['account']),
      syncing: map['syncing'] == true,
      lastSyncedAt: last is int
          ? DateTime.fromMillisecondsSinceEpoch(last)
          : null,
      error: CloudSyncError.fromName(map['error']),
    );
  }

  /// The iCloud account.
  final CloudAccount account;

  /// Whether changes are being fetched or sent right now.
  final bool syncing;

  /// When a fetch or a send last finished without an error.
  final DateTime? lastSyncedAt;

  /// What last went wrong, cleared by the next sync that goes through.
  final CloudSyncError? error;

  @override
  bool operator ==(Object other) =>
      other is CloudSyncStatus &&
      other.account == account &&
      other.syncing == syncing &&
      other.lastSyncedAt == lastSyncedAt &&
      other.error == error;

  @override
  int get hashCode => Object.hash(account, syncing, lastSyncedAt, error);
}
