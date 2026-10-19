import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:velorki_io/io.dart';
import 'package:velorki_io/worker.dart';

import '../../../core/db/database.dart';
import '../domain/cloud_record.dart';

/// The record format this build writes. A newer build only adds fields and
/// body keys, which an older one ignores; a change an older build would
/// misread takes a new record type instead.
const int recordSchemaVersion = 1;

/// Field names shared by both record types.
abstract final class _F {
  static const String schemaVersion = 'schemaVersion';
  static const String modifiedAt = 'modifiedAt';
}

/// A record decoded into a row, with what sync needs beside it.
class DecodedRecord<T> {
  /// Creates the result.
  const DecodedRecord(this.row, {required this.modifiedAtMs});

  /// The row to write.
  final T row;

  /// When the record was last changed, on whichever device.
  final int modifiedAtMs;
}

/// Turns `routes` and `rides` rows into CloudKit records and back.
///
/// Small values are record fields; the track and everything else that can
/// grow (waypoints, turns, points of interest, the original file's line)
/// goes into one gzip-compressed JSON file sent as the `body` asset, so no
/// record comes near CloudKit's 1 MB limit for fields.
///
/// Never in a record: a route's partner ids and the time it was read from
/// its service (Ride with GPS ids stay on the phone that imported it; Strava
/// routes are not synced at all), and where a ride was uploaded to (its
/// Strava and Ride with GPS activity links).
class RecordCodec {
  /// Creates a codec writing its body files into [outbox].
  RecordCodec(this.outbox);

  /// Where the body files of records to be sent are written; the native
  /// side deletes each once its save is done.
  final Directory outbox;

  // --- Routes ---------------------------------------------------------------

  /// The record for [row], changed at [changedAtMs].
  Future<CloudRecord> encodeRoute(
    RouteRow row, {
    required int changedAtMs,
    Uint8List? systemFields,
  }) async {
    final name = recordNameOf(SyncKind.route, row.id);
    final body = <String, Object?>{
      'geometry': base64Encode(row.geometry),
      'waypoints': row.waypointsJson,
      'routingOptions': row.routingOptionsJson,
      'surfaceStats': row.surfaceStatsJson,
      'turns': row.turnsJson,
      'pois': row.poisJson,
      'original': row.originalJson,
      if (row.originalGeometry != null)
        'originalGeometry': base64Encode(row.originalGeometry!),
    };
    return CloudRecord(
      name: name,
      type: SyncKind.route.recordType,
      systemFields: systemFields,
      assetPath: await _writeBody(name, body),
      fields: <String, Object?>{
        _F.schemaVersion: recordSchemaVersion,
        _F.modifiedAt: changedAtMs,
        'name': row.name,
        'description': row.description,
        'source': row.source.name,
        'profile': row.profile,
        'createdAt': row.createdAt.millisecondsSinceEpoch,
        'updatedAt': row.updatedAt.millisecondsSinceEpoch,
        'distanceM': row.distanceM,
        'ascentM': row.ascentM,
        'descentM': row.descentM,
        'bboxMinLat': row.bboxMinLat,
        'bboxMinLon': row.bboxMinLon,
        'bboxMaxLat': row.bboxMaxLat,
        'bboxMaxLon': row.bboxMaxLon,
        'aiDescriptionGenerated': row.aiDescriptionGenerated ? 1 : 0,
        'turnsGenerated': row.turnsGenerated ? 1 : 0,
        'link': row.link,
        'creator': row.creator,
      },
    );
  }

  /// The row [record] describes, or null when it lacks what a route cannot
  /// do without (its body, its line). The partner columns are left absent,
  /// so writing it over a row keeps that row's own.
  Future<DecodedRecord<RoutesCompanion>?> decodeRoute(
    CloudRecord record,
  ) async {
    final parsed = parseRecordName(record.name);
    if (parsed == null || parsed.$1 != SyncKind.route) return null;
    final body = await _readBody(record.assetPath);
    final f = record.fields;
    final geometry = _bytes(body?['geometry']);
    if (body == null || geometry == null) return null;
    final createdAt = _date(f['createdAt']) ?? DateTime.now();
    return DecodedRecord(
      RoutesCompanion.insert(
        id: parsed.$2,
        name: _string(f['name']) ?? '',
        description: Value(_string(f['description'])),
        source: RouteSource.values.firstWhere(
          (s) => s.name == f['source'],
          orElse: () => RouteSource.planned,
        ),
        profile: _string(f['profile']) ?? 'trekking',
        createdAt: createdAt,
        updatedAt: _date(f['updatedAt']) ?? createdAt,
        distanceM: _double(f['distanceM']),
        ascentM: _double(f['ascentM']),
        descentM: _double(f['descentM']),
        bboxMinLat: _double(f['bboxMinLat']),
        bboxMinLon: _double(f['bboxMinLon']),
        bboxMaxLat: _double(f['bboxMaxLat']),
        bboxMaxLon: _double(f['bboxMaxLon']),
        geometry: geometry,
        waypointsJson: _string(body['waypoints']) ?? '[]',
        routingOptionsJson: _string(body['routingOptions']) ?? '{}',
        surfaceStatsJson: Value(_string(body['surfaceStats'])),
        turnsJson: Value(_string(body['turns'])),
        poisJson: Value(_string(body['pois'])),
        originalJson: Value(_string(body['original'])),
        originalGeometry: Value(_bytes(body['originalGeometry'])),
        aiDescriptionGenerated: Value(_bool(f['aiDescriptionGenerated'])),
        turnsGenerated: Value(_bool(f['turnsGenerated'])),
        link: Value(_string(f['link'])),
        creator: Value(_string(f['creator'])),
      ),
      modifiedAtMs: _int(f[_F.modifiedAt]) ?? 0,
    );
  }

  // --- Rides ----------------------------------------------------------------

  /// The record for [row], changed at [changedAtMs]. [routeId] is the
  /// followed route as it may be synced: null for one that stays on the
  /// phone.
  Future<CloudRecord> encodeRide(
    RideRow row, {
    required int changedAtMs,
    required String? routeId,
    Uint8List? systemFields,
  }) async {
    final name = recordNameOf(SyncKind.ride, row.id);
    final body = <String, Object?>{
      'geometry': base64Encode(row.geometry),
      'pauses': row.pausesJson,
      'surfaceStats': row.surfaceStatsJson,
      'laps': row.lapsJson,
      'deviceTotals': row.deviceTotalsJson,
      if (row.temperatures != null)
        'temperatures': base64Encode(row.temperatures!),
    };
    return CloudRecord(
      name: name,
      type: SyncKind.ride.recordType,
      systemFields: systemFields,
      assetPath: await _writeBody(name, body),
      fields: <String, Object?>{
        _F.schemaVersion: recordSchemaVersion,
        _F.modifiedAt: changedAtMs,
        'name': row.name,
        'startedAt': row.startedAt.millisecondsSinceEpoch,
        'endedAt': row.endedAt.millisecondsSinceEpoch,
        'distanceM': row.distanceM,
        'movingTimeS': row.movingTimeS,
        'elapsedTimeS': row.elapsedTimeS,
        'ascentM': row.ascentM,
        'descentM': row.descentM,
        'avgSpeedMps': row.avgSpeedMps,
        'maxSpeedMps': row.maxSpeedMps,
        'avgHeartRateBpm': row.avgHeartRateBpm,
        'maxHeartRateBpm': row.maxHeartRateBpm,
        'avgCadenceRpm': row.avgCadenceRpm,
        'avgPowerW': row.avgPowerW,
        'routeId': routeId,
        'notes': row.notes,
        'sourceFormat': row.sourceFormat,
        'creator': row.creator,
      },
    );
  }

  /// The row [record] describes, or null when it lacks its body or track.
  /// `uploads_json` is left absent, so a ride written over keeps its own.
  Future<DecodedRecord<RidesCompanion>?> decodeRide(CloudRecord record) async {
    final parsed = parseRecordName(record.name);
    if (parsed == null || parsed.$1 != SyncKind.ride) return null;
    final body = await _readBody(record.assetPath);
    final f = record.fields;
    final geometry = _bytes(body?['geometry']);
    if (body == null || geometry == null) return null;
    final startedAt = _date(f['startedAt']) ?? DateTime.now();
    return DecodedRecord(
      RidesCompanion.insert(
        id: parsed.$2,
        name: _string(f['name']) ?? '',
        startedAt: startedAt,
        endedAt: _date(f['endedAt']) ?? startedAt,
        distanceM: _double(f['distanceM']),
        movingTimeS: _int(f['movingTimeS']) ?? 0,
        elapsedTimeS: _int(f['elapsedTimeS']) ?? 0,
        ascentM: _double(f['ascentM']),
        descentM: _double(f['descentM']),
        avgSpeedMps: _double(f['avgSpeedMps']),
        maxSpeedMps: _double(f['maxSpeedMps']),
        avgHeartRateBpm: Value(_int(f['avgHeartRateBpm'])),
        maxHeartRateBpm: Value(_int(f['maxHeartRateBpm'])),
        avgCadenceRpm: Value(_int(f['avgCadenceRpm'])),
        avgPowerW: Value(_int(f['avgPowerW'])),
        routeId: Value(_string(f['routeId'])),
        geometry: geometry,
        pausesJson: _string(body['pauses']) ?? '[]',
        notes: Value(_string(f['notes'])),
        surfaceStatsJson: Value(_string(body['surfaceStats'])),
        lapsJson: Value(_string(body['laps'])),
        deviceTotalsJson: Value(_string(body['deviceTotals'])),
        temperatures: Value(_bytes(body['temperatures'])),
        sourceFormat: Value(_string(f['sourceFormat'])),
        creator: Value(_string(f['creator'])),
      ),
      modifiedAtMs: _int(f[_F.modifiedAt]) ?? 0,
    );
  }

  /// The modification time [record] carries, 0 when it has none.
  static int modifiedAtOf(CloudRecord record) =>
      _int(record.fields[_F.modifiedAt]) ?? 0;

  // --- Body files -----------------------------------------------------------

  Future<String> _writeBody(String name, Map<String, Object?> body) async {
    await outbox.create(recursive: true);
    final path = p.join(outbox.path, '$name.json.gz');
    // A long track is megabytes of JSON: encoded and compressed off the
    // UI isolate where there are isolates.
    final bytes = await runIsolated(
      () => gzip.encode(utf8.encode(jsonEncode(body))),
    );
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Reads a body file and deletes it: an incoming file is the codec's to
  /// clean up.
  static Future<Map<String, Object?>?> _readBody(String? path) async {
    if (path == null) return null;
    final file = File(path);
    try {
      final bytes = await file.readAsBytes();
      final decoded = await runIsolated(
        () => jsonDecode(utf8.decode(gzip.decode(bytes))),
      );
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
    } finally {
      try {
        await file.delete();
      } on FileSystemException {
        // Gone already.
      }
    }
  }

  static String? _string(Object? value) => value is String ? value : null;

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static double _double(Object? value) => value is num ? value.toDouble() : 0.0;

  static bool _bool(Object? value) =>
      value == true || (value is num && value != 0);

  static DateTime? _date(Object? value) =>
      value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;

  static Uint8List? _bytes(Object? value) {
    if (value is! String) return null;
    try {
      return base64Decode(value);
    } on FormatException {
      return null;
    }
  }
}
