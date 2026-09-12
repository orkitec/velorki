import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../data/routing_backend_provider.dart';
import '../domain/planner_state.dart';
import '../domain/route_profile.dart';
import '../domain/routing_options.dart';
import '../domain/saved_route.dart';
import '../domain/segment_math.dart';
import '../domain/waypoint.dart';

part 'planner_controller.g.dart';

/// How long the planner waits after the last edit before it routes.
const Duration plannerDebounce = Duration(milliseconds: 300);

/// The message [PlannerState.error] carries when no routing server is set.
const String noRoutingBackendError = 'no routing server configured';

/// The Plan tab's state machine.
///
/// Every waypoint change pushes the previous list on the undo stack, then
/// schedules a routing request [plannerDebounce] later, cancelling the request
/// that is already in flight. Cancellations are never reported as errors.
@Riverpod(keepAlive: true)
class PlannerController extends _$PlannerController {
  Timer? _debounce;
  CancelToken? _pending;
  bool _disposed = false;

  @override
  PlannerState build() {
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      _pending?.cancel('planner disposed');
    });
    return const PlannerState();
  }

  /// Appends a waypoint at the end of the route (the map's tap gesture).
  void addWaypoint(LatLng pos, {String? name}) {
    _pushUndo();
    _setWaypoints([...state.waypoints, Waypoint(pos: pos, name: name)]);
  }

  /// Inserts a via point into the segment it lies closest to (the map's
  /// long-press gesture). With fewer than two waypoints it appends instead.
  void insertWaypoint(LatLng pos, {String? name}) {
    if (state.waypoints.length < 2) {
      addWaypoint(pos, name: name);
      return;
    }
    _pushUndo();
    final at = nearestSegmentIndex(state.positions, pos) + 1;
    final next = [...state.waypoints]
      ..insert(at, Waypoint(pos: pos, name: name));
    _setWaypoints(next);
  }

  /// Moves the waypoint at [index] (the map's drag gesture).
  void moveWaypoint(int index, LatLng pos) {
    if (index < 0 || index >= state.waypoints.length) return;
    _pushUndo();
    final next = [...state.waypoints];
    // The label belonged to the place that was dropped, so it goes with it.
    next[index] = next[index].copyWith(pos: pos, name: null);
    _setWaypoints(next);
  }

  /// Removes the waypoint at [index].
  void removeWaypoint(int index) {
    if (index < 0 || index >= state.waypoints.length) return;
    _pushUndo();
    final next = [...state.waypoints]..removeAt(index);
    _setWaypoints(next);
  }

  /// Replaces the whole plan with [waypoints], undoably.
  ///
  /// The assistant hands its resolved start, vias and destination over this
  /// way: one undo entry for the whole change rather than one per point, and
  /// a single routing request after the usual debounce.
  void setWaypoints(List<Waypoint> waypoints) {
    if (waypoints.isEmpty) {
      clear();
      return;
    }
    _pushUndo();
    _setWaypoints(waypoints);
  }

  /// Rides the route the other way round.
  void reverse() {
    if (state.waypoints.length < 2) return;
    _pushUndo();
    _setWaypoints(state.waypoints.reversed.toList());
  }

  /// Throws the whole plan away, undoably.
  void clear() {
    if (state.waypoints.isEmpty) return;
    _pushUndo();
    _setWaypoints(const <Waypoint>[]);
  }

  /// Takes back the last waypoint change.
  void undo() {
    if (state.undoStack.isEmpty) return;
    final stack = [...state.undoStack];
    final previous = stack.removeLast();
    state = state.copyWith(undoStack: stack);
    _setWaypoints(previous);
  }

  /// Switches the routing profile and re-routes.
  void setProfile(RouteProfile profile) {
    if (state.options.profile == profile) return;
    state = state.copyWith(
      options: state.options.copyWith(profile: profile, alternativeIdx: 0),
      alternatives: const <RouteResult>[],
    );
    _scheduleRoute();
  }

  /// Shows alternative [idx] (`0`..`3`), using an already fetched one when
  /// [loadAlternatives] has run.
  void setAlternative(int idx) {
    final wanted = idx.clamp(0, RoutingOptions.maxAlternativeIdx);
    state = state.copyWith(
      options: state.options.copyWith(alternativeIdx: wanted),
    );
    if (wanted < state.alternatives.length) {
      _debounce?.cancel();
      _pending?.cancel('alternative switched');
      state = state.copyWith(
        route: AsyncData<RouteResult?>(state.alternatives[wanted]),
        loadedSurfaceStats: null,
        error: null,
      );
      return;
    }
    _scheduleRoute();
  }

  /// Fetches alternatives 0..3 from the routing server.
  ///
  /// They are never fetched by default: four routes are four requests. Returns
  /// `false` when the server produced none.
  Future<bool> loadAlternatives() async {
    if (!state.isRoutable) return false;
    final backend = ref.read(routingBackendProvider);
    if (backend == null) {
      state = state.copyWith(error: noRoutingBackendError);
      return false;
    }
    _debounce?.cancel();
    _pending?.cancel('alternatives requested');
    final token = CancelToken();
    _pending = token;
    state = state.copyWith(loadingAlternatives: true, error: null);

    final results = <RouteResult>[];
    String? failure;
    for (var i = 0; i <= RoutingOptions.maxAlternativeIdx; i++) {
      try {
        results.add(
          await backend.route(_query(alternativeIdx: i), cancel: token),
        );
      } on RoutingException catch (e) {
        if (e.kind == RoutingErrorKind.cancelled) return false;
        failure ??= e.message;
        // A missing alternative is normal: BRouter serves fewer than four for
        // many routes. Keep the ones that worked.
        break;
      }
    }
    if (_disposed || token.isCancelled) return false;
    _pending = null;

    if (results.isEmpty) {
      state = state.copyWith(loadingAlternatives: false, error: failure);
      return false;
    }
    final selected = state.options.alternativeIdx < results.length
        ? state.options.alternativeIdx
        : 0;
    state = state.copyWith(
      alternatives: results,
      loadingAlternatives: false,
      options: state.options.copyWith(alternativeIdx: selected),
      route: AsyncData<RouteResult?>(results[selected]),
      loadedSurfaceStats: null,
      error: null,
      routingSource: _sourceOf(backend),
    );
    return true;
  }

  /// Puts a route from the library back on the map.
  ///
  /// Nothing is routed: the stored geometry is shown as it was saved, and only
  /// the user's next edit asks the routing server again.
  void loadSavedRoute(SavedRoute saved) {
    _debounce?.cancel();
    _pending?.cancel('saved route loaded');
    final geometry = saved.geometry;
    state = PlannerState(
      waypoints: normalizeWaypointKinds(saved.waypoints),
      options: saved.options,
      route: AsyncData<RouteResult?>(
        RouteResult(
          geometry: geometry,
          lengthM: saved.distanceM,
          ascentM: saved.ascentM,
          descentM: saved.descentM,
          messages: const [],
          raw: const <String, dynamic>{},
          name: saved.name,
        ),
      ),
      loadedSurfaceStats: saved.surfaceStats,
      savedRouteId: saved.id,
      savedRouteName: saved.name,
    );
  }

  /// Puts an already computed route on the map.
  ///
  /// Nothing is routed: [result] is shown as it came back, with [waypoints] as
  /// the points it was computed from, so the user can look at it, save it to
  /// the library or edit it — the first edit re-routes as usual. The smart
  /// loop sheet hands its chosen candidate over this way.
  void loadComputedRoute({
    required RouteResult result,
    required List<Waypoint> waypoints,
    required RoutingOptions options,
  }) {
    _debounce?.cancel();
    _pending?.cancel('computed route loaded');
    _pending = null;
    state = PlannerState(
      waypoints: normalizeWaypointKinds(waypoints),
      options: options,
      route: AsyncData<RouteResult?>(result),
    );
  }

  /// Remembers which library row the plan belongs to after a save.
  void markSaved(String id, String name) {
    state = state.copyWith(savedRouteId: id, savedRouteName: name);
  }

  /// Clears [PlannerState.error] once the screen has shown it.
  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(error: null);
  }

  void _pushUndo() {
    state = state.copyWith(undoStack: [...state.undoStack, state.waypoints]);
  }

  void _setWaypoints(List<Waypoint> waypoints) {
    state = state.copyWith(
      waypoints: normalizeWaypointKinds(waypoints),
      alternatives: const <RouteResult>[],
      savedRouteId: waypoints.isEmpty ? null : state.savedRouteId,
      savedRouteName: waypoints.isEmpty ? null : state.savedRouteName,
    );
    _scheduleRoute();
  }

  void _scheduleRoute() {
    _debounce?.cancel();
    _pending?.cancel('superseded');
    _pending = null;
    if (!state.isRoutable) {
      state = state.copyWith(
        route: const AsyncData<RouteResult?>(null),
        loadedSurfaceStats: null,
        error: null,
      );
      return;
    }
    state = state.copyWith(
      route: const AsyncLoading<RouteResult?>(),
      error: null,
    );
    _debounce = Timer(plannerDebounce, () => unawaited(_route()));
  }

  Future<void> _route() async {
    final backend = ref.read(routingBackendProvider);
    if (backend == null) {
      state = state.copyWith(
        route: const AsyncData<RouteResult?>(null),
        error: noRoutingBackendError,
      );
      return;
    }
    final token = CancelToken();
    _pending = token;
    try {
      final result = await backend.route(_query(), cancel: token);
      if (_disposed || token.isCancelled) return;
      state = state.copyWith(
        route: AsyncData<RouteResult?>(result),
        loadedSurfaceStats: null,
        error: null,
        routingSource: _sourceOf(backend),
      );
    } on RoutingException catch (e, st) {
      if (_disposed ||
          token.isCancelled ||
          e.kind == RoutingErrorKind.cancelled) {
        return;
      }
      state = state.copyWith(
        route: AsyncError<RouteResult?>(e, st),
        error: e.message,
        routingSource: null,
      );
    } catch (e, st) {
      if (_disposed || token.isCancelled) return;
      state = state.copyWith(
        route: AsyncError<RouteResult?>(e, st),
        error: e.toString(),
      );
    } finally {
      if (identical(_pending, token)) _pending = null;
    }
  }

  /// Where a route came from, for the planner's "on device"/"server" chip.
  /// Only the composite backend knows; anything else stays silent.
  static RoutingSource? _sourceOf(RoutingBackend backend) =>
      backend is CompositeRoutingBackend ? backend.lastSource : null;

  RouteQuery _query({int? alternativeIdx}) => RouteQuery(
    points: state.positions,
    profile: state.options.profile.brouterName,
    alternativeIdx: alternativeIdx ?? state.options.alternativeIdx,
  );
}
