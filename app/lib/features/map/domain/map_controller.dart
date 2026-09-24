import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/widgets.dart' show IconData;
import 'package:velorki_geo/velorki_geo.dart';

/// The planner, recorder and library talk to the map only through this
/// contract. The production implementation wraps maplibre_gl; tests use a
/// fake. Nothing outside `features/map` may import maplibre types.
abstract class MapController {
  /// Whether the map can draw right now: its style is loaded and attached.
  /// A layer set on a map that is not ready is remembered and drawn once it
  /// is; a page that wants to be sure draws again when this turns true.
  bool get isReady => true;

  /// Camera.
  ///
  /// A `null` [bearing] leaves the map turned the way it is; pass `0` to put
  /// north back at the top.
  ///
  /// [duration] is how long the animation takes; `null` leaves it to the
  /// platform. A follow move asks for roughly the gap between two fixes, so
  /// the camera glides along with the rider instead of jumping and waiting.
  ///
  /// [padding] is what covers the map's edges, in pixels per side: with it,
  /// [center] lands in the middle of the part left visible rather than in
  /// the middle of the whole map, so a located rider is not under the sheet.
  Future<void> moveTo(
    LatLng center, {
    double? zoom,
    double? bearing,
    bool animate = true,
    Duration? duration,
    EdgeInsets padding = EdgeInsets.zero,
  });

  /// Moves the camera so that [bounds] fills the view inside [padding], in
  /// pixels per side: a screen with a card over the lower half asks for a
  /// bottom inset the height of the card, so the route lands above it.
  Future<void> fitBounds(
    BoundingBox bounds, {
    EdgeInsets padding = const EdgeInsets.all(48),
  });
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

  /// Points of interest beside the route, each a small marker with its name;
  /// an empty list takes them away. A tap on one reports through
  /// [onPoiTapped] with its index.
  Future<void> setPois(List<MapPoi> pois);

  /// Small markers on the turns of a route, for a screen that reads the
  /// route rather than rides it; an empty list takes them away. A tap on one
  /// reports through [onTurnTapped] with its index.
  Future<void> setTurnMarkers(List<MapTurnMarker> turns);

  /// A recorded or recording track, drawn distinct from planned routes.
  Future<void> setTrackLine(List<LatLng> points);

  /// The same track cut into pieces and coloured by how fast each was ridden.
  ///
  /// Replaces whatever [setTrackLine] drew, and vice versa: there is one
  /// track on the map. A finished ride is drawn this way, a running recording
  /// through [setTrackLine], which has nothing to colour by yet.
  Future<void> setTrackSegments(List<TrackSegment> segments);

  /// User position puck. `null` hides it.
  ///
  /// [headingDeg] is a course over ground, so [speedMps] comes with it: the
  /// direction cone is only drawn while the rider actually moves.
  ///
  /// [headingFromCompass] says the heading came from the phone's magnetometer
  /// instead, which is true standing still: the cone is then drawn whatever
  /// the speed.
  ///
  /// [minimal] draws the bare dot: no accuracy ring, no direction cone. That
  /// is what a battery-saver ride asks for — fewer pixels lit and less for the
  /// map to redraw on every fix.
  Future<void> setPosition(
    LatLng? position, {
    double? accuracyM,
    double? headingDeg,
    double? speedMps,
    bool headingFromCompass = false,
    bool minimal = false,
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

  /// A tap on a point of interest, with its index in the last [setPois].
  set onPoiTapped(void Function(int index)? handler);

  /// A tap on a turn marker, with its index in the last [setTurnMarkers].
  set onTurnTapped(void Function(int index)? handler);
  set onCameraIdle(VoidCallback? handler);

  /// Visible area, for offline downloads and search bias.
  BoundingBox? get visibleBounds;
}

/// One piece of a coloured track: a polyline and where it sits between the
/// ride's slowest and its fastest stretch.
@immutable
class TrackSegment {
  /// Creates a segment; [t] is clamped to 0..1.
  TrackSegment({required this.points, required double t})
    : t = t.clamp(0.0, 1.0);

  /// The polyline, in riding order.
  final List<LatLng> points;

  /// 0 is the slow end of the colour ramp, 1 the fast end.
  final double t;

  @override
  bool operator ==(Object other) =>
      other is TrackSegment && other.t == t && listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(t, Object.hashAll(points));

  @override
  String toString() => 'TrackSegment(${points.length} points, t: $t)';
}

enum RouteLineStyle { main, alternative, preview }

enum MapWaypointKind { start, via, end }

/// What a point of interest is about, which picks its colour.
enum MapPoiKind { danger, water, food, generic }

/// A turn marker: where a route turns, for reading the route on a map.
class MapTurnMarker {
  const MapTurnMarker({required this.position});

  final LatLng position;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapTurnMarker && other.position == position;

  @override
  int get hashCode => position.hashCode;
}

/// A point of interest marker: a named place beside the route.
class MapPoi {
  const MapPoi({
    required this.position,
    required this.name,
    required this.kind,
    this.icon,
    this.selected = false,
  });

  final LatLng position;
  final String name;
  final MapPoiKind kind;

  /// The icon drawn on the marker, from the app's own icon table; `null`
  /// leaves the plain disc. [kind] still picks the colour.
  final IconData? icon;

  /// Whether this is the point the rider has chosen, from the map or from a
  /// list beside it. A chosen point wears a wider disc in the chosen colour
  /// and a larger name; it keeps its icon, like every other state.
  final bool selected;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapPoi &&
          other.position == position &&
          other.name == name &&
          other.kind == kind &&
          other.icon == icon &&
          other.selected == selected;

  @override
  int get hashCode => Object.hash(position, name, kind, icon, selected);
}

@immutable
class MapWaypoint {
  const MapWaypoint({
    required this.position,
    required this.kind,
    this.label,
    this.icon,
    this.selected = false,
  });

  final LatLng position;
  final MapWaypointKind kind;
  final String? label;

  /// What the point stands for: a fountain, a hazard, a summit. The disc
  /// carries this instead of the point's number, and the number moves into
  /// the label. `null` for a plain point, whose disc carries the number.
  final IconData? icon;

  /// Whether this is the point the rider has chosen. See [MapPoi.selected].
  final bool selected;

  @override
  bool operator ==(Object other) =>
      other is MapWaypoint &&
      other.position == position &&
      other.kind == kind &&
      other.label == label &&
      other.icon == icon &&
      other.selected == selected;

  @override
  int get hashCode => Object.hash(position, kind, label, icon, selected);
}
