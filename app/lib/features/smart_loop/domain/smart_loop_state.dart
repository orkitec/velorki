import 'package:freezed_annotation/freezed_annotation.dart';

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
      hasSearched && !running && error == null && candidates.isEmpty;
}
