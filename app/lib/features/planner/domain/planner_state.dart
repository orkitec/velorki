import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'route_poi.dart';
import 'routing_options.dart';
import 'waypoint.dart';

part 'planner_state.freezed.dart';

/// One step on the planner's undo stack: the plan as it stood, and the
/// route that was on the map with it.
///
/// Waypoints alone are not enough: closing a loop and cycling the way home
/// change the plan without touching the waypoint list, and each of those has
/// to come back one step at a time.
///
/// Neither is the plan alone. A step carries [result], so taking the step
/// back puts the very route the rider was looking at back on the map instead
/// of asking the router for one between the same points. For a route that
/// came out of a file that is the difference between the course the file
/// drew and the router's own line through it; for a planned one it is the
/// difference between an answer and a wait for the same answer.
///
/// Only the two loop options are kept of the routing options — undoing an
/// edit must not also undo a profile the rider picked since.
@immutable
class PlannerEdit {
  /// Captures one step.
  const PlannerEdit({
    required this.waypoints,
    required this.pois,
    required this.result,
    required this.loadedSurfaceStats,
    required this.routeIsSaved,
    required this.savedRouteId,
    required this.savedRouteName,
    required this.differentWayBack,
    required this.returnVariant,
  });

  /// Snapshots [state] as one step.
  factory PlannerEdit.of(PlannerState state) => PlannerEdit(
    waypoints: state.waypoints,
    pois: state.pois,
    result: state.result,
    loadedSurfaceStats: state.loadedSurfaceStats,
    routeIsSaved: state.routeIsSaved,
    savedRouteId: state.savedRouteId,
    savedRouteName: state.savedRouteName,
    differentWayBack: state.options.differentWayBack,
    returnVariant: state.options.returnVariant,
  );

  /// The waypoints as they were.
  final List<Waypoint> waypoints;

  /// The points beside the route as they were.
  final List<RoutePoi> pois;

  /// The route that was on the map, or `null` when there was none — an
  /// empty plan, or one whose route had not come back yet.
  final RouteResult? result;

  /// [PlannerState.loadedSurfaceStats] as it was, which is the only surface
  /// breakdown a route from the library has.
  final SurfaceStats? loadedSurfaceStats;

  /// [PlannerState.routeIsSaved] as it was.
  final bool routeIsSaved;

  /// [PlannerState.savedRouteId] as it was, so a step that emptied the plan
  /// gives the library row back when it is taken back.
  final String? savedRouteId;

  /// [PlannerState.savedRouteName] as it was.
  final String? savedRouteName;

  /// [RoutingOptions.differentWayBack] as it was.
  final bool differentWayBack;

  /// [RoutingOptions.returnVariant] as it was.
  final int returnVariant;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlannerEdit &&
          other.waypoints == waypoints &&
          other.pois == pois &&
          identical(other.result, result) &&
          other.loadedSurfaceStats == loadedSurfaceStats &&
          other.routeIsSaved == routeIsSaved &&
          other.savedRouteId == savedRouteId &&
          other.savedRouteName == savedRouteName &&
          other.differentWayBack == differentWayBack &&
          other.returnVariant == returnVariant;

  @override
  int get hashCode => Object.hash(
    waypoints,
    pois,
    identityHashCode(result),
    loadedSurfaceStats,
    routeIsSaved,
    savedRouteId,
    savedRouteName,
    differentWayBack,
    returnVariant,
  );
}

/// Everything the Plan tab shows.
@freezed
abstract class PlannerState with _$PlannerState {
  const factory PlannerState({
    /// The waypoints in ride order; the first is the start, the last the end.
    @Default(<Waypoint>[]) List<Waypoint> waypoints,

    /// The plan's points beside the route: places the route is not routed
    /// through, drawn with their kind's icon and saved as the route's own
    /// points of interest.
    @Default(<RoutePoi>[]) List<RoutePoi> pois,

    /// Profile and selected alternative.
    @Default(RoutingOptions()) RoutingOptions options,

    /// The route for [waypoints]; `data(null)` while there is nothing to route.
    @Default(AsyncData<RouteResult?>(null)) AsyncValue<RouteResult?> route,

    /// Alternatives 0..3, fetched only when the user asks for them.
    @Default(<RouteResult>[]) List<RouteResult> alternatives,

    /// Previous edits, newest last.
    @Default(<PlannerEdit>[]) List<PlannerEdit> undoStack,

    /// The last routing failure, in the routing server's own words.
    String? error,

    /// Set while [alternatives] is being fetched.
    @Default(false) bool loadingAlternatives,

    /// Id of the saved route these waypoints were loaded from, if any.
    String? savedRouteId,

    /// Name of that saved route, used as the default in the save dialog.
    String? savedRouteName,

    /// Whether the route shown is the one stored under [savedRouteId], as
    /// loaded or as just saved. Cleared by anything that routes again, so
    /// the planner knows when a change to a waypoint's details alone can go
    /// straight into the library.
    @Default(false) bool routeIsSaved,

    /// Surface statistics of a route loaded from the library, which carries
    /// no BRouter `messages` any more. Cleared as soon as a fresh route
    /// arrives from the routing server.
    SurfaceStats? loadedSurfaceStats,

    /// Which backend computed the shown route, when the composite backend
    /// said. `null` for a route loaded from the library or computed by a
    /// backend that does not report a source.
    RoutingSource? routingSource,
  }) = _PlannerState;

  const PlannerState._();

  /// The route currently shown, or `null` while there is none.
  RouteResult? get result => route.value;

  /// Surface shares of the shown route, from the routing answer or, for a
  /// route loaded from the library, from the stored statistics.
  SurfaceStats? get surfaceStats {
    if (loadedSurfaceStats != null) return loadedSurfaceStats;
    final r = result;
    if (r == null || r.messages.isEmpty) return null;
    return r.surfaceStats;
  }

  /// Estimated riding time of the shown route at the profile's typical speed.
  Duration? get estimatedTime {
    final r = result;
    if (r == null) return null;
    return options.profile.estimatedTime(r.lengthM);
  }

  /// The routing failure of the shown attempt, when it was one.
  RoutingException? get failure {
    final error = route.error;
    return error is RoutingException ? error : null;
  }

  /// The tiles the on-device engine is missing for these waypoints.
  ///
  /// Non-empty only when the composite backend refused the route because it
  /// has no server to fall back to; the planner then offers the download
  /// rather than showing a failure the rider cannot act on.
  List<TileName> get missingTiles {
    final e = failure;
    return e != null && e.kind == RoutingErrorKind.missingTiles
        ? e.missingTiles
        : const <TileName>[];
  }

  /// Whether a route request is in flight.
  bool get isRouting => route.isLoading;

  bool get canUndo => undoStack.isNotEmpty;

  bool get canReverse => waypoints.length >= 2;

  bool get isEmpty => waypoints.isEmpty;

  /// Whether the plan holds anything at all: a waypoint, or a point beside
  /// the route. What Clear has to throw away.
  bool get hasPoints => waypoints.isNotEmpty || pois.isNotEmpty;

  /// Whether enough waypoints are set to ask for a route.
  bool get isRoutable => waypoints.length >= 2;

  /// Whether the plan ends where it started, which is what "Close the loop"
  /// leaves behind.
  bool get isClosedLoop =>
      waypoints.length >= 3 && waypoints.first.pos == waypoints.last.pos;

  /// Whether the route home should avoid the roads of the route out.
  ///
  /// Only a closed plan can: for an ordinary A to B there is no way out to
  /// stay off.
  bool get ridesBackAnotherWay => isClosedLoop && options.differentWayBack;

  /// The waypoint positions, for the routing query and the map.
  List<LatLng> get positions =>
      waypoints.map((w) => w.pos).toList(growable: false);

  /// Whether the current route can be saved to the library.
  bool get canSave {
    final r = result;
    return r != null && r.geometry.isNotEmpty;
  }
}
