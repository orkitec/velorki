import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:velorki/features/sync/data/cloud_sync_bridge.dart';
import 'package:velorki/features/sync/domain/cloud_record.dart';
import 'package:velorki/features/sync/domain/cloud_sync_status.dart';

/// A record as the fake server keeps it: its fields, its body's bytes and
/// its change tag.
class _Stored {
  _Stored(this.record, this.body, this.tag);

  final CloudRecord record;
  final Uint8List? body;
  final int tag;
}

/// The rider's private database, as far as CKSyncEngine shows it: records
/// with change tags, a save over a stale tag refused with the server's
/// record, and a change log every device fetches from.
class FakeCloud {
  /// Creates an empty cloud whose incoming body files go into [dir].
  FakeCloud(this.dir);

  /// Where bodies handed to a device are written.
  final Directory dir;

  final Map<String, _Stored> _records = <String, _Stored>{};

  /// Every change, in order: a record name, deleted or not.
  final List<(String, bool)> _log = <(String, bool)>[];
  int _nextTag = 1;
  int _files = 0;

  /// The names of the records on the server.
  Set<String> get names => _records.keys.toSet();

  /// The fields of the record [name], or null.
  Map<String, Object?>? fields(String name) => _records[name]?.record.fields;

  /// Deletes [name] as another device would.
  void deleteElsewhere(String name) {
    if (_records.remove(name) != null) _log.add((name, true));
  }

  static Uint8List _systemFields(int tag) =>
      Uint8List.fromList(utf8.encode('tag:$tag'));

  static int? _tagOf(Uint8List? systemFields) {
    if (systemFields == null) return null;
    final text = utf8.decode(systemFields);
    return text.startsWith('tag:') ? int.tryParse(text.substring(4)) : null;
  }

  CloudRecord _handOut(_Stored stored) {
    String? path;
    if (stored.body != null) {
      path = p.join(dir.path, 'in_${_files++}.json.gz');
      File(path).writeAsBytesSync(stored.body!);
    }
    return CloudRecord(
      name: stored.record.name,
      type: stored.record.type,
      fields: stored.record.fields,
      assetPath: path,
      systemFields: _systemFields(stored.tag),
    );
  }

  /// Saves [record] unless its tag is stale; returns the new system fields,
  /// or the server's record for a conflict.
  (Uint8List?, CloudRecord?) _save(CloudRecord record) {
    final current = _records[record.name];
    if (current != null && _tagOf(record.systemFields) != current.tag) {
      return (null, _handOut(current));
    }
    final body = record.assetPath == null
        ? current?.body
        : File(record.assetPath!).readAsBytesSync();
    // As the native side does once a save is done.
    if (record.assetPath != null) File(record.assetPath!).deleteSync();
    final fields = <String, Object?>{...?current?.record.fields};
    for (final MapEntry(:key, :value) in record.fields.entries) {
      if (value == null) {
        fields.remove(key);
      } else {
        fields[key] = value;
      }
    }
    final tag = _nextTag++;
    _records[record.name] = _Stored(
      CloudRecord(name: record.name, type: record.type, fields: fields),
      body,
      tag,
    );
    _log.add((record.name, false));
    return (_systemFields(tag), null);
  }
}

/// One device's engine over a [FakeCloud].
class FakeCloudSyncBridge implements CloudSyncBridge {
  /// Creates a device's engine.
  FakeCloudSyncBridge(this.cloud, {this.supported = true});

  /// The server.
  final FakeCloud cloud;

  /// What [isSupported] answers.
  bool supported;

  CloudSyncHandler? _handler;
  final Set<String> pendingSaves = <String>{};
  final Set<String> pendingDeletes = <String>{};
  int _cursor = 0;

  /// Whether [start] was called and [stop] not since.
  bool started = false;

  /// What [readSettings] reads and [writeSettings] writes: the key-value
  /// store.
  final Map<String, Object?> settings = <String, Object?>{};

  /// The writes [writeSettings] received.
  final List<Map<String, Object?>> settingWrites = <Map<String, Object?>>[];

  final StreamController<CloudSyncStatus> _status =
      StreamController<CloudSyncStatus>.broadcast();

  /// Sends a status as the native side would.
  void emit(CloudSyncStatus status) => _status.add(status);

  @override
  Future<bool> isSupported() async => supported;

  @override
  void setHandler(CloudSyncHandler? handler) => _handler = handler;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async => started = false;

  @override
  Future<void> enqueue({
    List<String> saves = const <String>[],
    List<String> deletes = const <String>[],
  }) async {
    pendingSaves.addAll(saves);
    for (final name in deletes) {
      pendingSaves.remove(name);
      pendingDeletes.add(name);
    }
  }

  @override
  Future<void> fetchNow() => fetch();

  @override
  Stream<CloudSyncStatus> get status => _status.stream;

  @override
  Future<Map<String, Object?>> readSettings(List<String> keys) async => {
    for (final key in keys)
      if (settings[key] != null) key: settings[key],
  };

  @override
  Future<void> writeSettings(Map<String, Object?> values) async {
    settingWrites.add(values);
    for (final MapEntry(:key, :value) in values.entries) {
      if (value == null) {
        settings.remove(key);
      } else {
        settings[key] = value;
      }
    }
  }

  /// Sends everything pending, as one round, until nothing is left.
  Future<void> send() async {
    final handler = _handler!;
    while (pendingSaves.isNotEmpty || pendingDeletes.isNotEmpty) {
      final names = pendingSaves.toList();
      pendingSaves.clear();
      final deletes = pendingDeletes.toList();
      pendingDeletes.clear();
      final records = await handler.recordsToSave(names);
      final saved = <String, Uint8List>{};
      final failed = <FailedSave>[];
      for (final record in records) {
        final (systemFields, server) = cloud._save(record);
        if (systemFields != null) {
          saved[record.name] = systemFields;
        } else {
          failed.add(
            FailedSave(record.name, SaveFailure.conflict, serverRecord: server),
          );
        }
      }
      for (final name in deletes) {
        cloud.deleteElsewhere(name);
      }
      await handler.sent(
        SentChanges(saved: saved, failedSaves: failed, deleted: deletes),
      );
    }
  }

  /// Fetches what changed since this device last fetched.
  Future<void> fetch() async {
    final log = cloud._log.sublist(_cursor);
    _cursor = cloud._log.length;
    if (log.isEmpty) return;
    final touched = <String>{for (final (name, _) in log) name};
    final modifications = <CloudRecord>[];
    final deletions = <String>[];
    for (final name in touched) {
      final stored = cloud._records[name];
      if (stored == null) {
        deletions.add(name);
      } else {
        modifications.add(cloud._handOut(stored));
      }
    }
    await _handler!.applyRemote(modifications, deletions);
  }

  /// A full round: send, then fetch.
  Future<void> sync() async {
    await send();
    await fetch();
  }

  /// Delivers [values] from the key-value store as another device's change.
  Future<void> settingsFromElsewhere(Map<String, Object?> values) async {
    settings.addAll(values);
    await _handler!.settingsChanged(values);
  }
}

/// [CloudSyncHandler] around a library sync and nothing else, for tests
/// that drive [LibrarySync] without the controller.
class LibraryHandler implements CloudSyncHandler {
  /// Creates the handler.
  LibraryHandler({
    required this.toSave,
    required this.apply,
    required this.onSent,
  });

  /// [CloudSyncHandler.recordsToSave].
  final Future<List<CloudRecord>> Function(List<String>) toSave;

  /// [CloudSyncHandler.applyRemote].
  final Future<void> Function(List<CloudRecord>, List<String>) apply;

  /// [CloudSyncHandler.sent].
  final Future<void> Function(SentChanges) onSent;

  @override
  Future<List<CloudRecord>> recordsToSave(List<String> names) => toSave(names);

  @override
  Future<void> applyRemote(
    List<CloudRecord> modifications,
    List<String> deletions,
  ) => apply(modifications, deletions);

  @override
  Future<void> sent(SentChanges changes) => onSent(changes);

  @override
  Future<void> accountChanged(AccountChange change) async {}

  @override
  Future<void> zoneDeleted(ZoneDeletion reason) async {}

  @override
  Future<void> settingsChanged(Map<String, Object?> values) async {}
}
