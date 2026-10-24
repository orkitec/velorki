import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:velorki/features/sync/data/drive_cloud_store.dart';

import 'sync_device.dart';

/// One file in a [FakeDrive] folder.
class FakeDriveFile {
  FakeDriveFile(this.id, this.name, this.created);

  final String id;
  final String name;
  final DateTime created;
  int version = 1;
  Map<String, String> appProperties = <String, String>{};
  Uint8List content = Uint8List(0);
  bool deleted = false;

  Map<String, Object?> toJson() => {
    'kind': 'drive#file',
    'id': id,
    'name': name,
    'version': '$version',
    'size': '${content.length}',
    'createdTime': created.toUtc().toIso8601String(),
    'trashed': false,
    'appProperties': appProperties,
  };
}

/// One account's app data folder: its files and its change log.
class _Folder {
  final Map<String, FakeDriveFile> files = <String, FakeDriveFile>{};
  final List<String> log = <String>[];

  /// Bumped by [FakeDrive.expirePageTokens]: older tokens are refused.
  int epoch = 0;
}

/// Google Drive v3 as far as [DriveCloudStore] uses it, at the HTTP layer:
/// the app data folder of each account, `files.list` with the name
/// queries the store sends, multipart uploads, `alt=media` downloads,
/// deletes and `changes.list` with page tokens that can expire. Access
/// tokens name their account; [expireTokens] makes Drive refuse them all
/// (401), [quotaFull] refuses uploads (403 `storageQuotaExceeded`),
/// [failNext] fails the next requests with a status of its own.
class FakeDrive {
  final Map<String, _Folder> _folders = <String, _Folder>{};
  final Set<String> _validTokens = <String>{};
  int _ids = 0;
  int _tokens = 0;
  DateTime _clock = DateTime.utc(2026, 10, 19);

  /// Whether uploads are refused for a full Drive.
  bool quotaFull = false;

  /// Statuses the next requests get, one each, in order.
  final List<int> failNext = <int>[];

  /// Statuses the next uploads and deletes get, one each, in order.
  final List<int> failWrites = <int>[];

  /// The requests, as `METHOD path`.
  final List<String> requests = <String>[];

  /// How many requests were downloads of a file's content.
  int get downloads => requests.where((r) => r.endsWith('?media')).length;

  /// The page size `files.list` keeps to, at most.
  int maxPageSize = 1000;

  _Folder _folder(String account) => _folders.putIfAbsent(account, _Folder.new);

  /// A token for [account] Drive takes.
  String issueToken(String account) {
    final token = '$account|${_tokens++}';
    _validTokens.add(token);
    return token;
  }

  /// Every token given out so far is refused from now on.
  void expireTokens() => _validTokens.clear();

  /// Every page token given out so far is refused from now on.
  void expirePageTokens(String account) => _folder(account).epoch++;

  /// The record names in [account]'s folder.
  Set<String> namesOf(String account) => {
    for (final f in _folder(account).files.values) f.name,
  };

  /// The files in [account]'s folder.
  List<FakeDriveFile> filesOf(String account) =>
      _folder(account).files.values.toList();

  /// The fields of the record [name] in [account]'s folder, or null.
  Map<String, Object?>? fields(String account, String name) {
    for (final f in _folder(account).files.values) {
      if (f.name != name) continue;
      return readDriveRecord(
        name,
        f.appProperties,
        f.content,
        version: '',
      )?.fields;
    }
    return null;
  }

  /// Writes a file as another app on the account would, for duplicates.
  FakeDriveFile put(
    String account,
    String name,
    Map<String, Object?> fields, {
    DateTime? created,
  }) {
    final folder = _folder(account);
    final (:properties, :content) = driveRecordFile('Route', fields, null);
    final file = FakeDriveFile('f${_ids++}', name, created ?? _tick())
      ..appProperties = properties
      ..content = content;
    folder.files[file.id] = file;
    folder.log.add(file.id);
    return file;
  }

  DateTime _tick() => _clock = _clock.add(const Duration(seconds: 1));

  /// The client the stores send through.
  http.Client get client => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final url = request.url;
    final media = url.queryParameters['alt'] == 'media';
    requests.add('${request.method} ${url.path}${media ? '?media' : ''}');
    final auth = request.headers['authorization'] ?? '';
    final token = auth.startsWith('Bearer ') ? auth.substring(7) : '';
    if (!_validTokens.contains(token)) {
      return _error(401, 'authError', 'Invalid Credentials');
    }
    final write = request.method != 'GET';
    if (failNext.isNotEmpty || (write && failWrites.isNotEmpty)) {
      final status = failNext.isNotEmpty
          ? failNext.removeAt(0)
          : failWrites.removeAt(0);
      return _error(
        status,
        status == 403 ? 'userRateLimitExceeded' : 'backendError',
        'failed on purpose',
      );
    }
    final folder = _folder(token.split('|').first);
    final path = url.path;
    final method = request.method;
    if (path == '/drive/v3/changes/startPageToken' && method == 'GET') {
      return _json({'startPageToken': '${folder.epoch}:${folder.log.length}'});
    }
    if (path == '/drive/v3/changes' && method == 'GET') {
      return _changes(folder, url);
    }
    if (path == '/drive/v3/files' && method == 'GET') return _list(folder, url);
    if (path == '/upload/drive/v3/files' && method == 'POST') {
      return _upload(folder, request, null);
    }
    final upload = RegExp(r'^/upload/drive/v3/files/([^/]+)$').firstMatch(path);
    if (upload != null && method == 'PATCH') {
      return _upload(folder, request, upload.group(1));
    }
    final one = RegExp(r'^/drive/v3/files/([^/]+)$').firstMatch(path);
    if (one != null) {
      final file = folder.files[one.group(1)];
      if (file == null || file.deleted) {
        return _error(404, 'notFound', 'File not found: ${one.group(1)}');
      }
      if (method == 'DELETE') {
        file.deleted = true;
        folder.files.remove(file.id);
        folder.log.add(file.id);
        return http.Response('', 204);
      }
      if (method == 'GET' && media) {
        return http.Response.bytes(
          file.content,
          200,
          headers: {'content-type': 'application/octet-stream'},
        );
      }
      if (method == 'GET') return _json(file.toJson());
    }
    return _error(400, 'badRequest', 'not faked: $method $path');
  }

  http.Response _list(_Folder folder, Uri url) {
    final q = url.queryParameters['q'] ?? '';
    expectSpace(url);
    final names = {
      for (final m in RegExp(r"name = '((?:[^'\\]|\\.)*)'").allMatches(q))
        m.group(1)!.replaceAll(r"\'", "'").replaceAll(r'\\', r'\'),
    };
    final all = [
      for (final f in folder.files.values)
        if (names.isEmpty || names.contains(f.name)) f,
    ];
    final size = (int.tryParse(url.queryParameters['pageSize'] ?? '') ?? 100)
        .clamp(1, maxPageSize);
    final from = int.tryParse(url.queryParameters['pageToken'] ?? '') ?? 0;
    final to = (from + size).clamp(from, all.length);
    return _json({
      'files': [for (final f in all.sublist(from, to)) f.toJson()],
      if (to < all.length) 'nextPageToken': '$to',
    });
  }

  http.Response _changes(_Folder folder, Uri url) {
    expectSpace(url);
    final token = url.queryParameters['pageToken'] ?? '';
    final parts = token.split(':');
    if (parts.length != 2 || int.tryParse(parts[0]) != folder.epoch) {
      return _error(400, 'invalid', 'Invalid Value');
    }
    final from = int.parse(parts[1]);
    final size = int.tryParse(url.queryParameters['pageSize'] ?? '') ?? 100;
    final to = (from + size).clamp(from, folder.log.length);
    final ids = folder.log.sublist(from, to).toSet();
    return _json({
      'changes': [
        for (final id in ids)
          if (folder.files[id] case final file?)
            {'fileId': id, 'removed': false, 'file': file.toJson()}
          else
            {'fileId': id, 'removed': true},
      ],
      if (to < folder.log.length)
        'nextPageToken': '${folder.epoch}:$to'
      else
        'newStartPageToken': '${folder.epoch}:$to',
    });
  }

  http.Response _upload(_Folder folder, http.Request request, String? id) {
    expectSpace(request.url, upload: true);
    final (meta, content) = _multipart(request);
    if (quotaFull) {
      return _error(403, 'storageQuotaExceeded', 'The user’s quota is full');
    }
    final FakeDriveFile file;
    if (id == null) {
      if (meta['parents'] case final List<Object?> parents
          when parents.contains('appDataFolder')) {
        file = FakeDriveFile('f${_ids++}', meta['name']! as String, _tick());
        folder.files[file.id] = file;
      } else {
        return _error(400, 'badRequest', 'not in the app data folder');
      }
    } else {
      final existing = folder.files[id];
      if (existing == null) return _error(404, 'notFound', 'File not found');
      file = existing..version += 3;
    }
    final properties = meta['appProperties'];
    if (properties is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in properties.entries) {
        value == null
            ? file.appProperties.remove(key)
            : file.appProperties[key] = '$value';
      }
    }
    file.content = content;
    folder.log.add(file.id);
    return _json({'id': file.id, 'version': '${file.version}'});
  }

  /// The metadata and the media of a multipart upload, as googleapis
  /// sends it (the media in base64).
  static (Map<String, Object?>, Uint8List) _multipart(http.Request request) {
    final type = request.headers['content-type'] ?? '';
    final boundary = RegExp('boundary="?([^";]+)"?').firstMatch(type)!.group(1);
    final parts = request.body.split('--$boundary');
    String bodyOf(String part) => part.substring(part.indexOf('\r\n\r\n') + 4);
    final meta = jsonDecode(bodyOf(parts[1]).trim()) as Map<String, Object?>;
    final media = base64Decode(bodyOf(parts[2]).trim());
    return (meta, media);
  }

  static void expectSpace(Uri url, {bool upload = false}) {
    if (upload) return;
    if (url.queryParameters['spaces'] != 'appDataFolder' &&
        !url.path.endsWith('startPageToken')) {
      throw StateError('outside the app data folder: $url');
    }
  }

  static http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  static http.Response _error(int status, String reason, String message) =>
      http.Response(
        jsonEncode({
          'error': {
            'code': status,
            'message': message,
            'errors': [
              {'domain': 'global', 'reason': reason, 'message': message},
            ],
          },
        }),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}

/// [DriveAuth] signed in to [account] on a [FakeDrive]: a token issued on
/// first use and again when Drive refused one, unless [lostAccess].
class FakeDriveAuth implements DriveAuth {
  FakeDriveAuth(this.drive, this.account);

  final FakeDrive drive;
  String? account;

  /// While set, no new token comes without the rider.
  bool lostAccess = false;

  /// How often a new token was fetched.
  int refreshes = 0;
  String? _token;

  @override
  String? get accountId => account;

  @override
  Future<String?> accessToken({String? stale}) async {
    final current = account;
    if (current == null) return null;
    if (_token != null && _token != stale) return _token;
    if (lostAccess) {
      account = null;
      return _token = null;
    }
    refreshes++;
    return _token = drive.issueToken(current);
  }
}

/// A [DriveCloudStore] signed in to [account] on [drive].
DriveCloudStore driveStore(
  FakeDrive drive, {
  String account = 'rider-a',
  FakeDriveAuth? auth,
  int pageSize = 100,
}) => DriveCloudStore(
  auth: auth ?? FakeDriveAuth(drive, account),
  state: MapSyncState(),
  client: drive.client,
  pageSize: pageSize,
);
