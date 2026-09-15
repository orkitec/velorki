import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../domain/map_controller.dart';

/// One recorded [MapController.moveTo] call.
@immutable
class RecordedCameraMove {
  const RecordedCameraMove({
    required this.center,
    required this.zoom,
    required this.animate,
    this.bearing,
    this.duration,
  });

  final LatLng center;
  final double? zoom;

  /// The bearing asked for, `null` when the move left the map turned as it
  /// was.
  final double? bearing;
  final bool animate;

  /// How long the move was asked to take, `null` for the platform default.
  final Duration? duration;

  @override
  bool operator ==(Object other) =>
      other is RecordedCameraMove &&
      other.center == center &&
      other.zoom == zoom &&
      other.bearing == bearing &&
      other.animate == animate &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(center, zoom, bearing, animate, duration);

  @override
  String toString() =>
      'RecordedCameraMove($center, zoom: $zoom, bearing: $bearing, '
      'animate: $animate, duration: $duration)';
}

/// One recorded [MapController.fitBounds] call.
@immutable
class RecordedFitBounds {
  const RecordedFitBounds({required this.bounds, required this.paddingPx});

  final BoundingBox bounds;
  final double paddingPx;

  @override
  bool operator ==(Object other) =>
      other is RecordedFitBounds &&
      other.bounds == bounds &&
      other.paddingPx == paddingPx;

  @override
  int get hashCode => Object.hash(bounds, paddingPx);

  @override
  String toString() => 'RecordedFitBounds($bounds, padding: $paddingPx)';
}

/// A route line as the fake last saw it.
@immutable
class RecordedRouteLine {
  const RecordedRouteLine({
    required this.id,
    required this.points,
    required this.style,
  });

  final String id;
  final List<LatLng> points;
  final RouteLineStyle style;

  @override
  String toString() =>
      'RecordedRouteLine($id, ${points.length} points, ${style.name})';
}

/// The last position pushed into [MapController.setPosition].
@immutable
class RecordedPosition {
  const RecordedPosition({
    this.position,
    this.accuracyM,
    this.headingDeg,
    this.speedMps,
    this.headingFromCompass = false,
    this.minimal = false,
  });

  final LatLng? position;
  final double? accuracyM;
  final double? headingDeg;
  final double? speedMps;

  /// Whether the heading came from the phone's compass rather than the GPS.
  final bool headingFromCompass;

  /// Whether the bare dot was asked for, without ring or cone.
  final bool minimal;

  @override
  bool operator ==(Object other) =>
      other is RecordedPosition &&
      other.position == position &&
      other.accuracyM == accuracyM &&
      other.headingDeg == headingDeg &&
      other.speedMps == speedMps &&
      other.headingFromCompass == headingFromCompass &&
      other.minimal == minimal;

  @override
  int get hashCode => Object.hash(
    position,
    accuracyM,
    headingDeg,
    speedMps,
    headingFromCompass,
    minimal,
  );

  @override
  String toString() =>
      'RecordedPosition($position, accuracy: $accuracyM, '
      'heading: $headingDeg, speed: $speedMps, '
      'fromCompass: $headingFromCompass, minimal: $minimal)';
}

/// A [MapController] that records everything and renders nothing.
///
/// This is the seam that lets the planner, the recorder and the library be
/// widget tested: a real map is a platform view and cannot run in
/// `flutter test`. Handlers can be fired from a test with the `emit*` methods.
class FakeMapController implements MapController {
  /// Every [moveTo] call, in order.
  final List<RecordedCameraMove> cameraMoves = <RecordedCameraMove>[];

  /// Every [fitBounds] call, in order.
  final List<RecordedFitBounds> boundsFits = <RecordedFitBounds>[];

  /// Live route lines by id, in insertion order.
  final Map<String, RecordedRouteLine> routeLines =
      <String, RecordedRouteLine>{};

  /// Every [setRouteLine] call, including replacements of the same id.
  final List<RecordedRouteLine> routeLineCalls = <RecordedRouteLine>[];

  /// Ids passed to [removeRouteLine].
  final List<String> removedRouteLines = <String>[];

  /// How often [clearRouteLines] was called.
  int clearRouteLinesCount = 0;

  /// The waypoints of the last [setWaypoints] call.
  List<MapWaypoint> waypoints = const <MapWaypoint>[];

  /// Every [setWaypoints] call, in order.
  final List<List<MapWaypoint>> waypointCalls = <List<MapWaypoint>>[];

  /// The points of the last [setTrackLine] call.
  List<LatLng> trackLine = const <LatLng>[];

  /// Every [setTrackLine] call, in order.
  final List<List<LatLng>> trackLineCalls = <List<LatLng>>[];

  /// The last [setPosition] call, `null` until one happens.
  RecordedPosition? position;

  /// Every [setPosition] call, in order.
  final List<RecordedPosition> positionCalls = <RecordedPosition>[];

  /// The last value passed to [setCyclosmOverlay].
  bool cyclosmOverlay = false;

  /// Every [setCyclosmOverlay] call, in order.
  final List<bool> cyclosmOverlayCalls = <bool>[];

  @override
  LatLng? center;

  @override
  double? zoom;

  @override
  double? bearing;

  @override
  BoundingBox? visibleBounds;

  @override
  ValueChanged<LatLng>? onTap;

  @override
  ValueChanged<LatLng>? onLongPress;

  @override
  void Function(int index, LatLng position)? onWaypointDragged;

  @override
  void Function(int index)? onWaypointTapped;

  @override
  VoidCallback? onCameraIdle;

  /// Forgets every recorded call; the handlers and the camera stay.
  void reset() {
    cameraMoves.clear();
    boundsFits.clear();
    routeLines.clear();
    routeLineCalls.clear();
    removedRouteLines.clear();
    clearRouteLinesCount = 0;
    waypoints = const <MapWaypoint>[];
    waypointCalls.clear();
    trackLine = const <LatLng>[];
    trackLineCalls.clear();
    position = null;
    positionCalls.clear();
    cyclosmOverlay = false;
    cyclosmOverlayCalls.clear();
  }

  // ------------------------------------------------------- event injection

  /// Pretends the user tapped the map at [position].
  void emitTap(LatLng position) => onTap?.call(position);

  /// Pretends the user long pressed the map at [position].
  void emitLongPress(LatLng position) => onLongPress?.call(position);

  /// Pretends the user dragged waypoint [index] to [position].
  void emitWaypointDragged(int index, LatLng position) =>
      onWaypointDragged?.call(index, position);

  /// Pretends the user tapped waypoint [index].
  void emitWaypointTapped(int index) => onWaypointTapped?.call(index);

  /// Pretends the camera came to rest.
  void emitCameraIdle() => onCameraIdle?.call();

  // ------------------------------------------------------------- recording

  @override
  Future<void> moveTo(
    LatLng center, {
    double? zoom,
    double? bearing,
    bool animate = true,
    Duration? duration,
  }) async {
    cameraMoves.add(
      RecordedCameraMove(
        center: center,
        zoom: zoom,
        bearing: bearing,
        animate: animate,
        duration: duration,
      ),
    );
    this.center = center;
    if (zoom != null) this.zoom = zoom;
    if (bearing != null) this.bearing = bearing;
  }

  @override
  Future<void> fitBounds(BoundingBox bounds, {double paddingPx = 48}) async {
    boundsFits.add(RecordedFitBounds(bounds: bounds, paddingPx: paddingPx));
    center = bounds.center;
    visibleBounds = bounds;
  }

  @override
  Future<void> setRouteLine(
    String id,
    List<LatLng> points, {
    RouteLineStyle style = RouteLineStyle.main,
  }) async {
    final line = RecordedRouteLine(
      id: id,
      points: List<LatLng>.unmodifiable(points),
      style: style,
    );
    routeLines[id] = line;
    routeLineCalls.add(line);
  }

  @override
  Future<void> removeRouteLine(String id) async {
    removedRouteLines.add(id);
    routeLines.remove(id);
  }

  @override
  Future<void> clearRouteLines() async {
    clearRouteLinesCount++;
    routeLines.clear();
  }

  @override
  Future<void> setWaypoints(List<MapWaypoint> waypoints) async {
    final copy = List<MapWaypoint>.unmodifiable(waypoints);
    this.waypoints = copy;
    waypointCalls.add(copy);
  }

  @override
  Future<void> setTrackLine(List<LatLng> points) async {
    final copy = List<LatLng>.unmodifiable(points);
    trackLine = copy;
    trackLineCalls.add(copy);
  }

  @override
  Future<void> setPosition(
    LatLng? position, {
    double? accuracyM,
    double? headingDeg,
    double? speedMps,
    bool headingFromCompass = false,
    bool minimal = false,
  }) async {
    final recorded = RecordedPosition(
      position: position,
      accuracyM: accuracyM,
      headingDeg: headingDeg,
      speedMps: speedMps,
      headingFromCompass: headingFromCompass,
      minimal: minimal,
    );
    this.position = recorded;
    positionCalls.add(recorded);
  }

  /// The searched place shown, if any.
  LatLng? searchPin;

  /// Its label.
  String? searchPinLabel;

  @override
  Future<void> setSearchPin(LatLng? position, {String? label}) async {
    searchPin = position;
    searchPinLabel = position == null ? null : label;
  }

  @override
  Future<void> setCyclosmOverlay(bool visible) async {
    cyclosmOverlay = visible;
    cyclosmOverlayCalls.add(visible);
  }
}
