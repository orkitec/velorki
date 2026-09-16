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
import 'photon_client.dart';

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
/// hit's rowid names exactly one row in exactly one table — or one alternative
/// name in `aliases`, which points back at its row). The files are read only
/// on the phone and rebuilt from scratch by the builder, so nothing here ever
/// writes.
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
  /// [near], which is the map centre when there is one. A query that carried a
  /// house number ("400 w 42nd") puts the streets above places and POIs of the
  /// same bm25 score: a number means the rider is after an address. Returns at
  /// most [limit] results, and an empty list for anything shorter than
  /// [gazetteerMinChars], for a query that tokenises to nothing, and for any
  /// file that fails to answer — the search box must never throw at the rider.
  Future<List<SearchResult>> search(
    String text, {
    LatLng? near,
    int limit = 10,
  }) async {
    if (_closed || _open.isEmpty) return const <SearchResult>[];
    final query = gazetteerMatchExpression(text);
    if (query == null) return const <SearchResult>[];

    final hits = <_Hit>[];
    for (final file in _open.values) {
      try {
        hits.addAll(file.search(query, near));
      } on Object catch (e) {
        debugPrint('velorki: gazetteer ${file.tile} could not answer: $e');
      }
    }
    final addressed = query.houseNumber != null;
    hits.sort((a, b) => _byRank(a, b, addressed: addressed));
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

  static int _byRank(_Hit a, _Hit b, {required bool addressed}) {
    final rank = a.rank.compareTo(b.rank);
    if (rank != 0) return rank;
    if (addressed) {
      // A number in the query is an address: the street it belongs to beats
      // the café of the same name.
      final street = _isStreet(b).compareTo(_isStreet(a));
      if (street != 0) return street;
    }
    // The index keeps no column sizes, so bm25 cannot tell "Monte" from
    // "Monte Tea House": the shorter name is the closer match.
    final length = a.result.name.length.compareTo(b.result.name.length);
    if (length != 0) return length;
    final population = b.population.compareTo(a.population);
    if (population != 0) return population;
    return a.distance.compareTo(b.distance);
  }

  static int _isStreet(_Hit hit) =>
      hit.result.kind == SearchKind.street ? 1 : 0;
}

/// What a typed query asks one gazetteer for.
@immutable
class GazetteerQuery {
  /// Creates a query.
  const GazetteerQuery({required this.match, this.houseNumber});

  /// The FTS5 `MATCH` expression, every token a quoted prefix.
  final String match;

  /// The house number that was taken out of the match, as it was typed, or
  /// `null` when the query held none.
  final String? houseNumber;

  /// [houseNumber] as a number, or `null` when there is none.
  int? get number => houseNumber == null ? null : int.tryParse(houseNumber!);

  @override
  String toString() => 'GazetteerQuery($match, number: $houseNumber)';
}

/// What [text] asks the index for, or `null` when there is nothing to search.
///
/// The text is first normalised the way Photon needs it ("400w 42nd" ->
/// "400 w 42nd"), then split on whitespace. A digits-only token at the start or
/// the end of a query with more than one token is the house number: it is
/// carried separately and left out of the match, because no name in the index
/// contains it. An ordinal such as "42nd" is a name, not a number, and the only
/// token of a query is never a house number either.
///
/// Every remaining token is quoted (with `"` doubled inside) so that FTS5
/// operators a rider typed are read as text, and every one of them is a prefix,
/// so "w 42nd" finds "West 42nd Street". Tokens without a single letter or
/// digit are dropped: quoting them would leave an empty phrase, which FTS5
/// rejects. What is left has to be at least [gazetteerMinChars] characters
/// long — the floor applies to the text that is actually matched, not to what
/// the number made of it.
@visibleForTesting
GazetteerQuery? gazetteerMatchExpression(String text) {
  final normalized = PhotonClient.normalizeQuery(text);
  final capped = normalized.length > _maxQueryChars
      ? normalized.substring(0, _maxQueryChars)
      : normalized;
  final words = <String>[];
  for (final token in capped.split(RegExp(r'\s+'))) {
    if (token.isEmpty || !_hasWordChar.hasMatch(token)) continue;
    words.add(token);
  }

  String? houseNumber;
  if (words.length > 1) {
    if (_isHouseNumber(words.first)) {
      houseNumber = words.removeAt(0);
    } else if (_isHouseNumber(words.last)) {
      houseNumber = words.removeLast();
    }
  }
  if (words.length > _maxTokens) words.removeRange(_maxTokens, words.length);
  if (words.isEmpty) return null;
  if (words.join(' ').length < gazetteerMinChars) return null;

  return GazetteerQuery(
    match: words.map((word) => '"${word.replaceAll('"', '""')}"*').join(' '),
    houseNumber: houseNumber,
  );
}

/// Whether [token] is a house number: nothing but digits, and a number this
/// machine can compare.
bool _isHouseNumber(String token) =>
    _digitsOnly.hasMatch(token) && int.tryParse(token) != null;

final RegExp _hasWordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
final RegExp _digitsOnly = RegExp(r'^\d+$');

/// One open `<TILE>.gaz`, with the statements a search runs.
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
      ),
      _alias = _prepareOrNull(_db, 'SELECT ref_id FROM aliases WHERE id = ?'),
      _houseNumbers = _prepareOrNull(
        _db,
        'SELECT number, lat, lon FROM house_numbers WHERE street_id = ? '
        'ORDER BY number',
      );

  /// The tile this file covers, e.g. `E5_N45`.
  final String tile;

  final Database _db;
  final PreparedStatement _match;
  final PreparedStatement _place;
  final PreparedStatement? _street;
  final PreparedStatement? _poi;
  final PreparedStatement? _alias;
  final PreparedStatement? _houseNumbers;

  /// The hits for [query], hydrated and measured against [near].
  ///
  /// A rowid that is none of the three tables is an alternative name: it is
  /// resolved through `aliases` and answers with the row's primary name, so
  /// searching "Bruxelles" finds "Brussel". Two hits on the same row (the name
  /// and one of its aliases both matched) are one row, with the better rank.
  List<_Hit> search(GazetteerQuery query, LatLng? near) {
    final byRow = <int, _Hit>{};
    for (final row in _match.select(<Object?>[query.match, _fetchLimit])) {
      final id = _asInt(row['rowid']);
      if (id == null) continue;
      final rank = _asDouble(row['rank']);
      final target = _resolveAlias(id);
      final seen = byRow[target];
      if (seen != null) {
        if (rank < seen.rank) byRow[target] = seen.withRank(rank);
        continue;
      }
      final hit =
          _hydratePlace(target, rank, near) ??
          _hydrateStreet(target, rank, near, query) ??
          _hydratePoi(target, rank, near);
      if (hit != null) byRow[target] = hit;
    }
    return byRow.values.toList();
  }

  /// Releases the statements and the database.
  void close() {
    _match.close();
    _place.close();
    _street?.close();
    _poi?.close();
    _alias?.close();
    _houseNumbers?.close();
    _db.close();
  }

  /// The row an FTS rowid stands for: itself, or the row an alias belongs to.
  int _resolveAlias(int id) {
    final statement = _alias;
    if (statement == null) return id;
    final rows = statement.select(<Object?>[id]);
    if (rows.isEmpty) return id;
    return _asInt(rows.first['ref_id']) ?? id;
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

  /// A street, at the house number the query carried when it carried one.
  _Hit? _hydrateStreet(
    int id,
    double rank,
    LatLng? near,
    GazetteerQuery query,
  ) {
    final statement = _street;
    if (statement == null) return null;
    final rows = statement.select(<Object?>[id]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final street = _position(row);
    if (street == null) return null;
    final number = query.number;
    final located = number == null
        ? (position: street, approximate: false)
        : _locate(id, number, street);
    return _Hit(
      result: SearchResult(
        name: row['name']?.toString() ?? '',
        position: located.position,
        city: _contextName(_asInt(row['place_id'])),
        source: SearchSource.local,
        kind: SearchKind.street,
        houseNumber: number == null ? null : query.houseNumber,
        approximate: located.approximate,
      ),
      rank: rank,
      population: 0,
      distance: _distance(near, located.position),
    );
  }

  _Hit? _hydratePoi(int id, double rank, LatLng? near) {
    final statement = _poi;
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
        kind: SearchKind.poi,
        detail: row['kind']?.toString(),
      ),
      rank: rank,
      population: 0,
      distance: _distance(near, position),
    );
  }

  /// Where number [number] of street [streetId] is.
  ///
  /// The builder keeps anchors, not every address: the lowest number, the
  /// highest and every tenth in between. An anchor for the number itself is
  /// the exact spot; between two anchors the position is interpolated by
  /// number; beyond either end it is the end anchor; with no anchors at all it
  /// is [fallback], the street itself. Everything but a hit on an anchor is
  /// approximate, and the row says so.
  ({LatLng position, bool approximate}) _locate(
    int streetId,
    int number,
    LatLng fallback,
  ) {
    final statement = _houseNumbers;
    if (statement == null) return (position: fallback, approximate: true);
    final anchors = <({int number, LatLng position})>[];
    for (final row in statement.select(<Object?>[streetId])) {
      final value = _asInt(row['number']);
      final position = _position(row);
      if (value == null || position == null) continue;
      anchors.add((number: value, position: position));
    }
    if (anchors.isEmpty) return (position: fallback, approximate: true);

    for (final anchor in anchors) {
      if (anchor.number == number) {
        return (position: anchor.position, approximate: false);
      }
    }
    if (number < anchors.first.number) {
      return (position: anchors.first.position, approximate: true);
    }
    if (number > anchors.last.number) {
      return (position: anchors.last.position, approximate: true);
    }
    for (var i = 0; i + 1 < anchors.length; i++) {
      final low = anchors[i];
      final high = anchors[i + 1];
      if (number <= low.number || number >= high.number) continue;
      final t = (number - low.number) / (high.number - low.number);
      return (
        position: LatLng(
          low.position.lat + (high.position.lat - low.position.lat) * t,
          low.position.lon + (high.position.lon - low.position.lon) * t,
        ),
        approximate: true,
      );
    }
    return (position: fallback, approximate: true);
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
      // file from an older builder has no aliases and no house numbers at all;
      // one missing table must not take the places with it.
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

  /// The same hit with a better score, for a row an alias matched too.
  _Hit withRank(double rank) => _Hit(
    result: result,
    rank: rank,
    population: population,
    distance: distance,
  );
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
