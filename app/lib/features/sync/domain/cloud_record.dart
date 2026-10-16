import 'package:flutter/foundation.dart';

/// The two kinds of record in the iCloud zone, and the kind column of
/// `sync_records`.
enum SyncKind {
  /// A saved route.
  route('route', 'Route'),

  /// A recorded ride.
  ride('ride', 'Ride');

  const SyncKind(this.column, this.recordType);

  /// The `sync_records.kind` value.
  final String column;

  /// The CloudKit record type.
  final String recordType;

  /// The kind stored as [column], or null.
  static SyncKind? fromColumn(String column) {
    for (final kind in values) {
      if (kind.column == column) return kind;
    }
    return null;
  }
}

/// The CloudKit record name of a row: its kind and its id, so a name says
/// what it is even where CloudKit gives no record type (a pending save).
String recordNameOf(SyncKind kind, String id) => '${kind.column}_$id';

/// The kind and id a record name stands for, or null for a name this
/// build does not know.
(SyncKind, String)? parseRecordName(String name) {
  final split = name.indexOf('_');
  if (split <= 0) return null;
  final kind = SyncKind.fromColumn(name.substring(0, split));
  if (kind == null) return null;
  return (kind, name.substring(split + 1));
}

/// One CloudKit record as it crosses the platform channel.
///
/// [fields] hold strings, integers and doubles; a null value removes the
/// field from the server's copy. [assetPath] is a gzip file with what is
/// too large for fields (the track above all), sent as the record's `body`
/// asset. [systemFields] are CloudKit's own (the change tag), opaque here.
@immutable
class CloudRecord {
  /// Creates the record.
  const CloudRecord({
    required this.name,
    required this.type,
    required this.fields,
    this.assetPath,
    this.systemFields,
  });

  /// Reads the map the platform channel carries.
  factory CloudRecord.fromMap(Map<Object?, Object?> map) => CloudRecord(
    name: map['name']! as String,
    type: map['type']! as String,
    fields: <String, Object?>{
      for (final entry in ((map['fields'] as Map?) ?? const {}).entries)
        '${entry.key}': entry.value,
    },
    assetPath: map['asset'] as String?,
    systemFields: map['systemFields'] as Uint8List?,
  );

  /// The record name, [recordNameOf].
  final String name;

  /// The record type, [SyncKind.recordType].
  final String type;

  /// The record's fields.
  final Map<String, Object?> fields;

  /// The gzip file of the `body` asset, or null.
  final String? assetPath;

  /// CloudKit's system fields, or null for a record the server never had.
  final Uint8List? systemFields;

  /// The map the platform channel carries.
  Map<String, Object?> toMap() => <String, Object?>{
    'name': name,
    'type': type,
    'fields': fields,
    'asset': assetPath,
    'systemFields': systemFields,
  };
}
