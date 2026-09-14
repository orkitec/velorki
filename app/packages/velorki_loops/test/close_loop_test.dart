import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_loops/velorki_loops.dart';

import 'fake_routing_backend.dart';

const LatLng _start = LatLng(48.0, 11.0);
const LatLng _far = LatLng(48.05, 11.0);

/// A straight line east of [_start], [meters] long, sampled every 10 m.
List<LatLng> _line(double meters) => <LatLng>[
  for (var d = 0.0; d <= meters; d += 10) destinationPoint(_start, 90, d),
];

RouteResult _leg({
  required List<TrackPoint> geometry,
  double lengthM = 1000,
  double ascentM = 10,
  double descentM = 5,
  List<double> times = const <double>[],
  Duration? totalTime,
  double? energyJ,
  String? name,
  List<TurnHint> turns = const <TurnHint>[],
}) => RouteResult(
  geometry: geometry,
  lengthM: lengthM,
  ascentM: ascentM,
  descentM: descentM,
  plainAscentM: ascentM + 1,
  messages: <SegmentMessage>[
    SegmentMessage(
      position: geometry.last.pos,
      elevationM: 100,
      distanceM: lengthM,
      costPerKm: 1000,
      elevCost: 0,
      turnCost: 0,
      nodeCost: 0,
      initialCost: 0,
      wayTags: SegmentMessage.parseTags('highway=residential surface=asphalt'),
      nodeTags: const <String, String>{},
      timeS: lengthM / 5,
      energyJ: lengthM * 30,
    ),
  ],
  raw: <String, dynamic>{'leg': name ?? 'x'},
  totalTime: totalTime,
  energyJ: energyJ,
  times: times,
  turns: turns,
  name: name,
);

void main() {
  group('nogosAlong', () {
    test('samples the middle and leaves both ends free', () {
      final nogos = nogosAlong(_line(2000));

      expect(nogos, hasLength(9));
      expect(haversineMeters(nogos.first.center, _start), closeTo(400, 15));
      expect(
        haversineMeters(nogos.last.center, destinationPoint(_start, 90, 2000)),
        closeTo(400, 15),
      );
      // Consecutive circles are one sampling step apart ...
      expect(
        haversineMeters(nogos[0].center, nogos[1].center),
        closeTo(closeLoopSampleEveryM, 5),
      );
      // ... and overlap on the way between them, so nothing slips through.
      expect(nogos.first.radiusM * 2, greaterThan(closeLoopSampleEveryM));
    });

    test('every circle is weighted, never forbidding', () {
      for (final nogo in nogosAlong(_line(2000))) {
        expect(nogo.weight, closeLoopNogoWeight);
        expect(nogo.weight, isNotNull);
        expect(nogo.radiusM, closeLoopNogoRadiusM);
      }
    });

    test('thins the sampling instead of exceeding the cap', () {
      final nogos = nogosAlong(_line(100000), maxNogos: 20);

      expect(nogos, hasLength(lessThanOrEqualTo(20)));
      expect(nogos, hasLength(20));
      expect(
        haversineMeters(nogos[0].center, nogos[1].center),
        greaterThan(closeLoopSampleEveryM),
      );
    });

    test('a route shorter than the two free ends gets none', () {
      expect(nogosAlong(_line(500)), isEmpty);
      expect(nogosAlong(const <LatLng>[]), isEmpty);
    });
  });

  group('mergeLegs', () {
    test('joins the two legs into one route', () {
      final a = _leg(
        geometry: <TrackPoint>[
          TrackPoint(_start, ele: 100),
          TrackPoint(_far, ele: 150),
        ],
        lengthM: 5000,
        ascentM: 60,
        descentM: 10,
        times: const <double>[0, 600],
        totalTime: const Duration(minutes: 10),
        energyJ: 1000,
        name: 'out',
      );
      final b = _leg(
        geometry: <TrackPoint>[
          TrackPoint(_far, ele: 150),
          TrackPoint(const LatLng(48.02, 11.02), ele: 120),
          TrackPoint(_start, ele: 100),
        ],
        lengthM: 6000,
        ascentM: 20,
        descentM: 70,
        times: const <double>[0, 300, 700],
        totalTime: const Duration(minutes: 12),
        energyJ: 1200,
        name: 'back',
      );

      final merged = mergeLegs(a, b);

      // The join point appears once.
      expect(merged.geometry, hasLength(4));
      expect(merged.geometry[1].pos, _far);
      expect(merged.geometry[2].pos, const LatLng(48.02, 11.02));
      expect(merged.lengthM, 11000);
      expect(merged.ascentM, 80);
      expect(merged.descentM, 80);
      expect(merged.plainAscentM, a.plainAscentM + b.plainAscentM);
      expect(merged.messages, hasLength(2));
      expect(merged.totalTime, const Duration(minutes: 22));
      expect(merged.energyJ, 2200);
      // The return leg's clock carries on from the outbound leg's.
      expect(merged.times, <double>[0, 600, 900, 1300]);
      expect(merged.name, 'out');
      expect(merged.raw['velorki-legs'], hasLength(2));
      // The surface statistics see both legs' messages.
      expect(merged.surfaceStats.pavedShare, closeTo(1, 0.001));
    });

    test('the return leg\'s turns move with its points', () {
      final a = _leg(
        geometry: <TrackPoint>[
          TrackPoint(_start),
          TrackPoint(const LatLng(48.01, 11.01)),
          TrackPoint(_far),
        ],
        turns: const <TurnHint>[
          TurnHint(pointIndex: 1, kind: TurnKind.right, angleDeg: 90),
          // the outbound leg's arrival, in the middle of the loop now
          TurnHint(pointIndex: 2, kind: TurnKind.end),
        ],
      );
      final b = _leg(
        geometry: <TrackPoint>[
          TrackPoint(_far),
          TrackPoint(const LatLng(48.02, 11.02)),
          TrackPoint(_start),
        ],
        turns: const <TurnHint>[
          TurnHint(pointIndex: 1, kind: TurnKind.left, angleDeg: -90),
          TurnHint(pointIndex: 2, kind: TurnKind.end),
        ],
      );

      final merged = mergeLegs(a, b);

      // 3 + 2 points: the return leg's point 1 is the merged point 3.
      expect(merged.geometry, hasLength(5));
      expect(merged.turns, const <TurnHint>[
        TurnHint(pointIndex: 1, kind: TurnKind.right, angleDeg: 90),
        TurnHint(pointIndex: 3, kind: TurnKind.left, angleDeg: -90),
        TurnHint(pointIndex: 4, kind: TurnKind.end),
      ]);
      // The one "end" hint left is the last point of the loop.
      expect(merged.turns.last.pointIndex, merged.geometry.length - 1);
    });

    test('legs without turns merge to none', () {
      final a = _leg(
        geometry: <TrackPoint>[TrackPoint(_start), TrackPoint(_far)],
      );
      final b = _leg(
        geometry: <TrackPoint>[TrackPoint(_far), TrackPoint(_start)],
      );
      expect(mergeLegs(a, b).turns, isEmpty);
    });

    test('leaves the times empty when a leg has none', () {
      final a = _leg(
        geometry: <TrackPoint>[TrackPoint(_start), TrackPoint(_far)],
        times: const <double>[0, 600],
      );
      final b = _leg(
        geometry: <TrackPoint>[TrackPoint(_far), TrackPoint(_start)],
      );

      expect(mergeLegs(a, b).times, isEmpty);
      expect(mergeLegs(a, b).totalTime, isNull);
    });
  });

  group('CloseLoopRouter', () {
    RouteQuery closed({int alternativeIdx = 0}) => RouteQuery(
      points: const <LatLng>[_start, _far, _start],
      profile: 'gravel',
      alternativeIdx: alternativeIdx,
    );

    test('routes the outbound leg, then the way home around it', () async {
      final backend = FakeRoutingBackend();
      final result = await CloseLoopRouter(backend).route(closed());

      expect(backend.seen, hasLength(2));
      final outbound = backend.seen[0];
      final back = backend.seen[1];
      expect(outbound.points, <LatLng>[_start, _far]);
      expect(outbound.nogos, isEmpty);
      expect(back.points, <LatLng>[_far, _start]);
      expect(back.nogos, isNotEmpty);
      expect(back.profile, 'gravel');
      expect(
        result.lengthM,
        backend.synthesize(outbound).lengthM + backend.synthesize(back).lengthM,
      );
    });

    test(
      'the way out keeps its alternative, the way home takes its own',
      () async {
        final backend = FakeRoutingBackend();
        await CloseLoopRouter(backend)
            .route(closed(alternativeIdx: 2), returnAlternativeIdx: 3);

        expect(backend.seen.map((q) => q.alternativeIdx), <int>[2, 3]);
      },
    );

    test(
      'without a return variant the way home is the first alternative',
      () async {
        final backend = FakeRoutingBackend();
        await CloseLoopRouter(backend).route(closed(alternativeIdx: 1));

        expect(backend.seen.map((q) => q.alternativeIdx), <int>[1, 0]);
      },
    );

    test('the retry without no-gos keeps the return variant', () async {
      final backend = FakeRoutingBackend(failWhen: (q) => q.nogos.isNotEmpty);
      await CloseLoopRouter(backend).route(closed(), returnAlternativeIdx: 2);

      expect(backend.seen.map((q) => q.alternativeIdx), <int>[0, 2, 2]);
    });

    test('retries the way home without the no-gos when it fails', () async {
      final backend = FakeRoutingBackend(failWhen: (q) => q.nogos.isNotEmpty);

      final result = await CloseLoopRouter(backend).route(closed());

      expect(backend.seen, hasLength(3));
      expect(backend.seen[1].nogos, isNotEmpty);
      expect(backend.seen[2].nogos, isEmpty);
      expect(backend.seen[2].points, <LatLng>[_far, _start]);
      expect(result.lengthM, greaterThan(0));
    });

    test('a way home nobody can route reaches the caller', () async {
      final backend = FakeRoutingBackend(failWhen: (q) => q.start == _far);

      await expectLater(
        CloseLoopRouter(backend).route(closed()),
        throwsA(isA<RoutingException>()),
      );
    });

    test('an open plan is routed in one call', () async {
      final backend = FakeRoutingBackend();
      const open = RouteQuery(points: <LatLng>[_start, _far]);

      await CloseLoopRouter(backend).route(open);

      expect(backend.seen, hasLength(1));
      expect(backend.seen.single.points, <LatLng>[_start, _far]);
    });
  });
}
