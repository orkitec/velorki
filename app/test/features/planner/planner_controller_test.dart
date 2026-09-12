import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';

const LatLng _a = LatLng(48.0, 11.0);
const LatLng _b = LatLng(48.2, 11.2);
const LatLng _c = LatLng(48.4, 11.4);

ProviderContainer _container(FakeRoutingBackend? backend) {
  final container = ProviderContainer(
    overrides: [routingBackendProvider.overrideWithValue(backend)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('waypoint editing', () {
    test('a tap appends and the kinds follow the order', () {
      final container = _container(FakeRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier);

      planner.addWaypoint(_a);
      expect(container.read(plannerControllerProvider).waypoints, [
        const Waypoint(pos: _a, kind: WaypointKind.start),
      ]);

      planner.addWaypoint(_b);
      planner.addWaypoint(_c);
      expect(
        container
            .read(plannerControllerProvider)
            .waypoints
            .map((w) => w.kind)
            .toList(),
        [WaypointKind.start, WaypointKind.via, WaypointKind.end],
      );
    });

    test('a long press inserts into the nearest segment', () {
      final container = _container(FakeRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b)
        ..addWaypoint(_c);

      // Close to the middle of the first segment.
      planner.insertWaypoint(const LatLng(48.1, 11.1));

      expect(container.read(plannerControllerProvider).positions, [
        _a,
        const LatLng(48.1, 11.1),
        _b,
        _c,
      ]);
    });

    test('a long press with one waypoint appends instead', () {
      final container = _container(FakeRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..insertWaypoint(_b);

      expect(container.read(plannerControllerProvider).positions, [_a, _b]);
      expect(planner, isNotNull);
    });

    test('moving a waypoint replaces its position and drops its label', () {
      final container = _container(FakeRoutingBackend());
      container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a, name: 'Munich')
        ..addWaypoint(_b)
        ..moveWaypoint(0, _c);

      final first = container.read(plannerControllerProvider).waypoints.first;
      expect(first.pos, _c);
      expect(first.name, isNull);
    });

    test('moving an unknown index does nothing', () {
      final container = _container(FakeRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..moveWaypoint(7, _b);

      expect(container.read(plannerControllerProvider).positions, [_a]);
      expect(container.read(plannerControllerProvider).canUndo, isTrue);
      expect(planner, isNotNull);
    });

    test('removing takes a waypoint out', () {
      final container = _container(FakeRoutingBackend());
      container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b)
        ..addWaypoint(_c)
        ..removeWaypoint(1);

      expect(container.read(plannerControllerProvider).positions, [_a, _c]);
    });

    test('reverse swaps start and end', () {
      final container = _container(FakeRoutingBackend());
      container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b)
        ..addWaypoint(_c)
        ..reverse();

      final state = container.read(plannerControllerProvider);
      expect(state.positions, [_c, _b, _a]);
      expect(state.waypoints.first.kind, WaypointKind.start);
      expect(state.waypoints.last.kind, WaypointKind.end);
    });

    test('clear empties the plan and undo brings it back', () {
      final container = _container(FakeRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b)
        ..clear();

      expect(container.read(plannerControllerProvider).waypoints, isEmpty);

      planner.undo();
      expect(container.read(plannerControllerProvider).positions, [_a, _b]);

      planner
        ..undo()
        ..undo();
      expect(container.read(plannerControllerProvider).waypoints, isEmpty);
      expect(container.read(plannerControllerProvider).canUndo, isFalse);

      // Undoing an empty stack is a no-op, not an error.
      planner.undo();
      expect(container.read(plannerControllerProvider).waypoints, isEmpty);
    });
  });

  group('routing', () {
    testWidgets('waits 300 ms, then routes once', (tester) async {
      final backend = FakeRoutingBackend();
      final container = _container(backend);
      container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b);

      expect(container.read(plannerControllerProvider).isRouting, isTrue);
      await tester.pump(const Duration(milliseconds: 250));
      expect(backend.callCount, 0);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(backend.callCount, 1);

      final state = container.read(plannerControllerProvider);
      expect(state.result, isNotNull);
      expect(state.result!.lengthM, 10000);
      expect(state.error, isNull);
      expect(backend.queries.single.points, [_a, _b]);
      expect(backend.queries.single.profile, 'trekking');
    });

    testWidgets('edits inside the debounce window produce one request', (
      tester,
    ) async {
      final backend = FakeRoutingBackend();
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b);

      await tester.pump(const Duration(milliseconds: 100));
      planner.addWaypoint(_c);
      await tester.pump(const Duration(milliseconds: 100));
      planner.moveWaypoint(0, const LatLng(47.9, 10.9));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(backend.callCount, 1);
      expect(backend.queries.single.points.length, 3);
    });

    testWidgets('a new edit cancels the request in flight', (tester) async {
      final backend = FakeRoutingBackend(
        delay: const Duration(milliseconds: 500),
      );
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b);

      await tester.pump(const Duration(milliseconds: 350));
      expect(backend.callCount, 1);

      planner.addWaypoint(_c);
      expect(backend.tokens.single.isCancelled, isTrue);

      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump();

      expect(backend.callCount, 2);
      // The cancelled answer never became the shown route.
      expect(container.read(plannerControllerProvider).error, isNull);
      expect(backend.queries.last.points.length, 3);
    });

    testWidgets('fewer than two waypoints clears the route', (tester) async {
      final backend = FakeRoutingBackend();
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(container.read(plannerControllerProvider).result, isNotNull);

      planner.removeWaypoint(1);
      await tester.pump(const Duration(milliseconds: 400));

      final state = container.read(plannerControllerProvider);
      expect(state.result, isNull);
      expect(state.isRouting, isFalse);
      expect(backend.callCount, 1);
    });

    testWidgets('a routing failure lands in the state', (tester) async {
      final backend = FakeRoutingBackend()
        ..error = const RoutingException(
          kind: RoutingErrorKind.noRoute,
          message: 'target island detached',
        );
      final container = _container(backend);
      container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final state = container.read(plannerControllerProvider);
      expect(state.error, 'target island detached');
      expect(state.route.hasError, isTrue);
    });

    testWidgets('without a routing server the planner says so', (tester) async {
      final container = _container(null);
      container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(
        container.read(plannerControllerProvider).error,
        noRoutingBackendError,
      );
    });

    testWidgets('switching the profile re-routes with it', (tester) async {
      final backend = FakeRoutingBackend();
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      planner.setProfile(RouteProfile.gravel);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(backend.queries.last.profile, 'gravel');
      expect(
        container.read(plannerControllerProvider).options.profile,
        RouteProfile.gravel,
      );
    });
  });

  group('alternatives', () {
    testWidgets('are fetched only on request', (tester) async {
      final backend = FakeRoutingBackend();
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(container.read(plannerControllerProvider).alternatives, isEmpty);

      final loaded = planner.loadAlternatives();
      await tester.pump();
      await tester.pump();
      expect(await loaded, isTrue);

      final state = container.read(plannerControllerProvider);
      expect(state.alternatives, hasLength(4));
      expect(state.loadingAlternatives, isFalse);
      expect(backend.queries.map((q) => q.alternativeIdx).toList(), [
        0,
        0,
        1,
        2,
        3,
      ]);
    });

    testWidgets('switching to a fetched one does not route again', (
      tester,
    ) async {
      final backend = FakeRoutingBackend();
      backend.byAlternative[2] = syntheticRoute(lengthM: 12345);
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await planner.loadAlternatives();
      final before = backend.callCount;

      planner.setAlternative(2);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(backend.callCount, before);
      expect(container.read(plannerControllerProvider).result!.lengthM, 12345);
    });

    testWidgets('report failure when the server has none', (tester) async {
      final backend = FakeRoutingBackend()
        ..error = const RoutingException(
          kind: RoutingErrorKind.noRoute,
          message: 'no alternatives',
        );
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(await planner.loadAlternatives(), isFalse);
      expect(
        container.read(plannerControllerProvider).loadingAlternatives,
        isFalse,
      );
    });
  });
}
