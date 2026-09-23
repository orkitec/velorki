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
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
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
  double heading = 90,
}) => geo.Position(
  latitude: position.lat,
  longitude: position.lon,
  timestamp: DateTime.utc(2026, 9, 12, 10, 0, seconds),
  accuracy: 4,
  altitude: ele,
  altitudeAccuracy: 2,
  heading: heading,
  headingAccuracy: 5,
  speed: speed,
  speedAccuracy: 1,
  hasAccuracy: true,
  hasAltitude: true,
  hasHeading: true,
  hasSpeed: true,
);

/// A rider following a planned route, one fix at a time.
///
/// Wraps a [ScriptedPositionSource] and walks [line]: [rideTo] pushes a fix
/// every [stepM] metres up to a distance along the route, [strayTo] pushes one
/// beside it. Every fix carries the course of the segment being ridden and a
/// speed, which `adb emu geo fix` cannot give and navigation needs — the
/// re-route only goes out for a rider who is actually moving, and the map
/// turns with the course.
///
/// The timestamps advance by the distance covered at [speedMps] rather than
/// with the wall clock, so the recorder sees a steady ride however fast the
/// test pushes the fixes; they are always at least a second apart, because a
/// fix that does not move the clock on is rejected as a duplicate.
class ScriptedRide {
  /// Creates a rider for [line], pushing into [source].
  ScriptedRide({
    required this.source,
    required List<LatLng> line,
    this.stepM = 10,
    this.speedMps = 5,
  }) : line = List<LatLng>.unmodifiable(line),
       _cumulative = List<double>.filled(line.length, 0) {
    for (var i = 1; i < this.line.length; i++) {
      _cumulative[i] =
          _cumulative[i - 1] + haversineMeters(this.line[i - 1], this.line[i]);
    }
  }

  /// Where the fixes go.
  final ScriptedPositionSource source;

  /// The route geometry being ridden.
  final List<LatLng> line;

  /// Metres between two fixes.
  final double stepM;

  /// How fast the rider travels, in metres per second.
  final double speedMps;

  final List<double> _cumulative;
  double _alongM = 0;
  int _seconds = 0;
  LatLng? _last;

  /// The length of the route, in metres.
  double get totalM => _cumulative.isEmpty ? 0 : _cumulative.last;

  /// How far along the route the rider has got, in metres.
  double get alongM => _alongM;

  /// The point [metres] along the route.
  LatLng pointAt(double metres) {
    if (line.isEmpty) return const LatLng(0, 0);
    if (metres <= 0) return line.first;
    if (metres >= totalM) return line.last;
    var i = 1;
    while (i < _cumulative.length - 1 && _cumulative[i] < metres) {
      i++;
    }
    final span = _cumulative[i] - _cumulative[i - 1];
    final t = span <= 0 ? 0.0 : (metres - _cumulative[i - 1]) / span;
    return LatLng(
      line[i - 1].lat + (line[i].lat - line[i - 1].lat) * t,
      line[i - 1].lon + (line[i].lon - line[i - 1].lon) * t,
    );
  }

  /// Which way the route runs [metres] along it, in degrees from north.
  double bearingAt(double metres) {
    if (line.length < 2) return 0;
    var i = 1;
    while (i < _cumulative.length - 1 && _cumulative[i] < metres) {
      i++;
    }
    return bearingDegrees(line[i - 1], line[i]);
  }

  /// Rides on to [targetM] metres along the route, pumping [pump] between the
  /// fixes so the app has a frame to take each of them in.
  Future<void> rideTo(
    WidgetTester tester,
    double targetM, {
    Duration pump = const Duration(milliseconds: 40),
  }) async {
    final target = targetM.clamp(0.0, totalM);
    while (_alongM < target) {
      _alongM = math.min(target, _alongM + stepM);
      await _emit(tester, pointAt(_alongM), bearingAt(_alongM), pump);
    }
  }

  /// Pushes one fix [offsetM] metres to the right of where the rider stands,
  /// without moving them along the route.
  ///
  /// Called again with a different offset it is a rider carrying on away from
  /// the route: the clock moves with the distance between the two, so the
  /// recorder still reports a rider under way.
  Future<void> strayTo(
    WidgetTester tester,
    double offsetM, {
    Duration pump = const Duration(milliseconds: 40),
  }) async {
    final bearing = bearingAt(_alongM);
    await _emit(
      tester,
      destinationPoint(pointAt(_alongM), bearing + 90, offsetM),
      bearing,
      pump,
    );
  }

  Future<void> _emit(
    WidgetTester tester,
    LatLng position,
    double heading,
    Duration pump,
  ) async {
    final metres = _last == null ? 0.0 : haversineMeters(_last!, position);
    _seconds += math.max(1, (metres / speedMps).round());
    _last = position;
    source.emit(
      fix(position, seconds: _seconds, speed: speedMps, heading: heading),
    );
    await tester.pump(pump);
  }
}

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
  @override
  bool get isReady => true;

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
  Future<void> setPois(List<MapPoi> pois) => inner.setPois(pois);

  @override
  Future<void> setTurnMarkers(List<MapTurnMarker> turns) =>
      inner.setTurnMarkers(turns);

  @override
  set onPoiTapped(void Function(int index)? handler) =>
      inner.onPoiTapped = handler;

  @override
  set onTurnTapped(void Function(int index)? handler) =>
      inner.onTurnTapped = handler;

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
    EdgeInsets padding = EdgeInsets.zero,
  }) => inner.moveTo(
    center,
    zoom: zoom,
    bearing: bearing,
    animate: animate,
    duration: duration,
    padding: padding,
  );

  @override
  Future<void> fitBounds(
    BoundingBox bounds, {
    EdgeInsets padding = const EdgeInsets.all(48),
  }) => inner.fitBounds(bounds, padding: padding);

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
