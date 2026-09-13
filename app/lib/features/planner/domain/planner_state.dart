import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'routing_options.dart';
import 'waypoint.dart';

part 'planner_state.freezed.dart';

/// One step on the planner's undo stack.
///
/// Waypoints alone are not enough any more: closing a loop and cycling the way
/// home change the plan without touching the waypoint list, and each of those
/// has to come back one step at a time. Only the two loop options are kept —
/// undoing an edit must not also undo a profile the rider picked since.
@immutable
class PlannerEdit {
  /// Captures one state of the plan.
  const PlannerEdit({
    required this.waypoints,
    required this.differentWayBack,
    required this.returnVariant,
  });

  /// Snapshots the loop-shaping part of [state].
  factory PlannerEdit.of(PlannerState state) => PlannerEdit(
    waypoints: state.waypoints,
    differentWayBack: state.options.differentWayBack,
    returnVariant: state.options.returnVariant,
  );

  /// The waypoints as they were.
  final List<Waypoint> waypoints;

  /// [RoutingOptions.differentWayBack] as it was.
  final bool differentWayBack;

  /// [RoutingOptions.returnVariant] as it was.
  final int returnVariant;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlannerEdit &&
          other.waypoints == waypoints &&
          other.differentWayBack == differentWayBack &&
          other.returnVariant == returnVariant;

  @override
  int get hashCode => Object.hash(waypoints, differentWayBack, returnVariant);
}

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
