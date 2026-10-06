import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
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
import '../domain/search_text.dart';
import '../domain/street_numbers.dart';
import '../domain/translit.dart';
import 'photon_client.dart';

part 'gazetteer_store.g.dart';

/// The gazetteer file format this app can read (`meta.schema_version`).
const String gazetteerSchemaVersion = '1';

/// Below this many characters the index is not queried at all.
///
/// A two-letter prefix matches a large part of a tile, which is both slow and
/// useless as a suggestion list.
const int gazetteerMinChars = 3;

/// Up to this many matches of one expression in one file are all read and
/// scored; the ranking, not the index, decides which are shown.
const int _fetchAll = 1000;

/// Up to this many matches the rows nearest to the map centre are picked in
/// SQLite instead; above it a word is too common to be worth measuring.
const int _scanLimit = 20000;

/// How many rows of each table the nearest-first path reads.
const int _nearestLimit = 300;

/// Up to this many words the second look leaves out each word in turn;
/// above it only words from the end, then from the start.
const int _dropOneMaxWords = 4;

/// Letters, for telling a town after a comma from a postcode.
final RegExp _letterRun = RegExp(r'\p{L}', unicode: true);

/// The most settlements of one name a trailing place is chosen from.
const int _settlementLimit = 50;

/// The most match expressions the second look runs per file.
const int _maxSecondLookQueries = 12;

/// The most vocabulary words one spelling scan reads.
const int _maxScannedTerms = 30000;

/// A word in more rows than this is looked up as itself, never as a prefix:
/// the prefix would merge the lists of every longer word.
const int _commonDocs = 15000;

/// The longest word that is taken for an abbreviation.
const int _maxShortChars = 4;

/// The longest word a short one is taken to abbreviate.
const int _maxAbbreviatedChars = 14;

/// The longest query text that is looked at; the rest is a paste accident.
const int _maxQueryChars = 100;

/// How many rows a "nearest tap" search answers with.
const int kindSearchLimit = 5;

/// The bounding boxes a kind search tries, in metres, until it has
/// [kindSearchLimit] rows. A tap five kilometres away is a detour; one fifty
/// kilometres away is only worth showing when there is nothing else.
const List<double> kindSearchRadiiMeters = <double>[5000, 10000, 25000, 50000];

/// The `places.kind` values a ride can be named after. Everything else in
/// `places` — an island, a locality — is not a place a rider sets off from.
const List<String> settlementKinds = <String>[
  'city',
  'town',
  'village',
  'suburb',
  'neighbourhood',
  'hamlet',
];

/// The settlements that name a ride before any smaller place does.
///
/// A rider who sets off in São Roque says they rode from Funchal, not from
/// the parish they happened to be standing in, so a suburb, a neighbourhood
/// or a hamlet only names a ride when none of these is in range.
const List<String> primarySettlementKinds = <String>['city', 'town', 'village'];

/// How far a city or a town still names a ride from, in kilometres.
///
/// Wider than the radius the smaller kinds get: a ride that starts on the
/// edge of a city is a ride from that city, and the edge of a city is
/// further from its centre than the edge of a village is from theirs.
const double citySettlementMaxKm = 5;

/// Where [kind] stands in the order settlements name a ride: 0 for a city, a
/// town or a village, 1 for everything smaller.
int settlementRank(String? kind) =>
    primarySettlementKinds.contains(kind) ? 0 : 1;

/// The most rows one file hands back per kind search, before the distances
/// are measured. A bounding box over a dense city can hold thousands of bike
/// parkings and only the five nearest ever matter.
const int _kindFetchLimit = 400;

/// The most spelling candidates one mistyped token is rewritten into.
const int _maxCandidates = 5;

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
/// The SQLite work is synchronous — a typical query on a dense tile is a few
/// milliseconds on a laptop, a second look tens, and a phone is several times
/// slower. With [background] the searches run on a worker isolate with its
/// own read-only connections, so a slow one never holds up a frame while the
/// rider types; [covers], [hasTiles] and [tiles] stay here, they only look
/// at which files are open.
class GazetteerStore {
  /// Creates a store over [directory].
  ///
  /// A `null` directory (the app could not find its support directory) is a
  /// store with no files: [hasTiles] stays false and search falls back online.
  GazetteerStore(this.directory, {this.background = false});

  /// Where the `.gaz` files live.
  final Directory? directory;

  /// Whether [lookup], [inBox] and [nearestSettlement] run on a worker
  /// isolate. It is started with the first of them that has a file to read,
  /// and a store whose worker fails answers on the calling isolate instead.
  final bool background;

  Future<_GazetteerWorker?>? _worker;

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

  /// The settlement [point] is named after, or `null` when none is in range —
  /// which is also the answer when no downloaded tile covers the point.
  ///
  /// This is the reverse of the search box: not "where is Funchal" but "what
  /// is this place called", which is how a finished ride gets a name. The
  /// answer is the best [settlementKinds] row in range: a city, a town or a
  /// village first and the nearest of those, and only when none is in range
  /// the nearest suburb, neighbourhood or hamlet. [maxKm] is how far that
  /// reaches, except for a city or a town, which reach [citySettlementMaxKm].
  ///
  /// One indexed bounding-box query per open file, so it is cheap enough to
  /// run twice while a ride is being saved.
  Future<SearchResult?> nearestSettlement(
    LatLng point, {
    double maxKm = 3,
  }) async {
    if (_closed || _open.isEmpty) return null;
    final worker = await _workerOrNull();
    if (worker != null) {
      final answer = await worker.ask(_Ask.nearestSettlement, (point, maxKm));
      if (answer case _Answered(:final SearchResult? value)) return value;
    }
    return _nearestSettlementHere(point, maxKm);
  }

  SearchResult? _nearestSettlementHere(LatLng point, double maxKm) {
    if (_closed || _open.isEmpty) return null;
    SearchResult? best;
    for (final file in _open.values) {
      try {
        final found = file.nearestSettlement(point, maxKm);
        if (found == null) continue;
        if (best == null || _outranks(found, best)) best = found;
      } on Object catch (e) {
        debugPrint('velorki: gazetteer ${file.tile} has no place index: $e');
      }
    }
    return best;
  }

  /// Every place of [placeKinds] and every POI of [poiKinds] inside [box],
  /// at most [limit] of each per open file, in no particular order.
  ///
  /// The raw rows a route is matched against: a place carries
  /// [SearchKind.place], a POI [SearchKind.poi], both with their kind in
  /// [SearchResult.detail]. One indexed bounding-box query per table and
  /// file, on `idx_places_pos` and `idx_pois_pos`; a file that cannot answer
  /// is left out rather than failing the rest.
  Future<List<SearchResult>> inBox(
    BoundingBox box, {
    List<String> placeKinds = const <String>[],
    List<String> poiKinds = const <String>[],
    int limit = _kindFetchLimit,
  }) async {
    if (_closed || _open.isEmpty) return const <SearchResult>[];
    final worker = await _workerOrNull();
    if (worker != null) {
      final answer = await worker.ask(_Ask.inBox, (
        box,
        placeKinds,
        poiKinds,
        limit,
      ));
      if (answer case _Answered(:final List<SearchResult> value)) return value;
    }
    return _inBoxHere(box, placeKinds, poiKinds, limit);
  }

  List<SearchResult> _inBoxHere(
    BoundingBox box,
    List<String> placeKinds,
    List<String> poiKinds,
    int limit,
  ) {
    if (_closed || _open.isEmpty) return const <SearchResult>[];
    final found = <SearchResult>[];
    for (final file in _open.values) {
      try {
        found.addAll(file.inBox(box, placeKinds, poiKinds, limit));
      } on Object catch (e) {
        debugPrint('velorki: gazetteer ${file.tile} has no position index: $e');
      }
    }
    return found;
  }

  /// Whether [row] is the better name for a ride than [other]: a bigger kind
  /// first, the nearer of two of the same standing second.
  static bool _outranks(SearchResult row, SearchResult other) {
    final rank = settlementRank(row.detail);
    final otherRank = settlementRank(other.detail);
    if (rank != otherRank) return rank < otherRank;
    return (row.distanceMeters ?? 0) < (other.distanceMeters ?? 0);
  }

  /// Opens gazetteers that appeared and closes those that are gone.
  ///
  /// Called when the routing tiles change (a download finished, a tile was
  /// deleted) and on demand. Cheap enough to call often: a file that is
  /// already open is left alone.
  Future<void> refresh() async {
    if (_closed) return;
    await _refreshHere();
    final worker = _worker == null ? null : await _worker;
    await worker?.ask(_Ask.refresh, null);
  }

  Future<void> _refreshHere() async {
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
  /// Ranked by how well each name answers the query ([matchName]), then by
  /// the way to [near], the map centre when there is one, and by the size of
  /// a place. A query that carried a house number ("400 w 42nd") lifts the
  /// streets above places and POIs: a number means the rider is after an
  /// address. Returns at most [limit] results, and an empty list for anything
  /// shorter than [gazetteerMinChars], for a query that tokenises to nothing,
  /// and for any file that fails to answer — the search box must never throw
  /// at the rider.
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
  /// On top of [search] this is where the things the plain result list
  /// cannot express happen:
  ///
  /// * **The nearest of a kind.** When the typed text is, or starts, the name
  ///   of a kind — "drinking water", "bakery", the localised label out of
  ///   [keywords] — the answer opens with the [kindSearchLimit] rows of that
  ///   kind nearest to [near], found on the position index in a box that
  ///   grows through [kindSearchRadiiMeters] until it holds enough of them.
  ///   Each carries its [SearchResult.distanceMeters]. Name matches follow,
  ///   and a row that is already in the kind list is not repeated.
  /// * **A second look.** Every word is first looked for as typed, as a
  ///   prefix. When that answers nothing well, the index's own vocabulary is
  ///   asked what each word could have been — a typo of a stored word, an
  ///   abbreviation of one, two words written as one or one written as two —
  ///   and words are left out one at a time, so a town or a floor after the
  ///   street does not sink it. When the best row only matched through such
  ///   a guess, the words it was read as come back in
  ///   [GazetteerSearch.correctedQuery] so the list can say what it searched
  ///   for.
  ///
  /// [preferences] is Settings → Search: rows of a switched-off group are left
  /// out of the name matches (a kind search asks for a kind explicitly, so it
  /// is never filtered), and the group order lifts one group above another
  /// when the names answer equally well.
  Future<GazetteerSearch> lookup(
    String text, {
    LatLng? near,
    int limit = 10,
    SearchPreferences preferences = SearchPreferences.defaults,
    Map<String, String> keywords = const <String, String>{},
  }) async {
    if (_closed || _open.isEmpty) return GazetteerSearch.empty;
    final worker = await _workerOrNull();
    if (worker != null) {
      final answer = await worker.ask(_Ask.lookup, (
        text,
        near,
        limit,
        preferences,
        keywords,
      ));
      switch (answer) {
        case _Answered(:final GazetteerSearch value):
          return value;
        case _Superseded():
          // The rider has typed on; whoever asked has moved on as well.
          return GazetteerSearch.empty;
        default:
          break;
      }
    }
    return _lookupHere(
      text,
      near: near,
      limit: limit,
      preferences: preferences,
      keywords: keywords,
    );
  }

  GazetteerSearch _lookupHere(
    String text, {
    required LatLng? near,
    required int limit,
    required SearchPreferences preferences,
    required Map<String, String> keywords,
  }) {
    if (_closed || _open.isEmpty) return GazetteerSearch.empty;
    final cap = math.max(0, limit);
    final kindResults = near == null
        ? const <SearchResult>[]
        : _nearestOfKind(text, keywords, near);

    final query = gazetteerMatchExpression(text);
    final pool = _Pool(query: query, near: near, preferences: preferences);
    String? corrected;
    if (query != null) {
      final words = _searchedWords(query.tokens);
      String firstLook(Iterable<_Searched> searched) => searched
          .map((w) => _firstLookTerm(query.tokens[w.index], exact: w.exact))
          .join(' AND ');
      _collect(pool, <String>[firstLook(words)], near);

      final place = _trailingPlace(query.tokens, text, pool, near);
      if (place != null) {
        pool.namedPlace = place.position;
        final rest = words.where((w) => w.index < place.from);
        if (rest.isNotEmpty) {
          _collect(pool, <String>[firstLook(rest)], place.position);
        }
      }

      if (pool.wantsSecondLook()) {
        final plan = _secondLook(query.tokens, words);
        _collect(pool, plan.take(1).toList(), pool.origin);
        for (final relaxed in plan.skip(1)) {
          if (!pool.wantsRelaxing()) break;
          _collect(pool, <String>[relaxed], pool.origin);
        }
        corrected = pool.correctedText();
      }
    }

    final results = <SearchResult>[...kindResults.take(cap)];
    final seen = <String>{for (final row in results) _identity(row)};
    for (final hit in pool.ranked()) {
      if (results.length >= cap) break;
      final result = hit.file.result(hit.row, query);
      if (!seen.add(_identity(result))) continue;
      results.add(result);
    }
    return GazetteerSearch(results: results, correctedQuery: corrected);
  }

  /// Every file's rows for each of [expressions], scored into [pool].
  void _collect(_Pool pool, List<String> expressions, LatLng? near) {
    for (final expression in expressions) {
      if (!pool.tried.add(expression)) continue;
      for (final file in _open.values) {
        try {
          pool.addAll(file, file.candidates(expression, near));
        } on Object catch (e) {
          debugPrint('velorki: gazetteer ${file.tile} could not answer: $e');
        }
      }
    }
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

  /// The settlement the last words of [typed] name, when the rider added
  /// one to say where: "hauptstrasse berlin", "soho, new york".
  ///
  /// The last three, two or one words are looked for as a city, a town, a
  /// village or a part of one whose name is exactly those words (or whose
  /// alternative name is), the one nearest to [near] when there are several.
  /// They only count as a place when the words are set apart by a comma, or
  /// when no row holds every word of the query as it was typed: "Rue de
  /// Paris" is a street in every town, and a rider who typed it means that
  /// street, not one in Paris. `from` is where the place's words begin.
  ({int from, LatLng position})? _trailingPlace(
    List<String> typed,
    String text,
    _Pool pool,
    LatLng? near,
  ) {
    final n = typed.length;
    if (n < 2) return null;
    final comma = text.lastIndexOf(',');
    final afterComma = comma < 0
        ? 0
        : indexWords(text.substring(comma + 1))
              .where(_letterRun.hasMatch)
              .length;
    final complete = pool.hasComplete;
    for (var k = math.min(3, n - 1); k >= 1; k--) {
      if (complete && k != afterComma) continue;
      final run = typed.sublist(n - k);
      final folded = run.map(foldForMatch).toList();
      final expression = run
          .map((w) => _firstLookTerm(foldSearchTerm(w), exact: true))
          .join(' AND ');
      ({LatLng position, double rank})? best;
      for (final file in _open.values) {
        try {
          for (final place in file.settlements(expression)) {
            final words = indexWords(place.name).map(foldForMatch).toList();
            if (!listEquals(words, folded)) continue;
            // Nearest first; without a map centre the biggest.
            final rank = near == null
                ? -place.population.toDouble()
                : haversineMeters(near, place.position);
            if (best == null || rank < best.rank) {
              best = (position: place.position, rank: rank);
            }
          }
        } on Object catch (e) {
          debugPrint('velorki: gazetteer ${file.tile} could not answer: $e');
        }
      }
      if (best != null) return (from: n - k, position: best.position);
    }
    return null;
  }

  /// The match expressions of the second look at [query]: every word with
  /// what the index says it could also have been, all of them together, and
  /// then with words left out.
  ///
  /// A word gets alternatives when the index does not know it as typed: no
  /// stored word starts with it, or — for any word but the last, which may
  /// still be being typed — no stored word is exactly it. The alternatives
  /// are the stored words one or two edits away ([allowedEdits]), the common
  /// stored words a short word abbreviates ("rd", "blvd"), and the two stored
  /// words a long one was written as ("hauptstrasse" for "Haupt Straße").
  /// Two neighbouring words that are one stored word ("haupt strasse") are
  /// tried as that word too.
  ///
  /// The words are then dropped one at a time, and from either end, so a
  /// town, a floor or a word the index has never heard of after the name
  /// does not take the name down with it; the scoring decides how much the
  /// missing word costs.
  List<String> _secondLook(List<String> typed, List<_Searched> searched) {
    final words = <String>[for (final w in searched) typed[w.index]];
    List<String> groupsOf({required bool narrowed}) => <String>[
      for (final w in searched)
        _alternatives(
          typed[w.index],
          exact: w.exact,
          common: w.common,
          last: w.index == typed.length - 1,
          narrowed: narrowed,
        ),
    ];
    // The full query has every word to narrow it down, so it can afford
    // the short words a long one may be stored as; with words left out
    // those would match half the tile.
    final fullGroups = groupsOf(narrowed: true);
    final groups = groupsOf(narrowed: false);

    final pairs = <int, String>{};
    for (var i = 0; i + 1 < words.length; i++) {
      if (searched[i + 1].index != searched[i].index + 1) continue;
      final joined = foldSearchTerm(words[i]) + foldSearchTerm(words[i + 1]);
      if (joined.length < gazetteerMinChars) continue;
      final spellings = _spellings(joined).where(_knownPrefix).toList();
      if (spellings.isEmpty) continue;
      pairs[i] = spellings.map(_prefixTerm).join(' OR ');
    }

    final expressions = <String>[];
    final full = <String>[];
    for (var i = 0; i < fullGroups.length; i++) {
      final pair = pairs[i];
      if (pair != null) {
        full.add('((${fullGroups[i]} AND ${fullGroups[i + 1]}) OR $pair)');
        i++;
      } else {
        full.add(fullGroups[i]);
      }
    }
    expressions.add(full.join(' AND '));

    if (groups.length > 1) {
      // A short query has one word too many; a long one is a whole address
      // whose name comes first and whose town, postcode and country follow.
      final n = groups.length;
      final subsets = <List<int>>[
        if (n <= _dropOneMaxWords)
          for (var drop = 0; drop < n; drop++)
            <int>[
              for (var i = 0; i < n; i++)
                if (i != drop) i,
            ],
        for (var keep = n - 1; keep >= 1; keep--)
          <int>[for (var i = 0; i < keep; i++) i],
        for (var keep = n - 1; keep >= 1; keep--)
          <int>[for (var i = n - keep; i < n; i++) i],
      ];
      for (final subset in subsets) {
        final text = subset.map((i) => words[i]).join(' ');
        if (text.length < gazetteerMinChars) continue;
        // Nothing but common words ("chemin du") narrows nothing down.
        if (subset.every((i) => searched[i].common)) continue;
        expressions.add(subset.map((i) => groups[i]).join(' AND '));
        if (expressions.length > _maxSecondLookQueries) break;
      }
    }
    return expressions;
  }

  /// The words of [typed] the index is asked for, and how.
  ///
  /// The last word is a prefix: it may still be being typed. Any other word
  /// is a prefix too ("str" for "Straße", "w" for "West"), unless it is two
  /// letters or less, or so common that it is in more than [_commonDocs]
  /// rows ("de", "la", "rue", "street"), and the index holds it as a word:
  /// then it is that word exactly, because a prefix that short or that
  /// common makes the index merge the lists of thousands of words. A single
  /// letter beside other words is left to the scoring alone, which still
  /// reads "w" as "west".
  List<_Searched> _searchedWords(List<String> typed) {
    final searched = <_Searched>[];
    for (var i = 0; i < typed.length; i++) {
      final folded = foldSearchTerm(typed[i]);
      if (typed.length > 1 && folded.length <= 1) continue;
      final last = i == typed.length - 1;
      var exact = false;
      var common = false;
      if (!last) {
        final docs = _spellings(folded).fold(0, (sum, s) => sum + _docs(s));
        common = docs > _commonDocs;
        exact = docs > 0 && (folded.length <= 2 || common);
      }
      searched.add((index: i, exact: exact, common: common));
    }
    if (searched.isNotEmpty) return searched;
    var longest = 0;
    for (var i = 1; i < typed.length; i++) {
      if (typed[i].length > typed[longest].length) longest = i;
    }
    return <_Searched>[(index: longest, exact: false, common: false)];
  }

  /// How many rows of all open files hold the stored word [term].
  int _docs(String term) {
    var sum = 0;
    for (final file in _open.values) {
      _guarded(file, () {
        sum += file.termDocs(term);
        return true;
      });
    }
    return sum;
  }

  /// One word of the second look as an FTS5 group: itself as the first look
  /// had it, its other spelling of "ß", and what the index offers for it.
  String _alternatives(
    String word, {
    required bool exact,
    required bool common,
    required bool last,
    required bool narrowed,
  }) {
    final folded = foldSearchTerm(word);
    // A short word the first look took exactly may be the start of the
    // stored one ("pl" for "ploshtad"); the second look can afford the prefix
    // unless the word is too common for it.
    final terms = <String>{
      for (final spelling in _spellings(folded)) ...<String>[
        if (exact) _exactTerm(spelling),
        if (!exact || !common) _prefixTerm(spelling),
      ],
    };
    final known = _spellings(folded).any(_knownPrefix);
    final whole = known && _spellings(folded).any(_knownTerm);
    // The index's words come in the script the file was built with: as
    // written in an older file, in Latin in a newer one.
    for (final form in <String>{folded, transliterate(folded)}) {
      var oneEdit = false;
      if (form.length >= gazetteerMinChars && !whole) {
        final typos = _typoCandidates(form);
        oneEdit = typos.any(
          (term) => damerauLevenshtein(form, term, max: 1) <= 1,
        );
        for (final term in typos) {
          terms.add(_exactTerm(term));
        }
        for (final split in _splits(form)) {
          terms.add('(${_exactTerm(split.$1)} AND ${_prefixTerm(split.$2)})');
        }
      }
      if (form.length >= 2 &&
          form.length <= 4 &&
          !common &&
          !oneEdit &&
          (!last || !whole)) {
        for (final term in _abbreviated(form)) {
          terms.add(_exactTerm(term));
        }
      }
      if (narrowed && form.length > _maxShortChars && !common && !last) {
        for (final term in _abbreviations(form)) {
          terms.add(_exactTerm(term));
        }
      }
    }
    return terms.length == 1 ? terms.first : '(${terms.join(' OR ')})';
  }

  /// Whether any open file holds a word starting with [prefix].
  bool _knownPrefix(String prefix) => _open.values.any(
    (file) => _guarded(file, () => file.terms(prefix, limit: 1).isNotEmpty),
  );

  /// Whether any open file holds the word [term] itself.
  bool _knownTerm(String term) =>
      _open.values.any((file) => _guarded(file, () => file.termDocs(term) > 0));

  /// The at most [_maxCandidates] stored words [folded] is likeliest to be a
  /// typo of: the fewest edits first, the commonest word among equals.
  ///
  /// Looked for among the words that share the first two letters, the first
  /// two letters swapped, and the first and the third (a second letter
  /// dropped or swapped with the third), and only when none of those is one
  /// edit away, among all words that share the first letter, which catches
  /// a slip on the second.
  List<String> _typoCandidates(String folded) {
    final edits = allowedEdits(folded);
    if (edits == 0) return const <String>[];
    final minLength = math.max(1, folded.length - edits);
    final maxLength = folded.length + edits;
    final scored = <String, ({int distance, int doc})>{};
    void scan(String prefix) {
      final docs = <String, int>{};
      for (final file in _open.values) {
        _guarded(file, () {
          for (final term in file.terms(
            prefix,
            minLength: minLength,
            maxLength: maxLength,
            limit: _maxScannedTerms,
          )) {
            docs[term.term] = (docs[term.term] ?? 0) + term.doc;
          }
          return true;
        });
      }
      for (final entry in docs.entries) {
        if (entry.key == folded) continue;
        final distance = damerauLevenshtein(folded, entry.key, max: edits);
        if (distance > edits) continue;
        scored[entry.key] = (distance: distance, doc: entry.value);
      }
    }

    if (folded.length >= 2) {
      scan(folded.substring(0, 2));
      scan(folded[1] + folded[0]);
    }
    if (folded.length >= 3) scan(folded[0] + folded[2]);
    if (!scored.values.any((s) => s.distance <= 1)) {
      scan(folded.substring(0, 1));
    }
    final ranked = scored.entries.toList()
      ..sort((a, b) {
        final distance = a.value.distance.compareTo(b.value.distance);
        if (distance != 0) return distance;
        final doc = b.value.doc.compareTo(a.value.doc);
        return doc != 0 ? doc : a.key.compareTo(b.key);
      });
    return <String>[for (final e in ranked.take(_maxCandidates)) e.key];
  }

  /// The commonest stored words that [short] could abbreviate: longer words
  /// with the same first letter that hold its letters in order, "rd" for
  /// "road", "blvd" for "boulevard", "ul" for "ulica".
  List<String> _abbreviated(String short) {
    final docs = <String, int>{};
    for (final file in _open.values) {
      _guarded(file, () {
        for (final term in file.terms(
          short.substring(0, 1),
          minLength: short.length + 1,
          maxLength: _maxAbbreviatedChars,
          limit: _maxScannedTerms,
        )) {
          if (!_holdsInOrder(term.term, short)) continue;
          docs[term.term] = (docs[term.term] ?? 0) + term.doc;
        }
        return true;
      });
    }
    final ranked = docs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return <String>[for (final e in ranked.take(_maxCandidates)) e.key];
  }

  /// The commonest short stored words that abbreviate [long]: its first
  /// letter and some of the others, in order, "st" for "saint" or "street",
  /// "av" for "avenue" — the name may be the one that is abbreviated.
  List<String> _abbreviations(String long) {
    final docs = <String, int>{};
    for (final file in _open.values) {
      _guarded(file, () {
        for (final term in file.terms(
          long.substring(0, 1),
          minLength: 2,
          maxLength: _maxShortChars,
          limit: _maxScannedTerms,
        )) {
          if (!_holdsInOrder(long, term.term)) continue;
          docs[term.term] = (docs[term.term] ?? 0) + term.doc;
        }
        return true;
      });
    }
    final ranked = docs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return <String>[for (final e in ranked.take(_maxCandidates)) e.key];
  }

  /// The ways [folded] splits into a stored word and the start of another,
  /// longest first word first, at most [_maxCandidates].
  List<(String, String)> _splits(String folded) {
    final found = <(String, String)>[];
    for (var k = folded.length - 1; k >= 3; k--) {
      final head = folded.substring(0, k);
      final tail = folded.substring(k);
      if (!_knownTerm(head)) continue;
      // A tail of a letter or two has to be a word of its own ("paul" "s"
      // for "pauls"); a longer one may be the start of one.
      final known = tail.length < 3 ? _knownTerm : _knownPrefix;
      for (final spelling in _spellings(tail)) {
        if (!known(spelling)) continue;
        found.add((head, spelling));
        break;
      }
      if (found.length >= _maxCandidates) break;
    }
    return found;
  }

  /// [folded] and its other spelling: the index keeps "ß" as it is, so
  /// "strasse" is also looked for as "straße", and the other way round.
  static List<String> _spellings(String folded) => spellingsOf(folded);

  static bool _holdsInOrder(String long, String short) {
    var j = 0;
    for (var i = 0; i < long.length && j < short.length; i++) {
      if (long.codeUnitAt(i) == short.codeUnitAt(j)) j++;
    }
    return j == short.length;
  }

  static bool _guarded(_GazetteerFile file, bool Function() ask) {
    try {
      return ask();
    } on Object catch (e) {
      debugPrint('velorki: gazetteer ${file.tile} has no vocabulary: $e');
      return false;
    }
  }

  /// What tells two rows of two files apart: a tile boundary can put the same
  /// tap in both, and a kind search must not list what the names already did.
  static String _identity(SearchResult result) =>
      '${result.name}@${result.position.lat.toStringAsFixed(6)},'
      '${result.position.lon.toStringAsFixed(6)}';

  /// Whether a worker isolate has been started, for tests.
  @visibleForTesting
  bool get workerStarted => _worker != null;

  /// The worker, started on first use; `null` without [background], without
  /// a directory, or when it could not be started.
  Future<_GazetteerWorker?> _workerOrNull() {
    final dir = directory;
    if (!background || dir == null || _closed) return Future.value();
    return _worker ??= _GazetteerWorker.spawn(dir).then<_GazetteerWorker?>(
      (worker) => worker,
      onError: (Object e) {
        debugPrint('velorki: gazetteer worker did not start: $e');
        return null;
      },
    );
  }

  /// Closes every open file and the worker. The store answers nothing
  /// afterwards.
  void close() {
    _closed = true;
    final worker = _worker;
    _worker = null;
    if (worker != null) unawaited(worker.then((w) => w?.close()));
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
    this.number,
  });

  /// The FTS5 `MATCH` expression of the first look: every word a quoted
  /// prefix, and a word with "ß" or "ss" in it in both spellings.
  final String match;

  /// The words [match] was built from, as they were typed.
  final List<String> tokens;

  /// The house number that was taken out of the match, as it was typed, or
  /// `null` when the query held none.
  final String? houseNumber;

  /// The number [houseNumber] starts with, which locates the address.
  final int? number;

  @override
  String toString() => 'GazetteerQuery($match, number: $houseNumber)';
}

/// What [text] asks the index for, or `null` when there is nothing to search.
///
/// The text is first normalised the way Photon needs it ("400w 42nd" ->
/// "400 w 42nd") and then read by [parseQuery]: the words the index's
/// tokenizer would cut out of it, and a house number taken out wherever it
/// stands, because no name in the index contains it. An ordinal such as
/// "42nd" is a name, not a number, and a query that is only a number is that
/// number.
///
/// Every word is quoted (with `"` doubled inside) so that FTS5 operators a
/// rider typed are read as text, and every one of them is a prefix, so
/// "w 42nd" finds "West 42nd Street". What is left has to be at least
/// [gazetteerMinChars] characters long — the floor applies to the text that
/// is actually matched, not to what the number made of it.
@visibleForTesting
GazetteerQuery? gazetteerMatchExpression(String text) {
  final normalized = PhotonClient.normalizeQuery(text);
  final capped = normalized.length > _maxQueryChars
      ? normalized.substring(0, _maxQueryChars)
      : normalized;
  final parsed = parseQuery(capped);
  final words = parsed.words;
  if (words.isEmpty) return null;
  if (words.join(' ').length < gazetteerMinChars) return null;

  return GazetteerQuery(
    match: words.map(_firstLookTerm).join(' AND '),
    tokens: words,
    houseNumber: parsed.houseNumber,
    number: parsed.number,
  );
}

/// One word of the first look: a prefix, or the word itself when [exact],
/// in both spellings of "ß".
String _firstLookTerm(String word, {bool exact = false}) {
  final term = exact ? _exactTerm : _prefixTerm;
  final others = spellingsOf(foldSearchTerm(word)).skip(1);
  if (others.isEmpty) return term(word);
  return '(${<String>[term(word), ...others.map(term)].join(' OR ')})';
}

/// [folded] and the other ways the index may hold it: "ß" for "ss" and the
/// other way round (the tokenizer keeps "ß"), and a Cyrillic or Greek word
/// spelled in Latin, which is how a file with `meta.search_script` = `latin`
/// indexes it; an older file indexes the word as written, so both are asked.
@visibleForTesting
List<String> spellingsOf(String folded) {
  final found = <String>[folded];
  void add(String spelling) {
    if (!found.contains(spelling)) found.add(spelling);
  }

  for (final base in <String>[folded, transliterate(folded)]) {
    add(base);
    if (base.contains('ß')) add(base.replaceAll('ß', 'ss'));
    if (base.contains('ss')) add(base.replaceAll('ss', 'ß'));
  }
  return found;
}

/// One word the index is asked for: its place in the query, and whether it
/// is asked for exactly or as a prefix.
typedef _Searched = ({int index, bool exact, bool common});

/// One word as FTS5 reads it: quoted, so an operator a rider typed is text,
/// and a prefix, so "w" finds "West".
String _prefixTerm(String word) => '"${word.replaceAll('"', '""')}"*';

/// One stored word, exactly: a correction is a whole word, not a prefix.
String _exactTerm(String word) => '"${word.replaceAll('"', '""')}"';

/// One open `<TILE>.gaz`, with the statements a search runs.
class _GazetteerFile {
  _GazetteerFile(this.tile, this._db)
    : _match = _db.prepare(
        'SELECT rowid FROM search WHERE search MATCH ? LIMIT ?',
      ),
      _place = _db.prepare(
        'SELECT name, kind, lat, lon, population, admin_id '
        'FROM places WHERE id = ?',
      ),
      _places = _db.prepare(
        'SELECT id, name, kind, lat, lon, population, admin_id, '
        '${_fame(_db, 'places')} FROM places '
        'WHERE id IN (SELECT value FROM json_each(?))',
      ),
      _streets = _prepareOrNull(
        _db,
        'SELECT id, name, lat, lon, place_id FROM streets '
        'WHERE id IN (SELECT value FROM json_each(?))',
      ),
      _pois = _prepareOrNull(
        _db,
        'SELECT id, name, kind, lat, lon, place_id, ${_fame(_db, 'pois')} '
        'FROM pois WHERE id IN (SELECT value FROM json_each(?))',
      ),
      _aliases = _prepareOrNull(
        _db,
        'SELECT id, ref_id, name FROM aliases '
        'WHERE id IN (SELECT value FROM json_each(?))',
      ),
      _houseNumbers = _prepareOrNull(
        _db,
        'SELECT number, lat, lon FROM house_numbers WHERE street_id = ? '
        'ORDER BY number',
      ),
      _streetNumbers = _prepareOrNull(
        _db,
        'SELECT data FROM street_numbers WHERE street_id = ?',
      );

  /// The tile this file covers, e.g. `E5_N45`.
  final String tile;

  final Database _db;
  final PreparedStatement _match;
  final PreparedStatement _place;
  final PreparedStatement _places;
  final PreparedStatement? _streets;
  final PreparedStatement? _pois;
  final PreparedStatement? _aliases;
  final PreparedStatement? _houseNumbers;
  final PreparedStatement? _streetNumbers;

  PreparedStatement? _vocabRange;
  PreparedStatement? _vocabTerm;
  bool _vocabAttempted = false;

  /// The words of a place and of the place above it, by place id.
  final Map<int, Set<String>> _context = <int, Set<String>>{};

  /// The rows [match] finds, with what scoring them needs.
  ///
  /// Up to [_fetchAll] matches are all read, with one batched query per
  /// table: the ranking, not the index, decides which of them are shown, so
  /// the "Hauptstraße" around the corner is not lost among the others. Between that and [_scanLimit] the [_nearestLimit] rows of each
  /// table nearest to [near] are read instead; beyond it — a word as common
  /// as "street" — the first [_fetchAll].
  ///
  /// A match on an alternative name stands for the row it belongs to and
  /// carries that name along for the scoring.
  List<_Row> candidates(String match, LatLng? near) {
    final ids = <int>[
      for (final row in _match.select(<Object?>[match, _scanLimit + 1]))
        ?_asInt(row['rowid']),
    ];
    if (ids.isEmpty) return const <_Row>[];
    if (ids.length <= _fetchAll) return _hydrate(ids);
    if (near != null && ids.length <= _scanLimit) {
      return _nearestMatches(match, near);
    }
    return _hydrate(ids.sublist(0, _fetchAll));
  }

  List<_Row> _hydrate(List<int> ids) {
    final targets = <int>{...ids};
    final aliasNames = <int, List<String>>{};
    final aliases = _aliases;
    if (aliases != null) {
      for (final row in aliases.select(<Object?>[jsonEncode(ids)])) {
        final id = _asInt(row['id']);
        final ref = _asInt(row['ref_id']);
        final name = row['name']?.toString();
        if (id == null || ref == null || name == null) continue;
        targets
          ..remove(id)
          ..add(ref);
        (aliasNames[ref] ??= <String>[]).add(name);
      }
    }
    final json = jsonEncode(targets.toList());
    final rows = <_Row>[
      ..._read(_places, json, _Table.place),
      ..._read(_streets, json, _Table.street),
      ..._read(_pois, json, _Table.poi),
    ];
    for (final row in rows) {
      final names = aliasNames[row.id];
      if (names != null) row.aliases.addAll(names);
    }
    return rows;
  }

  List<_Row> _read(PreparedStatement? statement, Object? arg, _Table table) {
    if (statement == null) return const <_Row>[];
    return <_Row>[
      for (final row in statement.select(<Object?>[arg])) ?_row(row, table),
    ];
  }

  /// The [_nearestLimit] rows of each table that [match] finds nearest to
  /// [near], measured in SQLite so the thousands of others never become Dart
  /// objects. Alternative names are left out of this path.
  List<_Row> _nearestMatches(String match, LatLng near) {
    final lat = (near.lat * 1e7).round();
    final lon = (near.lon * 1e7).round();
    final squeeze = math.pow(math.cos(near.lat * math.pi / 180), 2);
    const order =
        'ORDER BY (lat - ?1) * (lat - ?1) + (lon - ?2) * (lon - ?2) * ?3 '
        'LIMIT ?4';
    const matching = 'id IN (SELECT rowid FROM search WHERE search MATCH ?5)';
    final args = <Object?>[lat, lon, squeeze, _nearestLimit, match];
    final rows = <_Row>[];
    void read(String sql, _Table table) {
      try {
        for (final row in _db.select(sql, args)) {
          final read = _row(row, table);
          if (read != null) rows.add(read);
        }
      } on SqliteException catch (e) {
        // A file from the first builder has no POI table.
        debugPrint('velorki: gazetteer $tile skipped ${table.name}: $e');
      }
    }

    read(
      'SELECT id, name, kind, lat, lon, population, admin_id, '
      '${_fame(_db, 'places')} FROM places WHERE $matching $order',
      _Table.place,
    );
    read(
      'SELECT id, name, lat, lon, place_id FROM streets WHERE $matching $order',
      _Table.street,
    );
    read(
      'SELECT id, name, kind, lat, lon, place_id, ${_fame(_db, 'pois')} '
      'FROM pois WHERE $matching $order',
      _Table.poi,
    );
    return rows;
  }

  static _Row? _row(Row row, _Table table) {
    final id = _asInt(row['id']);
    final position = _position(row);
    final name = row['name']?.toString();
    if (id == null || position == null || name == null || name.isEmpty) {
      return null;
    }
    return _Row(
      id: id,
      table: table,
      name: name,
      position: position,
      kind: table == _Table.street ? null : row['kind']?.toString(),
      population: table == _Table.place ? _asInt(row['population']) ?? 0 : 0,
      importance: table == _Table.street ? 0 : _asInt(row['importance']) ?? 0,
      placeId: _asInt(
        table == _Table.place ? row['admin_id'] : row['place_id'],
      ),
    );
  }

  /// The settlements [match] finds, by their own name or an alternative one,
  /// with the name that matched.
  List<({String name, LatLng position, int population})> settlements(
    String match,
  ) {
    final kinds = settlementKinds.map((k) => "'$k'").join(', ');
    final found = <({String name, LatLng position, int population})>[];
    void read(String sql) {
      for (final row in _db.select(sql, <Object?>[match])) {
        final position = _position(row);
        final name = row['name']?.toString();
        if (position == null || name == null) continue;
        found.add((
          name: name,
          position: position,
          population: _asInt(row['population']) ?? 0,
        ));
      }
    }

    read(
      'SELECT name, lat, lon, population FROM places '
      'WHERE id IN (SELECT rowid FROM search WHERE search MATCH ?) '
      'AND kind IN ($kinds) LIMIT $_settlementLimit',
    );
    if (_aliases != null) {
      read(
        'SELECT a.name AS name, p.lat AS lat, p.lon AS lon, '
        'p.population AS population FROM aliases a '
        'JOIN places p ON p.id = a.ref_id '
        'WHERE a.id IN (SELECT rowid FROM search WHERE search MATCH ?) '
        'AND p.kind IN ($kinds) LIMIT $_settlementLimit',
      );
    }
    return found;
  }

  /// The folded words of place [placeId] and of the place it belongs to:
  /// what a query word the name lacks may still be answered by.
  Set<String> contextWords(int? placeId) {
    if (placeId == null) return const <String>{};
    final cached = _context[placeId];
    if (cached != null) return cached;
    final words = <String>{};
    var id = placeId;
    for (var level = 0; level < 2; level++) {
      final rows = _place.select(<Object?>[id]);
      if (rows.isEmpty) break;
      final name = rows.first['name']?.toString() ?? '';
      words.addAll(indexWords(name).map(foldForMatch));
      final parent = _asInt(rows.first['admin_id']);
      if (parent == null || parent == id) break;
      id = parent;
    }
    return _context[placeId] = words;
  }

  /// [row] as the list shows it: with the place it lies in, and a street at
  /// the house number [query] carried, when it carried one.
  SearchResult result(_Row row, GazetteerQuery? query) {
    final number = row.table == _Table.street ? query?.number : null;
    final located = number == null
        ? (position: row.position, approximate: false)
        : _locate(row.id, number, row.position);
    return SearchResult(
      name: row.name,
      position: located.position,
      city: _contextName(row.placeId),
      source: SearchSource.local,
      kind: row.table.kind,
      detail: row.kind,
      houseNumber: number == null ? null : query?.houseNumber,
      approximate: located.approximate,
    );
  }

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
    if (_pois == null || kinds.isEmpty) return const <SearchResult>[];
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

  /// The rows of [placeKinds] in `places` and of [poiKinds] in `pois` inside
  /// [box], at most [limit] from each table.
  List<SearchResult> inBox(
    BoundingBox box,
    List<String> placeKinds,
    List<String> poiKinds,
    int limit,
  ) {
    final bounds = <Object?>[
      (box.south * 1e7).round(),
      (box.north * 1e7).round(),
      (box.west * 1e7).round(),
      (box.east * 1e7).round(),
    ];
    final found = <SearchResult>[];
    void query(String table, SearchKind kind, List<String> kinds) {
      if (kinds.isEmpty) return;
      final placeholders = List<String>.filled(kinds.length, '?').join(', ');
      final rows = _db.select(
        'SELECT name, kind, lat, lon FROM $table '
        'WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? '
        'AND kind IN ($placeholders) LIMIT ?',
        <Object?>[...bounds, ...kinds, limit],
      );
      for (final row in rows) {
        final position = _position(row);
        if (position == null) continue;
        found.add(
          SearchResult(
            name: row['name']?.toString() ?? '',
            position: position,
            source: SearchSource.local,
            kind: kind,
            detail: row['kind']?.toString(),
          ),
        );
      }
    }

    query('places', SearchKind.place, placeKinds);
    if (_pois != null) query('pois', SearchKind.poi, poiKinds);
    return found;
  }

  /// The settlement of this file that names a ride starting at [near], or
  /// `null` when none is in range.
  ///
  /// One box wide enough for the furthest-reaching kind, on `idx_places_pos`
  /// — the same shape as [nearest] — and every row measured properly
  /// afterwards against the reach its own kind gets: [citySettlementMaxKm]
  /// for a city or a town, [maxKm] for everything smaller. A city or a town
  /// or a village then beats anything smaller however close that is, and two
  /// of the same standing are decided by distance.
  SearchResult? nearestSettlement(LatLng near, double maxKm) {
    final radius = math.max(maxKm, citySettlementMaxKm) * 1000;
    final dLat = radius / _metersPerDegree;
    final dLon =
        radius /
        (_metersPerDegree *
            math.max(math.cos(near.lat * math.pi / 180).abs(), 0.01));
    final placeholders = List<String>.filled(
      settlementKinds.length,
      '?',
    ).join(', ');
    final rows = _db.select(
      'SELECT name, kind, lat, lon, admin_id FROM places '
      'WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? '
      'AND kind IN ($placeholders) LIMIT ?',
      <Object?>[
        ((near.lat - dLat) * 1e7).round(),
        ((near.lat + dLat) * 1e7).round(),
        ((near.lon - dLon) * 1e7).round(),
        ((near.lon + dLon) * 1e7).round(),
        ...settlementKinds,
        _kindFetchLimit,
      ],
    );
    SearchResult? best;
    var bestRank = 2;
    var bestMeters = double.infinity;
    for (final row in rows) {
      final position = _position(row);
      if (position == null) continue;
      final name = row['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final kind = row['kind']?.toString();
      final reach =
          (kind == 'city' || kind == 'town'
              ? math.max(maxKm, citySettlementMaxKm)
              : maxKm) *
          1000;
      final meters = haversineMeters(near, position);
      if (meters > reach) continue;
      final rank = settlementRank(kind);
      if (rank > bestRank || (rank == bestRank && meters >= bestMeters)) {
        continue;
      }
      bestRank = rank;
      bestMeters = meters;
      best = SearchResult(
        name: name,
        position: position,
        city: _contextName(_asInt(row['admin_id'])),
        source: SearchSource.local,
        kind: SearchKind.place,
        detail: kind,
        distanceMeters: meters,
      );
    }
    return best;
  }

  /// The stored words starting with [prefix], at most [limit], each with the
  /// number of rows it is in; [minLength] and [maxLength] bound their length.
  ///
  /// Read from the file's `vocab` table, or, in a file from before it, from
  /// an `fts5vocab` table in the connection's own `temp` schema, which is
  /// writable even though the file itself is opened read-only: `temp` lives
  /// in this connection, not in the `.gaz`. Either answers a range on the
  /// term from a b-tree, so a prefix costs what its words cost, not what
  /// the whole vocabulary does. Set up the first time a query needs it and
  /// never for a search that spells everything correctly.
  List<({String term, int doc})> terms(
    String prefix, {
    int minLength = 1,
    int maxLength = 1 << 20,
    int limit = 1 << 20,
  }) {
    _vocabulary();
    final statement = _vocabRange;
    if (statement == null || prefix.isEmpty) {
      return const <({String term, int doc})>[];
    }
    final rows = statement.select(<Object?>[
      prefix,
      '$prefix\u{10FFFF}',
      minLength,
      maxLength,
      limit,
    ]);
    return <({String term, int doc})>[
      for (final row in rows)
        if (row['term']?.toString() case final String term)
          (term: term, doc: _asInt(row['doc']) ?? 0),
    ];
  }

  /// How many rows hold the stored word [term]; 0 when none does.
  int termDocs(String term) {
    _vocabulary();
    final statement = _vocabTerm;
    if (statement == null) return 0;
    final rows = statement.select(<Object?>[term]);
    return rows.isEmpty ? 0 : _asInt(rows.first['doc']) ?? 0;
  }

  /// Releases the statements and the database.
  void close() {
    _match.close();
    _place.close();
    _places.close();
    _streets?.close();
    _pois?.close();
    _aliases?.close();
    _houseNumbers?.close();
    _streetNumbers?.close();
    _vocabRange?.close();
    _vocabTerm?.close();
    _db.close();
  }

  void _vocabulary() {
    if (_vocabAttempted) return;
    _vocabAttempted = true;
    try {
      // A builder from 2026-10 on stores the index's words with their row
      // counts in `vocab`. Older files only have what `fts5vocab` computes,
      // which walks each word's whole list of rows to count them: the same
      // answers, but a range that passes "de" or "street" pays for it.
      final stored = _db
          .select(
            "SELECT 1 FROM sqlite_schema WHERE type = 'table' "
            "AND name = 'vocab'",
          )
          .isNotEmpty;
      final table = stored ? 'main.vocab' : 'temp.vocab';
      final docs = stored ? 'docs' : 'doc';
      if (!stored) {
        _db.execute(
          'CREATE VIRTUAL TABLE IF NOT EXISTS temp.vocab '
          "USING fts5vocab(main, 'search', 'row');",
        );
      }
      _vocabRange = _db.prepare(
        'SELECT term, $docs AS doc FROM $table WHERE term >= ? AND term < ? '
        'AND length(term) BETWEEN ? AND ? LIMIT ?',
      );
      _vocabTerm = _db.prepare(
        'SELECT $docs AS doc FROM $table WHERE term = ?',
      );
    } on Object catch (e) {
      // An old SQLite without fts5vocab, or a file whose index cannot be
      // read: spelling help is the one thing a search can do without.
      debugPrint('velorki: $tile.gaz has no vocabulary: $e');
    }
  }

  /// Where number [number] of street [streetId] is.
  ///
  /// A file from 2026-10 on keeps each side of the street in
  /// `street_numbers`, thinned to 20 m ([locateOnStreet]). An older one keeps
  /// anchors in `house_numbers`: the lowest number, the highest and every
  /// twentieth in between. An anchor for the number itself is the exact
  /// spot; between two anchors the position is interpolated by number;
  /// beyond either end it is the end anchor. With nothing stored it is
  /// [fallback], the street itself. Whatever is not known to within a few
  /// metres is approximate, and the row says so.
  ({LatLng position, bool approximate}) _locate(
    int streetId,
    int number,
    LatLng fallback,
  ) {
    final sides = _streetNumbers;
    if (sides != null) {
      final rows = sides.select(<Object?>[streetId]);
      final data = rows.isEmpty ? null : rows.first['data'];
      if (data is Uint8List) {
        final decoded = decodeStreetNumbers(data);
        final located = decoded == null
            ? null
            : locateOnStreet(decoded, number);
        if (located != null) return located;
      }
      return (position: fallback, approximate: true);
    }
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

  /// The `importance` column of [table], or a 0 in its place for a file
  /// built before it.
  static String _fame(Database db, String table) {
    final columns = db.select('PRAGMA table_info($table)');
    return columns.any((c) => c['name'] == 'importance')
        ? 'importance'
        : '0 AS importance';
  }

  static PreparedStatement? _prepareOrNull(Database db, String sql) {
    // A file from an older builder has no aliases and house_numbers instead
    // of street_numbers, a newer one the other way round: a table that is
    // simply not there is no news. One that is there and still cannot be
    // read must not take the places with it.
    final table = RegExp(r'\bFROM (\w+)').firstMatch(sql)?[1];
    if (table != null &&
        db.select(
          "SELECT 1 FROM sqlite_schema WHERE type = 'table' AND name = ?",
          <Object?>[table],
        ).isEmpty) {
      return null;
    }
    try {
      return db.prepare(sql);
    } on Object catch (e) {
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
}

/// Which table a row comes from.
enum _Table {
  place(SearchKind.place),
  street(SearchKind.street),
  poi(SearchKind.poi);

  const _Table(this.kind);

  /// What the list calls a row of this table.
  final SearchKind kind;
}

/// One row a match expression found, before it is scored.
class _Row {
  _Row({
    required this.id,
    required this.table,
    required this.name,
    required this.position,
    required this.kind,
    required this.population,
    required this.importance,
    required this.placeId,
  });

  final int id;
  final _Table table;
  final String name;
  final LatLng position;

  /// The place or POI kind; `null` for a street.
  final String? kind;
  final int population;

  /// How widely known the place or POI is: the languages its name is given
  /// in, and 5 more for a Wikidata or Wikipedia link (`importance` in a file
  /// from 2026-10 on; 0 otherwise).
  final int importance;

  /// The place a street or a POI lies in, or the place a place belongs to.
  final int? placeId;

  /// The alternative names that matched, for the scoring.
  final List<String> aliases = <String>[];

  /// The Settings → Search group this row belongs to.
  SearchGroup? get group => switch (table) {
    _Table.place => SearchGroup.places,
    _Table.street => SearchGroup.streets,
    _Table.poi => searchGroupOfPoiKind[kind],
  };
}

/// A scored row and the file it came from.
class _Scored {
  const _Scored(this.file, this.row, this.match, this.score, this.km);

  final _GazetteerFile file;
  final _Row row;
  final NameMatch match;
  final double score;

  /// The way from the pool's origin, in kilometres; 0 without one.
  final double km;
}

/// Every row one lookup found, scored once, ranked at the end.
///
/// The score is how well the name answers the query ([matchName]) less a
/// cost for the way there and plus a little for a bigger place: the match
/// comes first, a near row beats a far one of the same match, and a city
/// reaches further than a hamlet. A query with a house number lifts the
/// streets ([_addressBonus]); the rider's group order in Settings → Search
/// breaks what is left ([_groupStep]).
class _Pool {
  _Pool({required this.query, required this.near, required this.preferences})
    : words = <String>[
        for (final word in query?.tokens ?? const <String>[])
          foldForMatch(word),
      ];

  final GazetteerQuery? query;
  final LatLng? near;
  final SearchPreferences preferences;

  /// Where distances are measured from.
  LatLng? get origin => near;

  /// The settlement the query named, if it named one. A row that lies in it
  /// — its place answered a query word — is measured from there instead of
  /// from [near]: "hauptstrasse berlin" typed in Munich is about Berlin.
  LatLng? get namedPlace => _namedPlace;
  set namedPlace(LatLng? place) {
    _namedPlace = place;
    for (final entry in _rows.entries) {
      final scored = entry.value;
      if (scored == null || !scored.match.usedContext) continue;
      _rows[entry.key] = _scoredRow(scored.file, scored.row, scored.match);
    }
  }

  LatLng? _namedPlace;

  /// The query's words, folded the way names are.
  final List<String> words;

  late final bool _customOrder = !listEquals(
    preferences.order,
    SearchGroup.values,
  );

  /// The match expressions already run, so the second look skips them.
  final Set<String> tried = <String>{};

  final Map<String, _Scored?> _rows = <String, _Scored?>{};

  /// Scores [rows] of [file]; a row already scored is not scored again.
  void addAll(_GazetteerFile file, List<_Row> rows) {
    for (final row in rows) {
      final key = '${file.tile}#${row.id}';
      if (_rows.containsKey(key)) continue;
      if (!preferences.isEnabled(row.group)) {
        _rows[key] = null;
        continue;
      }
      var match = _match(row);
      if (match.unmatched.isNotEmpty && row.placeId != null) {
        final context = file.contextWords(row.placeId);
        if (match.unmatched.any((i) => context.contains(words[i]))) {
          match = _match(row, context: context);
        }
      }
      if (match.quality < _minQuality) {
        _rows[key] = null;
        continue;
      }
      _rows[key] = _scoredRow(file, row, match);
    }
  }

  /// What [matchName] made of a name, for the names that come back again
  /// and again ("Rue de Paris", "Main Street") without a place to help.
  final Map<String, NameMatch> _byName = <String, NameMatch>{};

  NameMatch _match(_Row row, {Set<String> context = const <String>{}}) {
    if (context.isEmpty && row.aliases.isEmpty) {
      return _byName[row.name] ??= matchName(words, _nameWords(row.name));
    }
    var best = matchName(words, _nameWords(row.name), context: context);
    for (final alias in row.aliases) {
      // The row is shown under its own name: an alternative one that
      // matches is a little less of a match than the name on the screen.
      final match = matchName(
        words,
        _nameWords(alias),
        context: context,
      ).scaled(_aliasShare);
      if (match.quality > best.quality) best = match;
    }
    return best;
  }

  static List<String> _nameWords(String name) =>
      indexWords(name).map(foldForMatch).toList();

  _Scored _scoredRow(_GazetteerFile file, _Row row, NameMatch match) {
    // The declaration order of the groups is no one's preference: it only
    // breaks an exact tie. An order the rider chose weighs [_groupStep] a
    // step.
    final step = _customOrder ? _groupStep : _tieStep;
    var score = match.quality - preferences.rankOf(row.group) * step;
    final from = match.usedContext ? _namedPlace ?? origin : origin;
    var km = 0.0;
    if (from != null) {
      km = haversineMeters(from, row.position) / 1000;
      score -= _distanceWeight * math.log(1 + km) / math.ln2;
    }
    if (row.table == _Table.place) {
      score +=
          (_placeWeight[row.kind] ?? 0) +
          math.min(
            _populationCap,
            _populationWeight * math.log(1 + row.population) / math.ln10,
          );
    }
    final fame = row.importance - _fameFloor;
    if (fame > 0) {
      score += math.min(_fameCap, _fameWeight * math.log(1 + fame) / math.ln2);
    }
    if (row.table == _Table.street && query?.houseNumber != null) {
      score += _addressBonus;
    }
    return _Scored(file, row, match, score, km);
  }

  /// Whether the first look answered too little to stop at: no row matches
  /// the query well, or none within [_nearbyKm] of [origin] does — the
  /// "Mariahilfer Straße" around the corner may be written in two words
  /// where the one 300 km away is written in one.
  bool wantsSecondLook() => !_rows.values.any(
    (scored) =>
        scored != null &&
        scored.match.quality >= _goodQuality &&
        (origin == null || scored.km <= _nearbyKm),
  );

  /// Whether some row holds every word of the query exactly as typed.
  bool get hasComplete =>
      _rows.values.any((scored) => scored != null && scored.match.complete);

  /// Whether even the guessed spellings answered nothing decently, so words
  /// have to be left out. A query with a house number is after a street, so
  /// a station named after the street and its neighbourhood does not count.
  bool wantsRelaxing() {
    final address = query?.houseNumber != null;
    return !_rows.values.any(
      (scored) =>
          scored != null &&
          scored.match.quality >= _decentQuality &&
          (!address || scored.row.table == _Table.street),
    );
  }

  /// Every scored row, best first.
  List<_Scored> ranked() {
    final all = <_Scored>[for (final scored in _rows.values) ?scored];
    all.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final length = a.row.name.length.compareTo(b.row.name.length);
      if (length != 0) return length;
      return a.row.id.compareTo(b.row.id);
    });
    return all;
  }

  /// The query as the best row read it, when that row only matched through a
  /// guessed word; `null` when it matched as typed.
  String? correctedText() {
    final best = ranked().firstOrNull;
    if (best == null || best.match.corrected.isEmpty) return null;
    return <String>[
      for (var i = 0; i < words.length; i++)
        best.match.corrected[i] ?? words[i],
    ].join(' ');
  }
}

/// Below this a row is not worth showing at all.
const double _minQuality = 0.45;

/// A row this good, found with every word or a guess at it, means no word
/// has to be left out.
const double _decentQuality = 0.75;

/// A row this good answers the query: the first look may stop.
const double _goodQuality = 0.9;

/// What doubling the way to a row costs: 1 km 0.06, 10 km 0.21, 100 km 0.4.
const double _distanceWeight = 0.06;

/// What a street is worth on top when the query carries a house number.
const double _addressBonus = 0.25;

/// How far a good row may be from the origin and still end the first look.
const double _nearbyKm = 30;

/// What a match on an alternative name is worth against the row's own name.
const double _aliasShare = 0.97;

/// What each step down the rider's group order costs.
const double _groupStep = 0.05;

/// What each step down the default group order costs: a tie-breaker only.
const double _tieStep = 0.001;

/// What a place is worth for its kind alone.
const Map<String, double> _placeWeight = <String, double>{
  'city': 0.10,
  'town': 0.07,
  'village': 0.04,
  'suburb': 0.03,
  'island': 0.03,
  'neighbourhood': 0.02,
  'hamlet': 0.01,
};

/// Importance up to this is no fame: a Wikidata link alone is worth 5, and
/// around Paris every bike rental station and many hotels have one.
const int _fameFloor = 5;

/// What a row is worth per doubling of its importance above [_fameFloor], up
/// to [_fameCap]: Notre-Dame de Paris (22) 0.17, the Eiffel Tower (56) 0.23.
const double _fameWeight = 0.04;
const double _fameCap = 0.25;

/// What a place is worth per tenfold population, up to [_populationCap].
const double _populationWeight = 0.015;
const double _populationCap = 0.1;

/// How long a closed worker has to close its files before it is killed.
const Duration _workerExitGrace = Duration(seconds: 2);

/// What the calling isolate asks the worker.
enum _Ask { lookup, inBox, nearestSettlement, refresh, close }

/// How the worker answered.
sealed class _Answer {
  const _Answer();
}

/// The answer, whatever it is.
final class _Answered extends _Answer {
  const _Answered(this.value);

  final Object? value;
}

/// A lookup the worker skipped because a newer one was already waiting.
final class _Superseded extends _Answer {
  const _Superseded();
}

/// A question the worker could not answer; the caller answers it itself.
final class _Failed extends _Answer {
  const _Failed(this.error);

  final String error;
}

/// A [GazetteerStore] on its own isolate, asked through ports.
///
/// The worker answers in the order it is asked, with one exception: a lookup
/// with a newer lookup already waiting behind it is skipped, so a rider who
/// types faster than a slow phone searches never waits for the words in
/// between.
class _GazetteerWorker {
  _GazetteerWorker._(this._isolate, this._send, this._replies);

  /// Starts the worker over [directory] and waits for its port.
  ///
  /// One [ReceivePort] carries everything the worker sends: its own port
  /// first, then the answers, each matched to its question by id.
  static Future<_GazetteerWorker> spawn(Directory directory) async {
    final replies = ReceivePort();
    final port = Completer<SendPort>();
    late final _GazetteerWorker worker;
    replies.listen((message) {
      if (!port.isCompleted) {
        if (message is SendPort) port.complete(message);
        return;
      }
      worker._onReply(message);
    });
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(_run, (
        replies.sendPort,
        directory.path,
      ), debugName: 'gazetteer');
    } on Object {
      replies.close();
      rethrow;
    }
    final send = await port.future;
    return worker = _GazetteerWorker._(isolate, send, replies);
  }

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _replies;
  bool _closed = false;
  final Map<int, Completer<_Answer>> _waiting = <int, Completer<_Answer>>{};
  int _next = 0;

  Future<_Answer> ask(_Ask what, Object? args) {
    if (_closed) return Future.value(const _Failed('closed'));
    final id = _next++;
    final answer = Completer<_Answer>();
    _waiting[id] = answer;
    _send.send((id, what, args));
    return answer.future;
  }

  void _onReply(Object? message) {
    if (message is! (int, _Answer)) return;
    final (id, answer) = message;
    _waiting.remove(id)?.complete(answer);
    if (answer is _Failed) {
      debugPrint('velorki: gazetteer worker failed: ${answer.error}');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _send.send((-1, _Ask.close, null));
    for (final waiting in _waiting.values) {
      waiting.complete(const _Failed('closed'));
    }
    _waiting.clear();
    _replies.close();
    // The worker closes its files and exits; this is only for a worker that
    // is stuck in a query.
    Timer(_workerExitGrace, _isolate.kill);
  }

  /// The worker isolate: a store of its own over the same directory.
  static Future<void> _run((SendPort, String) start) async {
    final (reply, path) = start;
    final inbox = ReceivePort();
    reply.send(inbox.sendPort);
    final store = GazetteerStore(Directory(path));
    await store.refresh();

    final queue = Queue<(int, _Ask, Object?)>();
    var draining = false;
    Future<void> drain() async {
      draining = true;
      while (queue.isNotEmpty) {
        final (id, what, args) = queue.removeFirst();
        if (what == _Ask.close) {
          store.close();
          inbox.close();
          Isolate.exit();
        }
        if (what == _Ask.lookup &&
            queue.any((waiting) => waiting.$2 == _Ask.lookup)) {
          reply.send((id, const _Superseded()));
          continue;
        }
        try {
          reply.send((id, _Answered(await _answer(store, what, args))));
        } on Object catch (e) {
          reply.send((id, _Failed('$e')));
        }
        // Let the questions that came in meanwhile reach the queue, so the
        // next lookup can see whether a newer one is behind it.
        await Future<void>.delayed(Duration.zero);
      }
      draining = false;
    }

    await for (final message in inbox) {
      if (message is! (int, _Ask, Object?)) continue;
      queue.add(message);
      if (!draining) unawaited(drain());
    }
  }

  static Future<Object?> _answer(
    GazetteerStore store,
    _Ask what,
    Object? args,
  ) async {
    switch (what) {
      case _Ask.lookup:
        final (
          text,
          near,
          limit,
          preferences,
          keywords,
        ) = args!
            as (String, LatLng?, int, SearchPreferences, Map<String, String>);
        return store._lookupHere(
          text,
          near: near,
          limit: limit,
          preferences: preferences,
          keywords: keywords,
        );
      case _Ask.inBox:
        final (box, placeKinds, poiKinds, limit) =
            args! as (BoundingBox, List<String>, List<String>, int);
        return store._inBoxHere(box, placeKinds, poiKinds, limit);
      case _Ask.nearestSettlement:
        final (point, maxKm) = args! as (LatLng, double);
        return store._nearestSettlementHere(point, maxKm);
      case _Ask.refresh:
        await store.refresh();
        return null;
      case _Ask.close:
        return null;
    }
  }
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
  final store = GazetteerStore(directory, background: true);
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
