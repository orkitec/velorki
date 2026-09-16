/// Test doubles for the emulator suite.
///
/// The widget tests under `test/features/*/support/` have equivalents of most
/// of these, but `test/` is not on the import path of a `package:velorki`
/// build: `integration_test/` would have to reach them through a relative
/// `../test/...` import, which drags that whole harness (an in-memory drift
/// database, dio fixtures, a fake map view) into an on-device build where the
/// real ones are wanted. So the few doubles that are needed here are copied,
/// kept to the minimum, and nothing else is shared.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A location permission that is simply granted, so nothing on the emulator
/// has to tap a system dialog the test runner cannot see.
class GrantedLocationPermission implements LocationPermissionGateway {
  /// Creates the gateway.
  const GrantedLocationPermission();

  @override
  Future<LocationPermissionStatus> check() async =>
      LocationPermissionStatus.granted;

  @override
  Future<LocationPermissionStatus> request() async =>
      LocationPermissionStatus.granted;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

/// A position source that always answers with the same fix.
class FixedPositionSource implements PositionSource {
  /// Creates a source answering with [position].
  const FixedPositionSource(this.position);

  /// Where the device is.
  final LatLng position;

  geo.Position get _fix => fix(position, seconds: 0, speed: 0);

  @override
  Stream<geo.Position> positions(geo.LocationSettings settings) =>
      Stream<geo.Position>.value(_fix);

  @override
  Future<geo.Position?> lastKnown() async => _fix;

  @override
  Future<geo.Position?> current({
    Duration timeLimit = const Duration(seconds: 10),
  }) async => _fix;
}

/// A position source the test feeds one fix at a time.
///
/// The recorder subscribes to [positions] once; [emit] then pushes a fix into
/// that subscription, so the test decides exactly how the ride unfolds.
class ScriptedPositionSource implements PositionSource {
  /// Creates a source whose first answer to [current]/[lastKnown] is [origin].
  ScriptedPositionSource(this.origin);

  /// Where the ride starts.
  final LatLng origin;

  final StreamController<geo.Position> _positions =
      StreamController<geo.Position>.broadcast();

  /// Every fix that was pushed, in order.
  final List<geo.Position> emitted = <geo.Position>[];

  /// Whether the recorder has subscribed yet.
  bool get isListenedTo => _positions.hasListener;

  /// Pushes one fix.
  void emit(geo.Position position) {
    emitted.add(position);
    _positions.add(position);
  }

  @override
  Stream<geo.Position> positions(geo.LocationSettings settings) =>
      _positions.stream;

  @override
  Future<geo.Position?> lastKnown() async =>
      emitted.isEmpty ? fix(origin, seconds: 0, speed: 0) : emitted.last;

  @override
  Future<geo.Position?> current({
    Duration timeLimit = const Duration(seconds: 10),
  }) async => lastKnown();

  /// Closes the stream.
  Future<void> close() => _positions.close();
}

/// A geolocator fix at [position], timestamped [seconds] after 10:00 UTC.
geo.Position fix(
  LatLng position, {
  required int seconds,
  double speed = 5,
  double ele = 0,
}) => geo.Position(
  latitude: position.lat,
  longitude: position.lon,
  timestamp: DateTime.utc(2026, 9, 12, 10, 0, seconds),
  accuracy: 4,
  altitude: ele,
  altitudeAccuracy: 2,
  heading: 90,
  headingAccuracy: 5,
  speed: speed,
  speedAccuracy: 1,
  hasAccuracy: true,
  hasAltitude: true,
  hasHeading: true,
  hasSpeed: true,
);

/// A notification permission that is always granted, so `start()` never waits
/// for the POST_NOTIFICATIONS prompt.
class GrantedNotificationPermission implements NotificationPermissionGateway {
  /// Creates the gateway.
  const GrantedNotificationPermission();

  @override
  Future<bool> isGranted() async => true;

  @override
  Future<bool> request() async => true;
}

/// A battery-optimisation gateway that is already exempt, so the recording
/// screen never opens the system settings page.
class ExemptBatteryOptimization implements BatteryOptimizationGateway {
  /// Creates the gateway.
  const ExemptBatteryOptimization();

  @override
  Future<bool> isIgnored() async => true;

  @override
  Future<bool> request() async => true;
}

/// A wake lock that only remembers its state.
class RecordingScreenWake implements ScreenWake {
  /// Whether the display is being kept awake.
  bool enabled = false;

  @override
  Future<void> enable() async => enabled = true;

  @override
  Future<void> disable() async => enabled = false;
}

/// A dio adapter that answers every request from a canned body.
///
/// Used for the Photon geocoder: the public instance is a third-party service,
/// so hanging the search test off its availability would make the suite red
/// for reasons that have nothing to do with Velorki. The request still goes
/// through the real [PhotonClient], the real URL builder and the real
/// GeoJSON parser — only the socket is replaced.
class CannedHttpAdapter implements HttpClientAdapter {
  /// Answers every request with [body].
  CannedHttpAdapter(this.body);

  /// The body to return.
  String body;

  /// Every request that arrived, in order.
  final List<Uri> requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// An HTTP adapter that fails every request.
///
/// The offline search test hands this to the geocoder: if anything reaches
/// the network the test does not merely slow down, it goes red, which is the
/// only way to prove that the results came off the device.
class FailingHttpAdapter implements HttpClientAdapter {
  /// Creates the adapter.
  FailingHttpAdapter();

  /// Every request that arrived, in order. Must stay empty.
  final List<Uri> requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'the offline search test allows no network',
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A one-feature Photon `FeatureCollection` for [name] at [position].
String photonAnswer({
  required String name,
  required LatLng position,
  required String city,
}) =>
    '{"type":"FeatureCollection","features":[{"type":"Feature",'
    '"geometry":{"type":"Point","coordinates":'
    '[${position.lon},${position.lat}]},'
    '"properties":{"osm_key":"place","osm_value":"suburb",'
    '"name":"$name","city":"$city","country":"Testland"}}]}';

/// A [MapController] that records what the app drew and forwards it to the
/// real map underneath.
///
/// The map controller the planner talks to is private to the screen, and the
/// real MapLibre one has no getter for the lines on it, so this is the only
/// way to assert from a test that the route is still drawn — for instance
/// after a style reload, which throws the layers away and rebuilds them.
class RecordingMapController implements MapController {
  /// Wraps [inner].
  RecordingMapController(this.inner);

  /// The real controller.
  final MapController inner;

  /// The points of each line currently on the map, by id.
  final Map<String, List<LatLng>> lines = <String, List<LatLng>>{};

  /// Every `setRouteLine` call, in order, as `id:pointCount`.
  final List<String> routeLineCalls = <String>[];

  /// The waypoints last pushed.
  List<MapWaypoint> waypoints = const <MapWaypoint>[];

  @override
  Future<void> setRouteLine(
    String id,
    List<LatLng> points, {
    RouteLineStyle style = RouteLineStyle.main,
  }) async {
    lines[id] = points;
    routeLineCalls.add('$id:${points.length}');
    return inner.setRouteLine(id, points, style: style);
  }

  @override
  Future<void> removeRouteLine(String id) async {
    lines.remove(id);
    return inner.removeRouteLine(id);
  }

  @override
  Future<void> clearRouteLines() async {
    lines.clear();
    return inner.clearRouteLines();
  }

  @override
  Future<void> setWaypoints(List<MapWaypoint> waypoints) {
    this.waypoints = waypoints;
    return inner.setWaypoints(waypoints);
  }

  @override
  LatLng? get center => inner.center;

  @override
  double? get zoom => inner.zoom;

  @override
  double? get bearing => inner.bearing;

  @override
  BoundingBox? get visibleBounds => inner.visibleBounds;

  @override
  set onTap(ValueChanged<LatLng>? handler) => inner.onTap = handler;

  @override
  set onLongPress(ValueChanged<LatLng>? handler) => inner.onLongPress = handler;

  @override
  set onWaypointDragged(void Function(int index, LatLng position)? handler) =>
      inner.onWaypointDragged = handler;

  @override
  set onWaypointTapped(void Function(int index)? handler) =>
      inner.onWaypointTapped = handler;

  @override
  set onCameraIdle(VoidCallback? handler) => inner.onCameraIdle = handler;

  @override
  Future<void> moveTo(
    LatLng center, {
    double? zoom,
    double? bearing,
    bool animate = true,
    Duration? duration,
  }) => inner.moveTo(
    center,
    zoom: zoom,
    bearing: bearing,
    animate: animate,
    duration: duration,
  );

  @override
  Future<void> fitBounds(BoundingBox bounds, {double paddingPx = 48}) =>
      inner.fitBounds(bounds, paddingPx: paddingPx);

  @override
  Future<void> setTrackLine(List<LatLng> points) => inner.setTrackLine(points);

  @override
  Future<void> setTrackSegments(List<TrackSegment> segments) =>
      inner.setTrackSegments(segments);

  @override
  Future<void> setPosition(
    LatLng? position, {
    double? accuracyM,
    double? headingDeg,
    double? speedMps,
    bool headingFromCompass = false,
    bool minimal = false,
  }) => inner.setPosition(
    position,
    accuracyM: accuracyM,
    headingDeg: headingDeg,
    speedMps: speedMps,
    headingFromCompass: headingFromCompass,
    minimal: minimal,
  );

  @override
  Future<void> setSearchPin(LatLng? position, {String? label}) =>
      inner.setSearchPin(position, label: label);

  @override
  Future<void> setCyclosmOverlay(bool visible) =>
      inner.setCyclosmOverlay(visible);
}
