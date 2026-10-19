import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/platform_features.dart';
import '../domain/cloud_record.dart';
import '../domain/cloud_sync_status.dart';
import 'sync_backend.dart';

part 'cloud_sync_bridge.g.dart';

final Logger _log = Logger('velorki.sync.bridge');

/// [SyncBackend] over `velorki/cloud_sync`, mirrored in
/// `ios/Runner/CloudSync.swift`.
class MethodChannelCloudSyncBridge implements SyncBackend {
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
SyncBackend? cloudSyncBridge(Ref ref) =>
    defaultTargetPlatform == TargetPlatform.iOS &&
        ref.watch(platformFeaturesProvider).cloudSync
    ? MethodChannelCloudSyncBridge()
    : null;
