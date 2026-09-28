import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import 'loops.dart';

part 'smart_loop_state.freezed.dart';

/// Everything the "Make a loop" sheet shows about one loop search.
@freezed
abstract class SmartLoopState with _$SmartLoopState {
  const factory SmartLoopState({
    /// The request the current or last search was started with.
    LoopRequest? request,

    /// Everything that routed, best first.
    @Default(<LoopCandidate>[]) List<LoopCandidate> candidates,

    /// Which of [candidates] is on the map; "Another" moves it on.
    @Default(0) int index,

    /// Whether a search is in flight.
    @Default(false) bool running,

    /// Routing requests finished divided by requests planned, `0`..`1`.
    @Default(0.0) double progress,

    /// Why the search failed, in the routing server's own words.
    String? error,

    /// The routing tiles a search that found nothing was missing: with no
    /// routing server, the first loop in a new area needs its tiles
    /// downloaded, which is not the same as "try another distance".
    @Default(<TileName>[]) List<TileName> missingTiles,
  }) = _SmartLoopState;

  const SmartLoopState._();

  /// The loop currently on the map, or `null` while there is none.
  LoopCandidate? get current =>
      index >= 0 && index < candidates.length ? candidates[index] : null;

  /// Whether a search has been started at all.
  bool get hasSearched => request != null;

  /// Whether the finished search found nothing, which is the "try another
  /// distance" state rather than an error.
  bool get foundNothing =>
      hasSearched &&
      !running &&
      error == null &&
      missingTiles.isEmpty &&
      candidates.isEmpty;
}
