import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../data/photon_client.dart';
import '../domain/search_result.dart';

part 'place_search_controller.g.dart';

/// How long the search field waits after the last keystroke.
const Duration searchDebounce = Duration(milliseconds: 250);

/// Below this many characters nothing is sent to the geocoder.
const int searchMinChars = 3;

/// The place search behind the planner's search field.
///
/// Debounced [searchDebounce], never fired below [searchMinChars] characters,
/// and every keystroke cancels the request that is still in flight.
@riverpod
class PlaceSearch extends _$PlaceSearch {
  Timer? _debounce;
  CancelToken? _pending;
  bool _disposed = false;

  @override
  AsyncValue<List<SearchResult>> build() {
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      _pending?.cancel('search disposed');
    });
    return const AsyncData<List<SearchResult>>(<SearchResult>[]);
  }

  /// Searches for [text], biased towards [bias] when the map centre is known.
  void query(String text, {String? lang, LatLng? bias}) {
    _debounce?.cancel();
    _pending?.cancel('superseded');
    _pending = null;
    final trimmed = text.trim();
    if (trimmed.length < searchMinChars) {
      state = const AsyncData<List<SearchResult>>(<SearchResult>[]);
      return;
    }
    state = const AsyncLoading<List<SearchResult>>();
    _debounce = Timer(
      searchDebounce,
      () => unawaited(_search(trimmed, lang: lang, bias: bias)),
    );
  }

  /// Empties the result list and drops any pending request.
  void clear() {
    _debounce?.cancel();
    _pending?.cancel('cleared');
    _pending = null;
    state = const AsyncData<List<SearchResult>>(<SearchResult>[]);
  }

  Future<void> _search(String text, {String? lang, LatLng? bias}) async {
    final client = ref.read(photonClientProvider);
    if (client == null) {
      state = AsyncError<List<SearchResult>>(
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
      state = AsyncData<List<SearchResult>>(results);
    } on SearchException catch (e, st) {
      if (_disposed || token.isCancelled) return;
      state = AsyncError<List<SearchResult>>(e, st);
    } catch (e, st) {
      if (_disposed || token.isCancelled) return;
      state = AsyncError<List<SearchResult>>(e, st);
    } finally {
      if (identical(_pending, token)) _pending = null;
    }
  }
}
