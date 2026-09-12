import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A [RoutingBackend] that invents circular routes instead of routing.
///
/// The same idea as `packages/velorki_loops/test/fake_routing_backend.dart`,
/// kept here because the app's tests must not reach into a package's test
/// folder: a query is answered with a ring around its start whose length and
/// way tags the test dictates, so the scorer ranks the candidates in a known
/// order.
class FakeLoopBackend implements RoutingBackend {
  /// Creates a fake backend.
  FakeLoopBackend({
    this.lengthFor,
    this.wayTagsFor,
    this.ascentPerKm = 10,
    this.failWhen,
    this.failureKind = RoutingErrorKind.noRoute,
    this.delay = Duration.zero,
    this.pointsPerRoute = 12,
  });

  /// The length the invented route should have. Defaults to the length the
  /// query asks for, which makes every candidate score the same.
  final double Function(RouteQuery query)? lengthFor;

  /// OSM way tags for the whole route, e.g. `'highway=track surface=gravel'`.
  final String Function(RouteQuery query)? wayTagsFor;

  /// Metres of ascent per kilometre.
  final double ascentPerKm;

  /// Queries the backend should refuse.
  final bool Function(RouteQuery query)? failWhen;

  /// Why a refused query fails.
  final RoutingErrorKind failureKind;

  /// Artificial latency, so a test can cancel a search mid-flight.
  final Duration delay;

  /// How many geometry points a route gets.
  final int pointsPerRoute;

  /// Every query that arrived, in order.
  final List<RouteQuery> queries = <RouteQuery>[];

  /// The tokens handed in, so a test can assert a request was cancelled.
  final List<CancelToken> tokens = <CancelToken>[];

  /// How many requests are running right now.
  int inFlight = 0;

  /// The highest [inFlight] ever observed.
  int maxInFlight = 0;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    queries.add(q);
    if (cancel != null) tokens.add(cancel);
    inFlight++;
    maxInFlight = math.max(maxInFlight, inFlight);
    try {
      if (delay > Duration.zero) {
        final wait = Future<void>.delayed(delay);
        if (cancel == null) {
          await wait;
        } else {
          await Future.any<void>([wait, cancel.whenCancelled]);
        }
      }
      if (cancel != null && cancel.isCancelled) throw cancel.toException();
      if (failWhen?.call(q) ?? false) {
        throw RoutingException(
          kind: failureKind,
          message: 'fake: no track found',
        );
      }
      return synthesize(q);
    } finally {
      inFlight--;
    }
  }

  /// Builds the invented result for [q], without going through [route].
  RouteResult synthesize(RouteQuery q) {
    final length = lengthFor?.call(q) ?? _defaultLength(q);
    final tags = wayTagsFor?.call(q) ?? 'highway=residential surface=asphalt';
    final radius = length / (2 * math.pi);
    final geometry = <TrackPoint>[
      for (var i = 0; i <= pointsPerRoute; i++)
        TrackPoint(
          destinationPoint(q.start, i * 360.0 / pointsPerRoute, radius),
          ele: 500 + 10 * math.sin(i * 2 * math.pi / pointsPerRoute),
        ),
    ];
    final ascent = ascentPerKm * length / 1000;
    return RouteResult(
      geometry: geometry,
      lengthM: length,
      ascentM: ascent,
      descentM: ascent,
      plainAscentM: ascent,
      messages: <SegmentMessage>[
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
}
