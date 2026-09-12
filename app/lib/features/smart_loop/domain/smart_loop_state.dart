import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'loops.dart';

part 'smart_loop_state.freezed.dart';

/// Everything the smart-loop sheet shows about one loop search.
@freezed
abstract class SmartLoopState with _$SmartLoopState {
  const factory SmartLoopState({
    /// The request the current or last search was started with.
    LoopRequest? request,

    /// The best candidates found so far, best first. Grows while the search
    /// runs and is capped at `smartLoopTopN`.
    @Default(<LoopCandidate>[]) List<LoopCandidate> candidates,

    /// Index into [candidates] of the loop the user picked, or `null` while
    /// there is nothing to pick.
    int? selected,

    /// Whether a search is in flight.
    @Default(false) bool running,

    /// Routing requests finished divided by requests planned, `0`..`1`.
    @Default(0.0) double progress,

    /// Why the search failed, in the routing server's own words.
    String? error,
  }) = _SmartLoopState;

  const SmartLoopState._();

  /// The candidate the user picked, or `null`.
  LoopCandidate? get selectedCandidate {
    final i = selected;
    if (i == null || i < 0 || i >= candidates.length) return null;
    return candidates[i];
  }

  /// Whether a search has been started at all.
  bool get hasSearched => request != null;

  /// Whether the finished search found nothing, which is the "try a shorter
  /// distance or another via" state rather than an error.
  bool get foundNothing =>
      hasSearched && !running && error == null && candidates.isEmpty;

  /// Whether a candidate can be handed to the planner.
  bool get canAdopt => selectedCandidate != null;

  /// The geometries currently drawn on the map, best first.
  List<List<LatLng>> get previewLines =>
      candidates.map((c) => c.result.positions).toList(growable: false);
}
