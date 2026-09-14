import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// One call recorded by [TestMapController].
class MapCall {
  /// Records a call to [method] with [arguments].
  const MapCall(this.method, [this.arguments = const <Object?>[]]);

  /// The method name, e.g. `setRouteLine`.
  final String method;

  /// The positional arguments as they came in.
  final List<Object?> arguments;

  @override
  String toString() => '$method($arguments)';
}

/// A [MapController] that records instead of rendering.
///
/// Deliberately written here rather than reusing the map feature's own fake:
/// the planner tests must not depend on that feature's internals.
class TestMapController implements MapController {
  /// Every call, in order.
  final List<MapCall> calls = <MapCall>[];

  /// The last waypoints pushed.
  List<MapWaypoint> waypoints = const <MapWaypoint>[];

  /// The route lines currently on the map, by id.
  final Map<String, List<LatLng>> lines = <String, List<LatLng>>{};

  /// The style each line was drawn with.
  final Map<String, RouteLineStyle> styles = <String, RouteLineStyle>{};

  /// The last bounds [fitBounds] was asked for.
  BoundingBox? fittedBounds;

  /// The last camera target.
  LatLng? movedTo;

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

  @override
  Future<void> moveTo(
    LatLng center, {
    double? zoom,
    double? bearing,
    bool animate = true,
  }) async {
    movedTo = center;
    this.center = center;
    if (bearing != null) this.bearing = bearing;
    calls.add(MapCall('moveTo', [center, zoom, bearing]));
  }

  @override
  Future<void> fitBounds(BoundingBox bounds, {double paddingPx = 48}) async {
    fittedBounds = bounds;
    calls.add(MapCall('fitBounds', [bounds]));
  }

  @override
  Future<void> setRouteLine(
    String id,
    List<LatLng> points, {
    RouteLineStyle style = RouteLineStyle.main,
  }) async {
    lines[id] = points;
    styles[id] = style;
    calls.add(MapCall('setRouteLine', [id, points, style]));
  }

  @override
  Future<void> removeRouteLine(String id) async {
    lines.remove(id);
    styles.remove(id);
    calls.add(MapCall('removeRouteLine', [id]));
  }

  @override
  Future<void> clearRouteLines() async {
    lines.clear();
    styles.clear();
    calls.add(const MapCall('clearRouteLines'));
  }

  @override
  Future<void> setWaypoints(List<MapWaypoint> waypoints) async {
    this.waypoints = waypoints;
    calls.add(MapCall('setWaypoints', [waypoints]));
  }

  @override
  Future<void> setTrackLine(List<LatLng> points) async {
    calls.add(MapCall('setTrackLine', [points]));
  }

  @override
  Future<void> setPosition(
    LatLng? position, {
    double? accuracyM,
    double? headingDeg,
    double? speedMps,
  }) async {
    calls.add(MapCall('setPosition', [position]));
  }

  /// The searched place shown, if any.
  LatLng? searchPin;

  @override
  Future<void> setSearchPin(LatLng? position, {String? label}) async {
    searchPin = position;
  }

  @override
  Future<void> setCyclosmOverlay(bool visible) async {
    calls.add(MapCall('setCyclosmOverlay', [visible]));
  }
}

/// A [RoutingBackend] that answers from a script instead of the network.
class FakeRoutingBackend implements RoutingBackend {
  /// Creates a backend that answers every query with [result].
  FakeRoutingBackend({
    RouteResult? result,
    this.error,
    this.delay = Duration.zero,
  }) : result = result ?? syntheticRoute();

  /// The answer for queries without a per-alternative override.
  RouteResult result;

  /// Answers per `alternativeIdx`, for the alternatives tests.
  final Map<int, RouteResult?> byAlternative = <int, RouteResult?>{};

  /// When set, every query throws this instead of answering.
  RoutingException? error;

  /// How long an answer takes.
  Duration delay;

  /// Every query that arrived, in order.
  final List<RouteQuery> queries = <RouteQuery>[];

  /// The tokens handed in, so a test can assert a request was cancelled.
  final List<CancelToken> tokens = <CancelToken>[];

  /// How often [route] was called.
  int get callCount => queries.length;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    queries.add(q);
    if (cancel != null) tokens.add(cancel);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (cancel != null && cancel.isCancelled) throw cancel.toException();
    final failure = error;
    if (failure != null) throw failure;
    if (byAlternative.containsKey(q.alternativeIdx)) {
      final alternative = byAlternative[q.alternativeIdx];
      if (alternative == null) {
        throw const RoutingException(
          kind: RoutingErrorKind.noRoute,
          message: 'no such alternative',
        );
      }
      return alternative;
    }
    return result;
  }
}

/// A [RoutingBackend] whose answer depends on the alternative asked for.
///
/// The plain fake answers every query with the same route, which is exactly
/// what "another way back" must treat as "nothing changed"; this one gives
/// each alternative its own road so a test can tell the variants apart.
///
/// [sameAs] maps an alternative index onto the one it is identical to.
class VariedRoutingBackend extends FakeRoutingBackend {
  /// Creates the backend.
  VariedRoutingBackend({this.sameAs = const <int, int>{}});

  /// Which alternatives draw the same road as which other.
  final Map<int, int> sameAs;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    await super.route(q, cancel: cancel);
    final idx = sameAs[q.alternativeIdx] ?? q.alternativeIdx;
    return syntheticRoute(lengthM: 10000 + idx * 1000, startLat: 48.0 + idx);
  }
}

/// A small route with elevations and two tagged segments.
RouteResult syntheticRoute({
  double lengthM = 10000,
  double ascentM = 120,
  double descentM = 80,
  int points = 5,
  double startLat = 48.0,
  double startLon = 11.0,
  bool withMessages = true,
  List<TurnHint> turns = const <TurnHint>[],
}) {
  final geometry = List<TrackPoint>.generate(
    points,
    (i) => TrackPoint(
      LatLng(startLat + i * 0.01, startLon + i * 0.01),
      ele: 500 + i * 10.0,
    ),
    growable: false,
  );
  return RouteResult(
    geometry: geometry,
    lengthM: lengthM,
    ascentM: ascentM,
    descentM: descentM,
    messages: withMessages
        ? <SegmentMessage>[
            syntheticMessage(LatLng(startLat, startLon), lengthM * 0.6, const {
              'highway': 'residential',
              'surface': 'asphalt',
            }),
            syntheticMessage(
              LatLng(startLat + 0.02, startLon + 0.02),
              lengthM * 0.4,
              const {'highway': 'track', 'surface': 'gravel'},
            ),
          ]
        : const <SegmentMessage>[],
    raw: const <String, dynamic>{},
    turns: turns,
  );
}

/// One row of a synthetic `messages` table.
SegmentMessage syntheticMessage(
  LatLng position,
  double distanceM,
  Map<String, String> wayTags,
) => SegmentMessage(
  position: position,
  elevationM: 500,
  distanceM: distanceM,
  costPerKm: 1000,
  elevCost: 0,
  turnCost: 0,
  nodeCost: 0,
  initialCost: 0,
  wayTags: wayTags,
  nodeTags: const <String, String>{},
  timeS: 600,
  energyJ: 0,
);
