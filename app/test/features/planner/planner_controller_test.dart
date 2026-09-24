import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
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

ProviderContainer _container(
  FakeRoutingBackend? backend, {
  List<Override> overrides = const <Override>[],
}) {
  final container = ProviderContainer(
    overrides: [
      routingBackendProvider.overrideWithValue(backend),
      sharedPreferencesProvider.overrideWithValue(_prefs),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A repository that remembers which waypoints the planner wrote back to
/// which route, over a database nothing else reads.
class _RecordingRepository extends RouteRepository {
  _RecordingRepository(VelorkiDatabase db) : super(db.routesDao);

  final List<(String, List<Waypoint>)> written = [];

  @override
  Future<void> setWaypoints(String id, List<Waypoint> waypoints) async {
    written.add((id, waypoints));
  }
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

  group('waypoint details', () {
    testWidgets('a name, a kind and a note are set undoably, without routing', (
      tester,
    ) async {
      final backend = FakeRoutingBackend();
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier);
      planner.addWaypoint(_a);
      planner.addWaypoint(_b);
      await tester.pump(const Duration(milliseconds: 400));
      final calls = backend.callCount;

      planner.setWaypointDetails(
        1,
        name: '  Bakery ',
        poiKind: PoiKind.food,
        note: 'Croissants',
      );
      await tester.pump(const Duration(milliseconds: 400));
      final point = container.read(plannerControllerProvider).waypoints[1];
      expect(point.name, 'Bakery');
      expect(point.poiKind, PoiKind.food);
      expect(point.note, 'Croissants');
      expect(point.kind, WaypointKind.end);
      expect(backend.callCount, calls, reason: 'details change no road');

      // Blank fields clear; the whole edit is one undo step.
      planner.setWaypointDetails(1, name: '', note: '   ');
      expect(
        container.read(plannerControllerProvider).waypoints[1].name,
        isNull,
      );
      expect(
        container.read(plannerControllerProvider).waypoints[1].note,
        isNull,
      );
      planner.undo();
      expect(
        container.read(plannerControllerProvider).waypoints[1].name,
        'Bakery',
      );
      planner.undo();
      expect(
        container.read(plannerControllerProvider).waypoints[1].name,
        isNull,
      );
      // An undo schedules a route; let it run out.
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('points beside the route', () {
    const mid = LatLng(48.02, 11.02);

    testWidgets('a point moves off the route and back, one undo step each', (
      tester,
    ) async {
      final backend = FakeRoutingBackend();
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier);
      planner.addWaypoint(_a);
      planner.addWaypoint(mid);
      planner.addWaypoint(_b);
      await tester.pump(const Duration(milliseconds: 400));
      final routed = backend.callCount;
      expect(container.read(plannerControllerProvider).waypoints, hasLength(3));

      planner.movePointBeside(1);
      await tester.pump(const Duration(milliseconds: 400));
      var state = container.read(plannerControllerProvider);
      expect(state.waypoints, hasLength(2));
      expect(state.pois.single.pos, mid);
      expect(
        backend.callCount,
        greaterThan(routed),
        reason: 'the route is drawn again without the point',
      );

      planner.movePointOnRoute(0);
      await tester.pump(const Duration(milliseconds: 400));
      state = container.read(plannerControllerProvider);
      expect(state.pois, isEmpty);
      expect(state.waypoints, hasLength(3));
      expect(state.waypoints[1].pos, mid, reason: 'a via where it lies');
      expect(state.waypoints[1].kind, WaypointKind.via);

      planner.undo();
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(plannerControllerProvider).pois, hasLength(1));
      planner.undo();
      await tester.pump(const Duration(milliseconds: 400));
      state = container.read(plannerControllerProvider);
      expect(state.pois, isEmpty);
      expect(state.waypoints, hasLength(3));
    });

    testWidgets('the name, the kind and the note go with it both ways', (
      tester,
    ) async {
      final container = _container(FakeRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier);
      planner.addWaypoint(_a);
      planner.addWaypoint(mid);
      planner.addWaypoint(_b);
      await tester.pump(const Duration(milliseconds: 400));
      planner.setWaypointDetails(
        1,
        name: 'Bakery',
        poiKind: PoiKind.food,
        note: 'Croissants',
      );

      planner.movePointBeside(1);
      await tester.pump(const Duration(milliseconds: 400));
      final poi = container.read(plannerControllerProvider).pois.single;
      expect(poi.name, 'Bakery');
      expect(poi.kind, PoiKind.food);
      expect(poi.description, 'Croissants');

      planner.movePointOnRoute(0);
      await tester.pump(const Duration(milliseconds: 400));
      final back = container.read(plannerControllerProvider).waypoints[1];
      expect(back.name, 'Bakery');
      expect(back.poiKind, PoiKind.food);
      expect(back.note, 'Croissants');
    });

    testWidgets('a turn taken off the route is only a place: a cue of a road '
        'the ride no longer takes is nothing', (tester) async {
      final container = _container(FakeRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier);
      planner.addWaypoint(_a);
      planner.addWaypoint(mid);
      planner.addWaypoint(_b);
      await tester.pump(const Duration(milliseconds: 400));
      planner.setWaypointDetails(
        1,
        name: 'Left at the mill',
        poiKind: PoiKind.turn,
        turn: TurnKind.left,
      );

      planner.movePointBeside(1);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        container.read(plannerControllerProvider).pois.single.kind,
        PoiKind.generic,
      );
    });

    testWidgets('one is added, named and removed without routing', (
      tester,
    ) async {
      final backend = FakeRoutingBackend();
      final container = _container(backend);
      final planner = container.read(plannerControllerProvider.notifier);
      planner.addWaypoint(_a);
      planner.addWaypoint(_b);
      await tester.pump(const Duration(milliseconds: 400));
      final routed = backend.callCount;

      planner.addPoi(_c, name: '  Fountain  ', kind: PoiKind.water);
      await tester.pump(const Duration(milliseconds: 400));
      var state = container.read(plannerControllerProvider);
      expect(state.pois.single.name, 'Fountain');
      expect(state.pois.single.kind, PoiKind.water);
      expect(state.waypoints, hasLength(2));
      expect(
        backend.callCount,
        routed,
        reason: 'a place beside the route changes no road',
      );

      planner.setPoiDetails(
        0,
        name: 'Tap',
        poiKind: PoiKind.water,
        note: '  cold  ',
      );
      state = container.read(plannerControllerProvider);
      expect(state.pois.single.name, 'Tap');
      expect(state.pois.single.description, 'cold');

      planner.removePoi(0);
      expect(container.read(plannerControllerProvider).pois, isEmpty);
      expect(backend.callCount, routed);

      planner.undo();
      expect(container.read(plannerControllerProvider).pois.single.name, 'Tap');
      // An undo schedules a route; let it run out.
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('Clear throws the places away with the waypoints', (
      tester,
    ) async {
      final container = _container(FakeRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier);
      planner.addWaypoint(_a);
      planner.addWaypoint(_b);
      planner.addPoi(_c, name: 'Tap');
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(plannerControllerProvider).hasPoints, isTrue);

      planner.clear();
      await tester.pump(const Duration(milliseconds: 400));
      var state = container.read(plannerControllerProvider);
      expect(state.waypoints, isEmpty);
      expect(state.pois, isEmpty);
      expect(state.hasPoints, isFalse);

      planner.undo();
      await tester.pump(const Duration(milliseconds: 400));
      state = container.read(plannerControllerProvider);
      expect(state.waypoints, hasLength(2));
      expect(state.pois, hasLength(1));
    });
  });

  group('saved routes', () {
    SavedRoute saved({
      required RouteSource source,
      required List<Waypoint> waypoints,
      List<TrackPoint>? geometry,
    }) {
      final points = geometry ?? syntheticRoute().geometry;
      return SavedRoute(
        id: 'r1',
        name: 'Saved',
        source: source,
        profile: RouteProfile.trekking,
        createdAt: DateTime.utc(2026, 9, 12),
        updatedAt: DateTime.utc(2026, 9, 12),
        distanceM: 10000,
        ascentM: 120,
        descentM: 80,
        bounds: BoundingBox.fromPoints(points.map((p) => p.pos)),
        geometryBlob: PackedTrack.encode(points),
        waypoints: waypoints,
        options: const RoutingOptions(),
      );
    }

    test('a planned route comes back with every waypoint and its details', () {
      final container = _container(FakeRoutingBackend());
      const waypoints = [
        Waypoint(pos: _a, kind: WaypointKind.start, name: 'Home'),
        Waypoint(
          pos: LatLng(48.1, 11.1),
          name: 'Bakery',
          poiKind: PoiKind.food,
          note: 'Croissants',
        ),
        Waypoint(pos: _b, kind: WaypointKind.end),
      ];
      container
          .read(plannerControllerProvider.notifier)
          .loadSavedRoute(
            saved(source: RouteSource.planned, waypoints: waypoints),
          );
      expect(container.read(plannerControllerProvider).waypoints, waypoints);
    });

    testWidgets('details on a saved route as stored go straight to the '
        'library; once the plan is routed again they wait for Save', (
      tester,
    ) async {
      final db = VelorkiDatabase.memory();
      addTearDown(db.close);
      final repository = _RecordingRepository(db);
      final backend = FakeRoutingBackend();
      final container = _container(
        backend,
        overrides: [routeRepositoryProvider.overrideWithValue(repository)],
      );
      final planner = container.read(plannerControllerProvider.notifier);
      const waypoints = [
        Waypoint(pos: _a, kind: WaypointKind.start),
        Waypoint(pos: _b, kind: WaypointKind.end),
      ];
      planner.loadSavedRoute(
        saved(source: RouteSource.planned, waypoints: waypoints),
      );
      expect(container.read(plannerControllerProvider).routeIsSaved, isTrue);

      planner.setWaypointDetails(0, name: 'Home', note: 'Start here');
      await tester.pump();
      expect(repository.written, hasLength(1));
      final (id, written) = repository.written.single;
      expect(id, 'r1');
      expect(written[0].name, 'Home');
      expect(written[0].note, 'Start here');
      expect(written[1].kind, WaypointKind.end);
      expect(backend.callCount, 0, reason: 'details change no road');

      // A moved point routes again: the geometry on the map is no longer
      // the one in the library, so details from here on go with the next
      // Save rather than beside a stale route.
      planner.moveWaypoint(1, _c);
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(plannerControllerProvider).routeIsSaved, isFalse);
      planner.setWaypointDetails(1, name: 'Lake');
      await tester.pump();
      expect(repository.written, hasLength(1));

      // Saved again: the plan is the library's once more.
      planner.markSaved('r1', 'Saved');
      planner.setWaypointDetails(1, name: 'Lake', note: 'Swim');
      await tester.pump();
      expect(repository.written, hasLength(2));
      expect(repository.written.last.$2[1].note, 'Swim');
    });

    test('an imported route with only its ends gets shape points along its '
        'track, so an edit follows the course', () {
      final container = _container(FakeRoutingBackend());
      final track = <TrackPoint>[
        for (var i = 0; i < 200; i++)
          TrackPoint(
            LatLng(48 + i * 0.0005, 11 + (i.isEven ? 0 : 0.003) * (i % 3)),
          ),
      ];
      container
          .read(plannerControllerProvider.notifier)
          .loadSavedRoute(
            saved(
              source: RouteSource.importedGpx,
              geometry: track,
              waypoints: [
                Waypoint(pos: track.first.pos, kind: WaypointKind.start),
                Waypoint(pos: track.last.pos, kind: WaypointKind.end),
              ],
            ),
          );
      final waypoints = container.read(plannerControllerProvider).waypoints;
      expect(waypoints.length, greaterThan(2));
      expect(waypoints.length, lessThanOrEqualTo(22));
      expect(waypoints.first.pos, track.first.pos);
      expect(waypoints.first.kind, WaypointKind.start);
      expect(waypoints.last.pos, track.last.pos);
      expect(waypoints.last.kind, WaypointKind.end);
      for (final w in waypoints) {
        expect(track.map((p) => p.pos), contains(w.pos));
      }
      // Nothing was routed: the imported geometry is what shows.
      expect(
        container.read(plannerControllerProvider).result!.geometry.length,
        200,
      );
    });

    test('an imported route splits its points: the ones on the track are '
        'ridden through, the rest stand beside it', () {
      final container = _container(FakeRoutingBackend());
      final track = <TrackPoint>[
        for (var i = 0; i < 200; i++) TrackPoint(LatLng(48 + i * 0.0005, 11)),
      ];
      final onTrack = RoutePoi(
        pos: track[100].pos,
        name: 'Tap',
        kind: PoiKind.water,
      );
      const offTrack = RoutePoi(
        pos: LatLng(48.05, 11.4),
        name: 'Castle',
        kind: PoiKind.generic,
      );
      container
          .read(plannerControllerProvider.notifier)
          .loadSavedRoute(
            SavedRoute(
              id: 'r1',
              name: 'From a file',
              source: RouteSource.importedGpx,
              profile: RouteProfile.trekking,
              createdAt: DateTime.utc(2026, 9, 12),
              updatedAt: DateTime.utc(2026, 9, 12),
              distanceM: 10000,
              ascentM: 0,
              descentM: 0,
              bounds: BoundingBox.fromPoints(track.map((p) => p.pos)),
              geometryBlob: PackedTrack.encode(track),
              waypoints: [
                Waypoint(pos: track.first.pos, kind: WaypointKind.start),
                Waypoint(pos: track.last.pos, kind: WaypointKind.end),
              ],
              options: const RoutingOptions(),
              pois: [onTrack, offTrack],
            ),
          );
      final state = container.read(plannerControllerProvider);
      expect(
        state.waypoints.map((w) => w.name),
        contains('Tap'),
        reason: 'a point on the track is one the route goes through',
      );
      expect(state.pois, [offTrack]);
    });

    test('a route planned here keeps every point of interest beside the '
        'route, whatever it passes', () {
      final container = _container(FakeRoutingBackend());
      final geometry = syntheticRoute().geometry;
      const pois = <RoutePoi>[
        RoutePoi(pos: LatLng(48.01, 11.01), name: 'Tap', kind: PoiKind.water),
      ];
      container
          .read(plannerControllerProvider.notifier)
          .loadSavedRoute(
            SavedRoute(
              id: 'r1',
              name: 'Planned',
              source: RouteSource.planned,
              profile: RouteProfile.trekking,
              createdAt: DateTime.utc(2026, 9, 12),
              updatedAt: DateTime.utc(2026, 9, 12),
              distanceM: 10000,
              ascentM: 0,
              descentM: 0,
              bounds: BoundingBox.fromPoints(geometry.map((p) => p.pos)),
              geometryBlob: PackedTrack.encode(geometry),
              waypoints: const [
                Waypoint(pos: _a, kind: WaypointKind.start),
                Waypoint(pos: _b, kind: WaypointKind.end),
              ],
              options: const RoutingOptions(),
              pois: pois,
            ),
          );
      final state = container.read(plannerControllerProvider);
      expect(state.waypoints, hasLength(2));
      expect(state.pois, pois);
    });

    testWidgets('an import opened in the planner keeps both sets, and the '
        'word the file used, through a Save', (tester) async {
      final db = VelorkiDatabase.memory();
      addTearDown(db.close);
      final repository = RouteRepository(db.routesDao);
      final container = _container(
        FakeRoutingBackend(),
        overrides: [routeRepositoryProvider.overrideWithValue(repository)],
      );
      final track = <TrackPoint>[
        for (var i = 0; i < 200; i++) TrackPoint(LatLng(48 + i * 0.0005, 11)),
      ];
      final imported = await repository.saveImportedRoute(
        name: 'From a file',
        points: track,
        source: RouteSource.importedGpx,
        pois: [
          RoutePoi(
            pos: track[100].pos,
            name: 'Tap',
            kind: PoiKind.water,
            sourceType: 'Drinking Water',
          ),
          const RoutePoi(
            pos: LatLng(48.05, 11.4),
            name: 'Castle',
            sourceType: 'monument',
          ),
        ],
      );

      final planner = container.read(plannerControllerProvider.notifier);
      planner.loadSavedRoute(imported);
      var state = container.read(plannerControllerProvider);
      expect(state.waypoints.map((w) => w.name), contains('Tap'));
      expect(state.pois.single.name, 'Castle');

      // The rider says what the place off the course is, and saves.
      planner.setPoiDetails(0, name: 'Castle', poiKind: PoiKind.viewpoint);
      state = container.read(plannerControllerProvider);
      await repository.savePlannedRoute(
        name: imported.name,
        route: state.result!,
        waypoints: state.waypoints,
        pois: state.pois,
        options: state.options,
        id: state.savedRouteId,
      );

      final reloaded = (await repository.routeById(imported.id))!;
      expect(reloaded.pois.single.name, 'Castle');
      expect(reloaded.pois.single.kind, PoiKind.viewpoint);
      expect(
        reloaded.pois.single.sourceType,
        'monument',
        reason: 'the file\'s own word outlives the edit',
      );
      final tap = reloaded.waypoints.firstWhere((w) => w.name == 'Tap');
      expect(tap.poiKind, PoiKind.water);
      expect(tap.sourceType, 'Drinking Water');

      // Opened again, the two sets come back the same.
      planner.loadSavedRoute(reloaded);
      final again = container.read(plannerControllerProvider);
      expect(again.pois.single.name, 'Castle');
      expect(again.waypoints.map((w) => w.name), contains('Tap'));
      await tester.pump(const Duration(milliseconds: 400));
    });

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
