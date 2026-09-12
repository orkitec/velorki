import 'dart:async';

import 'package:velorki_geo/velorki_geo.dart';

import '../../map/domain/map_controller.dart';
import '../domain/planner_state.dart';
import '../domain/waypoint.dart';
import 'planner_controller.dart';

/// Id of the main route line on the map.
const String mainRouteLineId = 'main';

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
  int _lastWaypointCount = 0;
  bool _attached = false;

  /// Subscribes to the map's gestures.
  void attach() {
    if (_attached) return;
    _attached = true;
    map.onTap = (pos) => planner.addWaypoint(pos);
    map.onLongPress = (pos) => planner.insertWaypoint(pos);
    map.onWaypointDragged = planner.moveWaypoint;
  }

  /// Unsubscribes, so a disposed screen cannot move waypoints any more.
  void detach() {
    if (!_attached) return;
    _attached = false;
    map.onTap = null;
    map.onLongPress = null;
    map.onWaypointDragged = null;
  }

  /// Pushes [state] to the map: markers, the main line and the alternatives.
  ///
  /// The camera is only moved when a whole route appears at once — which is
  /// what loading a saved route does — never while the user is editing.
  Future<void> sync(PlannerState state) async {
    await map.setWaypoints(
      state.waypoints.map(_marker).toList(growable: false),
    );

    final result = state.result;
    final positions = result?.positions ?? const <LatLng>[];
    final wanted = <String>{};

    if (positions.isNotEmpty) {
      wanted.add(mainRouteLineId);
      await map.setRouteLine(mainRouteLineId, positions);
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

    final appearedAtOnce =
        _lastWaypointCount == 0 && state.waypoints.length > 1;
    _lastWaypointCount = state.waypoints.length;
    if (appearedAtOnce && positions.isNotEmpty) {
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
