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
    final geometry = _geometry(q.start, length);
    final ascent = ascentPerKm * length / 1000;
    return RouteResult(
      geometry: geometry,
      lengthM: length,
      ascentM: ascent,
      descentM: ascent,
      plainAscentM: ascent,
      messages: [
        SegmentMessage(
          position: geometry.last.pos,
          elevationM: 500,
          distanceM: length,
          costPerKm: 1000,
          elevCost: 0,
          turnCost: 0,
          nodeCost: 0,
          initialCost: 0,
          wayTags: SegmentMessage.parseTags(tags),
          nodeTags: const <String, String>{},
          timeS: length / 5,
          energyJ: length * 30,
        ),
      ],
      raw: const <String, dynamic>{'fake': true},
    );
  }

  double _defaultLength(RouteQuery q) {
    if (q.roundTrip && q.roundTripDistanceM != null) {
      return q.roundTripDistanceM! * (math.pi + 2);
    }
    return polylineLengthMeters(q.points);
  }

  List<TrackPoint> _geometry(LatLng start, double length) {
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
