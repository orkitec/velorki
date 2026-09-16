import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../routing_tiles/data/brouter_storage.dart';
import '../../routing_tiles/data/routing_tiles_repository.dart';
import '../domain/search_result.dart';

part 'gazetteer_store.g.dart';

/// The gazetteer file format this app can read (`meta.schema_version`).
const String gazetteerSchemaVersion = '1';

/// Below this many characters the index is not queried at all.
///
/// A two-letter prefix matches a large part of a tile, which is both slow and
/// useless as a suggestion list.
const int gazetteerMinChars = 3;

/// How many rows one file's FTS query returns before the Dart-side ranking.
const int _fetchLimit = 60;

/// The longest query text that is looked at; the rest is a paste accident.
const int _maxQueryChars = 100;

/// The most tokens one query is split into.
const int _maxTokens = 8;

/// The offline place search: every `<TILE>.gaz` under
/// `<appSupport>/brouter/gazetteer/`, opened read-only and queried together.
///
/// One small SQLite file per downloaded routing tile, built by
/// `tools/gazetteer`, holding that tile's places, streets and named POIs with
/// one FTS5 index over all three (`search`, ids from a single counter, so a
/// hit's rowid names exactly one row in exactly one table). The files are read
/// only on the phone and rebuilt from scratch by the builder, so nothing here
/// ever writes.
///
/// The SQLite work runs synchronously — a prefix query over a few hundred
/// thousand rows is a couple of milliseconds, far cheaper than shipping the
/// query to an isolate — but the API is async so the caller cannot tell and a
/// future move off the main thread stays invisible.
class GazetteerStore {
  /// Creates a store over [directory].
  ///
  /// A `null` directory (the app could not find its support directory) is a
  /// store with no files: [hasTiles] stays false and search falls back online.
  GazetteerStore(this.directory);

  /// Where the `.gaz` files live.
  final Directory? directory;

  final Map<String, _GazetteerFile> _open = <String, _GazetteerFile>{};
  final Set<String> _skipped = <String>{};
  bool _closed = false;

  /// Whether at least one readable gazetteer is open.
  bool get hasTiles => _open.isNotEmpty;

  /// The tiles that can be searched offline, sorted, for tests and logs.
  List<String> get tiles => _open.keys.toList()..sort();

  /// Opens gazetteers that appeared and closes those that are gone.
  ///
  /// Called when the routing tiles change (a download finished, a tile was
  /// deleted) and on demand. Cheap enough to call often: a file that is
  /// already open is left alone.
  Future<void> refresh() async {
    if (_closed) return;
    final dir = directory;
    final found = <String, String>{};
    if (dir != null && dir.existsSync()) {
      for (final entity in dir.listSync(followLinks: true)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.toLowerCase().endsWith('.gaz')) continue;
        found[name.substring(0, name.length - 4)] = entity.path;
      }
    }

    for (final tile in _open.keys.toList()) {
      if (found.containsKey(tile)) continue;
      _open.remove(tile)?.close();
    }
    _skipped.removeWhere((path) => !found.containsValue(path));

    for (final entry in found.entries) {
      if (_open.containsKey(entry.key) || _skipped.contains(entry.value)) {
        continue;
      }
      final file = _openFile(entry.key, entry.value);
      if (file == null) {
        _skipped.add(entry.value);
      } else {
        _open[entry.key] = file;
      }
    }
  }

  /// Searches every open gazetteer for [text].
  ///
  /// Ranked the way the file format prescribes: bm25 ascending, ties broken by
  /// the shorter name, then population descending and then by distance to
  /// [near], which is the map centre when there is one. Returns at most [limit] results, and an empty
  /// list for anything shorter than [gazetteerMinChars], for a query that
  /// tokenises to nothing, and for any file that fails to answer — the search
  /// box must never throw at the rider.
  Future<List<SearchResult>> search(
    String text, {
    LatLng? near,
    int limit = 10,
  }) async {
    if (_closed || _open.isEmpty) return const <SearchResult>[];
    final match = gazetteerMatchExpression(text);
    if (match == null) return const <SearchResult>[];

    final hits = <_Hit>[];
    for (final file in _open.values) {
      try {
        hits.addAll(file.search(match, near));
      } on Object catch (e) {
        debugPrint('velorki: gazetteer ${file.tile} could not answer: $e');
      }
    }
    hits.sort(_byRank);
    return <SearchResult>[
      for (final hit in hits.take(math.max(0, limit))) hit.result,
    ];
  }

  /// Closes every open file. The store answers nothing afterwards.
  void close() {
    _closed = true;
    for (final file in _open.values) {
      file.close();
    }
    _open.clear();
  }

  _GazetteerFile? _openFile(String tile, String path) {
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      final version = _metaValue(db, 'schema_version');
      if (version != gazetteerSchemaVersion) {
        debugPrint(
          'velorki: $tile.gaz is schema $version, not '
          '$gazetteerSchemaVersion; ignored',
        );
        db.close();
        return null;
      }
      return _GazetteerFile(tile, db);
    } on Object catch (e) {
      debugPrint('velorki: $tile.gaz could not be opened: $e');
      db?.close();
      return null;
    }
  }

  static String? _metaValue(Database db, String key) {
    final rows = db.select('SELECT value FROM meta WHERE key = ?', <Object?>[
      key,
    ]);
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  static int _byRank(_Hit a, _Hit b) {
    final rank = a.rank.compareTo(b.rank);
    if (rank != 0) return rank;
    // The index keeps no column sizes, so bm25 cannot tell "Monte" from
    // "Monte Tea House": the shorter name is the closer match.
    final length = a.result.name.length.compareTo(b.result.name.length);
    if (length != 0) return length;
    final population = b.population.compareTo(a.population);
    if (population != 0) return population;
    return a.distance.compareTo(b.distance);
  }
}

/// The FTS5 `MATCH` expression for [text], or `null` when there is nothing to
/// search for.
///
/// The typed text is split on whitespace, every token is quoted (with `"`
/// doubled inside) so that FTS5 operators a rider typed are read as text, and
/// only the last token gets the `*` that makes it a prefix. Tokens without a
/// single letter or digit are dropped: quoting them would leave an empty
/// phrase, which FTS5 rejects.
@visibleForTesting
String? gazetteerMatchExpression(String text) {
  final trimmed = text.trim();
  if (trimmed.length < gazetteerMinChars) return null;
  final capped = trimmed.length > _maxQueryChars
      ? trimmed.substring(0, _maxQueryChars)
      : trimmed;
  final tokens = <String>[];
  for (final token in capped.split(RegExp(r'\s+'))) {
    if (token.isEmpty || !_hasWordChar.hasMatch(token)) continue;
    tokens.add('"${token.replaceAll('"', '""')}"');
    if (tokens.length == _maxTokens) break;
  }
  if (tokens.isEmpty) return null;
  tokens[tokens.length - 1] = '${tokens.last}*';
  return tokens.join(' ');
}

final RegExp _hasWordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// One open `<TILE>.gaz`, with the four statements a search runs.
class _GazetteerFile {
  _GazetteerFile(this.tile, this._db)
    : _match = _db.prepare(
        'SELECT rowid, bm25(search) AS rank FROM search '
        'WHERE search MATCH ? ORDER BY rank LIMIT ?',
      ),
      _place = _db.prepare(
        'SELECT name, kind, lat, lon, population, admin_id '
        'FROM places WHERE id = ?',
      ),
      _street = _prepareOrNull(
        _db,
        'SELECT name, lat, lon, place_id FROM streets WHERE id = ?',
      ),
      _poi = _prepareOrNull(
        _db,
        'SELECT name, kind, lat, lon, place_id FROM pois WHERE id = ?',
      );

  /// The tile this file covers, e.g. `E5_N45`.
  final String tile;

  final Database _db;
  final PreparedStatement _match;
  final PreparedStatement _place;
  final PreparedStatement? _street;
  final PreparedStatement? _poi;

  /// The hits for [match], hydrated and measured against [near].
  List<_Hit> search(String match, LatLng? near) {
    final out = <_Hit>[];
    for (final row in _match.select(<Object?>[match, _fetchLimit])) {
      final id = _asInt(row['rowid']);
      final rank = _asDouble(row['rank']);
      if (id == null) continue;
      final hit =
          _hydratePlace(id, rank, near) ??
          _hydrate(_street, id, rank, near, SearchKind.street) ??
          _hydrate(_poi, id, rank, near, SearchKind.poi);
      if (hit != null) out.add(hit);
    }
    return out;
  }

  /// Releases the statements and the database.
  void close() {
    _match.close();
    _place.close();
    _street?.close();
    _poi?.close();
    _db.close();
  }

  _Hit? _hydratePlace(int id, double rank, LatLng? near) {
    final rows = _place.select(<Object?>[id]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final position = _position(row);
    if (position == null) return null;
    return _Hit(
      result: SearchResult(
        name: row['name']?.toString() ?? '',
        position: position,
        city: _contextName(_asInt(row['admin_id'])),
        source: SearchSource.local,
        kind: SearchKind.place,
        detail: row['kind']?.toString(),
      ),
      rank: rank,
      population: _asInt(row['population']) ?? 0,
      distance: _distance(near, position),
    );
  }

  _Hit? _hydrate(
    PreparedStatement? statement,
    int id,
    double rank,
    LatLng? near,
    SearchKind kind,
  ) {
    if (statement == null) return null;
    final rows = statement.select(<Object?>[id]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final position = _position(row);
    if (position == null) return null;
    return _Hit(
      result: SearchResult(
        name: row['name']?.toString() ?? '',
        position: position,
        city: _contextName(_asInt(row['place_id'])),
        source: SearchSource.local,
        kind: kind,
        detail: kind == SearchKind.poi ? row['kind']?.toString() : null,
      ),
      rank: rank,
      population: 0,
      distance: _distance(near, position),
    );
  }

  /// The name of the place a row hangs off, for the second line of the row.
  String? _contextName(int? placeId) {
    if (placeId == null) return null;
    final rows = _place.select(<Object?>[placeId]);
    if (rows.isEmpty) return null;
    final name = rows.first['name']?.toString();
    return name == null || name.isEmpty ? null : name;
  }

  static LatLng? _position(Row row) {
    final lat = _asInt(row['lat']);
    final lon = _asInt(row['lon']);
    if (lat == null || lon == null) return null;
    return LatLng(lat / 1e7, lon / 1e7);
  }

  static double _distance(LatLng? near, LatLng position) =>
      near == null ? 0 : haversineMeters(near, position);

  static PreparedStatement? _prepareOrNull(Database db, String sql) {
    try {
      return db.prepare(sql);
    } on Object catch (e) {
      // A gazetteer built without streets or POIs still has the tables, but a
      // file from a future builder may not; one missing table must not take
      // the places with it.
      debugPrint('velorki: gazetteer statement unavailable: $e');
      return null;
    }
  }

  static int? _asInt(Object? v) => v is int
      ? v
      : v is num
      ? v.round()
      : v == null
      ? null
      : int.tryParse(v.toString());

  static double _asDouble(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
}

/// One hit with everything the ranking needs.
class _Hit {
  const _Hit({
    required this.result,
    required this.rank,
    required this.population,
    required this.distance,
  });

  final SearchResult result;
  final double rank;
  final int population;
  final double distance;
}

/// The app's [GazetteerStore], re-scanned whenever the routing tiles change.
@Riverpod(keepAlive: true)
Future<GazetteerStore> gazetteerStore(Ref ref) async {
  Directory? directory;
  try {
    directory = (await ref.watch(brouterStorageProvider.future)).gazetteer;
  } on Object catch (e) {
    // No app support directory (a widget test without the plugin, a locked
    // down device): the rider simply searches online.
    debugPrint('velorki: no gazetteer directory: $e');
  }
  final store = GazetteerStore(directory);
  ref.onDispose(store.close);
  await store.refresh();
  if (directory != null) {
    ref.listen(
      routingTilesProvider,
      (_, _) => unawaited(store.refresh()),
      onError: (_, _) {},
    );
  }
  return store;
}
