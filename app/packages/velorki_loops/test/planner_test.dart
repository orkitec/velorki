import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_loops/velorki_loops.dart';

import 'fake_routing_backend.dart';

const start = LatLng(48.137213, 11.575612);
const lake = LatLng(48.0850, 11.2830);
const request = LoopRequest(start: start, targetM: 40000);

void main() {
  group('plan', () {
    test('returns at most three candidates, best first', () async {
      final backend = FakeRoutingBackend();
      final planner = LoopPlanner(backend: backend);
      final candidates = await planner.plan(request);
      expect(candidates, hasLength(3));
      for (var i = 1; i < candidates.length; i++) {
        expect(
          candidates[i - 1].score.total,
          lessThanOrEqualTo(candidates[i].score.total),
        );
      }
      expect(candidates.first.toString(), contains('LoopCandidate'));
    });

    test('a candidate carries its query, result, score and strategy', () async {
      final planner = LoopPlanner(backend: FakeRoutingBackend());
      final best = (await planner.plan(request)).first;
      expect(best.query.profile, 'trekking');
      expect(best.result.geometry, isNotEmpty);
      expect(best.score.features.targetM, 40000);
      expect(best.strategy, anyOf('roundtrip', 'viaOutAndBack', 'perimeter'));
    });

    test('candidates that do not route are skipped', () async {
      // Every round-trip query fails; only the perimeter ones survive.
      final backend = FakeRoutingBackend(failWhen: (q) => q.roundTrip);
      final planner = LoopPlanner(backend: backend);
      final candidates = await planner.plan(request);
      expect(candidates, isNotEmpty);
      expect(candidates.every((c) => c.strategy != 'roundtrip'), isTrue);
      // Eight directions, each rotated three times: "no track found" is worth
      // another try, and the round-trip strategy never produces anything here,
      // so it keeps turning the wheel to its limit.
      expect(backend.seen.where((q) => q.roundTrip), hasLength(32));
    });

    test('an entirely failing backend yields no candidates', () async {
      final planner = LoopPlanner(
        backend: FakeRoutingBackend(failWhen: (_) => true),
      );
      expect(await planner.plan(request), isEmpty);
    });

    test('a backend throwing something other than RoutingException is also '
        'survived', () async {
      final planner = LoopPlanner(backend: _ExplodingBackend());
      expect(await planner.plan(request), isEmpty);
    });

    test('no strategy proposing anything gives no candidates', () async {
      final backend = FakeRoutingBackend();
      final planner = LoopPlanner(
        backend: backend,
        strategies: const [ViaOutAndBackStrategy()], // needs a via
      );
      expect(await planner.plan(request), isEmpty);
      expect(backend.seen, isEmpty);
    });

    test('topN is configurable', () async {
      final planner = LoopPlanner(backend: FakeRoutingBackend(), topN: 1);
      expect(await planner.plan(request), hasLength(1));
    });
  });

  group('the loop filter', () {
    test('a candidate with a beeline over water is thrown away', () async {
      // Every answer carries eight kilometres of ferry, which is what the
      // Funchal round trip really came back with.
      final backend = FakeRoutingBackend(
        offRoadM: 8400,
        lengthFor: (_) => 30000,
      );
      final planner = LoopPlanner(backend: backend, maxRetries: 0);
      expect(await planner.plan(request), isEmpty);
      expect(backend.seen, isNotEmpty);
    });

    test('a doubled out-and-back is not a loop', () async {
      final backend = FakeRoutingBackend(shape: FakeShape.outAndBack);
      final planner = LoopPlanner(backend: backend, maxRetries: 0);
      expect(await planner.plan(request), isEmpty);
    });

    test('a proper loop comes through, and carries its quality', () async {
      final planner = LoopPlanner(backend: FakeRoutingBackend());
      final best = (await planner.plan(request)).first;
      expect(best.quality.offRoadM, 0);
      expect(best.quality.repeatedShare, 0);
      expect(best.quality.lengthM, best.result.lengthM);
    });

    test('"different way back" off keeps the out-and-back', () async {
      final backend = FakeRoutingBackend(shape: FakeShape.outAndBack);
      final planner = LoopPlanner(
        backend: backend,
        strategies: const [RoundtripStrategy(allowSameWayBack: true)],
        maxRetries: 0,
      );
      final found = await planner.plan(request);
      expect(found, isNotEmpty);
      expect(found.first.quality.repeatedShare, closeTo(0.5, 1e-6));
    });

    test('LoopFilter.none keeps what the default throws away', () async {
      final planner = LoopPlanner(
        backend: FakeRoutingBackend(shape: FakeShape.outAndBack),
        filter: LoopFilter.none,
        maxRetries: 0,
      );
      final found = await planner.plan(request);
      expect(found, isNotEmpty);
      expect(found.first.quality.repeatedShare, closeTo(0.5, 1e-6));
    });

    test('a rejected candidate is retried with a rotated bearing', () async {
      // The ferry is only in the water to the south-east; rotating away from
      // it finds a real loop, which is exactly the Funchal fix.
      final backend = FakeRoutingBackend(
        lengthFor: (_) => 30000,
        offRoadMFor: (q) =>
            (q.roundTripDirectionDeg ?? 0) % 360 == 180 ? 8400 : 0,
      );
      final planner = LoopPlanner(
        backend: backend,
        strategies: const [RoundtripStrategy()],
      );
      final found = await planner.plan(request);
      expect(found, hasLength(3));
      expect(
        backend.seen.map((q) => q.roundTripDirectionDeg),
        contains(180 + loopRetryRotationDeg),
      );
      expect(found.every((c) => c.quality.offRoadM == 0), isTrue);
    });

    test('a perimeter point that landed in the sea is thrown away', () async {
      // The fake draws a query through its waypoints, so a backend that
      // ignores one and rides somewhere else is what a snapped-far-away point
      // looks like from here.
      final backend = _DisplacingBackend(FakeRoutingBackend());
      final planner = LoopPlanner(
        backend: backend,
        strategies: [PerimeterStrategy(rotations: 1)],
        maxRetries: 0,
      );
      expect(await planner.plan(request), isEmpty);
    });

    test(
      'a strategy with nothing to show keeps rotating, three times',
      () async {
        // A coastal start where every invented bearing runs into the sea.
        final backend = FakeRoutingBackend(
          offRoadM: 8400,
          lengthFor: (_) => 30000,
        );
        final planner = LoopPlanner(
          backend: backend,
          strategies: const [RoundtripStrategy(directions: 2)],
        );
        expect(await planner.plan(request), isEmpty);
        expect(
          backend.seen,
          hasLength(8),
          reason: '2 queries, three rotations each',
        );
        expect(
          backend.seen.map((q) => q.roundTripDirectionDeg).toSet(),
          hasLength(8),
          reason: 'every attempt heads somewhere else',
        );
      },
    );

    test('a strategy that has a loop rotates once and stops', () async {
      // The whole southern quadrant is water, so the rotated retry is refused
      // as well; the other seven bearings are loops, so the wheel stops there
      // instead of eating the deadline.
      final backend = FakeRoutingBackend(
        lengthFor: (_) => 30000,
        offRoadMFor: (q) {
          final dir = (q.roundTripDirectionDeg ?? 0) % 360;
          return dir >= 135 && dir <= 225 ? 8400 : 0;
        },
      );
      final planner = LoopPlanner(
        backend: backend,
        strategies: const [RoundtripStrategy()],
      );
      expect(await planner.plan(request), isNotEmpty);
      expect(
        backend.seen,
        hasLength(11),
        reason: '8 directions, one retry for each of the three over water',
      );
      // 153 and 198 are still water, but the strategy already has loops, so
      // neither is rotated a second time.
      expect(
        backend.seen.map((q) => q.roundTripDirectionDeg),
        containsAll(<double>[153, 198, 243]),
      );
    });
  });

  group('candidate budget', () {
    test('maxCandidates caps the number of routing calls', () async {
      final backend = FakeRoutingBackend();
      final planner = LoopPlanner(backend: backend, maxCandidates: 5);
      await planner.plan(request);
      expect(backend.seen, hasLength(5));
    });

    test('the default budget covers all three strategies', () async {
      final backend = FakeRoutingBackend();
      final planner = LoopPlanner(backend: backend);
      await planner.plan(
        const LoopRequest(start: start, via: [lake], targetM: 120000),
      );
      // 8 roundtrip + 5 via variants would be 13; the budget is 12.
      expect(backend.seen, hasLength(12));
      expect(backend.seen.where((q) => q.roundTrip), hasLength(8));
    });
  });

  group('concurrency', () {
    test(
      'never more than the configured number of requests in flight',
      () async {
        final backend = FakeRoutingBackend(
          delay: const Duration(milliseconds: 5),
        );
        final planner = LoopPlanner(backend: backend, concurrency: 3);
        await planner.plan(request);
        expect(backend.maxInFlight, lessThanOrEqualTo(3));
        expect(backend.maxInFlight, greaterThan(1));
      },
    );

    test('concurrency 1 runs strictly sequentially, as on device', () async {
      final backend = FakeRoutingBackend(
        delay: const Duration(milliseconds: 2),
      );
      final planner = LoopPlanner(backend: backend, concurrency: 1);
      await planner.plan(request);
      expect(backend.maxInFlight, 1);
    });
  });

  group('timeout', () {
    test('a slow backend is cancelled and the run still finishes', () async {
      final backend = FakeRoutingBackend(delay: const Duration(seconds: 5));
      final planner = LoopPlanner(
        backend: backend,
        timeout: const Duration(milliseconds: 30),
        concurrency: 2,
      );
      expect(await planner.plan(request), isEmpty);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('planStream', () {
    test('emits candidates progressively and then closes', () async {
      final backend = FakeRoutingBackend(
        delay: const Duration(milliseconds: 2),
      );
      final planner = LoopPlanner(backend: backend);
      final seen = <LoopCandidate>[];
      await for (final c in planner.planStream(request)) {
        seen.add(c);
      }
      expect(seen, hasLength(backend.seen.length));
      expect(
        seen.map((c) => c.strategy).toSet(),
        containsAll(<String>['roundtrip', 'perimeter']),
      );
    });

    test('nothing is routed until someone listens', () async {
      final backend = FakeRoutingBackend();
      final planner = LoopPlanner(backend: backend);
      final stream = planner.planStream(request);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(backend.seen, isEmpty);
      await stream.toList();
      expect(backend.seen, isNotEmpty);
    });
  });

  test('an explicit scorer overrides the request preferences', () async {
    final backend = FakeRoutingBackend(
      wayTagsFor: (_) => 'highway=track surface=gravel',
    );
    final planner = LoopPlanner(
      backend: backend,
      scorer: const RouteScorer(LoopPrefs(surface: Surface.gravel)),
    );
    final withGravelScorer = await planner.plan(
      const LoopRequest(
        start: start,
        targetM: 40000,
        prefs: LoopPrefs(surface: Surface.paved),
      ),
    );
    final fromRequest = await LoopPlanner(backend: backend).plan(
      const LoopRequest(
        start: start,
        targetM: 40000,
        prefs: LoopPrefs(surface: Surface.paved),
      ),
    );
    expect(
      withGravelScorer.first.score.contributions['surface'],
      lessThan(fromRequest.first.score.contributions['surface']!),
    );
  });
}

/// Answers every query with a route that ignores its waypoints — what a
/// perimeter point invented out at sea comes back as, once the engine has
/// snapped it to the nearest way kilometres away.
class _DisplacingBackend implements RoutingBackend {
  _DisplacingBackend(this.inner);

  final FakeRoutingBackend inner;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async => inner
      .route(q.copyWith(points: <LatLng>[q.start, q.start]), cancel: cancel);
}

class _ExplodingBackend implements RoutingBackend {
  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async =>
      throw StateError('boom');
}
