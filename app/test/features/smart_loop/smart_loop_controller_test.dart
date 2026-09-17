import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/smart_loop/application/smart_loop_controller.dart';
import 'package:velorki/features/smart_loop/domain/loops.dart';
import 'package:velorki/features/smart_loop/domain/smart_loop_state.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fake_loop_backend.dart';

const LatLng _start = LatLng(48.137213, 11.575612);
const LoopRequest _request = LoopRequest(start: _start, targetM: 40000);

ProviderContainer _container(RoutingBackend? backend) {
  final container = ProviderContainer(
    overrides: [routingBackendProvider.overrideWithValue(backend)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('search', () {
    test('fires the round trip engine off in every direction', () async {
      final backend = FakeLoopBackend();
      final container = _container(backend);

      await container
          .read(smartLoopControllerProvider.notifier)
          .search(_request);

      expect(backend.queries, hasLength(smartLoopDirections));
      expect(backend.queries.every((q) => q.roundTrip), isTrue);
      expect(backend.queries.every((q) => !q.allowSameWayBack), isTrue);
      expect(
        backend.queries.map((q) => q.roundTripDirectionDeg).toSet(),
        hasLength(smartLoopDirections),
      );
      expect(backend.maxInFlight, lessThanOrEqualTo(smartLoopConcurrency));
    });

    test('no loop query may ride a ferry', () async {
      // The nearest way to a round-trip point invented out at sea is the
      // ferry line, which BRouter rides out and back as a straight segment
      // over open water. The sheet must never ask for one.
      final backend = FakeLoopBackend();
      await _container(backend)
          .read(smartLoopControllerProvider.notifier)
          .search(_request);

      expect(backend.queries, isNotEmpty);
      expect(
        backend.queries.every((q) => q.profileParams['allow_ferries'] == '0'),
        isTrue,
      );
    });

    test('the switch becomes BRouter\'s allowSamewayback', () async {
      final backend = FakeLoopBackend();
      await _container(backend)
          .read(smartLoopControllerProvider.notifier)
          .search(_request, allowSameWayBack: true);

      expect(backend.queries.every((q) => q.allowSameWayBack), isTrue);
    });

    test('keeps everything that routed, best first', () async {
      final backend = FakeLoopBackend(
        // Each direction gets its own length, so the scorer has an opinion.
        lengthFor: (q) => 40000 + (q.roundTripDirectionDeg ?? 0) * 10,
      );
      final container = _container(backend);

      await container
          .read(smartLoopControllerProvider.notifier)
          .search(_request);

      final state = container.read(smartLoopControllerProvider);
      expect(state.running, isFalse);
      expect(state.progress, 1);
      expect(state.candidates, hasLength(smartLoopDirections));
      expect(state.index, 0);
      for (var i = 1; i < state.candidates.length; i++) {
        expect(
          state.candidates[i - 1].score.total,
          lessThanOrEqualTo(state.candidates[i].score.total),
        );
      }
    });

    test('puts the best loop straight into the planner', () async {
      final container = _container(FakeLoopBackend());

      await container
          .read(smartLoopControllerProvider.notifier)
          .search(
            const LoopRequest(start: _start, targetM: 40000, profile: 'mtb'),
          );

      final best = container.read(smartLoopControllerProvider).current!;
      final planner = container.read(plannerControllerProvider);
      expect(planner.result, same(best.result));
      expect(planner.options.profile, RouteProfile.mtb);
      expect(planner.isRouting, isFalse);
      // A round trip is one point; BRouter invented the rest.
      expect(planner.waypoints, hasLength(1));
      expect(planner.waypoints.single.kind, WaypointKind.start);
      expect(planner.canSave, isTrue);
    });

    test('progress counts queries that failed as well', () async {
      final seen = <double>[];
      final container = _container(
        FakeLoopBackend(failWhen: (q) => (q.roundTripDirectionDeg ?? 0) < 180),
      );
      container.listen(
        smartLoopControllerProvider,
        (_, next) => seen.add(next.progress),
      );

      await container
          .read(smartLoopControllerProvider.notifier)
          .search(_request);

      expect(seen.where((p) => p > 0 && p < 1), isNotEmpty);
      expect(container.read(smartLoopControllerProvider).progress, 1);
      expect(
        container.read(smartLoopControllerProvider).candidates,
        hasLength(4),
      );
    });

    test('searching again replaces the previous search', () async {
      final backend = FakeLoopBackend(delay: const Duration(milliseconds: 20));
      final container = _container(backend);
      final controller = container.read(smartLoopControllerProvider.notifier);

      final first = controller.search(_request);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await controller.search(const LoopRequest(start: _start, targetM: 20000));
      await first;

      final state = container.read(smartLoopControllerProvider);
      expect(state.running, isFalse);
      expect(state.request?.targetM, 20000);
      expect(state.candidates, isNotEmpty);
    });
  });

  group('another', () {
    test('walks down the ranking without routing again', () async {
      final backend = FakeLoopBackend(
        lengthFor: (q) => 40000 + (q.roundTripDirectionDeg ?? 0) * 10,
      );
      final container = _container(backend);
      final controller = container.read(smartLoopControllerProvider.notifier);
      await controller.search(_request);
      final routed = backend.queries.length;
      final second = container.read(smartLoopControllerProvider).candidates[1];

      await controller.another();

      expect(backend.queries, hasLength(routed));
      expect(container.read(smartLoopControllerProvider).index, 1);
      expect(container.read(smartLoopControllerProvider).current, same(second));
      // The planner follows along.
      expect(container.read(plannerControllerProvider).result, second.result);
    });

    test('searches again, rotated, once the ranking is used up', () async {
      final backend = FakeLoopBackend();
      final container = _container(backend);
      final controller = container.read(smartLoopControllerProvider.notifier);
      await controller.search(_request);
      final firstRound = backend.queries
          .map((q) => q.roundTripDirectionDeg)
          .toSet();

      for (var i = 0; i < smartLoopDirections; i++) {
        await controller.another();
      }

      expect(backend.queries, hasLength(smartLoopDirections * 2));
      final secondRound = backend.queries
          .skip(smartLoopDirections)
          .map((q) => q.roundTripDirectionDeg)
          .toSet();
      expect(secondRound.intersection(firstRound), isEmpty);
      expect(
        container.read(smartLoopControllerProvider).candidates,
        isNotEmpty,
      );
    });

    test('does nothing before a search', () async {
      final backend = FakeLoopBackend();
      final container = _container(backend);

      await container.read(smartLoopControllerProvider.notifier).another();

      expect(backend.queries, isEmpty);
    });
  });

  group('cancel', () {
    test('stops the search and every request in flight', () async {
      final backend = FakeLoopBackend(delay: const Duration(seconds: 5));
      final container = _container(backend);
      final controller = container.read(smartLoopControllerProvider.notifier);

      final run = controller.search(_request);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(smartLoopControllerProvider).running, isTrue);

      controller.cancel();
      expect(container.read(smartLoopControllerProvider).running, isFalse);
      await run;

      expect(backend.tokens, isNotEmpty);
      expect(backend.tokens.every((t) => t.isCancelled), isTrue);
      expect(container.read(smartLoopControllerProvider).candidates, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('cancelling when nothing runs is a no-op', () {
      final container = _container(FakeLoopBackend());
      container.read(smartLoopControllerProvider.notifier).cancel();
      expect(
        container.read(smartLoopControllerProvider),
        const SmartLoopState(),
      );
    });

    test('reset forgets the last search', () async {
      final container = _container(FakeLoopBackend());
      final controller = container.read(smartLoopControllerProvider.notifier);
      await controller.search(_request);

      controller.reset();

      expect(
        container.read(smartLoopControllerProvider),
        const SmartLoopState(),
      );
    });
  });

  group('failure', () {
    test('nothing routable is an empty result, not an error', () async {
      final container = _container(FakeLoopBackend(failWhen: (_) => true));
      await container
          .read(smartLoopControllerProvider.notifier)
          .search(_request);

      final state = container.read(smartLoopControllerProvider);
      expect(state.running, isFalse);
      expect(state.candidates, isEmpty);
      expect(state.error, isNull);
      expect(state.foundNothing, isTrue);
    });

    test('an unreachable routing server is reported as an error', () async {
      final container = _container(
        FakeLoopBackend(
          failWhen: (_) => true,
          failureKind: RoutingErrorKind.network,
        ),
      );
      await container
          .read(smartLoopControllerProvider.notifier)
          .search(_request);

      final state = container.read(smartLoopControllerProvider);
      expect(state.error, 'fake: no track found');
      expect(state.foundNothing, isFalse);
      expect(state.candidates, isEmpty);
    });

    test(
      'no routing server configured is reported before anything runs',
      () async {
        final container = _container(null);
        await container
            .read(smartLoopControllerProvider.notifier)
            .search(_request);

        final state = container.read(smartLoopControllerProvider);
        expect(state.error, noRoutingBackendError);
        expect(state.running, isFalse);
        expect(state.candidates, isEmpty);
      },
    );

    test('adopt does nothing without a candidate', () {
      final container = _container(FakeLoopBackend());
      expect(
        container.read(smartLoopControllerProvider.notifier).adopt(),
        isFalse,
      );
      expect(container.read(plannerControllerProvider).waypoints, isEmpty);
    });
  });
}
