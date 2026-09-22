import 'dart:async';

import 'package:velorki_geo/velorki_geo.dart';

import '../../map/domain/map_controller.dart';
import '../domain/planner_state.dart';
import '../domain/waypoint.dart';
import 'planner_controller.dart';

/// Id of the main route line on the map.
const String mainRouteLineId = 'main';

/// The line id of the route the rider chose: the main route keeps
/// [mainRouteLineId]; a chosen alternative carries its index, so the map
/// draws it in that alternative's colour, on top like the main route.
String chosenRouteLineId(int alternativeIdx) =>
    alternativeIdx == 0 ? mainRouteLineId : '$mainRouteLineId-$alternativeIdx';

/// Id of alternative [index] on the map.
String alternativeLineId(int index) => 'alt-$index';

/// Keeps the map in step with [PlannerState] and turns map gestures into
/// planner actions.
///
/// The planner never touches maplibre: everything goes through
/// [MapController], which the widget tests fake.
class PlannerMapBinding {
  /// Binds [map] to [planner].
  PlannerMapBinding({required this.map, required this.planner});

  /// The map being driven.
  final MapController map;

  /// The planner the gestures are reported to.
  final PlannerController planner;

  final Set<String> _lineIds = <String>{};
  // `null` until the first sync: the first state is the baseline, not a change.
  int? _lastWaypointCount;
  bool _attached = false;

  /// Subscribes to the map's gestures.
  void attach() {
    if (_attached) return;
    _attached = true;
    map.onTap = (pos) => planner.addWaypoint(pos);
    map.onLongPress = (pos) => planner.insertWaypoint(pos);
    map.onWaypointDragged = planner.moveWaypoint;
    map.onWaypointTapped = (index) => onWaypointTap?.call(index);
  }

  /// What the screen does when a marker is tapped; `null` does nothing.
  void Function(int index)? onWaypointTap;

  /// Unsubscribes, so a disposed screen cannot move waypoints any more.
  void detach() {
    if (!_attached) return;
    _attached = false;
    map.onTap = null;
    map.onLongPress = null;
    map.onWaypointDragged = null;
    map.onWaypointTapped = null;
  }

  /// Takes everything this binding drew off the map — the markers and every
  /// line — for a tab that leaves the shared map to the other. The next
  /// [sync] draws it all again; what it remembers of the plan's history
  /// stays, so a route that arrived whole while the tab was away still gets
  /// its fit when the tab comes back.
  Future<void> clear() async {
    await map.setWaypoints(const <MapWaypoint>[]);
    for (final id in _lineIds) {
      await map.removeRouteLine(id);
    }
    _lineIds.clear();
  }

  /// Pushes [state] to the map: markers, the main line and the alternatives.
  ///
  /// The camera is only moved when a whole route appears at once — which is
  /// what loading a saved route does — never while the user is editing.
  Future<void> sync(PlannerState state) async {
    // A closed loop's last waypoint sits exactly on its first: one marker
    // is enough, and the start marker stays the one to drag.
    final shown = state.isClosedLoop
        ? state.waypoints.sublist(0, state.waypoints.length - 1)
        : state.waypoints;
    await map.setWaypoints(shown.map(_marker).toList(growable: false));

    final result = state.result;
    final positions = result?.positions ?? const <LatLng>[];
    final wanted = <String>{};

    if (positions.isNotEmpty) {
      final chosen = chosenRouteLineId(state.options.alternativeIdx);
      wanted.add(chosen);
      await map.setRouteLine(chosen, positions);
    }
    for (var i = 0; i < state.alternatives.length; i++) {
      if (i == state.options.alternativeIdx) continue;
      final points = state.alternatives[i].positions;
      if (points.isEmpty) continue;
      final id = alternativeLineId(i);
      wanted.add(id);
      await map.setRouteLine(id, points, style: RouteLineStyle.alternative);
    }
    for (final id in _lineIds.difference(wanted)) {
      await map.removeRouteLine(id);
    }
    _lineIds
      ..clear()
      ..addAll(wanted);

    // Only a plan that went from nothing to a whole route in one step (a
    // saved route being loaded) moves the camera. A binding that is new
    // because the map's style reloaded must not: the rider was somewhere
    // else on purpose, and a jump to the route would look like a jump back
    // to the start.
    final previous = _lastWaypointCount;
    final appearedAtOnce = previous == 0 && state.waypoints.length > 1;
    _lastWaypointCount = state.waypoints.length;
    if (previous != null && appearedAtOnce && positions.isNotEmpty) {
      await map.fitBounds(BoundingBox.fromPoints(positions));
    }
  }

  MapWaypoint _marker(Waypoint w) => MapWaypoint(
    position: w.pos,
    kind: switch (w.kind) {
      WaypointKind.start => MapWaypointKind.start,
      WaypointKind.via => MapWaypointKind.via,
      WaypointKind.end => MapWaypointKind.end,
    },
    label: w.name,
  );
}
