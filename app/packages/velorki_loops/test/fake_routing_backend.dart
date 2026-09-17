import 'dart:async';
import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// The shape the fake backend draws for a query.
enum FakeShape {
  /// A closed ring around the start: no segment is ridden twice.
  circle,

  /// Out to a turning point and back the same way: half the segments repeat.
  outAndBack,
}

/// A [RoutingBackend] that invents plausible routes instead of doing any
/// routing, so the strategies, the scorer and the planner can be tested
/// offline and deterministically.
class FakeRoutingBackend implements RoutingBackend {
  /// Creates a fake backend.
  FakeRoutingBackend({
    this.lengthFor,
    this.wayTagsFor,
    this.ascentPerKm = 10,
    this.shape = FakeShape.circle,
    this.failWhen,
    this.delay = Duration.zero,
    this.pointsPerRoute = 24,
    this.offRoadM = 0,
    this.offRoadMFor,
  });

  /// The length the invented route should have; defaults to the round-trip
  /// radius restored to a length, or the straight-line length of the query.
  final double Function(RouteQuery query)? lengthFor;

  /// OSM way tags for the whole route, e.g.
  /// `'highway=track surface=gravel'`.
  final String Function(RouteQuery query)? wayTagsFor;

  /// Metres of ascent per kilometre.
  final double ascentPerKm;

  /// Which shape to draw.
  final FakeShape shape;

  /// Queries for which the backend should throw instead of answering.
  final bool Function(RouteQuery query)? failWhen;

  /// Artificial latency, used to observe concurrency.
  final Duration delay;

  /// How many geometry points to emit.
  final int pointsPerRoute;

  /// Metres of the route that run over a ferry instead of a road — what a
  /// waypoint snapped out to sea comes back as. It is emitted as a second
  /// `messages` row with no `highway` tag.
  final double offRoadM;

  /// [offRoadM] per query, for a backend whose sea is only in one direction.
  final double Function(RouteQuery query)? offRoadMFor;

  /// Every query the backend was asked, in call order.
  final List<RouteQuery> seen = <RouteQuery>[];

  /// How many calls are running right now.
  int inFlight = 0;

  /// The highest [inFlight] ever observed.
  int maxInFlight = 0;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    seen.add(q);
    inFlight++;
    maxInFlight = math.max(maxInFlight, inFlight);
    try {
      if (delay > Duration.zero) {
        final wait = Future<void>.delayed(delay);
        if (cancel == null) {
          await wait;
        } else {
          // Behave like a real backend: give up as soon as the token is
          // cancelled instead of sitting out the whole latency.
          await Future.any<void>([wait, cancel.whenCancelled]);
        }
      }
      if (cancel != null && cancel.isCancelled) throw cancel.toException();
      if (failWhen != null && failWhen!(q)) {
        throw const RoutingException(
          kind: RoutingErrorKind.noRoute,
          message: 'fake: no track found',
        );
      }
      return synthesize(q);
    } finally {
      inFlight--;
    }
  }

  /// Builds the invented [RouteResult] for [q]. Public so tests can build a
  /// result without going through [route].
  RouteResult synthesize(RouteQuery q) {
    final length = lengthFor?.call(q) ?? _defaultLength(q);
    final tags = wayTagsFor?.call(q) ?? 'highway=residential surface=asphalt';
    final offRoad = offRoadMFor?.call(q) ?? offRoadM;
    final geometry = _geometry(q, length);
    final ascent = ascentPerKm * length / 1000;
    return RouteResult(
      geometry: geometry,
      lengthM: length,
      ascentM: ascent,
      descentM: ascent,
      plainAscentM: ascent,
      messages: [
        _message(geometry.last.pos, length - offRoad, tags),
        if (offRoad > 0)
          _message(
            geometry.last.pos,
            offRoad,
            'route=ferry foot=yes bicycle=yes',
          ),
      ],
      raw: const <String, dynamic>{'fake': true},
    );
  }

  static SegmentMessage _message(LatLng at, double distanceM, String tags) =>
      SegmentMessage(
        position: at,
        elevationM: 500,
        distanceM: distanceM,
        costPerKm: 1000,
        elevCost: 0,
        turnCost: 0,
        nodeCost: 0,
        initialCost: 0,
        wayTags: SegmentMessage.parseTags(tags),
        nodeTags: const <String, String>{},
        timeS: distanceM / 5,
        energyJ: distanceM * 30,
      );

  double _defaultLength(RouteQuery q) {
    if (q.roundTrip && q.roundTripDistanceM != null) {
      return q.roundTripDistanceM! * (math.pi + 2);
    }
    return polylineLengthMeters(q.points);
  }

  /// The invented geometry for [q].
  ///
  /// A query with waypoints of its own is drawn *through them*, the way a
  /// router would: that is what lets a test assert on where a strategy put
  /// its synthetic points. A round trip has none, so it gets a ring (or an
  /// out-and-back) around its start.
  List<TrackPoint> _geometry(RouteQuery q, double length) {
    if (!q.roundTrip && q.points.length >= 2) {
      return _throughWaypoints(q.points);
    }
    return _aroundStart(q.start, length);
  }

  List<TrackPoint> _throughWaypoints(List<LatLng> waypoints) {
    final line = <LatLng>[];
    for (var i = 1; i < waypoints.length; i++) {
      final a = waypoints[i - 1];
      final b = waypoints[i];
      final bearing = bearingDegrees(a, b);
      final leg = haversineMeters(a, b);
      const steps = 6;
      for (var k = 0; k < steps; k++) {
        line.add(destinationPoint(a, bearing, leg * k / steps));
      }
    }
    line.add(waypoints.last);
    final out = <LatLng>[
      ...line,
      if (shape == FakeShape.outAndBack) ...line.reversed.skip(1),
    ];
    return <TrackPoint>[for (final p in out) TrackPoint(p, ele: 500)];
  }

  List<TrackPoint> _aroundStart(LatLng start, double length) {
    switch (shape) {
      case FakeShape.circle:
        final radius = length / (2 * math.pi);
        return <TrackPoint>[
          for (var i = 0; i <= pointsPerRoute; i++)
            TrackPoint(
              destinationPoint(start, i * 360.0 / pointsPerRoute, radius),
              ele: 500 + 10 * math.sin(i * 2 * math.pi / pointsPerRoute),
            ),
        ];
      case FakeShape.outAndBack:
        final half = pointsPerRoute ~/ 2;
        final leg = <LatLng>[
          for (var i = 0; i <= half; i++)
            destinationPoint(start, 90, i * length / (2 * half)),
        ];
        return <TrackPoint>[
          for (final p in leg) TrackPoint(p, ele: 500),
          for (final p in leg.reversed.skip(1)) TrackPoint(p, ele: 500),
        ];
    }
  }
}
