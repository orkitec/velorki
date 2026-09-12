import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'routing_options.dart';
import 'waypoint.dart';

part 'planner_state.freezed.dart';

/// Everything the Plan tab shows.
@freezed
abstract class PlannerState with _$PlannerState {
  const factory PlannerState({
    /// The waypoints in ride order; the first is the start, the last the end.
    @Default(<Waypoint>[]) List<Waypoint> waypoints,

    /// Profile and selected alternative.
    @Default(RoutingOptions()) RoutingOptions options,

    /// The route for [waypoints]; `data(null)` while there is nothing to route.
    @Default(AsyncData<RouteResult?>(null)) AsyncValue<RouteResult?> route,

    /// Alternatives 0..3, fetched only when the user asks for them.
    @Default(<RouteResult>[]) List<RouteResult> alternatives,

    /// Previous waypoint lists, newest last.
    @Default(<List<Waypoint>>[]) List<List<Waypoint>> undoStack,

    /// The last routing failure, in the routing server's own words.
    String? error,

    /// Set while [alternatives] is being fetched.
    @Default(false) bool loadingAlternatives,

    /// Id of the saved route these waypoints were loaded from, if any.
    String? savedRouteId,

    /// Name of that saved route, used as the default in the save dialog.
    String? savedRouteName,

    /// Surface statistics of a route loaded from the library, which carries
    /// no BRouter `messages` any more. Cleared as soon as a fresh route
    /// arrives from the routing server.
    SurfaceStats? loadedSurfaceStats,
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

  /// Whether a route request is in flight.
  bool get isRouting => route.isLoading;

  bool get canUndo => undoStack.isNotEmpty;

  bool get canReverse => waypoints.length >= 2;

  bool get isEmpty => waypoints.isEmpty;

  /// Whether enough waypoints are set to ask for a route.
  bool get isRoutable => waypoints.length >= 2;

  /// The waypoint positions, for the routing query and the map.
  List<LatLng> get positions =>
      waypoints.map((w) => w.pos).toList(growable: false);

  /// Whether the current route can be saved to the library.
  bool get canSave {
    final r = result;
    return r != null && r.geometry.isNotEmpty;
  }
}
