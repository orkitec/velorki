import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:velorki_io/io.dart' show gzip;
import 'package:velorki_io/worker.dart' show runIsolated;

import '../../routing_tiles/domain/sha256.dart';
import 'cloud_store.dart';
import 'cloudkit_web.dart';
import 'store_sync_backend.dart';

/// Logs record names and codes only, never their content.
final Logger _log = Logger('velorki.sync.cloudkit');

/// The fields `RecordCodec` writes as doubles, which the schema (made by
/// the iOS app's saves) holds as Double: a whole number among them must
/// still go up as one, where a browser's numbers do not tell.
const Set<String> cloudKitDoubleFields = {
  'distanceM',
  'ascentM',
  'descentM',
  'bboxMinLat',
  'bboxMinLon',
  'bboxMaxLat',
  'bboxMaxLon',
  'avgSpeedMps',
  'maxSpeedMps',
};

/// The private database's `Library` zone as a [CloudStore], for the web
/// planner, over CloudKit JS ([CloudKitWeb]).
///
/// The records are the ones CKSyncEngine writes on iOS (`CloudSync.swift`):
/// the record name, the type (`Route`, `Ride`), the codec's fields as they
/// are, and the gzip body as the `body` asset. A record's version is its
/// change tag: a save names it and CloudKit refuses one that is stale
/// (`CONFLICT`), or a create where the record is there (`EXISTS`); the
/// record is then looked up for the conflict. Changes come from the zone's
/// change feed with its sync token; a token CloudKit no longer takes lists
/// the zone again. A zone not there yet is made on the first save. The
/// account is the user record name; while the session has run out it stays
/// the one kept in [state] (nothing is resent), and every call fails as
/// [CloudStoreFailure.signInNeeded] until the rider signs in again,
/// without asking CloudKit: a refused session (HTTP 421) is not tried
/// again, as the retries after a transient failure would.
///
/// No settings: the iOS app keeps them in iCloud's key-value store, which
/// CloudKit JS cannot reach (`StoreSyncBackend.syncsSettings` off).
class CloudKitJsCloudStore implements CloudStore {
  /// Creates the store over [api].
  CloudKitJsCloudStore({
    required this.api,
    required this.state,
    this.parallel = 4,
  }) {
    // A sign-in ends the wait for one: the next call goes to CloudKit.
    api.users.listen((user) {
      if (user != null) _signInNeeded = false;
    });
  }

  /// CloudKit JS.
  final CloudKitWeb api;

  /// Where the account last signed in is kept.
  final SyncEngineState state;

  /// The most bodies downloaded at once.
  final int parallel;

  /// Versions written from here this run: fetched back, they are not
  /// downloaded again.
  final Set<String> _written = <String>{};

  static const String _userKey = 'user';

  /// Whether the session ran out (CloudKit refused it, or the browser has
  /// none for the account kept): calls fail at once until a sign-in.
  bool _signInNeeded = false;

  @override
  Future<String?> accountId() async {
    final String? user;
    try {
      user = await api.userRecordName();
    } on CloudKitException catch (e) {
      throw _exceptionOf(e.error);
    }
    if (user != null) {
      _signInNeeded = false;
      if (user != state.read(_userKey)) await state.write(_userKey, user);
      return user;
    }
    // Signed out by the session running out, not by the rider: still
    // theirs, until they sign in again or out for good ([signedOut]).
    final kept = state.read(_userKey);
    if (kept != null) _signInNeeded = true;
    return kept;
  }

  /// The rider signed out here: no account until someone signs in.
  Future<void> signedOut() {
    _signInNeeded = false;
    return state.write(_userKey, null);
  }

  @override
  Future<StoredRecord?> get(String name) => _call(() async {
    final result = (await api.lookup([name])).single;
    final record = result.record;
    if (record == null) {
      if (result.error?.code == 'NOT_FOUND') return null;
      throw _exceptionOf(result.error!);
    }
    return _download(record);
  });

  // --- Writing ---------------------------------------------------------------

  @override
  Future<List<StoreResult>> push(List<StoreWrite> writes) => _call(() async {
    final prepared = [for (final write in writes) await _prepare(write)];
    final ck = [for (final p in prepared) p.write];
    List<CkResult> results;
    try {
      results = await api.modify(ck);
    } on CloudKitException catch (e) {
      if (e.error.code != 'ZONE_NOT_FOUND') rethrow;
      _log.info('no zone yet: made');
      await api.createZone();
      results = await api.modify(ck);
    }
    if (results.any((r) => r.error?.code == 'ZONE_NOT_FOUND')) {
      await api.createZone();
      results = await api.modify(ck);
    }
    final conflicts = <String>[
      for (var i = 0; i < writes.length; i++)
        if (writes[i] is StoreSave && _isConflict(results[i].error))
          writes[i].name,
    ];
    final servers = conflicts.isEmpty
        ? const <String, CkResult>{}
        : {
            for (final (i, r) in (await api.lookup(conflicts)).indexed)
              conflicts[i]: r,
          };
    final out = <StoreResult>[];
    for (var i = 0; i < writes.length; i++) {
      out.add(await _resultOf(writes[i], results[i], servers, prepared[i]));
    }
    return out;
  });

  /// The CloudKit write for [write]; a save whose body is the one the
  /// server has at the version it names goes without it ([CkSave.keepBody]).
  Future<_Prepared> _prepare(StoreWrite write) async {
    if (write is! StoreSave) return _Prepared(CkDelete(write.name));
    final fields = <String, CkValue>{
      for (final MapEntry(:key, :value) in write.fields.entries)
        key: ?_valueOf(key, value),
    };
    final known = _Version.parse(write.ifVersion);
    final body = write.body;
    final digest = body == null ? null : await _digestOf(body);
    // Only an update of a record that is there, whose server fields are
    // exactly these: `update` would leave a field the save left out.
    final unchanged =
        known != null &&
        digest != null &&
        digest == known.body &&
        _keysDigest(fields.keys) == known.keys;
    if (unchanged) _log.info('${write.name}: body unchanged, fields only');
    return _Prepared(
      CkSave(
        write.name,
        type: write.type,
        fields: fields,
        body: unchanged ? null : body,
        changeTag: known?.tag,
        keepBody: unchanged,
      ),
      body: digest,
    );
  }

  static CkValue? _valueOf(String key, Object? value) => switch (value) {
    final String s => CkValue(s, 'STRING'),
    final num n when cloudKitDoubleFields.contains(key) => CkValue(
      n.toDouble(),
      'DOUBLE',
    ),
    final int n => CkValue(n, 'INT64'),
    final double n when n == n.truncateToDouble() && n.abs() < 9e15 => CkValue(
      n.toInt(),
      'INT64',
    ),
    final double n => CkValue(n, 'DOUBLE'),
    _ => null,
  };

  static bool _isConflict(CkError? error) =>
      error != null &&
      (error.code == 'CONFLICT' ||
          error.code == 'EXISTS' ||
          error.code == 'UNIQUE_FIELD_ERROR');

  Future<StoreResult> _resultOf(
    StoreWrite write,
    CkResult result,
    Map<String, CkResult> servers,
    _Prepared prepared,
  ) async {
    final error = result.error;
    if (error == null) {
      final record = result.record;
      final tag = record?.changeTag;
      if (tag != null) _keep(write.name, tag);
      if (write is StoreDelete || tag == null) return StoreDone(tag);
      // The body is the one sent, or the one the server kept.
      return StoreDone(
        _Version(
          tag,
          body: prepared.body,
          keys: _keysDigest(record!.fields.keys),
        ).encode(),
      );
    }
    if (write is StoreDelete) {
      return error.code == 'NOT_FOUND'
          ? const StoreDone()
          : StoreFailed(_failureOf(error));
    }
    if (_isConflict(error)) {
      final server = servers[write.name];
      final record = server?.record;
      if (record != null) {
        try {
          return StoreConflict(await _download(record));
        } on CloudStoreException catch (e) {
          return StoreFailed(e.failure);
        }
      }
      if (server?.error?.code == 'NOT_FOUND') return const StoreMissing();
      return StoreFailed(
        server?.error == null
            ? CloudStoreFailure.transient
            : _failureOf(server!.error!),
      );
    }
    if (error.code == 'NOT_FOUND') return const StoreMissing();
    _log.info('${write.name}: $error');
    return StoreFailed(_failureOf(error));
  }

  void _keep(String name, String tag) {
    if (_written.length > 5000) _written.clear();
    _written.add('$name@$tag');
  }

  // --- Reading ---------------------------------------------------------------

  @override
  Future<StoreChanges> pull(String cursor) => _changes(cursor, listing: false);

  @override
  Future<StoreChanges> fullList([String? cursor]) =>
      _changes(cursor, listing: true);

  Future<StoreChanges> _changes(String? cursor, {required bool listing}) =>
      _call(() async {
        final token = cursor == null || cursor.isEmpty ? null : cursor;
        final CkZoneChanges page;
        try {
          page = await api.zoneChanges(token);
        } on CloudKitException catch (e) {
          switch (e.error.code) {
            case 'ZONE_NOT_FOUND':
              // Nothing synced to this account yet.
              return const StoreChanges(changed: [], deleted: [], cursor: '');
            case 'CHANGE_TOKEN_EXPIRED' || 'BAD_REQUEST' when token != null:
              throw const StoreCursorExpired();
          }
          rethrow;
        }
        final deleted = <String>[];
        final changed = <CkRecord>[];
        for (final record in page.records) {
          if (record.deleted) {
            if (!listing) deleted.add(record.name);
          } else if (!_written.contains('${record.name}@${record.changeTag}')) {
            changed.add(record);
          }
        }
        return StoreChanges(
          changed: await _downloadAll(changed),
          deleted: deleted,
          cursor: page.syncToken,
          more: page.moreComing,
        );
      });

  Future<List<StoredRecord>> _downloadAll(List<CkRecord> records) async {
    final out = List<StoredRecord?>.filled(records.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < records.length) {
        final i = next++;
        out[i] = await _download(records[i]);
      }
    }

    await Future.wait([
      for (var i = 0; i < parallel && i < records.length; i++) worker(),
    ]);
    return out.cast<StoredRecord>();
  }

  Future<StoredRecord> _download(CkRecord record) async {
    Uint8List? body;
    if (record.bodyUrl case final url?) {
      _log.info('download ${record.name}');
      try {
        body = await api.download(url);
      } on CloudKitException catch (e) {
        _log.info('download ${record.name} failed: ${e.error}');
        throw _exceptionOf(e.error);
      }
      _log.info('downloaded ${record.name}: ${body.length} bytes');
    }
    final digest = body == null ? null : await _digestOf(body);
    return StoredRecord(
      name: record.name,
      type: record.type ?? '',
      fields: {
        for (final MapEntry(:key, :value) in record.fields.entries)
          key: cloudKitDoubleFields.contains(key) && value is num
              ? value.toDouble()
              : value is double && value == value.truncateToDouble()
              ? value.toInt()
              : value,
      },
      body: body,
      version: record.changeTag == null
          ? ''
          : _Version(
              record.changeTag!,
              body: digest,
              keys: _keysDigest(record.fields.keys),
            ).encode(),
    );
  }

  // --- Failures --------------------------------------------------------------

  Future<T> _call<T>(Future<T> Function() call) async {
    if (_signInNeeded) {
      throw const CloudStoreException(
        CloudStoreFailure.signInNeeded,
        'signed out: waiting for a sign-in',
      );
    }
    try {
      return await call();
    } on CloudKitException catch (e) {
      _log.info('request failed: ${e.error}');
      throw _exceptionOf(e.error);
    }
  }

  CloudStoreException _exceptionOf(CkError error) {
    if (isCloudKitAuthError(error.code)) _signInNeeded = true;
    return CloudStoreException(_failureOf(error), '$error', error.retryAfter);
  }

  static CloudStoreFailure _failureOf(CkError error) => switch (error.code) {
    'NETWORK_ERROR' ||
    'SERVICE_UNAVAILABLE' ||
    'THROTTLED' ||
    'TRY_AGAIN_LATER' ||
    'ZONE_BUSY' ||
    'INTERNAL_ERROR' ||
    'UNEXPECTED_SERVER_RESPONSE' => CloudStoreFailure.transient,
    'QUOTA_EXCEEDED' => CloudStoreFailure.quotaExceeded,
    final code when isCloudKitAuthError(code) => CloudStoreFailure.signInNeeded,
    _ => CloudStoreFailure.other,
  };
}

/// A write ready to send, and the digest of the body it carries (or of the
/// one the server keeps).
class _Prepared {
  _Prepared(this.write, {this.body});

  final CkWrite write;
  final String? body;
}

/// The store's version of a record: the change tag, and what the browser
/// knows of the record at that tag so that a save can leave out what has not
/// changed. It rides in the opaque version `StoreSyncBackend` keeps beside
/// the record (`tag#<body digest>.<field names digest>`); a version without
/// the two parts (an older build's, or a body that did not unpack) just
/// sends everything.
class _Version {
  _Version(this.tag, {this.body, this.keys});

  final String tag;

  /// SHA-256 of the decompressed body, so that another compressor's bytes
  /// for the same content are the same; null when unknown.
  final String? body;

  /// A digest of the names of the fields the server has.
  final String? keys;

  static _Version? parse(String? version) {
    if (version == null) return null;
    final hash = version.indexOf('#');
    if (hash < 0) return _Version(version);
    final parts = version.substring(hash + 1).split('.');
    return _Version(
      version.substring(0, hash),
      body: parts[0].isEmpty ? null : parts[0],
      keys: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
    );
  }

  String encode() => body == null ? tag : '$tag#$body.${keys ?? ''}';
}

/// The digest of a gzip body's content; null when it does not unpack.
Future<String?> _digestOf(Uint8List gzipped) async {
  try {
    return await runIsolated(() {
      final sha = Sha256()..add(gzip.decode(gzipped));
      return sha.hexDigest();
    });
  } on Object {
    return null;
  }
}

String _keysDigest(Iterable<String> names) {
  final sha = Sha256()..add(utf8.encode((names.toList()..sort()).join(',')));
  return sha.hexDigest().substring(0, 16);
}
