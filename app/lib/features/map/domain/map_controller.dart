import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// The planner, recorder and library talk to the map only through this
/// contract. The production implementation wraps maplibre_gl; tests use a
/// fake. Nothing outside `features/map` may import maplibre types.
abstract class MapController {
  /// Camera.
  ///
  /// A `null` [bearing] leaves the map turned the way it is; pass `0` to put
  /// north back at the top.
  ///
  /// [duration] is how long the animation takes; `null` leaves it to the
  /// platform. A follow move asks for roughly the gap between two fixes, so
  /// the camera glides along with the rider instead of jumping and waiting.
  Future<void> moveTo(
    LatLng center, {
    double? zoom,
    double? bearing,
    bool animate = true,
    Duration? duration,
  });
  Future<void> fitBounds(BoundingBox bounds, {double paddingPx = 48});
  LatLng? get center;
  double? get zoom;

  /// Where the top of the map points, in degrees clockwise from north.
  double? get bearing;

  /// Route lines. `id` lets callers keep the main route and alternatives
  /// apart; the same id replaces the previous line.
  Future<void> setRouteLine(
    String id,
    List<LatLng> points, {
    RouteLineStyle style = RouteLineStyle.main,
  });
  Future<void> removeRouteLine(String id);
  Future<void> clearRouteLines();

  /// Waypoint markers, in order. Dragging a marker reports the new position
  /// through [onWaypointDragged] with the marker's index.
  Future<void> setWaypoints(List<MapWaypoint> waypoints);

  /// A recorded or recording track, drawn distinct from planned routes.
  Future<void> setTrackLine(List<LatLng> points);

  /// User position puck. `null` hides it.
  ///
  /// [headingDeg] is a course over ground, so [speedMps] comes with it: the
  /// direction cone is only drawn while the rider actually moves.
  Future<void> setPosition(
    LatLng? position, {
    double? accuracyM,
    double? headingDeg,
    double? speedMps,
  });

  /// Toggle the CyclOSM raster overlay above the vector base map.
  Future<void> setCyclosmOverlay(bool visible);

  /// A pin for a searched place the rider has not decided about yet, with
  /// its name; `null` removes it.
  Future<void> setSearchPin(LatLng? position, {String? label});

  /// Events from the map, set by the owning screen.
  set onTap(ValueChanged<LatLng>? handler);
  set onLongPress(ValueChanged<LatLng>? handler);
  set onWaypointDragged(void Function(int index, LatLng position)? handler);

  /// A tap on a waypoint marker, with the marker's index; the owning screen
  /// offers what can be done with the point (remove it, for one).
  set onWaypointTapped(void Function(int index)? handler);
  set onCameraIdle(VoidCallback? handler);

  /// Visible area, for offline downloads and search bias.
  BoundingBox? get visibleBounds;
}

enum RouteLineStyle { main, alternative, preview }

enum MapWaypointKind { start, via, end }

@immutable
class MapWaypoint {
  const MapWaypoint({required this.position, required this.kind, this.label});

  final LatLng position;
  final MapWaypointKind kind;
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is MapWaypoint &&
      other.position == position &&
      other.kind == kind &&
      other.label == label;

  @override
  int get hashCode => Object.hash(position, kind, label);
}
