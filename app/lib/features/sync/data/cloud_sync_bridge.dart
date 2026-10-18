import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/platform_features.dart';
import '../domain/cloud_record.dart';
import '../domain/cloud_sync_status.dart';

part 'cloud_sync_bridge.g.dart';

final Logger _log = Logger('velorki.sync.bridge');

/// How a save CloudKit refused failed, as far as the library cares.
enum SaveFailure {
  /// The server's copy changed since this device last saw it; the server's
  /// record comes along.
  conflict,

  /// The record is not on the server any more.
  unknownItem,

  /// The rider's iCloud storage is full.
  quotaExceeded,

  /// CloudKit tries again by itself (no network, busy, rate limited).
  retrying,

  /// Anything else.
  other;

  /// The failure named [name], [other] for anything unknown.
  static SaveFailure fromName(Object? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => other);
}

/// One save CloudKit refused.
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

/// What happened to the iCloud account under the running sync.
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

/// Why the iCloud zone went.
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

/// What the native side asks of the library and tells it.
abstract interface class CloudSyncHandler {
  /// The records with [names] as they are to be saved; a name without a
  /// record (deleted meanwhile, or never to be synced) is left out, and the
  /// native side drops its save.
  Future<List<CloudRecord>> recordsToSave(List<String> names);

  /// Writes what changed in iCloud. The native side waits for it, so the
  /// sync only moves on once the changes are in the database.
  Future<void> applyRemote(
    List<CloudRecord> modifications,
    List<String> deletions,
  );

  /// What happened to the records sent.
  Future<void> sent(SentChanges changes);

  /// The iCloud account changed.
  Future<void> accountChanged(AccountChange change);

  /// The iCloud zone was deleted.
  Future<void> zoneDeleted(ZoneDeletion reason);

  /// Settings keys another device changed, with their new values (null:
  /// removed).
  Future<void> settingsChanged(Map<String, Object?> values);
}

/// The platform's sync engine: CloudKit's CKSyncEngine on iOS 17 and later,
/// nothing anywhere else.
abstract interface class CloudSyncBridge {
  /// Whether this device can sync at all (iOS 17 or later).
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

  /// Fetches what changed in iCloud now, rather than when the engine would.
  Future<void> fetchNow();

  /// Where the sync stands, as it changes.
  Stream<CloudSyncStatus> get status;

  /// The iCloud key-value store's values for [keys]; missing keys are left
  /// out.
  Future<Map<String, Object?>> readSettings(List<String> keys);

  /// Writes [values] to the iCloud key-value store; a null value removes
  /// the key. Keys whose value is already there are not written again.
  Future<void> writeSettings(Map<String, Object?> values);
}

/// [CloudSyncBridge] over `velorki/cloud_sync`, mirrored in
/// `ios/Runner/CloudSync.swift`.
class MethodChannelCloudSyncBridge implements CloudSyncBridge {
  /// Creates the bridge and starts answering the native side.
  MethodChannelCloudSyncBridge() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const MethodChannel _channel = MethodChannel('velorki/cloud_sync');
  static const EventChannel _statusChannel = EventChannel(
    'velorki/cloud_sync/status',
  );

  CloudSyncHandler? _handler;

  @override
  void setHandler(CloudSyncHandler? handler) => _handler = handler;

  @override
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException catch (e) {
      _log.warning('isSupported failed', e);
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> start() => _invoke('start');

  @override
  Future<void> stop() => _invoke('stop');

  @override
  Future<void> enqueue({
    List<String> saves = const <String>[],
    List<String> deletes = const <String>[],
  }) {
    if (saves.isEmpty && deletes.isEmpty) return Future<void>.value();
    return _invoke('enqueue', {'saves': saves, 'deletes': deletes});
  }

  @override
  Future<void> fetchNow() => _invoke('fetchNow');

  @override
  late final Stream<CloudSyncStatus> status = _statusChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => CloudSyncStatus.fromMap(event as Map<Object?, Object?>));

  @override
  Future<Map<String, Object?>> readSettings(List<String> keys) async {
    try {
      final values = await _channel.invokeMapMethod<String, Object?>(
        'readSettings',
        {'keys': keys},
      );
      return values ?? const <String, Object?>{};
    } on PlatformException catch (e) {
      _log.warning('readSettings failed', e);
      return const <String, Object?>{};
    }
  }

  @override
  Future<void> writeSettings(Map<String, Object?> values) =>
      _invoke('writeSettings', {'values': values});

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (e) {
      _log.warning('$method failed', e);
    }
  }

  Future<Object?> _onCall(MethodCall call) async {
    final handler = _handler;
    if (handler == null) return null;
    final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
    switch (call.method) {
      case 'recordsToSave':
        final records = await handler.recordsToSave(_strings(args['names']));
        return [for (final r in records) r.toMap()];
      case 'remoteChanges':
        await handler.applyRemote(
          _records(args['modifications']),
          _strings(args['deletions']),
        );
        return null;
      case 'sentChanges':
        await handler.sent(
          SentChanges(
            saved: <String, Uint8List>{
              for (final entry in ((args['saved'] as Map?) ?? const {}).entries)
                '${entry.key}': entry.value as Uint8List,
            },
            failedSaves: [
              for (final f in (args['failedSaves'] as List?) ?? const [])
                if (f is Map)
                  FailedSave(
                    f['name']! as String,
                    SaveFailure.fromName(f['failure']),
                    serverRecord: f['serverRecord'] is Map
                        ? CloudRecord.fromMap(f['serverRecord'] as Map)
                        : null,
                  ),
            ],
            deleted: _strings(args['deleted']),
            failedDeletes: _strings(args['failedDeletes']),
          ),
        );
        return null;
      case 'accountChanged':
        final change = AccountChange.fromName(args['change']);
        if (change != null) await handler.accountChanged(change);
        return null;
      case 'zoneDeleted':
        await handler.zoneDeleted(ZoneDeletion.fromName(args['reason']));
        return null;
      case 'settingsChanged':
        await handler.settingsChanged(<String, Object?>{
          for (final entry in ((args['values'] as Map?) ?? const {}).entries)
            '${entry.key}': entry.value,
        });
        return null;
    }
    throw MissingPluginException(call.method);
  }

  static List<String> _strings(Object? list) => [
    for (final s in (list as List?) ?? const []) '$s',
  ];

  static List<CloudRecord> _records(Object? list) => [
    for (final r in (list as List?) ?? const [])
      if (r is Map) CloudRecord.fromMap(r),
  ];
}

/// The platform's sync engine, or null where there is none: iOS only, and
/// never in a browser (whose platform may say iOS too).
@Riverpod(keepAlive: true)
CloudSyncBridge? cloudSyncBridge(Ref ref) =>
    defaultTargetPlatform == TargetPlatform.iOS &&
        ref.watch(platformFeaturesProvider).cloudSync
    ? MethodChannelCloudSyncBridge()
    : null;
