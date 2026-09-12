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
const LatLng _lake = LatLng(48.0850, 11.2830);
const LoopRequest _request = LoopRequest(start: _start, targetM: 40000);

ProviderContainer _container(RoutingBackend? backend) {
  final container = ProviderContainer(
    overrides: [routingBackendProvider.overrideWithValue(backend)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('strategies', () {
    test('a request without a via uses the round trip engine', () {
      final names = strategiesForRequest(_request).map((s) => s.name).toList();
      expect(names, ['roundtrip', 'perimeter']);
    });

    test('a request with a via routes through it', () {
      final names = strategiesForRequest(
        const LoopRequest(start: _start, via: [_lake], targetM: 40000),
      ).map((s) => s.name).toList();
      expect(names, ['viaOutAndBack', 'perimeter']);
    });
  });

  group('start', () {
    test(
      'candidates appear progressively and the best three are kept',
      () async {
        final backend = FakeLoopBackend(delay: const Duration(milliseconds: 2));
        final container = _container(backend);
        final counts = <int>[];
        container.listen(
          smartLoopControllerProvider,
          (_, next) => counts.add(next.candidates.length),
          fireImmediately: false,
        );

        final controller = container.read(smartLoopControllerProvider.notifier);
        await controller.start(_request);

        final state = container.read(smartLoopControllerProvider);
        expect(state.running, isFalse);
        expect(state.progress, 1);
        expect(state.error, isNull);
        expect(state.candidates, hasLength(smartLoopTopN));
        expect(state.selected, 0);
        // Eleven queries: eight round trips plus three perimeter rings.
        expect(backend.queries, hasLength(11));
        expect(backend.maxInFlight, lessThanOrEqualTo(smartLoopConcurrency));
        // The list grew one candidate at a time before it settled.
        expect(counts.where((n) => n == 1), isNotEmpty);
        expect(counts.where((n) => n == 2), isNotEmpty);
        for (var i = 1; i < state.candidates.length; i++) {
          expect(
            state.candidates[i - 1].score.total,
            lessThanOrEqualTo(state.candidates[i].score.total),
          );
        }
      },
    );

    test('progress counts queries that failed as well', () async {
      final seen = <double>[];
      final container = _container(
        FakeLoopBackend(failWhen: (q) => q.roundTrip),
      );
      container.listen(
        smartLoopControllerProvider,
        (_, next) => seen.add(next.progress),
      );

      await container
          .read(smartLoopControllerProvider.notifier)
          .start(_request);

      expect(seen.where((p) => p > 0 && p < 1), isNotEmpty);
      expect(container.read(smartLoopControllerProvider).progress, 1);
      // Only the three perimeter rings routed.
      expect(
        container.read(smartLoopControllerProvider).candidates,
        hasLength(3),
      );
    });

    test('a request with a via is routed through it', () async {
      final backend = FakeLoopBackend();
      final container = _container(backend);
      await container
          .read(smartLoopControllerProvider.notifier)
          .start(
            const LoopRequest(start: _start, via: [_lake], targetM: 40000),
          );

      expect(backend.queries.any((q) => q.points.contains(_lake)), isTrue);
      expect(backend.queries.every((q) => !q.roundTrip), isTrue);
      expect(backend.queries.every((q) => !q.allowSameWayBack), isTrue);
    });

    test('the request and the profile reach the routing server', () async {
      final backend = FakeLoopBackend();
      final container = _container(backend);
      await container
          .read(smartLoopControllerProvider.notifier)
          .start(
            const LoopRequest(start: _start, targetM: 30000, profile: 'gravel'),
          );

      expect(backend.queries.every((q) => q.profile == 'gravel'), isTrue);
      expect(
        container.read(smartLoopControllerProvider).request?.targetM,
        30000,
      );
    });

    test(
      'a seed changes where the perimeter fallback puts its rings',
      () async {
        final first = FakeLoopBackend();
        await _container(first)
            .read(smartLoopControllerProvider.notifier)
            .start(_request, seed: 1);
        final second = FakeLoopBackend();
        await _container(second)
            .read(smartLoopControllerProvider.notifier)
            .start(_request, seed: 2);

        List<List<LatLng>> ringsOf(FakeLoopBackend b) =>
            b.queries.where((q) => !q.roundTrip).map((q) => q.points).toList();
        expect(ringsOf(first), isNot(equals(ringsOf(second))));
      },
    );

    test('starting again replaces the previous search', () async {
      final backend = FakeLoopBackend(delay: const Duration(milliseconds: 20));
      final container = _container(backend);
      final controller = container.read(smartLoopControllerProvider.notifier);

      final first = controller.start(_request);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await controller.start(const LoopRequest(start: _start, targetM: 20000));
      await first;

      final state = container.read(smartLoopControllerProvider);
      expect(state.running, isFalse);
      expect(state.request?.targetM, 20000);
      expect(state.candidates, isNotEmpty);
    });
  });

  group('select', () {
    test('picks a candidate and ignores impossible indices', () async {
      final container = _container(FakeLoopBackend());
      final controller = container.read(smartLoopControllerProvider.notifier);
      await controller.start(_request);

      controller.select(2);
      expect(container.read(smartLoopControllerProvider).selected, 2);

      controller
        ..select(-1)
        ..select(99);
      expect(container.read(smartLoopControllerProvider).selected, 2);
    });
  });

  group('adopt', () {
    test('hands the route and its waypoints to the planner', () async {
      final container = _container(FakeLoopBackend());
      final controller = container.read(smartLoopControllerProvider.notifier);
      await controller.start(
        const LoopRequest(start: _start, via: [_lake], targetM: 40000),
      );
      controller.select(0);

      expect(controller.adopt(), isTrue);

      final chosen = container.read(smartLoopControllerProvider).candidates[0];
      final planner = container.read(plannerControllerProvider);
      expect(planner.result, same(chosen.result));
      expect(planner.route.isLoading, isFalse);
      expect(planner.positions, chosen.query.points);
      expect(planner.waypoints.first.kind, WaypointKind.start);
      expect(planner.waypoints.last.kind, WaypointKind.end);
      expect(planner.canSave, isTrue);
      // The planner must not route again: the loop is already computed.
      expect(planner.isRouting, isFalse);
    });

    test('carries the profile the loop was routed with', () async {
      final container = _container(FakeLoopBackend());
      final controller = container.read(smartLoopControllerProvider.notifier);
      await controller.start(
        const LoopRequest(start: _start, targetM: 40000, profile: 'mtb'),
      );

      expect(controller.adopt(), isTrue);
      expect(
        container.read(plannerControllerProvider).options.profile,
        RouteProfile.mtb,
      );
    });

    test('a round trip arrives as a single start waypoint', () async {
      final container = _container(FakeLoopBackend());
      final controller = container.read(smartLoopControllerProvider.notifier);
      await controller.start(_request);
      // Pick a candidate the round trip engine produced, if there is one.
      final state = container.read(smartLoopControllerProvider);
      final i = state.candidates.indexWhere((c) => c.query.roundTrip);
      if (i < 0) return;
      controller.select(i);

      expect(controller.adopt(), isTrue);
      expect(container.read(plannerControllerProvider).waypoints, hasLength(1));
      expect(container.read(plannerControllerProvider).isRoutable, isFalse);
    });

    test('does nothing without a selection', () {
      final container = _container(FakeLoopBackend());
      expect(
        container.read(smartLoopControllerProvider.notifier).adopt(),
        isFalse,
      );
      expect(container.read(plannerControllerProvider).waypoints, isEmpty);
    });
  });

  group('cancel', () {
    test('stops the search and every request in flight', () async {
      final backend = FakeLoopBackend(delay: const Duration(seconds: 5));
      final container = _container(backend);
      final controller = container.read(smartLoopControllerProvider.notifier);

      final run = controller.start(_request);
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
  });

  group('failure', () {
    test('nothing routable is an empty result, not an error', () async {
      final container = _container(FakeLoopBackend(failWhen: (_) => true));
      await container
          .read(smartLoopControllerProvider.notifier)
          .start(_request);

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
          .start(_request);

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
            .start(_request);

        final state = container.read(smartLoopControllerProvider);
        expect(state.error, noRoutingBackendError);
        expect(state.running, isFalse);
        expect(state.candidates, isEmpty);
      },
    );

    test(
      'a search that produced nothing without a failure is "found nothing"',
      () async {
        // No strategy proposes anything for a zero-distance request with a via
        // list the via strategy cannot use, so nothing is routed at all.
        final backend = FakeLoopBackend();
        final container = _container(backend);
        await container
            .read(smartLoopControllerProvider.notifier)
            .start(const LoopRequest(start: _start, targetM: 0));

        final state = container.read(smartLoopControllerProvider);
        expect(state.running, isFalse);
        expect(state.error, isNull);
      },
    );
  });
}
