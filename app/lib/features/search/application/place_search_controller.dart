import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../data/gazetteer_store.dart';
import '../data/photon_client.dart';
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
  });

  /// The results, already ranked.
  final List<SearchResult> results;

  /// The text they answer.
  final String query;

  /// Whether they came off this device or off the network.
  final SearchSource source;

  /// Whether a geocoder is configured, so "Search online" can be offered.
  final bool canSearchOnline;

  @override
  String toString() =>
      'PlaceSearchState(${results.length} ${source.name} results for '
      '"$query", online available: $canSearchOnline)';
}

/// The place search behind the planner's search field.
///
/// A rider who downloaded routing tiles searches the `<TILE>.gaz` gazetteers
/// next to them: instant, free and working with no signal. Photon is then one
/// tap away, as the last row of the result list ([searchOnline]). Without a
/// single gazetteer on the device the field goes straight to Photon, which is
/// what it always did.
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
  void query(String text, {String? lang, LatLng? bias}) {
    _debounce?.cancel();
    _pending?.cancel('superseded');
    _pending = null;
    final trimmed = text.trim();
    _query = trimmed;
    if (trimmed.length < searchMinChars) {
      state = AsyncData<PlaceSearchState>(_emptyState(query: trimmed));
      return;
    }
    state = const AsyncLoading<PlaceSearchState>();
    _debounce = Timer(
      _store?.hasTiles ?? false ? searchLocalDebounce : searchDebounce,
      () => unawaited(_search(trimmed, lang: lang, bias: bias)),
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

  /// Empties the result list and drops any pending request.
  void clear() {
    _debounce?.cancel();
    _pending?.cancel('cleared');
    _pending = null;
    _query = '';
    state = AsyncData<PlaceSearchState>(_emptyState());
  }

  Future<void> _search(String text, {String? lang, LatLng? bias}) async {
    // Only the store that is already open is consulted: it is opened while the
    // app starts, long before anyone has typed three characters, and a search
    // must never wait on the file system.
    final store = _store;
    if (store != null && store.hasTiles) {
      await _searchLocal(store, text, near: bias);
      return;
    }
    await _searchOnline(text, lang: lang, bias: bias);
  }

  Future<void> _searchLocal(
    GazetteerStore store,
    String text, {
    LatLng? near,
  }) async {
    final results = await store.search(text, near: near);
    if (_disposed || _query != text) return;
    state = AsyncData<PlaceSearchState>(
      PlaceSearchState(
        results: results,
        query: text,
        source: SearchSource.local,
        canSearchOnline: _hasGeocoder,
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
        PlaceSearchState(results: results, query: text, canSearchOnline: true),
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

  PlaceSearchState _emptyState({String query = ''}) => PlaceSearchState(
    query: query,
    source: _store?.hasTiles ?? false
        ? SearchSource.local
        : SearchSource.online,
    canSearchOnline: _hasGeocoder,
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
