import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../data/gazetteer_store.dart';
import '../data/photon_client.dart';
import '../data/search_preferences_controller.dart';
import '../domain/search_result.dart';

part 'place_search_controller.g.dart';

/// How long the search field waits after the last keystroke, online.
const Duration searchDebounce = Duration(milliseconds: 250);

/// The same wait for the on-device index, which answers in milliseconds and
/// costs nothing per query.
const Duration searchLocalDebounce = Duration(milliseconds: 100);

/// Below this many characters nothing is searched for.
const int searchMinChars = gazetteerMinChars;

/// What the search field is showing.
@immutable
class PlaceSearchState {
  /// Creates the state.
  const PlaceSearchState({
    this.results = const <SearchResult>[],
    this.query = '',
    this.source = SearchSource.online,
    this.canSearchOnline = false,
    this.offlineAvailableHere = false,
    this.correctedQuery,
  });

  /// The results, already ranked.
  final List<SearchResult> results;

  /// The text they answer.
  final String query;

  /// Whether they came off this device or off the network.
  final SearchSource source;

  /// Whether a geocoder is configured, so "Search online" can be offered.
  final bool canSearchOnline;

  /// Whether the area under the map centre has a gazetteer, so this query
  /// could be answered on the device.
  ///
  /// False when there is no map centre to judge by, when nothing is
  /// downloaded, and when what is downloaded is somewhere else. The list then
  /// offers the download for the area on screen instead of "Show offline
  /// results".
  final bool offlineAvailableHere;

  /// What the on-device index was searched for when nothing matched [query]
  /// and the spelling was guessed at; `null` when [query] answered by itself.
  /// The list says so in a line above the results.
  final String? correctedQuery;

  @override
  String toString() =>
      'PlaceSearchState(${results.length} ${source.name} results for '
      '"$query"${correctedQuery == null ? '' : ' (corrected to '
                '"$correctedQuery")'}, online available: $canSearchOnline, '
      'offline available here: $offlineAvailableHere)';
}

/// The place search behind the planner's search field.
///
/// What answers depends on the area under the map centre, not on what the
/// device happens to hold: a rider looking at a region whose `<TILE>.gaz`
/// gazetteer is downloaded searches it — instant, free and working with no
/// signal — with Photon one tap away as the last row of the list
/// ([searchOnline]). Anywhere else the field goes straight to Photon, exactly
/// as a device with no gazetteer at all does, and the list offers the download
/// for the area on screen. [searchOffline] is the way back from an online list
/// to the local one, where there is one.
///
/// Debounced, never fired below [searchMinChars] characters, and every
/// keystroke cancels the request that is still in flight.
@riverpod
class PlaceSearch extends _$PlaceSearch {
  Timer? _debounce;
  CancelToken? _pending;
  GazetteerStore? _store;
  String _query = '';
  bool _disposed = false;

  /// Whether the last query's map centre had a gazetteer.
  bool _coveredHere = false;

  @override
  AsyncValue<PlaceSearchState> build() {
    // Warmed up here so the first keystroke already knows whether this device
    // searches locally, and which debounce that means.
    unawaited(_remember(ref.watch(gazetteerStoreProvider.future)));
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      _pending?.cancel('search disposed');
    });
    return AsyncData<PlaceSearchState>(_emptyState());
  }

  /// Searches for [text], biased towards [bias] when the map centre is known.
  ///
  /// [bias] is also what decides where the answer comes from: only a centre
  /// whose tile has a gazetteer is searched on the device, everything else
  /// goes to Photon.
  ///
  /// [keywords] is the localised kind table — "drinking water" → the
  /// `drinking_water` kind, in the language the app is running in — which only
  /// the widget can build, because only the widget has the localisations. With
  /// it and [bias], typing the name of a kind answers with the nearest ones of
  /// that kind before the name matches.
  void query(
    String text, {
    String? lang,
    LatLng? bias,
    Map<String, String> keywords = const <String, String>{},
  }) {
    _debounce?.cancel();
    _pending?.cancel('superseded');
    _pending = null;
    final trimmed = text.trim();
    _query = trimmed;
    _coveredHere = _covers(bias);
    if (trimmed.length < searchMinChars) {
      state = AsyncData<PlaceSearchState>(_emptyState(query: trimmed));
      return;
    }
    state = const AsyncLoading<PlaceSearchState>();
    _debounce = Timer(
      _coveredHere ? searchLocalDebounce : searchDebounce,
      () => unawaited(
        _search(trimmed, lang: lang, bias: bias, keywords: keywords),
      ),
    );
  }

  /// Runs the geocoder for the text the field is showing.
  ///
  /// The last row of a local result list; the results it brings back replace
  /// the local ones and are marked [SearchSource.online], so the row is gone
  /// until the next keystroke.
  Future<void> searchOnline({String? lang, LatLng? bias}) async {
    final text = _query;
    if (text.length < searchMinChars) return;
    _debounce?.cancel();
    _pending?.cancel('superseded');
    _pending = null;
    state = const AsyncLoading<PlaceSearchState>();
    await _searchOnline(text, lang: lang, bias: bias);
  }

  /// Answers the text the field is showing from the device again.
  ///
  /// The way back from an online list to the local one, offered as the last
  /// row whenever the results came off the network and the area under [bias]
  /// has a gazetteer. Does nothing when it has none.
  Future<void> searchOffline({
    LatLng? bias,
    Map<String, String> keywords = const <String, String>{},
  }) async {
    final text = _query;
    final store = _store;
    if (text.length < searchMinChars) return;
    if (store == null || bias == null || !store.covers(bias)) return;
    _debounce?.cancel();
    _pending?.cancel('superseded');
    _pending = null;
    _coveredHere = true;
    state = const AsyncLoading<PlaceSearchState>();
    await _searchLocal(store, text, near: bias, keywords: keywords);
  }

  /// Empties the result list and drops any pending request.
  void clear() {
    _debounce?.cancel();
    _pending?.cancel('cleared');
    _pending = null;
    _query = '';
    state = AsyncData<PlaceSearchState>(_emptyState());
  }

  Future<void> _search(
    String text, {
    String? lang,
    LatLng? bias,
    Map<String, String> keywords = const <String, String>{},
  }) async {
    // Only the store that is already open is consulted: it is opened while the
    // app starts, long before anyone has typed three characters, and a search
    // must never wait on the file system.
    final store = _store;
    if (store != null && bias != null && store.covers(bias)) {
      await _searchLocal(store, text, near: bias, keywords: keywords);
      return;
    }
    await _searchOnline(text, lang: lang, bias: bias);
  }

  Future<void> _searchLocal(
    GazetteerStore store,
    String text, {
    LatLng? near,
    Map<String, String> keywords = const <String, String>{},
  }) async {
    // Read, not watched: a change to the groups takes effect on the next
    // keystroke, and rebuilding the controller would throw away what is on
    // the screen.
    final found = await store.lookup(
      text,
      near: near,
      preferences: ref.read(searchPreferencesProvider),
      keywords: keywords,
    );
    if (_disposed || _query != text) return;
    state = AsyncData<PlaceSearchState>(
      PlaceSearchState(
        results: found.results,
        query: text,
        source: SearchSource.local,
        canSearchOnline: _hasGeocoder,
        offlineAvailableHere: true,
        correctedQuery: found.correctedQuery,
      ),
    );
  }

  Future<void> _searchOnline(String text, {String? lang, LatLng? bias}) async {
    final client = ref.read(photonClientProvider);
    if (client == null) {
      state = AsyncError<PlaceSearchState>(
        const SearchException('no search server configured'),
        StackTrace.current,
      );
      return;
    }
    final token = CancelToken();
    _pending = token;
    try {
      final results = await client.search(
        text,
        lang: lang,
        bias: bias,
        cancelToken: token,
      );
      if (_disposed || token.isCancelled) return;
      state = AsyncData<PlaceSearchState>(
        PlaceSearchState(
          results: results,
          query: text,
          canSearchOnline: true,
          offlineAvailableHere: _coveredHere,
        ),
      );
    } on SearchException catch (e, st) {
      if (_disposed || token.isCancelled) return;
      state = AsyncError<PlaceSearchState>(e, st);
    } catch (e, st) {
      if (_disposed || token.isCancelled) return;
      state = AsyncError<PlaceSearchState>(e, st);
    } finally {
      if (identical(_pending, token)) _pending = null;
    }
  }

  bool get _hasGeocoder => ref.read(photonClientProvider) != null;

  /// Whether the area under [bias] can be searched on this device.
  bool _covers(LatLng? bias) {
    final store = _store;
    return bias != null && store != null && store.covers(bias);
  }

  PlaceSearchState _emptyState({String query = ''}) => PlaceSearchState(
    query: query,
    source: _coveredHere ? SearchSource.local : SearchSource.online,
    canSearchOnline: _hasGeocoder,
    offlineAvailableHere: _coveredHere,
  );

  /// Remembers the gazetteer store as soon as it is open.
  ///
  /// A device without an app support directory, or with a broken one, must
  /// still search: the failure is logged and the field stays online.
  Future<void> _remember(Future<GazetteerStore> pending) async {
    try {
      final store = await pending;
      if (!_disposed) _store = store;
    } on Object catch (e) {
      debugPrint('velorki: offline place search unavailable: $e');
    }
  }
}
