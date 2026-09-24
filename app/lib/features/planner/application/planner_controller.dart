import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_loops/velorki_loops.dart';

import '../../../app/app_config.dart';
import '../../../core/db/tables/routes.dart' show RouteSource;
import '../../../core/geo/track_surface.dart';
import '../../routing_tiles/application/tile_update_check.dart';
import '../data/route_repository.dart';
import '../data/routing_backend_provider.dart';
import '../domain/planner_state.dart';
import '../domain/route_legs.dart';
import '../domain/route_poi.dart';
import '../domain/route_profile.dart';
import '../domain/routing_options.dart';
import '../domain/saved_route.dart';
import '../domain/route_waypoints.dart';
import '../domain/waypoint.dart';
import 'track_surface_service.dart';

part 'planner_controller.g.dart';

/// How long the planner waits after the last edit before it routes.
const Duration plannerDebounce = Duration(milliseconds: 300);

/// The message [PlannerState.error] carries when no routing server is set.
const String noRoutingBackendError = 'no routing server configured';

/// Where the profile the rider picked last is kept, by [RouteProfile.name],
/// so it is the one on the chips at the next start. Absent for the default.
const String _prefsProfile = 'planner.profile';

/// How many legs are asked of the router at once.
const int _legsAtOnce = 4;

/// The Plan tab's state machine.
///
/// Every waypoint change pushes the previous list on the undo stack, sets the
/// legs it touches to be routed again, then schedules a routing request
/// [plannerDebounce] later, cancelling the request that is already in flight.
/// Only those legs are routed, one request per leg, and joined with the legs
/// that stayed. Cancellations are never reported as errors.
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
    _setWaypoints(
      [...state.waypoints, Waypoint(pos: pos, name: name)],
      [...state.planLegs, if (state.waypoints.isNotEmpty) null],
    );
  }

  /// Puts a new waypoint at [pos] between the waypoints at [index] - 1 and
  /// [index]: the leg between them is split in two, and only those two are
  /// routed (the map's gesture on the route line).
  void insertWaypoint(int index, LatLng pos) {
    if (index < 1 || index >= state.waypoints.length) return;
    _pushUndo();
    _setWaypoints(
      [...state.waypoints]..insert(index, Waypoint(pos: pos)),
      [...state.planLegs]..replaceRange(index - 1, index, [null, null]),
    );
  }

  /// Moves the waypoint at [index] (the map's drag gesture).
  void moveWaypoint(int index, LatLng pos) {
    if (index < 0 || index >= state.waypoints.length) return;
    _pushUndo();
    final closed = state.isClosedLoop;
    final next = [...state.waypoints];
    final legs = [...state.planLegs];
    // The label belonged to the place that was dropped, so it goes with it.
    next[index] = next[index].copyWith(pos: pos, name: null);
    _touch(legs, index);
    // A closed loop starts and ends at one place: moving that place moves
    // both ends, so the loop stays closed.
    if (closed && (index == 0 || index == next.length - 1)) {
      final other = index == 0 ? next.length - 1 : 0;
      next[other] = next[other].copyWith(pos: pos, name: null);
      _touch(legs, other);
    }
    _setWaypoints(next, legs);
  }

  /// Removes the waypoint at [index].
  void removeWaypoint(int index) {
    if (index < 0 || index >= state.waypoints.length) return;
    _pushUndo();
    _setWaypoints(
      [...state.waypoints]..removeAt(index),
      _legsWithout(state.planLegs, index),
    );
  }

  /// Adds a point beside the route: a place the route is not routed
  /// through, drawn with its kind's icon. The map's long press puts one
  /// here.
  void addPoi(
    LatLng pos, {
    String? name,
    PoiKind kind = PoiKind.generic,
    String? note,
  }) {
    _pushUndo();
    _setPois([
      ...state.pois,
      RoutePoi(
        pos: pos,
        name: name?.trim() ?? '',
        description: _orNull(note),
        kind: kind,
      ),
    ]);
  }

  /// Gives the point beside the route at [index] a name, a kind and a note,
  /// undoably. Nothing is routed again: a point the route does not pass
  /// through cannot change it.
  void setPoiDetails(
    int index, {
    String? name,
    PoiKind poiKind = PoiKind.generic,
    String? note,
  }) {
    if (index < 0 || index >= state.pois.length) return;
    _pushUndo();
    final next = [...state.pois];
    final poi = next[index];
    next[index] = RoutePoi(
      pos: poi.pos,
      name: name?.trim() ?? '',
      description: _orNull(note),
      kind: poiKind,
      sourceType: poi.sourceType,
    );
    _setPois(next);
  }

  /// Removes the point beside the route at [index].
  void removePoi(int index) {
    if (index < 0 || index >= state.pois.length) return;
    _pushUndo();
    _setPois([...state.pois]..removeAt(index));
  }

  /// Takes the waypoint at [index] off the route and leaves it beside it:
  /// the marker stays where it is as a place, and the route is drawn again
  /// without it.
  void movePointBeside(int index) {
    if (index < 0 || index >= state.waypoints.length) return;
    _pushUndo();
    final point = state.waypoints[index];
    final waypoints = [...state.waypoints]..removeAt(index);
    _setWaypoints(
      waypoints,
      _legsWithout(state.planLegs, index),
      pois: [
        ...state.pois,
        RoutePoi(
          pos: point.pos,
          name: point.name ?? '',
          description: point.note,
          // A turn is a cue of the route, so a point taken off it is just a
          // place.
          kind: point.poiKind == PoiKind.turn ? PoiKind.generic : point.poiKind,
          sourceType: point.sourceType,
        ),
      ],
    );
  }

  /// Puts the point beside the route at [index] on it: a via where the
  /// route comes past it, so the ride now goes through the place.
  void movePointOnRoute(int index) {
    if (index < 0 || index >= state.pois.length) return;
    _pushUndo();
    final poi = state.pois[index];
    final pois = [...state.pois]..removeAt(index);
    final at = viaIndexAlongTrack(
      track: state.result?.positions ?? const <LatLng>[],
      waypoints: state.waypoints,
      pos: poi.pos,
    );
    final to = at.clamp(0, state.waypoints.length);
    final legs = [...state.planLegs];
    if (state.waypoints.isEmpty) {
      // The first point: no leg yet.
    } else if (to == 0) {
      legs.insert(0, null);
    } else if (to == state.waypoints.length) {
      legs.add(null);
    } else {
      legs.replaceRange(to - 1, to, [null, null]);
    }
    final waypoints = [...state.waypoints]
      ..insert(
        to,
        Waypoint(
          pos: poi.pos,
          name: poi.name.isEmpty ? null : poi.name,
          poiKind: poi.kind,
          note: poi.description,
          sourceType: poi.sourceType,
        ),
      );
    _setWaypoints(waypoints, legs, pois: pois);
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
      name: _orNull(name),
      poiKind: poiKind,
      note: _orNull(note),
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
    final legs = [...state.planLegs];
    _touch(legs, index);
    _touch(legs, other);
    _setWaypoints(next, legs);
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
    // A new plan: the file the old one came from is no concern of it.
    state = state.copyWith(original: null);
    _setWaypoints(
      waypoints,
      List<RouteLeg?>.filled(
        waypoints.length < 2 ? 0 : waypoints.length - 1,
        null,
      ),
    );
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
        // The way home is the one leg that depends on it.
        legs: [...state.planLegs]..last = null,
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
    _setWaypoints(
      [
        ...state.waypoints,
        Waypoint(
          pos: first.pos,
          name: first.name,
          poiKind: first.poiKind,
          note: first.note,
        ),
      ],
      [...state.planLegs, null],
    );
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
        legs: [...state.planLegs]..last = null,
      );
      await _routeNow();
      if (_disposed) return;
      final now = state.result;
      if (now == null || before == null || !_sameRoute(before, now)) return;
    }
  }

  /// Rides the route the other way round.
  ///
  /// A file's own line is ridden back to front as it is; a routed leg is
  /// routed again, since the way back is not always the way there.
  void reverse() {
    if (state.waypoints.length < 2) return;
    _pushUndo();
    _setWaypoints(state.waypoints.reversed.toList(), [
      for (final leg in state.planLegs.reversed)
        leg != null && leg.kept ? leg.reversedKept() : null,
    ]);
  }

  /// Throws the whole plan away, undoably: the waypoints and the points
  /// beside the route alike.
  void clear() {
    if (!state.hasPoints) return;
    _pushUndo();
    state = state.copyWith(original: null);
    _setWaypoints(
      const <Waypoint>[],
      const <RouteLeg?>[],
      pois: const <RoutePoi>[],
    );
  }

  /// Puts back the route as its file drew it: the file's line and markers,
  /// every leg kept, in one undoable step. The points beside the route stay
  /// as they are.
  void restoreOriginal() {
    final original = state.original;
    if (original == null) return;
    final legs = legsFromSaved(
      original.geometry,
      original.legs,
      turns: original.turns,
    );
    if (legs == null) return;
    _pushUndo();
    _debounce?.cancel();
    _pending?.cancel('original restored');
    _pending = null;
    state = state.copyWith(
      waypoints: normalizeWaypointKinds(original.waypoints),
      legs: legs,
      route: AsyncData<RouteResult?>(PlannedRoute.join(legs)),
      alternatives: const <RouteResult>[],
      loadedSurfaceStats: null,
      matchedSurface: null,
      error: null,
      routeIsSaved: false,
    );
    _matchSurface();
  }

  /// Takes back the last change, one step at a time.
  ///
  /// A step is put back as it was recorded, the route on the map included,
  /// rather than routed again between the restored points. The two are not
  /// the same thing: a route that came out of a file is the course its
  /// author drew, and asking the router for a line through the same points
  /// gives a slightly different one — which is what the rider saw when an
  /// undo quietly changed their imported ride. For a plan of our own the
  /// recorded route already answers the recorded points, so routing again
  /// would only be a wait for the same line.
  ///
  /// Anything in flight is dropped first, so a late answer to the edit
  /// being taken back cannot land on top of what was restored.
  void undo() {
    if (state.undoStack.isEmpty) return;
    final stack = [...state.undoStack];
    final previous = stack.removeLast();
    _debounce?.cancel();
    _pending?.cancel('undone');
    _pending = null;
    final profile = previous.profile;
    if (profile != null) unawaited(_rememberProfile(profile));
    state = state.copyWith(
      undoStack: stack,
      waypoints: normalizeWaypointKinds(previous.waypoints),
      pois: previous.pois,
      legs: previous.legs,
      original: previous.original,
      options: state.options.copyWith(
        differentWayBack: previous.differentWayBack,
        returnVariant: previous.returnVariant,
        profile: profile ?? state.options.profile,
      ),
      route: AsyncData<RouteResult?>(previous.result),
      loadedSurfaceStats: previous.loadedSurfaceStats,
      matchedSurface: null,
      // The variants belonged to the edit being taken back; the rider can
      // ask for them again against the plan that is back on screen.
      alternatives: const <RouteResult>[],
      error: null,
      routeIsSaved: previous.routeIsSaved,
      savedRouteId: previous.savedRouteId,
      savedRouteName: previous.savedRouteName,
    );
    // The one case with something left to do: a step recorded while its own
    // route was still on its way, so there is a plan but nothing to show
    // for it. An empty plan is not that case and stays empty.
    if (previous.result == null && state.isRoutable) {
      _scheduleRoute();
    } else {
      _matchSurface();
    }
  }

  /// Switches the routing profile, re-routes every leg with it and keeps
  /// the pick for the next start.
  ///
  /// Every leg, a file's own line included: the bike is what the choice
  /// means. With a route on the map the switch is a step of its own, so
  /// Undo puts the route back as it was, profile and all.
  void setProfile(RouteProfile profile) {
    if (state.options.profile == profile) return;
    if (state.isRoutable) {
      state = state.copyWith(
        undoStack: [
          ...state.undoStack,
          PlannerEdit.of(state, profile: state.options.profile),
        ],
      );
    }
    state = state.copyWith(
      options: state.options.copyWith(profile: profile, alternativeIdx: 0),
      alternatives: const <RouteResult>[],
      legs: List<RouteLeg?>.filled(state.planLegs.length, null),
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
      final chosen = state.alternatives[wanted];
      state = state.copyWith(
        route: AsyncData<RouteResult?>(chosen),
        legs: chosen is PlannedRoute
            ? chosen.legs
            : List<RouteLeg?>.filled(state.planLegs.length, null),
        loadedSurfaceStats: null,
        matchedSurface: null,
        error: null,
        routeIsSaved: false,
      );
      _matchSurface();
      return;
    }
    state = state.copyWith(
      legs: List<RouteLeg?>.filled(state.planLegs.length, null),
    );
    _scheduleRoute();
  }

  /// Fetches alternatives 0..3 from the routing server.
  ///
  /// They are never fetched by default: four routes are four requests (per
  /// leg). Each is a whole route the router drew, so a plan with a file's own
  /// line in it loses that line to them; that is one undo step, and Undo
  /// brings the line back. Returns `false` when the server produced none.
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
    final waypoints = state.waypoints;
    final unknown = List<RouteLeg?>.filled(state.planLegs.length, null);
    for (var i = 0; i <= RoutingOptions.maxAlternativeIdx; i++) {
      try {
        final legs = await _routeLegs(
          backend,
          waypoints: waypoints,
          legs: unknown,
          token: token,
          alternativeIdx: i,
        );
        results.add(PlannedRoute.join(legs));
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
    if (state.hasKeptLegs) _pushUndo();
    final chosen = results[selected] as PlannedRoute;
    state = state.copyWith(
      alternatives: results,
      loadingAlternatives: false,
      options: state.options.copyWith(alternativeIdx: selected),
      route: AsyncData<RouteResult?>(chosen),
      legs: chosen.legs,
      loadedSurfaceStats: null,
      matchedSurface: null,
      error: null,
      routingSource: _sourceOf(backend),
      routeIsSaved: false,
    );
    _matchSurface();
    return true;
  }

  /// Puts a route from the library back on the map.
  ///
  /// Nothing is routed: the stored geometry is shown as it was saved, with
  /// the legs it was saved with, and only the user's next edit asks the
  /// router again, for the legs it touches.
  ///
  /// A route that was imported rather than planned, and never saved from
  /// the planner, opens with its ends and the named points on its track as
  /// waypoints (see [trackMarkers]), and the file's line between them as
  /// kept legs. A route of unknown legs — planned before legs were stored —
  /// has its next edit route the whole of it.
  void loadSavedRoute(SavedRoute saved) {
    _debounce?.cancel();
    _pending?.cancel('saved route loaded');
    final geometry = saved.geometry;
    final (waypoints, pois, legs) = _planOf(saved, geometry);
    final known = legs.isNotEmpty && legs.every((l) => l != null);
    final imported =
        saved.source != RouteSource.planned && saved.source != RouteSource.loop;
    state = PlannerState(
      waypoints: normalizeWaypointKinds(waypoints),
      pois: pois,
      legs: legs,
      // A file that names no bike rides with the one the rider rode last.
      options: saved.profileKnown
          ? saved.options
          : saved.options.copyWith(profile: state.options.profile),
      // A route imported before its original was kept takes the line it
      // has as that, which it is unless it was edited.
      original:
          saved.original ??
          (imported && known && legs.every((l) => l!.kept)
              ? RouteOriginal(
                  geometryBlob: saved.geometryBlob,
                  waypoints: normalizeWaypointKinds(waypoints),
                  legs: PlannedRoute.join(legs.cast<RouteLeg>()).savedLegs,
                  turns: saved.turns,
                )
              : null),
      route: AsyncData<RouteResult?>(
        known
            ? PlannedRoute.join(
                legs.cast<RouteLeg>(),
                name: saved.name,
                lengthM: saved.distanceM,
                ascentM: saved.ascentM,
                descentM: saved.descentM,
                turns: saved.turns,
              )
            : RouteResult(
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
      // A track the map could not follow before will not be followed now.
      matchedSurface: saved.surfaceUnavailable
          ? const AsyncData<TrackSurface>(TrackSurface.unmatched)
          : null,
      savedRouteId: saved.id,
      savedRouteName: saved.name,
      routeIsSaved: true,
    );
    if (!saved.surfaceUnavailable) _matchSurface();
  }

  /// The plan a saved route opens as: the points the route is routed
  /// through, the points beside it, and the legs between the former.
  ///
  /// Every point of interest the route carries becomes one or the other.
  /// A route that was planned here keeps its waypoints as they are and all
  /// its points stay beside the route; an imported one has the points on
  /// its track turned into waypoints by [trackMarkers], and only the rest
  /// stay beside it.
  static (List<Waypoint>, List<RoutePoi>, List<RouteLeg?>) _planOf(
    SavedRoute saved,
    List<TrackPoint> geometry,
  ) {
    final waypoints = saved.waypoints;
    final count = waypoints.length < 2 ? 0 : waypoints.length - 1;
    final stored = saved.legs;
    if (stored != null && stored.length == count) {
      final legs = legsFromSaved(geometry, stored, turns: saved.turns);
      if (legs != null) return (waypoints, saved.pois, legs);
    }
    final unknown = List<RouteLeg?>.filled(count, null);
    if (saved.source == RouteSource.planned ||
        saved.source == RouteSource.loop ||
        waypoints.length > 2 ||
        geometry.length < 2) {
      return (waypoints, saved.pois, unknown);
    }
    final track = geometry.map((p) => p.pos).toList(growable: false);
    final markers = trackMarkers(
      track: track,
      saved: waypoints,
      pois: saved.pois,
      turns: saved.turns,
    );
    return (
      [for (final m in markers) m.$2],
      besideTrackPois(track: track, pois: saved.pois),
      keptLegs(geometry, [
        for (final m in markers.take(markers.length - 1)) m.$1,
      ], turns: saved.turns),
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
      // Drawn as one route, so not known leg by leg: the first edit routes
      // the whole of it, as it always did.
      legs: List<RouteLeg?>.filled(
        waypoints.length < 2 ? 0 : waypoints.length - 1,
        null,
      ),
      route: AsyncData<RouteResult?>(result),
    );
    _matchSurface();
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

  void _setWaypoints(
    List<Waypoint> waypoints,
    List<RouteLeg?> legs, {
    List<RoutePoi>? pois,
  }) {
    final empty = waypoints.isEmpty && (pois ?? state.pois).isEmpty;
    state = state.copyWith(
      waypoints: normalizeWaypointKinds(waypoints),
      legs: legs,
      pois: pois ?? state.pois,
      alternatives: const <RouteResult>[],
      savedRouteId: empty ? null : state.savedRouteId,
      savedRouteName: empty ? null : state.savedRouteName,
    );
    _scheduleRoute();
  }

  /// The points beside the route, changed without routing again: the road
  /// does not depend on them.
  ///
  /// As with a waypoint's details, a plan that is a saved route as stored
  /// gets the change written to the library at once, so a place the rider
  /// marked is not lost for want of a Save.
  void _setPois(List<RoutePoi> pois) {
    state = state.copyWith(pois: pois);
    final id = state.savedRouteId;
    if (id != null && state.routeIsSaved) {
      unawaited(ref.read(routeRepositoryProvider).setPois(id, pois));
    }
  }

  /// Marks the legs on either side of the waypoint at [index] in [legs] to
  /// be routed again.
  static void _touch(List<RouteLeg?> legs, int index) {
    if (index > 0 && index - 1 < legs.length) legs[index - 1] = null;
    if (index >= 0 && index < legs.length) legs[index] = null;
  }

  /// [legs] once the waypoint at [index] is gone: an end takes its leg
  /// with it, and a point between two legs leaves one leg in their place.
  /// Two of a file's own lines that met there stay the file's line; any
  /// other pair is routed again as one.
  static List<RouteLeg?> _legsWithout(List<RouteLeg?> legs, int index) {
    if (legs.length <= 1) return const <RouteLeg?>[];
    final next = [...legs];
    if (index == 0) return next..removeAt(0);
    if (index >= legs.length) return next..removeLast();
    final a = legs[index - 1];
    final b = legs[index];
    final merged = a != null && b != null && a.kept && b.kept
        ? RouteLeg.joinKept(a, b)
        : null;
    return next..replaceRange(index - 1, index + 1, [merged]);
  }

  /// A field the rider left blank, or filled only with spaces, is none.
  static String? _orNull(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _scheduleRoute() {
    _debounce?.cancel();
    _pending?.cancel('superseded');
    _pending = null;
    if (!state.isRoutable) {
      state = state.copyWith(
        route: const AsyncData<RouteResult?>(null),
        loadedSurfaceStats: null,
        matchedSurface: null,
        error: null,
        routeIsSaved: false,
      );
      return;
    }
    if (_joinIfDrawn()) return;
    state = state.copyWith(
      route: const AsyncLoading<RouteResult?>(),
      matchedSurface: null,
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
    if (_joinIfDrawn()) return;
    state = state.copyWith(
      route: const AsyncLoading<RouteResult?>(),
      matchedSurface: null,
      error: null,
      routeIsSaved: false,
    );
    await _route();
  }

  /// Settles the legs before a route: a loop that rides home another way
  /// routes its way home again whenever the way out changed, since that is
  /// what the way home keeps off. When no leg is left to route — an edit
  /// that only took a leg away, or joined two of a file's lines — the route
  /// is put together at once and `true` returned.
  bool _joinIfDrawn() {
    final legs = [...state.planLegs];
    if (state.ridesBackAnotherWay &&
        legs.take(legs.length - 1).any((l) => l == null)) {
      legs.last = null;
    }
    if (legs.any((l) => l == null)) {
      state = state.copyWith(legs: legs);
      return false;
    }
    state = state.copyWith(
      legs: legs,
      route: AsyncData<RouteResult?>(PlannedRoute.join(legs.cast<RouteLeg>())),
      loadedSurfaceStats: null,
      matchedSurface: null,
      error: null,
      routeIsSaved: false,
    );
    _matchSurface();
    return true;
  }

  /// Starts matching the shown route against the routing tiles when the
  /// router's own figures do not cover all of it, so the Surface section
  /// never shows figures for part of a route as if they were the whole.
  void _matchSurface() {
    final result = state.result;
    if (result == null || state.surfaceStats != null) return;
    if (state.matchedSurface != null) return;
    state = state.copyWith(matchedSurface: const AsyncLoading<TrackSurface>());
    unawaited(_runMatch(result));
  }

  Future<void> _runMatch(RouteResult result) async {
    AsyncValue<TrackSurface> outcome;
    try {
      outcome = AsyncData<TrackSurface>(
        await ref
            .read(trackSurfaceServiceProvider)
            .match(points: result.geometry, distanceM: result.lengthM),
      );
    } catch (e, st) {
      outcome = AsyncError<TrackSurface>(e, st);
    }
    // A route that changed meanwhile has its own matching, or none.
    if (_disposed || !identical(state.result, result)) return;
    state = state.copyWith(
      matchedSurface: outcome,
      loadedSurfaceStats: outcome.value?.stats,
    );
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
      final legs = await _routeLegs(
        backend,
        waypoints: state.waypoints,
        legs: state.planLegs,
        token: token,
        alternativeIdx: state.options.alternativeIdx,
      );
      if (_disposed || token.isCancelled) return;
      state = state.copyWith(
        route: AsyncData<RouteResult?>(PlannedRoute.join(legs)),
        legs: legs,
        loadedSurfaceStats: null,
        matchedSurface: null,
        error: null,
        routingSource: _sourceOf(backend),
      );
      _matchSurface();
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

  /// Routes every leg of [legs] that is `null`, from waypoint i to i + 1 of
  /// [waypoints], and returns the legs with them filled in.
  ///
  /// One request per leg, a few at a time, all on [token]. A failing leg
  /// fails the lot; when several lack routing tiles, the error names every
  /// tile any of them lacks, so one download banner covers the route.
  ///
  /// The way home of a loop that rides back another way is routed last,
  /// through [routeWayBack], off the roads of the way out.
  Future<List<RouteLeg>> _routeLegs(
    RoutingBackend backend, {
    required List<Waypoint> waypoints,
    required List<RouteLeg?> legs,
    required CancelToken token,
    required int alternativeIdx,
  }) async {
    final out = [...legs];
    final wayBack = state.ridesBackAnotherWay;
    final returnVariant = state.options.returnVariant;
    final profile = state.options.profile.brouterName;
    final last = legs.length - 1;
    RouteQuery query(int i, int alternative) => RouteQuery(
      points: [waypoints[i].pos, waypoints[i + 1].pos],
      profile: profile,
      alternativeIdx: alternative,
    );

    final todo = <int>[
      for (var i = 0; i < out.length; i++)
        if (out[i] == null && !(wayBack && i == last)) i,
    ];
    final failures = <RoutingException>[];
    for (var from = 0; from < todo.length; from += _legsAtOnce) {
      final batch = todo.sublist(
        from,
        from + _legsAtOnce < todo.length ? from + _legsAtOnce : todo.length,
      );
      await Future.wait([
        for (final i in batch)
          backend
              .route(query(i, alternativeIdx), cancel: token)
              .then<void>(
                (result) => out[i] = RouteLeg.routed(result),
                onError: (Object e, StackTrace st) {
                  if (e is! RoutingException) Error.throwWithStackTrace(e, st);
                  failures.add(e);
                },
              ),
      ]);
      if (token.isCancelled) throw token.toException();
      if (failures.isNotEmpty) throw _oneFailure(failures);
    }
    if (wayBack && out[last] == null) {
      final outbound = PlannedRoute.join(
        out.take(last).cast<RouteLeg>().toList(),
      );
      out[last] = RouteLeg.routed(
        await routeWayBack(
          backend,
          outbound: outbound.positions,
          back: query(last, returnVariant),
          cancel: token,
        ),
      );
    }
    return out.cast<RouteLeg>();
  }

  /// The failure a route of several legs reports: a cancellation as that,
  /// missing tiles as one list of every tile missing, anything else as the
  /// first failure.
  static RoutingException _oneFailure(List<RoutingException> failures) {
    for (final f in failures) {
      if (f.kind == RoutingErrorKind.cancelled) return f;
    }
    final missing = failures
        .where((f) => f.kind == RoutingErrorKind.missingTiles)
        .toList();
    if (missing.isEmpty) return failures.first;
    if (missing.length == 1) return missing.single;
    return RoutingException(
      kind: RoutingErrorKind.missingTiles,
      message: missing.first.message,
      missingTiles: <TileName>{for (final f in missing) ...f.missingTiles}
          .toList(),
    );
  }

  /// Where a route came from, for the planner's "on device"/"server" chip.
  /// Only the composite backend knows; anything else stays silent.
  static RoutingSource? _sourceOf(RoutingBackend backend) =>
      backend is CompositeRoutingBackend ? backend.lastSource : null;
}
