import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/links/location_link.dart';
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
    this.searching = false,
    this.choosingSource = false,
  });

  /// The results, already ranked.
  final List<SearchResult> results;

  /// The text they answer.
  final String query;

  /// Whether they came off this device or off the network.
  final SearchSource source;

  /// Whether a geocoder is configured, so "Search online" can be offered.
  final bool canSearchOnline;

  /// Whether this query could be answered on the device: the area under the
  /// map centre has a gazetteer, or, over an area that has none, other areas
  /// do. False when nothing is downloaded.
  final bool offlineAvailableHere;

  /// Whether nothing was searched yet because the area under the map centre
  /// is not downloaded while other areas are: the list asks whether to
  /// search online or the downloaded areas, and sends nothing off the phone
  /// until the rider says.
  final bool choosingSource;

  /// What the on-device index was searched for when nothing matched [query]
  /// and the spelling was guessed at; `null` when [query] answered by itself.
  /// The list says so in a line above the results.
  final String? correctedQuery;

  /// Whether a newer search is running and these results still answer the
  /// text before it: the list keeps them on screen under a thin progress bar
  /// instead of blanking on every keystroke.
  final bool searching;

  /// The same results, marked as waiting for a newer search.
  PlaceSearchState whileSearching() => PlaceSearchState(
    results: results,
    query: query,
    source: source,
    canSearchOnline: canSearchOnline,
    offlineAvailableHere: offlineAvailableHere,
    correctedQuery: correctedQuery,
    searching: true,
    choosingSource: choosingSource,
  );

  @override
  String toString() =>
      'PlaceSearchState(${results.length} ${source.name} results for '
      '"$query"${correctedQuery == null ? '' : ' (corrected to '
                '"$correctedQuery")'}, online available: $canSearchOnline, '
      'offline available here: $offlineAvailableHere'
      '${searching ? ', searching' : ''}'
      '${choosingSource ? ', choosing the source' : ''})';
}

/// The place search behind the planner's search field.
///
/// What answers depends on the area under the map centre, not on what the
/// device happens to hold: a rider looking at a region whose `<TILE>.gaz`
/// gazetteer is downloaded searches it — instant, free and working with no
/// signal — with Photon one tap away as the last row of the list
/// ([searchOnline]). Over an area that is not downloaded, a device with other
/// areas asks first: online, or the downloaded areas ([searchOffline]); the
/// pick holds until the search is cleared. A device with nothing downloaded
/// goes straight to Photon. Either way the list offers the download for the
/// area on screen.
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

  /// Where the rider asked to search an area that is not downloaded:
  /// `null` until they pick, then true for online, false for the device.
  bool? _online;

  /// Whether the device has a gazetteer for anywhere at all.
  bool get _anyDownloaded => _store?.hasTiles ?? false;

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
    _showSearching();
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
    if (!_coveredHere) _online = true;
    _debounce?.cancel();
    _pending?.cancel('superseded');
    _pending = null;
    _showSearching();
    await _searchOnline(text, lang: lang, bias: bias);
  }

  /// Answers the text the field is showing from the device again.
  ///
  /// The way back from an online list to the local one, offered as the last
  /// row whenever the results came off the network and the device has a
  /// gazetteer; over an area that is not downloaded, every downloaded area is
  /// searched, nearest first. Does nothing with none downloaded.
  Future<void> searchOffline({
    LatLng? bias,
    Map<String, String> keywords = const <String, String>{},
  }) async {
    final text = _query;
    final store = _store;
    if (text.length < searchMinChars) return;
    if (store == null || !store.hasTiles) return;
    _debounce?.cancel();
    _pending?.cancel('superseded');
    _pending = null;
    if (bias != null && store.covers(bias)) {
      _coveredHere = true;
    } else {
      _online = false;
    }
    _showSearching();
    await _searchLocal(store, text, near: bias, keywords: keywords);
  }

  /// Marks the list as waiting for a search: the results on screen stay,
  /// under a progress bar, until the new ones replace them; with none to keep
  /// (the first search, or after an error) the list is only the bar.
  void _showSearching() {
    final shown = state.value;
    state = shown != null && shown.results.isNotEmpty && !state.hasError
        ? AsyncData<PlaceSearchState>(shown.whileSearching())
        : const AsyncLoading<PlaceSearchState>();
  }

  /// Empties the result list and drops any pending request.
  void clear() {
    _debounce?.cancel();
    _pending?.cancel('cleared');
    _pending = null;
    _query = '';
    _online = null;
    state = AsyncData<PlaceSearchState>(_emptyState());
  }

  Future<void> _search(
    String text, {
    String? lang,
    LatLng? bias,
    Map<String, String> keywords = const <String, String>{},
  }) async {
    // Coordinates pasted from a map app ("40.71747 -73.94840",
    // "40,71747° N, 73,94840° W") are the place itself: nothing to look up.
    final pasted = parseLocationLink(text)?.position;
    if (pasted != null) {
      state = AsyncData<PlaceSearchState>(
        PlaceSearchState(
          results: <SearchResult>[
            SearchResult(
              name:
                  '${pasted.lat.toStringAsFixed(5)}, '
                  '${pasted.lon.toStringAsFixed(5)}',
              position: pasted,
              source: SearchSource.local,
            ),
          ],
          query: text,
          source: SearchSource.local,
          canSearchOnline: _hasGeocoder,
          offlineAvailableHere: _covers(bias),
        ),
      );
      return;
    }
    // Only the store that is already open is consulted: it is opened while the
    // app starts, long before anyone has typed three characters, and a search
    // must never wait on the file system.
    final store = _store;
    if (store != null && bias != null && store.covers(bias)) {
      await _searchLocal(store, text, near: bias, keywords: keywords);
      return;
    }
    // Not downloaded here, but somewhere: the device can answer too, so
    // nothing goes online until the rider says so, and with no online
    // search the device is the answer.
    if (store != null && bias != null && _anyDownloaded) {
      if (_online == false || !_hasGeocoder) {
        await _searchLocal(store, text, near: bias, keywords: keywords);
        return;
      }
      if (_online == null) {
        state = AsyncData<PlaceSearchState>(
          PlaceSearchState(
            query: text,
            canSearchOnline: true,
            offlineAvailableHere: true,
            choosingSource: true,
          ),
        );
        return;
      }
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
        const SearchException(
          'no search server configured',
          failure: SearchFailure.unconfigured,
        ),
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
          offlineAvailableHere: _coveredHere || _anyDownloaded,
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
