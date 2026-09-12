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
      expect(backend.seen.where((q) => q.roundTrip), hasLength(8));
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

class _ExplodingBackend implements RoutingBackend {
  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async =>
      throw StateError('boom');
}
