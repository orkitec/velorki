import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';

const LatLng _a = LatLng(48.0, 11.0);
const LatLng _b = LatLng(48.2, 11.2);
const LatLng _c = LatLng(48.4, 11.4);

/// The preferences the planner remembers its profile in, empty for every
/// test.
late SharedPreferences _prefs;

ProviderContainer _container(FakeRoutingBackend? backend) {
  final container = ProviderContainer(
    overrides: [
      routingBackendProvider.overrideWithValue(backend),
      sharedPreferencesProvider.overrideWithValue(_prefs),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _prefs = await SharedPreferences.getInstance();
  });
  setUp(() => _prefs.clear());

  group('the profile is remembered', () {
    Future<ProviderContainer> containerWith(Map<String, Object> stored) async {
      SharedPreferences.setMockInitialValues(stored);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          routingBackendProvider.overrideWithValue(FakeRoutingBackend()),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a stored profile is the one the planner starts with', () async {
      final container = await containerWith(<String, Object>{
        'planner.profile': 'gravel',
      });
      expect(
        container.read(plannerControllerProvider).options.profile,
        RouteProfile.gravel,
      );
    });

    test('a name no profile has falls back to the default', () async {
      final container = await containerWith(<String, Object>{
        'planner.profile': 'unicycle',
      });
      expect(
        container.read(plannerControllerProvider).options.profile,
        RouteProfile.trekking,
      );
    });

    testWidgets('picking a profile stores it; the default clears it', (
      tester,
    ) async {
      final container = _container(FakeRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier);

      planner.setProfile(RouteProfile.mtb);
      await tester.pump();
      expect(_prefs.getString('planner.profile'), 'mtb');

      planner.setProfile(RouteProfile.trekking);
      await tester.pump();
      expect(_prefs.getString('planner.profile'), isNull);
    });
  });

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

    testWidgets('a waypoint swaps places with a neighbour, undoably', (
      tester,
    ) async {
      final backend = FakeRoutingBackend();
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b)
        ..addWaypoint(_c);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      final before = backend.callCount;

      planner.swapWaypoint(1, 1);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      var positions = container
          .read(plannerControllerProvider)
          .waypoints
          .map((w) => w.pos)
          .toList();
      expect(positions, [_a, _c, _b]);
      expect(backend.callCount, before + 1);

      // The ends cannot move past the edges; nothing changes and no route.
      planner
        ..swapWaypoint(0, -1)
        ..swapWaypoint(2, 1)
        ..swapWaypoint(1, 0);
      await tester.pump(const Duration(milliseconds: 400));
      expect(backend.callCount, before + 1);

      planner.undo();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      positions = container
          .read(plannerControllerProvider)
          .waypoints
          .map((w) => w.pos)
          .toList();
      expect(positions, [_a, _b, _c]);
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

  group('closeLoop', () {
    testWidgets(
      'appends the start and routes the way home around the way out',
      (tester) async {
        final backend = FakeRoutingBackend();
        final container = _container(backend);
        final planner = container.read(plannerControllerProvider.notifier)
          ..addWaypoint(_a)
          ..addWaypoint(_b);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        backend.queries.clear();

        planner.closeLoop(differentWayBack: true);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        final state = container.read(plannerControllerProvider);
        expect(state.positions, [_a, _b, _a]);
        expect(state.isClosedLoop, isTrue);
        expect(state.options.differentWayBack, isTrue);
        expect(state.waypoints.last.kind, WaypointKind.end);

        expect(backend.queries, hasLength(2));
        expect(backend.queries[0].points, [_a, _b]);
        expect(backend.queries[0].nogos, isEmpty);
        expect(backend.queries[1].points, [_b, _a]);
        expect(backend.queries[1].nogos, isNotEmpty);
        // One route, not two: the legs are merged before anyone sees them.
        expect(state.result!.lengthM, 20000);
        expect(state.error, isNull);
      },
    );

    testWidgets('without a different way back it is one request', (
      tester,
    ) async {
      final backend = FakeRoutingBackend();
      final container = _container(backend);
      container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b)
        ..closeLoop(differentWayBack: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(backend.queries, hasLength(1));
      expect(backend.queries.single.points, [_a, _b, _a]);
      expect(container.read(plannerControllerProvider).result!.lengthM, 10000);
    });

    testWidgets('undo takes the whole loop back in one step', (tester) async {
      final container = _container(FakeRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      planner.closeLoop(differentWayBack: true);
      expect(container.read(plannerControllerProvider).positions, [_a, _b, _a]);

      planner.undo();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final state = container.read(plannerControllerProvider);
      expect(state.positions, [_a, _b]);
      expect(state.isClosedLoop, isFalse);
      // The option is stale but harmless: an open plan has no way out to avoid.
      expect(state.ridesBackAnotherWay, isFalse);
    });

    testWidgets('reversing a closed loop keeps it closed', (tester) async {
      final container = _container(FakeRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b)
        ..addWaypoint(_c)
        ..closeLoop(differentWayBack: true);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      planner.reverse();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final state = container.read(plannerControllerProvider);
      expect(state.positions, [_a, _c, _b, _a]);
      expect(state.isClosedLoop, isTrue);
      expect(state.ridesBackAnotherWay, isTrue);
    });

    testWidgets('a loop that will not route comes home the way it went', (
      tester,
    ) async {
      // Only the way home with no-gos fails; the retry without them works.
      final backend = _PickyBackend();
      final container = _container(backend);
      container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b)
        ..closeLoop(differentWayBack: true);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(backend.queries, hasLength(3));
      expect(container.read(plannerControllerProvider).result, isNotNull);
      expect(container.read(plannerControllerProvider).error, isNull);
    });

    testWidgets('variants change the way out, not the way home', (
      tester,
    ) async {
      final backend = FakeRoutingBackend();
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b)
        ..closeLoop(differentWayBack: true);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      backend.queries.clear();

      await planner.loadAlternatives();

      // Four alternatives, two legs each: the way out takes the variant the
      // planner asked for, the way home keeps its own.
      expect(backend.queries, hasLength(8));
      for (var i = 0; i < 8; i += 2) {
        expect(backend.queries[i].alternativeIdx, i ~/ 2);
        expect(backend.queries[i + 1].alternativeIdx, 0);
      }
      expect(
        container.read(plannerControllerProvider).alternatives,
        hasLength(4),
      );
    });

    test('a plan with one waypoint cannot be closed', () {
      final container = _container(FakeRoutingBackend());
      container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..closeLoop(differentWayBack: true);

      expect(container.read(plannerControllerProvider).positions, [_a]);
    });

    test('differentWayBack survives the database round trip', () {
      const options = RoutingOptions(
        profile: RouteProfile.gravel,
        alternativeIdx: 2,
        differentWayBack: true,
      );

      expect(RoutingOptions.fromMap(options.toMap()), options);
      expect(options.toMap()['differentWayBack'], isTrue);
      // An options blob written before the feature existed reads as "off".
      expect(
        RoutingOptions.fromMap(const <String, dynamic>{
          'profile': 'trekking',
          'alternativeIdx': 0,
        }).differentWayBack,
        isFalse,
      );
    });
  });
  group('anotherWayBack', () {
    /// Plots a closed loop and lets the first routing settle.
    Future<PlannerController> closedLoop(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b)
        ..closeLoop(differentWayBack: true);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      return planner;
    }

    testWidgets('asks for the next alternative of the way home only', (
      tester,
    ) async {
      final backend = VariedRoutingBackend();
      final container = _container(backend);
      final planner = await closedLoop(tester, container);
      backend.queries.clear();

      await planner.anotherWayBack();

      expect(
        container.read(plannerControllerProvider).options.returnVariant,
        1,
      );
      expect(backend.queries, hasLength(2));
      expect(backend.queries[0].points, [_a, _b]);
      expect(backend.queries[0].alternativeIdx, 0);
      expect(backend.queries[1].points, [_b, _a]);
      expect(backend.queries[1].alternativeIdx, 1);
    });

    testWidgets('wraps around after the last variant', (tester) async {
      final backend = VariedRoutingBackend();
      final container = _container(backend);
      final planner = await closedLoop(tester, container);

      final seen = <int>[];
      for (var i = 0; i < 5; i++) {
        await planner.anotherWayBack();
        seen.add(
          container.read(plannerControllerProvider).options.returnVariant,
        );
      }

      expect(seen, [1, 2, 3, 0, 1]);
    });

    testWidgets('skips a variant that draws the same way home', (tester) async {
      // Variants 1 and 2 are the same road; 3 is a different one.
      final backend = VariedRoutingBackend(sameAs: {1: 0, 2: 0});
      final container = _container(backend);
      final planner = await closedLoop(tester, container);

      await planner.anotherWayBack();

      expect(
        container.read(plannerControllerProvider).options.returnVariant,
        3,
      );
    });

    testWidgets('each press is one undo step', (tester) async {
      final backend = VariedRoutingBackend();
      final container = _container(backend);
      final planner = await closedLoop(tester, container);

      await planner.anotherWayBack();
      await planner.anotherWayBack();
      expect(
        container.read(plannerControllerProvider).options.returnVariant,
        2,
      );

      planner.undo();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(
        container.read(plannerControllerProvider).options.returnVariant,
        1,
      );
      expect(container.read(plannerControllerProvider).positions, [_a, _b, _a]);

      planner.undo();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      final state = container.read(plannerControllerProvider);
      expect(state.options.returnVariant, 0);
      expect(state.isClosedLoop, isTrue);

      // One more takes the whole loop back.
      planner.undo();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(container.read(plannerControllerProvider).positions, [_a, _b]);
    });

    testWidgets('an open route has no way home to redraw', (tester) async {
      final backend = VariedRoutingBackend();
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(_a)
        ..addWaypoint(_b);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      backend.queries.clear();

      await planner.anotherWayBack();

      expect(backend.queries, isEmpty);
      expect(
        container.read(plannerControllerProvider).options.returnVariant,
        0,
      );
    });

    test('the return variant survives the database round trip', () {
      const options = RoutingOptions(differentWayBack: true, returnVariant: 3);

      expect(RoutingOptions.fromMap(options.toMap()), options);
      expect(options.toMap()['returnVariant'], 3);
      expect(
        RoutingOptions.fromMap(const <String, dynamic>{
          'profile': 'trekking',
          'returnVariant': 9,
        }).returnVariant,
        RoutingOptions.maxAlternativeIdx,
      );
      expect(
        RoutingOptions.fromMap(const <String, dynamic>{'profile': 'trekking'})
            .returnVariant,
        0,
      );
    });
  });

  group('saved routes', () {
    test('loading one puts its turn instructions back on the plan', () {
      const turns = <TurnHint>[
        TurnHint(pointIndex: 1, kind: TurnKind.slightLeft, angleDeg: -30),
        TurnHint(pointIndex: 3, kind: TurnKind.right, angleDeg: 85),
      ];
      final geometry = syntheticRoute().geometry;
      final container = _container(FakeRoutingBackend());

      container
          .read(plannerControllerProvider.notifier)
          .loadSavedRoute(
            SavedRoute(
              id: 'r1',
              name: 'Saved',
              source: RouteSource.planned,
              profile: RouteProfile.trekking,
              createdAt: DateTime.utc(2026, 9, 12),
              updatedAt: DateTime.utc(2026, 9, 12),
              distanceM: 10000,
              ascentM: 120,
              descentM: 80,
              bounds: BoundingBox.fromPoints(geometry.map((p) => p.pos)),
              geometryBlob: PackedTrack.encode(geometry),
              waypoints: const [
                Waypoint(pos: _a, kind: WaypointKind.start),
                Waypoint(pos: _b, kind: WaypointKind.end),
              ],
              options: const RoutingOptions(),
              turns: turns,
            ),
          );

      final route = container.read(plannerControllerProvider).route.value!;
      expect(route.turns, turns);
      // The indices still point into the geometry that came back.
      expect(route.turns.last.pointIndex, lessThan(route.geometry.length));
    });
  });
}

/// A backend that refuses any query carrying no-gos, so the close-loop
/// fallback has something to fall back from.
class _PickyBackend extends FakeRoutingBackend {
  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) {
    if (q.nogos.isNotEmpty) {
      queries.add(q);
      throw const RoutingException(
        kind: RoutingErrorKind.noRoute,
        message: 'no track found',
      );
    }
    return super.route(q, cancel: cancel);
  }
}
