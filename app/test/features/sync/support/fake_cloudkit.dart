import 'dart:async';
import 'dart:typed_data';

import 'package:velorki/features/sync/data/cloudkit_web.dart';

/// One record as the fake server keeps it.
class _Stored {
  _Stored(this.name, this.type, this.fields, this.body, this.tag);

  final String name;
  final String type;
  final Map<String, CkValue> fields;
  final Uint8List? body;
  final String tag;
}

/// One user's private database: the `Library` zone, if made, and its
/// change log.
class _Database {
  bool zone = false;
  final Map<String, _Stored> records = <String, _Stored>{};

  /// Every change, in order: a record name.
  final List<String> log = <String>[];

  /// Bumped by [FakeCloudKit.expireTokens]: older tokens are refused.
  int epoch = 0;
}

/// CloudKit Web Services as the web planner sees them, in memory: users'
/// private databases with the `Library` zone, change tags, a change feed
/// with sync tokens that can expire, assets behind URLs.
class FakeCloudKit {
  final Map<String, _Database> _databases = <String, _Database>{};
  final Map<String, Uint8List> _assets = <String, Uint8List>{};
  int _tags = 0;

  /// The most records a page of the change feed holds.
  int pageSize = 100;

  /// Whether a new user's zone exists already (their iPhone synced).
  bool zoneExists = true;

  /// The asset URLs fetched, in order.
  final List<String> downloads = <String>[];

  /// The writes made, in order: `create route_1`, `replace route_1`, ...
  final List<String> writes = <String>[];

  _Database _db(String user) =>
      _databases.putIfAbsent(user, () => _Database()..zone = zoneExists);

  /// The record names in [user]'s zone.
  Set<String> namesOf(String user) => _db(user).records.keys.toSet();

  /// The typed fields of [user]'s record [name], or null.
  Map<String, CkValue>? fieldsOf(String user, String name) =>
      _db(user).records[name]?.fields;

  /// Whether [user]'s zone exists.
  bool hasZone(String user) => _db(user).zone;

  /// Deletes [name] as the iPhone would.
  void deleteElsewhere(String user, String name) {
    final db = _db(user);
    if (db.records.remove(name) != null) db.log.add(name);
  }

  /// Makes every sync token of [user] given out so far expire.
  void expireTokens(String user) => _db(user).epoch++;

  /// A client for one browser.
  FakeCloudKitWeb client({String? user = 'user-a'}) =>
      FakeCloudKitWeb(this, user);

  CkRecord _record(_Stored r) {
    String? url;
    if (r.body case final body?) {
      url =
          r'https://cvws.icloud-content.com/B/${f}?'
          'k=${r.name}-${r.tag}';
      _assets[url] = body;
    }
    return CkRecord(
      name: r.name,
      type: r.type,
      changeTag: r.tag,
      fields: {
        for (final MapEntry(:key, :value) in r.fields.entries)
          // As JSON brings numbers: whole doubles come as integers.
          key:
              value.value is double &&
                  (value.value as double) == (value.value as double).truncate()
              ? (value.value as double).toInt()
              : value.value,
      },
      bodyUrl: url,
    );
  }

  List<CkResult> _modify(String user, List<CkWrite> writes) {
    final db = _db(user);
    if (!db.zone) {
      return [
        for (final w in writes)
          CkResult(error: CkError('ZONE_NOT_FOUND', recordName: w.name)),
      ];
    }
    return [for (final write in writes) _apply(db, write)];
  }

  CkResult _apply(_Database db, CkWrite write) {
    final current = db.records[write.name];
    switch (write) {
      case CkDelete(:final name):
        writes.add('delete $name');
        if (current == null) {
          return CkResult(error: CkError('NOT_FOUND', recordName: name));
        }
        db.records.remove(name);
        db.log.add(name);
        return CkResult(record: CkRecord(name: name, deleted: true));
      case CkSave(:final name, :final changeTag):
        writes.add('${changeTag == null ? 'create' : 'replace'} $name');
        if (changeTag == null && current != null) {
          return CkResult(error: CkError('EXISTS', recordName: name));
        }
        if (changeTag != null && current == null) {
          return CkResult(error: CkError('NOT_FOUND', recordName: name));
        }
        if (changeTag != null && current!.tag != changeTag) {
          return CkResult(error: CkError('CONFLICT', recordName: name));
        }
        final stored = _Stored(
          name,
          write.type,
          Map.of(write.fields),
          write.body,
          't${++_tags}',
        );
        db.records[name] = stored;
        db.log.add(name);
        return CkResult(record: _record(stored));
    }
  }

  List<CkResult> _lookup(String user, List<String> names) {
    final db = _db(user);
    return [
      for (final name in names)
        if (db.records[name] case final r?)
          CkResult(record: _record(r))
        else
          CkResult(error: CkError('NOT_FOUND', recordName: name)),
    ];
  }

  CkZoneChanges _changes(String user, String? token) {
    final db = _db(user);
    if (!db.zone) throw const CloudKitException(CkError('ZONE_NOT_FOUND'));
    if (token == null) {
      // From the start: what there is now, no deletions.
      final all = db.records.values.toList();
      return CkZoneChanges(
        records: [for (final r in all) _record(r)],
        syncToken: '${db.epoch}:${db.log.length}',
        moreComing: false,
      );
    }
    final [epoch, at] = token.split(':');
    if (int.parse(epoch) != db.epoch) {
      throw const CloudKitException(
        CkError('BAD_REQUEST', reason: 'sync token expired'),
      );
    }
    final from = int.parse(at);
    final to = (from + pageSize).clamp(from, db.log.length);
    return CkZoneChanges(
      records: [
        for (final name in db.log.sublist(from, to).toSet())
          if (db.records[name] case final r?)
            _record(r)
          else
            CkRecord(name: name, deleted: true),
      ],
      syncToken: '${db.epoch}:$to',
      moreComing: to < db.log.length,
    );
  }
}

/// [CloudKitWeb] for one browser over a [FakeCloudKit].
class FakeCloudKitWeb implements CloudKitWeb {
  FakeCloudKitWeb(this.server, this._user);

  final FakeCloudKit server;
  String? _user;
  final StreamController<String?> _users =
      StreamController<String?>.broadcast();

  /// The user whose session it is, even after it ran out.
  String? get user => _user;

  /// Whether the session ran out: every call is refused until [signIn].
  bool expired = false;

  /// While set, every data call fails with it.
  CkError? failure;

  /// How often the sign-in button was asked for.
  int signInsShown = 0;

  /// [user] signs in with Apple's button.
  void signIn(String user) {
    _user = user;
    expired = false;
    _users.add(user);
  }

  @override
  Stream<String?> get users => _users.stream;

  @override
  Future<String?> userRecordName() async => expired ? null : _user;

  @override
  Future<void> showSignIn() async => signInsShown++;

  @override
  Future<void> signOut() async {
    _user = null;
    _users.add(null);
  }

  String _caller() {
    if (failure case final failure?) throw CloudKitException(failure);
    final user = _user;
    if (user == null || expired) {
      throw const CloudKitException(CkError('AUTHENTICATION_REQUIRED'));
    }
    return user;
  }

  @override
  Future<List<CkResult>> modify(List<CkWrite> writes) async =>
      server._modify(_caller(), writes);

  @override
  Future<List<CkResult>> lookup(List<String> names) async =>
      server._lookup(_caller(), names);

  @override
  Future<CkZoneChanges> zoneChanges(String? syncToken) async =>
      server._changes(_caller(), syncToken);

  @override
  Future<void> createZone() async => server._db(_caller()).zone = true;

  @override
  Future<Uint8List> download(String url) async {
    _caller();
    server.downloads.add(url);
    final bytes = server._assets[url];
    if (bytes == null) throw const CloudKitException(CkError('NOT_FOUND'));
    return bytes;
  }
}
