// What makes a routed candidate a loop at all: no beeline over water, and not
// the same road twice. The three shapes of the Funchal bug are all here — a
// beeline candidate, a doubled out-and-back and a proper loop.

import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_loops/velorki_loops.dart';

import 'fake_routing_backend.dart';

/// The rider's position in Funchal the bug was reported from.
const funchal = LatLng(32.6669, -16.9241);
const request = LoopRequest(start: funchal, targetM: 30000);

/// A ring of [n] points [radiusM] around [centre]: a loop that repeats
/// nothing.
List<LatLng> ring(LatLng centre, double radiusM, {int n = 24}) => <LatLng>[
  for (var i = 0; i <= n; i++) destinationPoint(centre, i * 360.0 / n, radiusM),
];

/// Out along [bearing] for [lengthM] and back the same way, in [n] steps.
List<LatLng> outAndBack(
  LatLng start,
  double bearing,
  double lengthM, {
  int n = 12,
}) {
  final leg = <LatLng>[
    for (var i = 0; i <= n; i++)
      destinationPoint(start, bearing, i * lengthM / n),
  ];
  return <LatLng>[...leg, ...leg.reversed.skip(1)];
}

void main() {
  group('RepeatedGeometry', () {
    test('a ring repeats nothing', () {
      expect(RepeatedGeometry.of(ring(funchal, 3000)).ratio, 0);
    });

    test('a pure out-and-back repeats half its length', () {
      final measured = RepeatedGeometry.of(outAndBack(funchal, 90, 5000));
      expect(measured.ratio, closeTo(0.5, 1e-9));
      expect(measured.repeatedM, closeTo(5000, 1));
      expect(measured.totalM, closeTo(10000, 1));
    });

    test('it counts metres, not point pairs', () {
      // The Funchal bug in miniature: a four-kilometre ferry leg ridden out
      // and back is two point pairs, while the town around it is hundreds of
      // short ones. Counting pairs called this route 2 % repeated; it is a
      // quarter of the way.
      final town = ring(funchal, 500, n: 200);
      final ferry = outAndBack(funchal, 135, 4000, n: 1);
      final ratio = RepeatedGeometry.of(<LatLng>[...town, ...ferry]).ratio;
      final townM = polylineLengthMeters(town);
      expect(ratio, closeTo(4000 / (townM + 8000), 0.02));
      expect(ratio, greaterThan(0.2));
    });

    test('degenerate input measures nothing', () {
      expect(RepeatedGeometry.of(const <LatLng>[]).ratio, 0);
      expect(RepeatedGeometry.of(const <LatLng>[funchal]).ratio, 0);
      expect(RepeatedGeometry.none.ratio, 0);
      expect(RepeatedGeometry.of(const <LatLng>[funchal, funchal]).ratio, 0);
    });

    test('it says what it measured', () {
      expect(
        RepeatedGeometry.of(outAndBack(funchal, 90, 5000)).toString(),
        contains('50.0 %'),
      );
    });
  });

  group('LoopQuality', () {
    final backend = FakeRoutingBackend();

    test('a proper loop is all road and repeats nothing', () {
      final quality = LoopQuality.of(
        backend.synthesize(
          const RouteQuery(
            points: [funchal],
            roundTrip: true,
            roundTripDistanceM: 5000,
          ),
        ),
      );
      expect(quality.offRoadM, 0);
      expect(quality.repeatedShare, 0);
      expect(quality.toString(), contains('offRoad 0 m'));
    });

    test('a ferry leg counts as off the road network', () {
      final ferrying = FakeRoutingBackend(
        offRoadM: 8400,
        lengthFor: (_) => 30000,
      );
      final quality = LoopQuality.of(
        ferrying.synthesize(const RouteQuery(points: [funchal, funchal])),
      );
      expect(quality.offRoadM, closeTo(8400, 1));
      expect(quality.offRoadShare, closeTo(0.28, 0.01));
    });

    test('an out-and-back repeats half of itself', () {
      final there = FakeRoutingBackend(
        shape: FakeShape.outAndBack,
        lengthFor: (_) => 20000,
      );
      final quality = LoopQuality.of(
        there.synthesize(
          const RouteQuery(
            points: [funchal],
            roundTrip: true,
            roundTripDistanceM: 3000,
          ),
        ),
      );
      expect(quality.repeatedShare, closeTo(0.5, 1e-6));
    });
  });

  group('synthetic points', () {
    test('the rider\'s own points are not the strategy\'s guesses', () {
      const lake = LatLng(32.75, -17.0);
      final invented = destinationPoint(funchal, 45, 8000);
      const withVia = LoopRequest(
        start: funchal,
        targetM: 30000,
        via: <LatLng>[lake],
      );
      expect(
        syntheticPoints(
          withVia,
          RouteQuery(points: <LatLng>[funchal, invented, lake, funchal]),
        ),
        <LatLng>[invented],
      );
      expect(
        syntheticPoints(
          request,
          const RouteQuery(points: [funchal], roundTrip: true),
        ),
        isEmpty,
      );
    });

    test('a point the router had to snap far away is measured', () {
      // The perimeter ring point that landed in the sea: the engine put the
      // route two kilometres away from where the strategy meant it.
      final backend = FakeRoutingBackend();
      final onLand = destinationPoint(funchal, 0, 4000);
      final inTheSea = destinationPoint(funchal, 210, 4000);
      final result = backend.synthesize(
        RouteQuery(
          points: <LatLng>[
            funchal,
            onLand,
            destinationPoint(funchal, 120, 4000),
            funchal,
          ],
        ),
      );
      expect(
        LoopQuality.of(result, waypoints: <LatLng>[onLand]).waypointOffsetM,
        lessThan(1),
      );
      final quality = LoopQuality.of(result, waypoints: <LatLng>[inTheSea]);
      expect(quality.waypointOffsetM, greaterThan(4000));
      expect(quality.toString(), contains('waypoint off by'));
      expect(const LoopFilter().reject(quality), contains('from the route'));
    });
  });

  group('LoopFilter', () {
    const filter = LoopFilter();

    test('a proper loop is accepted', () {
      expect(
        filter.reject(
          const LoopQuality(
            lengthM: 30000,
            offRoadM: 0,
            repeated: RepeatedGeometry(repeatedM: 900, totalM: 30000),
          ),
        ),
        isNull,
      );
    });

    test('a beeline over water is rejected, and says so', () {
      final reason = filter.reject(
        const LoopQuality(
          lengthM: 29300,
          offRoadM: 8400,
          repeated: RepeatedGeometry(repeatedM: 0, totalM: 29300),
        ),
      );
      expect(reason, contains('off the road network'));
    });

    test('riding a fifth of it twice is rejected', () {
      final reason = filter.reject(
        const LoopQuality(
          lengthM: 30000,
          offRoadM: 0,
          repeated: RepeatedGeometry(repeatedM: 9000, totalM: 30000),
        ),
      );
      expect(reason, contains('ridden twice'));
    });

    test('the rider may ask to come home the same way', () {
      const sameWayBack = LoopQuality(
        lengthM: 30000,
        offRoadM: 0,
        repeated: RepeatedGeometry(repeatedM: 15000, totalM: 30000),
      );
      expect(filter.reject(sameWayBack), isNotNull);
      expect(filter.reject(sameWayBack, ridesBackTheSameWay: true), isNull);
      // A ferry is still not a road, whichever way home they wanted.
      expect(
        filter.reject(
          const LoopQuality(
            lengthM: 30000,
            offRoadM: 8400,
            repeated: RepeatedGeometry(repeatedM: 15000, totalM: 30000),
          ),
          ridesBackTheSameWay: true,
        ),
        contains('off the road network'),
      );
    });

    test('a hundred metres of slack is allowed', () {
      expect(
        filter.reject(
          const LoopQuality(
            lengthM: 30000,
            offRoadM: 80,
            repeated: RepeatedGeometry(repeatedM: 0, totalM: 30000),
          ),
        ),
        isNull,
      );
    });

    test('a loop far off the requested distance is held back', () {
      const long = LoopQuality(
        lengthM: 38100,
        offRoadM: 0,
        repeated: RepeatedGeometry(repeatedM: 0, totalM: 38100),
      );
      // Nothing wrong with it as a loop — it is just not 30 km.
      expect(filter.reject(long), isNull);
      final reason = filter.tooFarFromTarget(long, targetM: 30000);
      expect(reason, contains('27 % off'));
      expect(reason, contains('38.1 km'));
    });

    test('a quarter off is close enough to show', () {
      const quarterLong = LoopQuality(
        lengthM: 37500,
        offRoadM: 0,
        repeated: RepeatedGeometry(repeatedM: 0, totalM: 37500),
      );
      expect(filter.tooFarFromTarget(quarterLong, targetM: 30000), isNull);
      // Short by a quarter is the same band on the other side.
      expect(
        filter.tooFarFromTarget(
          const LoopQuality(
            lengthM: 22500,
            offRoadM: 0,
            repeated: RepeatedGeometry(repeatedM: 0, totalM: 22500),
          ),
          targetM: 30000,
        ),
        isNull,
      );
      // Shorter than that is as wrong as longer.
      expect(
        filter.tooFarFromTarget(
          const LoopQuality(
            lengthM: 20000,
            offRoadM: 0,
            repeated: RepeatedGeometry(repeatedM: 0, totalM: 20000),
          ),
          targetM: 30000,
        ),
        isNotNull,
      );
    });

    test('a request with no distance in it is never too far', () {
      expect(
        filter.tooFarFromTarget(
          const LoopQuality(
            lengthM: 38100,
            offRoadM: 0,
            repeated: RepeatedGeometry(repeatedM: 0, totalM: 38100),
          ),
          targetM: 0,
        ),
        isNull,
      );
    });

    test('LoopFilter.none takes anything', () {
      expect(
        LoopFilter.none.reject(
          const LoopQuality(
            lengthM: 30000,
            offRoadM: 30000,
            repeated: RepeatedGeometry(repeatedM: 30000, totalM: 30000),
          ),
        ),
        isNull,
      );
      expect(
        LoopFilter.none.tooFarFromTarget(
          const LoopQuality(
            lengthM: 120000,
            offRoadM: 0,
            repeated: RepeatedGeometry(repeatedM: 0, totalM: 120000),
          ),
          targetM: 30000,
        ),
        isNull,
      );
      expect(filter.toString(), contains('LoopFilter'));
      expect(filter.toString(), contains('length within 25 %'));
    });
  });

  group('retryQuery', () {
    final backend = FakeRoutingBackend();

    test(
      'a round trip is rotated and its radius corrected by the overshoot',
      () {
        const query = RouteQuery(
          points: [funchal],
          roundTrip: true,
          roundTripDistanceM: 5836,
          roundTripDirectionDeg: 180,
        );
        final tooLong = backend.synthesize(query); // (pi + 2) * radius
        final again = retryQuery(request, query, result: tooLong)!;
        expect(again.roundTripDirectionDeg, 180 + loopRetryRotationDeg);
        expect(
          again.roundTripDistanceM,
          closeTo(5836 * request.targetM / tooLong.lengthM, 1),
        );
        expect(again.roundTripDistanceM, lessThan(5836));
        expect(again.profileParams, query.profileParams);
      },
    );

    test('a query that did not route at all shrinks by a quarter', () {
      const query = RouteQuery(
        points: [funchal],
        roundTrip: true,
        roundTripDistanceM: 5836,
        roundTripDirectionDeg: 180,
      );
      final again = retryQuery(request, query)!;
      expect(again.roundTripDistanceM, closeTo(5836 * 0.75, 1));
    });

    test('the scale is clamped, so one bad answer cannot collapse it', () {
      const query = RouteQuery(
        points: [funchal],
        roundTrip: true,
        roundTripDistanceM: 5836,
        roundTripDirectionDeg: 0,
      );
      final huge = FakeRoutingBackend(lengthFor: (_) => 400000);
      final again = retryQuery(request, query, result: huge.synthesize(query))!;
      expect(again.roundTripDistanceM, closeTo(5836 * loopRetryMinScale, 1e-6));
    });

    test('synthetic points move towards the start, the rider\'s do not', () {
      final synthetic = destinationPoint(funchal, 45, 8000);
      const lake = LatLng(32.75, -17.0);
      const withVia = LoopRequest(
        start: funchal,
        targetM: 30000,
        via: <LatLng>[lake],
      );
      final query = RouteQuery(
        points: <LatLng>[funchal, synthetic, lake, funchal],
      );
      final again = retryQuery(withVia, query)!;
      expect(again.points.first, funchal);
      expect(again.points.last, funchal);
      expect(again.points[2], lake, reason: 'a via the rider asked for');
      expect(
        haversineMeters(funchal, again.points[1]),
        closeTo(8000 * 0.75, 1),
      );
      expect(
        bearingDegrees(funchal, again.points[1]),
        closeTo(45 + loopRetryRotationDeg, 0.01),
        reason: 'and round the start, off the water it landed in',
      );
    });

    test('a query with nothing synthetic in it has no retry', () {
      const query = RouteQuery(points: <LatLng>[funchal, funchal]);
      expect(retryQuery(request, query), isNull);
      expect(
        retryQuery(
          request,
          const RouteQuery(points: [funchal], roundTrip: true),
        ),
        isNull,
        reason: 'a round trip without a radius',
      );
    });
  });
}
