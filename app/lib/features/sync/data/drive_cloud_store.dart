import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'cloud_store.dart';
import 'store_sync_backend.dart';

/// Logs record names and file ids only, never their content.
final Logger _log = Logger('velorki.sync.drive');

/// The hidden folder the app's files live in.
const String _space = 'appDataFolder';

/// The file fields every read asks for.
const String _fileFields =
    'id,name,version,size,createdTime,trashed,appProperties';

/// The version of the header line [driveRecordFile] writes; a reader skips
/// a file whose header is newer than it knows.
const int driveHeaderVersion = 1;

/// The `appProperties` every record file has (where its record has them).
const String _kind = 'kind';
const String _modifiedAt = 'modifiedAt';
const String _codec = 'codec';

/// Where a [DriveCloudStore] gets the signed-in account and its tokens.
abstract interface class DriveAuth {
  /// The signed-in Google account's id, or null.
  String? get accountId;

  /// An access token for `drive.appdata`, without asking the rider.
  /// [stale] is one Drive refused: it is let go of and another fetched.
  /// Null when only the rider can grant one (signed out, access taken
  /// back): the account is then gone until they sign in again. Throws
  /// [CloudStoreException] when it cannot be told now (no network).
  Future<String?> accessToken({String? stale});
}

/// The hidden app data folder of the rider's Google Drive as a
/// [CloudStore], over Drive v3.
///
/// One file per record, the file named by the record name exactly
/// (`route_<id>`, `ride_<id>`, `settings`); [driveRecordFile] lays it
/// out, [readDriveRecord] reads it (the layout is in docs/ARCHITECTURE.md,
/// as the relay reads it too). A record's version is the file id and
/// Drive's `version` of it: a save over a version reads the file's first and
/// compares (Drive has no conditional write; the race is accepted, the
/// newer change still wins on the next round). Changes come from
/// `changes.list` over the folder; Drive names no file once it is
/// deleted, so the file ids of the names are kept in [state]. A page
/// token Drive no longer takes lists the whole folder again.
class DriveCloudStore implements CloudStore {
  /// Creates the store over [client] (one with no credentials of its own:
  /// the token comes from [auth]). [pageSize] is the most records a page
  /// of [pull] or [fullList] holds, [parallel] the most requests in
  /// flight at once.
  DriveCloudStore({
    required this.auth,
    required this.state,
    http.Client? client,
    this.pageSize = 100,
    this.parallel = 4,
    String rootUrl = 'https://www.googleapis.com/',
  }) : _api = drive.DriveApi(
         _AuthClient(auth, client ?? http.Client()),
         rootUrl: rootUrl,
       );

  /// The account and its tokens.
  final DriveAuth auth;

  /// Where the file ids of the record names are kept.
  final SyncEngineState state;

  /// The most records a page holds.
  final int pageSize;

  /// The most requests in flight at once.
  final int parallel;

  final drive.DriveApi _api;

  /// Versions written from here this run: fetched back, they are not
  /// downloaded again.
  final Set<String> _written = <String>{};

  static const String _filesKey = 'files';

  /// What a cursor in the middle of a [fullList] starts with.
  static const String _listing = 'list:';

  @override
  Future<String?> accountId() async => auth.accountId;

  @override
  Future<StoredRecord?> get(String name) => _call(() async {
    final file = (await _lookup([name]))[name];
    return file == null ? null : _download(file);
  });

  // --- Writing ---------------------------------------------------------------

  @override
  Future<List<StoreResult>> push(List<StoreWrite> writes) => _call(() async {
    final current = await _lookup([for (final w in writes) w.name]);
    final results = await _pool(writes, (write) async {
      try {
        return await _write(write, current[write.name]);
      } on drive.DetailedApiRequestError catch (e) {
        _log.info('${write.name}: $e');
        return StoreFailed(_failureOf(e));
      } on CloudStoreException catch (e) {
        return StoreFailed(e.failure);
      } on http.ClientException catch (e) {
        _log.info('${write.name}: $e');
        return const StoreFailed(CloudStoreFailure.transient);
      } on TimeoutException {
        return const StoreFailed(CloudStoreFailure.transient);
      }
    });
    await _saveNames();
    return results;
  });

  Future<StoreResult> _write(StoreWrite write, drive.File? file) async {
    switch (write) {
      case StoreDelete():
        if (file != null) {
          await _deleteFile(file.id!);
          _names.remove(file.id);
        }
        return const StoreDone();
      case StoreSave(:final ifVersion):
        if (file == null) {
          if (ifVersion != null) return const StoreMissing();
          return StoreDone(await _create(write));
        }
        if (ifVersion != _versionOf(file)) {
          final server = await _download(file);
          return server == null
              ? const StoreFailed(CloudStoreFailure.other)
              : StoreConflict(server);
        }
        return StoreDone(await _update(write, file));
    }
  }

  Future<String> _create(StoreSave save) async {
    final (:properties, :content) = driveRecordFile(
      save.type,
      save.fields,
      save.body,
    );
    final file = await _api.files.create(
      drive.File(
        name: save.name,
        parents: const [_space],
        mimeType: 'application/octet-stream',
        appProperties: properties,
      ),
      uploadMedia: drive.Media(Stream.value(content), content.length),
      $fields: 'id,version',
    );
    return _keep(save.name, file);
  }

  Future<String> _update(StoreSave save, drive.File current) async {
    final (:properties, :content) = driveRecordFile(
      save.type,
      save.fields,
      save.body,
    );
    final file = await _api.files.update(
      drive.File(
        appProperties: <String, String?>{
          // Drive merges them: those no longer there are removed.
          for (final key in (current.appProperties ?? const {}).keys) key: null,
          ...properties,
        },
      ),
      current.id!,
      uploadMedia: drive.Media(Stream.value(content), content.length),
      $fields: 'id,version',
    );
    return _keep(save.name, file);
  }

  String _keep(String name, drive.File file) {
    _names[file.id!] = name;
    final version = _versionOf(file);
    if (_written.length > 5000) _written.clear();
    _written.add(version);
    return version;
  }

  Future<void> _deleteFile(String id) async {
    try {
      await _api.files.delete(id);
    } on drive.DetailedApiRequestError catch (e) {
      // Gone already.
      if (e.status != 404) rethrow;
    }
  }

  // --- Reading ---------------------------------------------------------------

  @override
  Future<StoreChanges> pull(String cursor) => _call(() async {
    final drive.ChangeList page;
    try {
      page = await _api.changes.list(
        cursor,
        spaces: _space,
        includeRemoved: true,
        pageSize: pageSize,
        $fields:
            'nextPageToken,newStartPageToken,'
            'changes(fileId,removed,file($_fileFields))',
      );
    } on drive.DetailedApiRequestError catch (e) {
      // A page token Drive no longer knows (or never did).
      if (const {400, 404, 410}.contains(e.status)) {
        throw const StoreCursorExpired();
      }
      rethrow;
    }
    final changed = <String, drive.File>{};
    final deleted = <String>{};
    for (final change in page.changes ?? const <drive.Change>[]) {
      final id = change.fileId ?? change.file?.id;
      if (id == null) continue;
      final file = change.file;
      if (change.removed == true || file == null || file.trashed == true) {
        final name = _names.remove(id);
        if (name == null || _names.containsValue(name)) continue;
        changed.remove(name);
        deleted.add(name);
        continue;
      }
      final name = file.name;
      if (name == null) continue;
      _names[id] = name;
      deleted.remove(name);
      // Written from here: the library has it already.
      if (_written.contains(_versionOf(file))) continue;
      changed[name] = file;
    }
    final records = await _downloadAll(changed.values.toList());
    await _saveNames();
    final next = page.nextPageToken;
    return StoreChanges(
      changed: records,
      deleted: deleted.toList(),
      cursor: next ?? page.newStartPageToken ?? cursor,
      more: next != null,
    );
  });

  @override
  Future<StoreChanges> fullList([String? cursor]) => _call(() async {
    String start;
    String? pageToken;
    if (cursor case final c? when c.startsWith(_listing)) {
      // Both page tokens, the listing's and the changes' after it.
      final [first, next] = (jsonDecode(c.substring(_listing.length)) as List)
          .cast<String>();
      start = first;
      pageToken = next;
    } else {
      // Taken before the listing, so nothing written while it runs is
      // missed.
      start = (await _api.changes.getStartPageToken()).startPageToken!;
      _names.clear();
    }
    final page = await _api.files.list(
      spaces: _space,
      q: 'trashed = false',
      pageSize: pageSize,
      pageToken: pageToken,
      $fields: 'nextPageToken,files($_fileFields)',
    );
    final files = _primaries(page.files ?? const <drive.File>[]);
    for (final MapEntry(key: name, value: file) in files.entries) {
      _names[file.id!] = name;
    }
    final records = await _downloadAll(files.values.toList());
    await _saveNames();
    final next = page.nextPageToken;
    return StoreChanges(
      changed: records,
      deleted: const <String>[],
      cursor: next == null ? start : '$_listing${jsonEncode([start, next])}',
      more: next != null,
    );
  });

  /// The files of [names] as Drive has them now, by name. A name two
  /// devices created at once has two files: the older counts, the other
  /// is deleted.
  Future<Map<String, drive.File>> _lookup(List<String> names) async {
    final found = <drive.File>[];
    final unique = names.toSet().toList();
    for (var i = 0; i < unique.length; i += 25) {
      final chunk = unique.sublist(i, (i + 25).clamp(0, unique.length));
      final query = chunk.map((n) => "name = '${_quote(n)}'").join(' or ');
      String? token;
      do {
        final page = await _api.files.list(
          spaces: _space,
          q: '($query) and trashed = false',
          pageSize: 1000,
          pageToken: token,
          $fields: 'nextPageToken,files($_fileFields)',
        );
        found.addAll(page.files ?? const <drive.File>[]);
        token = page.nextPageToken;
      } while (token != null);
    }
    final primaries = _primaries(found);
    final extras = [
      for (final file in found)
        if (primaries[file.name]?.id != file.id) file.id!,
    ];
    for (final id in extras) {
      _log.info('duplicate $id deleted');
      try {
        await _deleteFile(id);
      } on Object catch (e) {
        _log.info('duplicate $id not deleted: $e');
      }
    }
    for (final file in primaries.values) {
      _names[file.id!] = file.name!;
    }
    return primaries;
  }

  /// One file per name: the one created first, the oldest id on a tie.
  static Map<String, drive.File> _primaries(List<drive.File> files) {
    final byName = <String, drive.File>{};
    for (final file in files) {
      final name = file.name;
      if (name == null || file.id == null) continue;
      final kept = byName[name];
      if (kept == null || _older(file, kept)) byName[name] = file;
    }
    return byName;
  }

  static bool _older(drive.File a, drive.File b) {
    final at = a.createdTime;
    final bt = b.createdTime;
    if (at != null && bt != null && at != bt) return at.isBefore(bt);
    return a.id!.compareTo(b.id!) < 0;
  }

  Future<List<StoredRecord>> _downloadAll(List<drive.File> files) async => [
    for (final record in await _pool(files, _download)) ?record,
  ];

  /// The record in [file], or null for a file that is no record.
  Future<StoredRecord?> _download(drive.File file) async {
    final properties = <String, String>{
      for (final MapEntry(:key, :value)
          in (file.appProperties ?? const <String, String?>{}).entries)
        key: ?value,
    };
    // A record of fields alone is all in the metadata.
    if (file.size == '0') {
      return readDriveRecord(
        file.name!,
        properties,
        Uint8List(0),
        version: _versionOf(file),
      );
    }
    final drive.Media media;
    try {
      media = await _api.files.get(
        file.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
    } on drive.DetailedApiRequestError catch (e) {
      // Deleted since it was listed: its deletion comes with the changes.
      if (e.status == 404) return null;
      rethrow;
    }
    final builder = BytesBuilder(copy: false);
    await media.stream.forEach(builder.add);
    final record = readDriveRecord(
      file.name!,
      properties,
      builder.takeBytes(),
      version: _versionOf(file),
    );
    if (record == null) _log.warning('${file.id} is no record');
    return record;
  }

  // --- The file ids of the names -----------------------------------------------

  Map<String, String>? _namesCache;

  Map<String, String> get _names => _namesCache ??= () {
    final json = state.read(_filesKey);
    if (json == null) return <String, String>{};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, Object?>) {
        return {
          for (final MapEntry(:key, :value) in decoded.entries)
            if (value is String) key: value,
        };
      }
    } on FormatException {
      // Written by nothing but this; a damaged copy is started over.
    }
    return <String, String>{};
  }();

  Future<void> _saveNames() => state.write(_filesKey, jsonEncode(_names));

  // --- Calls -------------------------------------------------------------------

  /// Runs [body], every failure turned into a [CloudStoreException].
  Future<T> _call<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on drive.DetailedApiRequestError catch (e) {
      _log.info('drive: $e');
      throw CloudStoreException(_failureOf(e), e.message);
    } on http.ClientException catch (e) {
      throw CloudStoreException(CloudStoreFailure.transient, e.message);
    } on TimeoutException {
      throw const CloudStoreException(CloudStoreFailure.transient, 'timeout');
    } on drive.ApiRequestError catch (e) {
      throw CloudStoreException(CloudStoreFailure.other, e.message);
    }
  }

  /// Runs [task] over [items], [parallel] at a time, the results in order.
  Future<List<R>> _pool<T, R>(List<T> items, Future<R> Function(T) task) async {
    if (items.isEmpty) return <R>[];
    final results = List<R?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final i = next++;
        results[i] = await task(items[i]);
      }
    }

    await Future.wait([
      for (var i = 0; i < parallel.clamp(1, items.length); i++) worker(),
    ]);
    return results.cast<R>();
  }

  static CloudStoreFailure _failureOf(drive.DetailedApiRequestError e) {
    final reasons = {for (final d in e.errors) d.reason};
    if (reasons.contains('storageQuotaExceeded')) {
      return CloudStoreFailure.quotaExceeded;
    }
    final status = e.status ?? 0;
    if (status == 429 ||
        status >= 500 ||
        reasons.contains('rateLimitExceeded') ||
        reasons.contains('userRateLimitExceeded')) {
      return CloudStoreFailure.transient;
    }
    return CloudStoreFailure.other;
  }

  static String _versionOf(drive.File file) => '${file.id}:${file.version}';

  static String _quote(String name) =>
      name.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
}

/// The `appProperties` and the content of the file of a record of [type]
/// with [fields] and [body].
///
/// The properties are `kind` (the type), `modifiedAt` and `codec` (the
/// codec's schema version) where the fields have them. A record of short
/// text fields alone (each key and value 124 bytes at most, together)
/// keeps them in the properties too, with no content. Any other has one
/// UTF-8 JSON line, `{"v":1,"type":..,"fields":{..},"body":true|false}`,
/// then a newline and the body's gzip bytes as they are.
({Map<String, String> properties, Uint8List content}) driveRecordFile(
  String type,
  Map<String, Object?> fields,
  Uint8List? body,
) {
  final properties = <String, String>{
    _kind: type,
    if (fields['modifiedAt'] case final Object at) _modifiedAt: '$at',
    if (fields['schemaVersion'] case final Object v) _codec: '$v',
  };
  final inline =
      body == null &&
      fields.length + properties.length <= 100 &&
      fields.entries.every(
        (e) =>
            e.value is String &&
            !properties.containsKey(e.key) &&
            !const {_kind, _modifiedAt, _codec}.contains(e.key) &&
            utf8.encode(e.key).length +
                    utf8.encode(e.value! as String).length <=
                124,
      );
  if (inline) {
    return (
      properties: {
        ...properties,
        for (final e in fields.entries) e.key: e.value! as String,
      },
      content: Uint8List(0),
    );
  }
  final head = utf8.encode(
    jsonEncode({
      'v': driveHeaderVersion,
      'type': type,
      'fields': fields,
      'body': body != null,
    }),
  );
  return (
    properties: properties,
    content:
        (BytesBuilder(copy: false)
              ..add(head)
              ..addByte(0x0A)
              ..add(body ?? const <int>[]))
            .takeBytes(),
  );
}

/// The record [name] in a file with [properties] and [content] (see
/// [driveRecordFile]) at [version], or null when it is none this build
/// reads.
StoredRecord? readDriveRecord(
  String name,
  Map<String, String> properties,
  Uint8List content, {
  required String version,
}) {
  if (content.isEmpty) {
    final type = properties[_kind];
    if (type == null) return null;
    return StoredRecord(
      name: name,
      type: type,
      fields: {
        for (final MapEntry(:key, :value) in properties.entries)
          if (!const {_kind, _modifiedAt, _codec}.contains(key)) key: value,
      },
      version: version,
    );
  }
  final end = content.indexOf(0x0A);
  if (end < 0) return null;
  final Object? head;
  try {
    head = jsonDecode(utf8.decode(content.sublist(0, end)));
  } on FormatException {
    return null;
  }
  if (head is! Map<String, Object?>) return null;
  final v = head['v'];
  if (v is! int || v > driveHeaderVersion) return null;
  final type = head['type'];
  final fields = head['fields'];
  if (type is! String || fields is! Map<String, Object?>) return null;
  return StoredRecord(
    name: name,
    type: type,
    fields: fields,
    body: head['body'] == true ? Uint8List.sublistView(content, end + 1) : null,
    version: version,
  );
}

/// Sends every request with [DriveAuth]'s token; a token Drive refuses is
/// replaced once, without asking the rider.
class _AuthClient extends http.BaseClient {
  _AuthClient(this._auth, this._inner);

  final DriveAuth _auth;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Buffered, so a refused request can go again.
    final body = await request.finalize().toBytes();
    Future<http.StreamedResponse> attempt(String token) {
      final copy = http.Request(request.method, request.url)
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection
        ..headers.addAll(request.headers)
        ..headers['authorization'] = 'Bearer $token'
        ..bodyBytes = body;
      return _inner.send(copy).timeout(const Duration(seconds: 60));
    }

    final token = await _token();
    final response = await attempt(token);
    if (response.statusCode != 401) return response;
    await response.stream.drain<void>();
    return attempt(await _token(stale: token));
  }

  Future<String> _token({String? stale}) async {
    final token = await _auth.accessToken(stale: stale);
    if (token == null) {
      throw const CloudStoreException(
        CloudStoreFailure.other,
        'not signed in to Google',
      );
    }
    return token;
  }

  @override
  void close() => _inner.close();
}
