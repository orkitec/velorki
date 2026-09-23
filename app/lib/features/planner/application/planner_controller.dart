import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_loops/velorki_loops.dart';

import '../../../app/app_config.dart';
import '../../../core/db/tables/routes.dart' show RouteSource;
import '../../routing_tiles/application/tile_update_check.dart';
import '../data/route_repository.dart';
import '../data/routing_backend_provider.dart';
import '../domain/planner_state.dart';
import '../domain/route_poi.dart';
import '../domain/route_profile.dart';
import '../domain/routing_options.dart';
import '../domain/saved_route.dart';
import '../domain/segment_math.dart';
import '../domain/route_waypoints.dart';
import '../domain/waypoint.dart';

part 'planner_controller.g.dart';

/// How long the planner waits after the last edit before it routes.
const Duration plannerDebounce = Duration(milliseconds: 300);

/// The message [PlannerState.error] carries when no routing server is set.
const String noRoutingBackendError = 'no routing server configured';

/// Where the profile the rider picked last is kept, by [RouteProfile.name],
/// so it is the one on the chips at the next start. Absent for the default.
const String _prefsProfile = 'planner.profile';

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
    // The backend is rebuilt when a routing tile arrives or a server URL
    // changes; a plan that failed for want of either is routed again, so
    // the download banner turns into the route by itself.
    ref.listen(routingBackendProvider, (previous, next) {
      if (previous == next || next == null || _disposed) return;
      if (state.missingTiles.isNotEmpty ||
          (state.isRoutable && state.result == null)) {
        _scheduleRoute();
      }
    });
    // The profile picked last time; a name no profile has any more is the
    // default.
    final stored = ref
        .watch(sharedPreferencesProvider)
        .getString(_prefsProfile);
    final profile =
        RouteProfile.values.asNameMap()[stored] ?? RouteProfile.trekking;
    return PlannerState(options: RoutingOptions(profile: profile));
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
    final closed = state.isClosedLoop;
    final next = [...state.waypoints];
    // The label belonged to the place that was dropped, so it goes with it.
    next[index] = next[index].copyWith(pos: pos, name: null);
    // A closed loop starts and ends at one place: moving that place moves
    // both ends, so the loop stays closed.
    if (closed && (index == 0 || index == next.length - 1)) {
      final other = index == 0 ? next.length - 1 : 0;
      next[other] = next[other].copyWith(pos: pos, name: null);
    }
    _setWaypoints(next);
  }

  /// Removes the waypoint at [index].
  void removeWaypoint(int index) {
    if (index < 0 || index >= state.waypoints.length) return;
    _pushUndo();
    final next = [...state.waypoints]..removeAt(index);
    _setWaypoints(next);
  }

  /// Gives the waypoint at [index] a name, a kind and a note, undoably.
  /// Details change nothing about the road, so nothing is routed again.
  ///
  /// A plan that is a saved route as stored gets the change written to the
  /// library at once: there is no Save to press for a route that has not
  /// changed shape, and details a rider typed and then lost were the
  /// complaint. Once the plan has been routed again the details wait for the
  /// next Save, with the new geometry.
  void setWaypointDetails(
    int index, {
    String? name,
    PoiKind poiKind = PoiKind.generic,
    String? note,
    TurnKind? turn,
  }) {
    if (index < 0 || index >= state.waypoints.length) return;
    _pushUndo();
    final next = [...state.waypoints];
    next[index] = next[index].copyWith(
      name: name?.trim().isEmpty ?? true ? null : name!.trim(),
      poiKind: poiKind,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      turn: poiKind == PoiKind.turn ? (turn ?? TurnKind.straight) : null,
    );
    state = state.copyWith(waypoints: next);
    final id = state.savedRouteId;
    if (id != null && state.routeIsSaved) {
      unawaited(ref.read(routeRepositoryProvider).setWaypoints(id, next));
    }
  }

  /// Swaps the waypoint at [index] with the one [offset] places away
  /// (-1: visit it earlier, +1: later), undoably.
  void swapWaypoint(int index, int offset) {
    final other = index + offset;
    final n = state.waypoints.length;
    if (index < 0 || index >= n || other < 0 || other >= n || offset == 0) {
      return;
    }
    _pushUndo();
    final next = [...state.waypoints];
    final tmp = next[index];
    next[index] = next[other];
    next[other] = tmp;
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

  /// Turns the plan into a loop by riding back to where it started.
  ///
  /// A copy of the first waypoint is appended, so the plan now ends where it
  /// began, and [differentWayBack] is remembered in the options: with it set,
  /// [_route] asks for the way out and the way home separately and keeps the
  /// second off the first one's roads.
  ///
  /// One undo entry, like every other edit: taking it back drops the closing
  /// waypoint, and the plan is an ordinary A to B again — which is why the
  /// stale option left behind does nothing.
  void closeLoop({required bool differentWayBack}) {
    if (state.waypoints.length < 2) return;
    if (state.isClosedLoop) {
      // Already a loop: only the way home is up for debate, and changing that
      // is not a change to the plan, so it gets no undo entry.
      if (state.options.differentWayBack == differentWayBack) return;
      state = state.copyWith(
        options: state.options.copyWith(differentWayBack: differentWayBack),
        alternatives: const <RouteResult>[],
      );
      _scheduleRoute();
      return;
    }
    _pushUndo();
    state = state.copyWith(
      options: state.options.copyWith(
        differentWayBack: differentWayBack,
        returnVariant: 0,
      ),
    );
    final first = state.waypoints.first;
    _setWaypoints([
      ...state.waypoints,
      Waypoint(
        pos: first.pos,
        name: first.name,
        poiKind: first.poiKind,
        note: first.note,
      ),
    ]);
  }

  /// Draws another way home for a closed loop.
  ///
  /// The ride out stays exactly as it is; only the return leg is asked for
  /// again, with the next of BRouter's alternatives. A variant that comes back
  /// as the same road is skipped, so every press really does change something
  /// — or, when the network offers nothing else, leaves the loop alone.
  ///
  /// Each press is one undo step.
  Future<void> anotherWayBack() async {
    if (!state.ridesBackAnotherWay) return;
    _pushUndo();
    final before = state.result;
    for (var tried = 0; tried <= RoutingOptions.maxAlternativeIdx; tried++) {
      final next =
          (state.options.returnVariant + 1) %
          (RoutingOptions.maxAlternativeIdx + 1);
      state = state.copyWith(
        options: state.options.copyWith(returnVariant: next),
        alternatives: const <RouteResult>[],
      );
      await _routeNow();
      if (_disposed) return;
      final now = state.result;
      if (now == null || before == null || !_sameRoute(before, now)) return;
    }
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

  /// Takes back the last change, one step at a time.
  void undo() {
    if (state.undoStack.isEmpty) return;
    final stack = [...state.undoStack];
    final previous = stack.removeLast();
    state = state.copyWith(
      undoStack: stack,
      options: state.options.copyWith(
        differentWayBack: previous.differentWayBack,
        returnVariant: previous.returnVariant,
      ),
    );
    _setWaypoints(previous.waypoints);
  }

  /// Switches the routing profile, re-routes and keeps the pick for the next
  /// start.
  void setProfile(RouteProfile profile) {
    if (state.options.profile == profile) return;
    state = state.copyWith(
      options: state.options.copyWith(profile: profile, alternativeIdx: 0),
      alternatives: const <RouteResult>[],
    );
    unawaited(_rememberProfile(profile));
    _scheduleRoute();
  }

  /// The default is remembered by remembering nothing.
  Future<void> _rememberProfile(RouteProfile profile) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (profile == RouteProfile.trekking) {
      await prefs.remove(_prefsProfile);
    } else {
      await prefs.setString(_prefsProfile, profile.name);
    }
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
        routeIsSaved: false,
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
          await _routeOnce(backend, _query(alternativeIdx: i), token),
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
      routeIsSaved: false,
    );
    return true;
  }

  /// Puts a route from the library back on the map.
  ///
  /// Nothing is routed: the stored geometry is shown as it was saved, and only
  /// the user's next edit asks the routing server again. A route that was
  /// imported rather than planned has only its two ends as waypoints, and an
  /// edit would route between them and lose the course the file came with;
  /// it gets the file's own points on the track, with their names, and shape
  /// points between them, see [routeWaypoints].
  void loadSavedRoute(SavedRoute saved) {
    _debounce?.cancel();
    _pending?.cancel('saved route loaded');
    final geometry = saved.geometry;
    state = PlannerState(
      waypoints: normalizeWaypointKinds(_waypointsOf(saved, geometry)),
      options: saved.options,
      route: AsyncData<RouteResult?>(
        RouteResult(
          geometry: geometry,
          lengthM: saved.distanceM,
          ascentM: saved.ascentM,
          descentM: saved.descentM,
          messages: const [],
          raw: const <String, dynamic>{},
          turns: saved.turns,
          name: saved.name,
        ),
      ),
      loadedSurfaceStats: saved.surfaceStats,
      savedRouteId: saved.id,
      savedRouteName: saved.name,
      routeIsSaved: true,
    );
  }

  static List<Waypoint> _waypointsOf(
    SavedRoute saved,
    List<TrackPoint> geometry,
  ) {
    final waypoints = saved.waypoints;
    if (saved.source == RouteSource.planned ||
        saved.source == RouteSource.loop ||
        waypoints.length > 2 ||
        geometry.length <= 2) {
      return waypoints;
    }
    return routeWaypoints(
      track: geometry.map((p) => p.pos).toList(growable: false),
      saved: waypoints,
      pois: saved.pois,
      turns: saved.turns,
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
    state = state.copyWith(
      savedRouteId: id,
      savedRouteName: name,
      routeIsSaved: true,
    );
  }

  /// Clears [PlannerState.error] once the screen has shown it.
  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(error: null);
  }

  void _pushUndo() {
    state = state.copyWith(
      undoStack: [...state.undoStack, PlannerEdit.of(state)],
    );
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
        routeIsSaved: false,
      );
      return;
    }
    state = state.copyWith(
      route: const AsyncLoading<RouteResult?>(),
      error: null,
      routeIsSaved: false,
    );
    _debounce = Timer(plannerDebounce, () => unawaited(_route()));
  }

  /// Routes straight away instead of after the debounce, and waits for it.
  Future<void> _routeNow() async {
    _debounce?.cancel();
    _pending?.cancel('superseded');
    _pending = null;
    if (!state.isRoutable) return;
    state = state.copyWith(
      route: const AsyncLoading<RouteResult?>(),
      error: null,
      routeIsSaved: false,
    );
    await _route();
  }

  /// The weekly look at the mirror for rebuilt tiles, hung on the start of
  /// a route so a phone that never restarts still gets it. Nothing about
  /// routing may depend on it, so it can neither fail nor delay the route.
  Future<void> _checkTileUpdates() async {
    try {
      await ref.read(tileUpdateCheckerProvider).checkIfDue();
    } on Object {
      // The checker logs its own failures; a missing collaborator (as in a
      // test container) is simply no check.
    }
  }

  /// Whether two results are the same ride, near enough.
  ///
  /// Length plus the first and last few points: a different alternative that
  /// happens to follow the same roads matches on all of them, and comparing
  /// whole geometries to find that out would be wasteful.
  static bool _sameRoute(RouteResult a, RouteResult b) {
    if ((a.lengthM - b.lengthM).abs() > 1) return false;
    final x = a.geometry;
    final y = b.geometry;
    if (x.length != y.length) return false;
    for (var i = 0; i < 3; i++) {
      if (i >= x.length) break;
      if (x[i].pos != y[i].pos) return false;
      if (x[x.length - 1 - i].pos != y[y.length - 1 - i].pos) return false;
    }
    return true;
  }

  Future<void> _route() async {
    unawaited(_checkTileUpdates());
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
      final result = await _routeOnce(backend, _query(), token);
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

  /// Routes one query, in two legs when the plan is a loop that wants a
  /// different way home.
  ///
  /// [CloseLoopRouter] lives in `velorki_loops` so the two-leg logic can be
  /// tested without a planner; here it is simply which of two objects the
  /// query goes to.
  Future<RouteResult> _routeOnce(
    RoutingBackend backend,
    RouteQuery query,
    CancelToken token,
  ) => state.ridesBackAnotherWay
      ? CloseLoopRouter(backend).route(
          query,
          cancel: token,
          returnAlternativeIdx: state.options.returnVariant,
        )
      : backend.route(query, cancel: token);

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
