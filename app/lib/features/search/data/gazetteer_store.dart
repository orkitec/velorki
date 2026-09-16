import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../routing_tiles/data/brouter_storage.dart';
import '../../routing_tiles/data/routing_tiles_repository.dart';
import '../domain/fuzzy.dart';
import '../domain/search_group.dart';
import '../domain/search_kinds.dart';
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

/// How many rows a "nearest tap" search answers with.
const int kindSearchLimit = 5;

/// The bounding boxes a kind search tries, in metres, until it has
/// [kindSearchLimit] rows. A tap five kilometres away is a detour; one fifty
/// kilometres away is only worth showing when there is nothing else.
const List<double> kindSearchRadiiMeters = <double>[5000, 10000, 25000, 50000];

/// The most rows one file hands back per kind search, before the distances
/// are measured. A bounding box over a dense city can hold thousands of bike
/// parkings and only the five nearest ever matter.
const int _kindFetchLimit = 400;

/// The most spelling candidates one mistyped token is rewritten into.
const int _maxCandidates = 3;

/// Up to this many characters a token may only be one edit away from the
/// word it meant; a longer one may be two.
const int _shortTokenChars = 5;

/// Metres in a degree of latitude, near enough for a bounding box that is
/// re-measured with the haversine afterwards.
const double _metersPerDegree = 111320;

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

  /// Whether the 5° × 5° tile [point] falls into has an open gazetteer.
  ///
  /// [hasTiles] says the device can search *something* offline; this says it
  /// can search *here*. A rider who downloaded Madeira and is looking at the
  /// Alps has both a gazetteer and nothing to find in it, so the search goes
  /// online instead and the list offers the download for the area on screen.
  bool covers(LatLng point) {
    if (_closed || _open.isEmpty) return false;
    final TileName tile;
    try {
      tile = TileName.fromLatLng(point);
    } on ArgumentError {
      // A map that is not ready yet can answer with a non-finite centre.
      return false;
    }
    for (final name in _open.keys) {
      if (TileName.tryParse(name) == tile) return true;
    }
    return false;
  }

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
    SearchPreferences preferences = SearchPreferences.defaults,
    Map<String, String> keywords = const <String, String>{},
  }) async => (await lookup(
    text,
    near: near,
    limit: limit,
    preferences: preferences,
    keywords: keywords,
  )).results;

  /// The same search, with what the store had to do to answer it.
  ///
  /// On top of [search] this is where the two things the plain result list
  /// cannot express happen:
  ///
  /// * **The nearest of a kind.** When the typed text is, or starts, the name
  ///   of a kind — "drinking water", "bakery", the localised label out of
  ///   [keywords] — the answer opens with the [kindSearchLimit] rows of that
  ///   kind nearest to [near], found on the position index in a box that
  ///   grows through [kindSearchRadiiMeters] until it holds enough of them.
  ///   Each carries its [SearchResult.distanceMeters]. Name matches follow,
  ///   and a row that is already in the kind list is not repeated.
  /// * **Spelling.** When neither the kind search nor the names answer at all,
  ///   every token that matches no term in the index is looked up in the index
  ///   vocabulary and the query is run once more with the nearest words. The
  ///   corrected text comes back in [GazetteerSearch.correctedQuery] so the
  ///   list can say what it actually searched for.
  ///
  /// [preferences] is Settings → Search: rows of a switched-off group are left
  /// out of the name matches (a kind search asks for a kind explicitly, so it
  /// is never filtered), and the group order breaks a bm25 tie before the name
  /// length does.
  Future<GazetteerSearch> lookup(
    String text, {
    LatLng? near,
    int limit = 10,
    SearchPreferences preferences = SearchPreferences.defaults,
    Map<String, String> keywords = const <String, String>{},
  }) async {
    if (_closed || _open.isEmpty) return GazetteerSearch.empty;
    final cap = math.max(0, limit);
    final kindResults = near == null
        ? const <SearchResult>[]
        : _nearestOfKind(text, keywords, near);

    final query = gazetteerMatchExpression(text);
    var hits = query == null ? <_Hit>[] : _runQuery(query, near, preferences);
    String? corrected;
    if (query != null && hits.isEmpty && kindResults.isEmpty) {
      final fix = _correct(query);
      if (fix != null) {
        final retried = _runQuery(fix.query, near, preferences);
        if (retried.isNotEmpty) {
          hits = retried;
          corrected = fix.text;
        }
      }
    }

    final addressed = query?.houseNumber != null;
    hits.sort((a, b) => _byRank(a, b, addressed: addressed));
    final results = <SearchResult>[...kindResults.take(cap)];
    final seen = <String>{for (final row in results) _identity(row)};
    for (final hit in hits) {
      if (results.length >= cap) break;
      if (!seen.add(_identity(hit.result))) continue;
      results.add(hit.result);
    }
    return GazetteerSearch(results: results, correctedQuery: corrected);
  }

  /// Every file's answer to [query], minus the groups the rider switched off
  /// and with each hit's group rank attached.
  List<_Hit> _runQuery(
    GazetteerQuery query,
    LatLng? near,
    SearchPreferences preferences,
  ) {
    final hits = <_Hit>[];
    for (final file in _open.values) {
      try {
        for (final hit in file.search(query, near)) {
          final group = searchGroupOf(hit.result);
          if (!preferences.isEnabled(group)) continue;
          hits.add(hit.inGroup(preferences.rankOf(group)));
        }
      } on Object catch (e) {
        debugPrint('velorki: gazetteer ${file.tile} could not answer: $e');
      }
    }
    return hits;
  }

  /// The rows nearest to [near] of every kind [text] names, or nothing when it
  /// names none.
  List<SearchResult> _nearestOfKind(
    String text,
    Map<String, String> keywords,
    LatLng near,
  ) {
    if (text.trim().length < gazetteerMinChars) return const <SearchResult>[];
    final kinds = kindsForKeyword(text, keywords);
    if (kinds.isEmpty) return const <SearchResult>[];

    var best = const <SearchResult>[];
    for (final radius in kindSearchRadiiMeters) {
      final found = <SearchResult>[];
      for (final file in _open.values) {
        try {
          found.addAll(file.nearest(kinds, near, radius));
        } on Object catch (e) {
          debugPrint('velorki: gazetteer ${file.tile} has no kind index: $e');
        }
      }
      found.sort(
        (a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0),
      );
      best = found.length > kindSearchLimit
          ? found.sublist(0, kindSearchLimit)
          : found;
      if (best.length >= kindSearchLimit) break;
    }
    return best;
  }

  /// [query] with every token the index has never seen replaced by the words
  /// it probably meant, or `null` when nothing can be corrected.
  ///
  /// A token with a prefix match is left exactly as it was: only the words
  /// that found nothing are guessed at, so "cafe muinchen" still has to be a
  /// cafe.
  ({GazetteerQuery query, String text})? _correct(GazetteerQuery query) {
    final parts = <String>[];
    final words = <String>[];
    var changed = false;
    for (final token in query.tokens) {
      final folded = foldSearchTerm(token);
      if (folded.isEmpty || _indexKnows(token)) {
        parts.add(_prefixTerm(token));
        words.add(token);
        continue;
      }
      final candidates = _candidates(folded);
      if (candidates.isEmpty) {
        parts.add(_prefixTerm(token));
        words.add(token);
        continue;
      }
      changed = true;
      parts.add('(${candidates.map((term) => '"$term"').join(' OR ')})');
      words.add(candidates.first);
    }
    if (!changed) return null;
    return (
      query: GazetteerQuery(
        match: parts.join(' '),
        tokens: query.tokens,
        houseNumber: query.houseNumber,
      ),
      text: words.join(' '),
    );
  }

  /// Whether any open file holds a term starting with [token].
  bool _indexKnows(String token) {
    for (final file in _open.values) {
      try {
        if (file.matchesAnything(_prefixTerm(token))) return true;
      } on Object catch (e) {
        debugPrint('velorki: gazetteer ${file.tile} could not answer: $e');
      }
    }
    return false;
  }

  /// The at most [_maxCandidates] words the index holds that [folded] is
  /// likeliest to be a typo of, commonest first.
  List<String> _candidates(String folded) {
    final maxDistance = folded.length <= _shortTokenChars ? 1 : 2;
    final docs = <String, int>{};
    for (final file in _open.values) {
      try {
        for (final term in file.vocabulary(folded)) {
          docs[term.term] = (docs[term.term] ?? 0) + term.doc;
        }
      } on Object catch (e) {
        debugPrint('velorki: gazetteer ${file.tile} has no vocabulary: $e');
      }
    }
    final scored = <({String term, int doc})>[];
    for (final entry in docs.entries) {
      if (entry.key == folded) continue;
      if (damerauLevenshtein(folded, entry.key, max: maxDistance) >
          maxDistance) {
        continue;
      }
      scored.add((term: entry.key, doc: entry.value));
    }
    scored.sort((a, b) {
      final doc = b.doc.compareTo(a.doc);
      return doc != 0 ? doc : a.term.compareTo(b.term);
    });
    return <String>[
      for (final entry in scored.take(_maxCandidates)) entry.term,
    ];
  }

  /// What tells two rows of two files apart: a tile boundary can put the same
  /// tap in both, and a kind search must not list what the names already did.
  static String _identity(SearchResult result) =>
      '${result.name}@${result.position.lat.toStringAsFixed(6)},'
      '${result.position.lon.toStringAsFixed(6)}';

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
    // Settings → Search is the rider's own priority and outranks every
    // heuristic below it.
    final group = a.groupRank.compareTo(b.groupRank);
    if (group != 0) return group;
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

/// What one search found, and what it had to do to find it.
@immutable
class GazetteerSearch {
  /// Creates the answer.
  const GazetteerSearch({required this.results, this.correctedQuery});

  /// The rows, already ranked: the kind matches first, then the names.
  final List<SearchResult> results;

  /// The text the index was actually searched for, when nothing matched what
  /// was typed and the spelling had to be guessed at; `null` otherwise.
  final String? correctedQuery;

  /// Nothing found, nothing corrected.
  static const GazetteerSearch empty = GazetteerSearch(
    results: <SearchResult>[],
  );

  @override
  String toString() =>
      'GazetteerSearch(${results.length} results'
      '${correctedQuery == null ? '' : ', corrected to "$correctedQuery"'})';
}

/// What a typed query asks one gazetteer for.
@immutable
class GazetteerQuery {
  /// Creates a query.
  const GazetteerQuery({
    required this.match,
    required this.tokens,
    this.houseNumber,
  });

  /// The FTS5 `MATCH` expression, every token a quoted prefix.
  final String match;

  /// The words [match] was built from, as they were typed, so a query that
  /// found nothing can be spelled again.
  final List<String> tokens;

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
    match: words.map(_prefixTerm).join(' '),
    tokens: words,
    houseNumber: houseNumber,
  );
}

/// One token as FTS5 reads it: quoted, so an operator a rider typed is text,
/// and a prefix, so "w" finds "West".
String _prefixTerm(String word) => '"${word.replaceAll('"', '""')}"*';

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

  PreparedStatement? _vocab;
  bool _vocabAttempted = false;

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

  /// Whether the index holds a single row for [match].
  ///
  /// The cheapest question there is about a token: did the rider spell it the
  /// way this tile spells it?
  bool matchesAnything(String match) =>
      _match.select(<Object?>[match, 1]).isNotEmpty;

  /// The rows of any of [kinds] inside a [radius]-metre box around [near],
  /// nearest first, each carrying its distance.
  ///
  /// The box is on `idx_pois_pos`, which is what the format keeps the position
  /// index for; the corners of a box are further away than its edges, so every
  /// row is measured properly afterwards and the ones outside the circle are
  /// dropped. A row with no name at all is a valid answer here — an unnamed
  /// tap is still a tap — and comes back with an empty [SearchResult.name] for
  /// the widget to put the kind's label in.
  List<SearchResult> nearest(List<String> kinds, LatLng near, double radius) {
    if (_poi == null || kinds.isEmpty) return const <SearchResult>[];
    final dLat = radius / _metersPerDegree;
    // A degree of longitude shrinks towards the poles; the floor keeps the box
    // finite where the cosine does not.
    final dLon =
        radius /
        (_metersPerDegree *
            math.max(math.cos(near.lat * math.pi / 180).abs(), 0.01));
    final placeholders = List<String>.filled(kinds.length, '?').join(', ');
    final rows = _db.select(
      'SELECT name, kind, lat, lon, place_id FROM pois '
      'WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? '
      'AND kind IN ($placeholders) LIMIT ?',
      <Object?>[
        ((near.lat - dLat) * 1e7).round(),
        ((near.lat + dLat) * 1e7).round(),
        ((near.lon - dLon) * 1e7).round(),
        ((near.lon + dLon) * 1e7).round(),
        ...kinds,
        _kindFetchLimit,
      ],
    );
    final found = <SearchResult>[];
    for (final row in rows) {
      final position = _position(row);
      if (position == null) continue;
      final meters = haversineMeters(near, position);
      if (meters > radius) continue;
      found.add(
        SearchResult(
          name: row['name']?.toString() ?? '',
          position: position,
          city: _contextName(_asInt(row['place_id'])),
          source: SearchSource.local,
          kind: SearchKind.poi,
          detail: row['kind']?.toString(),
          distanceMeters: meters,
        ),
      );
    }
    found.sort(
      (a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0),
    );
    return found.length > kindSearchLimit
        ? found.sublist(0, kindSearchLimit)
        : found;
  }

  /// The index terms that could be what [folded] was meant to be: the same
  /// length give or take two, and starting with the same letter unless the
  /// term is short enough that its first letter may be the typo.
  ///
  /// Read from an `fts5vocab` table in the connection's own `temp` schema,
  /// which is writable even though the file itself is opened read-only:
  /// `temp` lives in this connection, not in the `.gaz`. It is created the
  /// first time a query needs it and never for a search that spells
  /// everything correctly.
  List<({String term, int doc})> vocabulary(String folded) {
    final statement = _vocabulary();
    if (statement == null || folded.isEmpty) {
      return const <({String term, int doc})>[];
    }
    final rows = statement.select(<Object?>[
      math.max(1, folded.length - 2),
      folded.length + 2,
      folded.substring(0, 1),
    ]);
    return <({String term, int doc})>[
      for (final row in rows)
        if (row['term']?.toString() case final String term)
          (term: term, doc: _asInt(row['doc']) ?? 0),
    ];
  }

  /// Releases the statements and the database.
  void close() {
    _match.close();
    _place.close();
    _street?.close();
    _poi?.close();
    _alias?.close();
    _houseNumbers?.close();
    _vocab?.close();
    _db.close();
  }

  PreparedStatement? _vocabulary() {
    if (_vocabAttempted) return _vocab;
    _vocabAttempted = true;
    try {
      _db.execute(
        'CREATE VIRTUAL TABLE IF NOT EXISTS temp.vocab '
        "USING fts5vocab(main, 'search', 'row');",
      );
      _vocab = _db.prepare(
        'SELECT term, doc FROM temp.vocab '
        'WHERE length(term) BETWEEN ? AND ? '
        'AND (substr(term, 1, 1) = ? OR length(term) <= 4)',
      );
    } on Object catch (e) {
      // An old SQLite without fts5vocab, or a file whose index cannot be
      // read: spelling help is the one thing a search can do without.
      debugPrint('velorki: $tile.gaz has no vocabulary: $e');
    }
    return _vocab;
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
    this.groupRank = 0,
  });

  final SearchResult result;
  final double rank;
  final int population;
  final double distance;

  /// Where the rider put this row's group in Settings → Search.
  final int groupRank;

  /// The same hit with a better score, for a row an alias matched too.
  _Hit withRank(double rank) => _Hit(
    result: result,
    rank: rank,
    population: population,
    distance: distance,
    groupRank: groupRank,
  );

  /// The same hit, ranked by the rider's group order.
  _Hit inGroup(int rank) => _Hit(
    result: result,
    rank: this.rank,
    population: population,
    distance: distance,
    groupRank: rank,
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
