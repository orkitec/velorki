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

    /// Whether the rider chose the loop at [index] ("Another", "Done") while
    /// the search was still running. Loops arriving after that are ranked
    /// round it, and [index] follows it; until then it stays on the best so
    /// far.
    @Default(false) bool pinned,

    /// Whether the rider took the loop on show with "Done" while the search
    /// was still running: the search goes on with the sheet closed, and
    /// nothing it finds later replaces that loop in the planner.
    @Default(false) bool handedOver,

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

    /// Whether the search ran out of its time budget (`smartLoopTimeout`)
    /// before it had tried every direction. With nothing found that is "this
    /// took too long", not "there is no loop here".
    @Default(false) bool timedOut,

    /// Whether the rider stopped the search, or closed the sheet over it.
    @Default(false) bool stopped,
  }) = _SmartLoopState;

  const SmartLoopState._();

  /// The loop currently on the map, or `null` while there is none.
  LoopCandidate? get current =>
      index >= 0 && index < candidates.length ? candidates[index] : null;

  /// Whether a search has been started at all.
  bool get hasSearched => request != null;

  /// Whether the finished search found nothing, which is the "try another
  /// distance" state rather than an error.
  ///
  /// A search cut short — by its time budget or by the rider — has not
  /// shown that there is nothing, so it is not this state.
  bool get foundNothing =>
      hasSearched &&
      !running &&
      error == null &&
      missingTiles.isEmpty &&
      !timedOut &&
      !stopped &&
      candidates.isEmpty;

  /// Whether the search ran out of time without a single loop to show.
  bool get tookTooLong =>
      hasSearched &&
      !running &&
      timedOut &&
      error == null &&
      missingTiles.isEmpty &&
      candidates.isEmpty;
}
