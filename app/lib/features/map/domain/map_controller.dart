import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// The planner, recorder and library talk to the map only through this
/// contract. The production implementation wraps maplibre_gl; tests use a
/// fake. Nothing outside `features/map` may import maplibre types.
abstract class MapController {
  /// Camera.
  Future<void> moveTo(LatLng center, {double? zoom, bool animate = true});
  Future<void> fitBounds(BoundingBox bounds, {double paddingPx = 48});
  LatLng? get center;
  double? get zoom;

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
  Future<void> setPosition(
    LatLng? position, {
    double? accuracyM,
    double? headingDeg,
  });

  /// Toggle the CyclOSM raster overlay above the vector base map.
  Future<void> setCyclosmOverlay(bool visible);

  /// Events from the map, set by the owning screen.
  set onTap(ValueChanged<LatLng>? handler);
  set onLongPress(ValueChanged<LatLng>? handler);
  set onWaypointDragged(void Function(int index, LatLng position)? handler);
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
