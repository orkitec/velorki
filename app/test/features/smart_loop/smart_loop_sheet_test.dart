import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/smart_loop/application/smart_loop_controller.dart';
import 'package:velorki/features/smart_loop/presentation/smart_loop_sheet.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../assistant/support/fakes.dart';
import '../planner/support/fakes.dart';
import '../planner/support/pump.dart';

const LatLng _first = LatLng(48.0, 11.0);
const LatLng _second = LatLng(48.05, 11.05);

/// The provider container behind the screen under test.
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)));

/// Scopes a finder to the sheet, so the planner underneath the modal barrier
/// does not match as well.
Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(SmartLoopSheet), matching: finder);

/// A gateway that refuses for good, so no rationale dialog is shown.
class _NoLocation implements LocationPermissionGateway {
  const _NoLocation();

  @override
  Future<LocationPermissionStatus> check() async =>
      LocationPermissionStatus.deniedForever;

  @override
  Future<LocationPermissionStatus> request() async =>
      LocationPermissionStatus.deniedForever;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

/// Plots [points] on the map and opens the loop sheet from the bottom bar.
Future<PlannerHarness> _openSheet(
  WidgetTester tester, {
  List<LatLng> points = const <LatLng>[_first],
  PlannerHarness? harness,
  bool withPosition = true,
  List<Override> extraOverrides = const <Override>[],
}) async {
  final h = await pumpScreen(
    tester,
    const PlannerScreen(),
    harness: harness,
    extraOverrides: [
      locationPermissionGatewayProvider.overrideWithValue(
        withPosition ? const GrantedLocationPermission() : const _NoLocation(),
      ),
      positionSourceProvider.overrideWithValue(
        const FixedPositionSource(_first),
      ),
      ...extraOverrides,
    ],
  );
  for (final point in points) {
    h.map.onTap!(point);
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(LabeledIconButton, 'Loop'));
  await tester.pumpAndSettle();
  return h;
}

Future<void> _make(WidgetTester tester) async {
  await tester.tap(_inSheet(find.widgetWithText(FilledButton, 'Make a loop')));
  await tester.pumpAndSettle();
}

void main() {
  group('a route on the map', () {
    testWidgets('offers to close it, a different way back', (tester) async {
      await _openSheet(tester, points: const [_first, _second]);

      expect(find.text('Make a loop'), findsOneWidget);
      expect(find.text('Ride back to where you started.'), findsOneWidget);
      expect(find.text('Different way back'), findsOneWidget);
      expect(find.text('Avoids the roads you already rode.'), findsOneWidget);
      expect(
        tester.widget<Switch>(_inSheet(find.byType(Switch))).value,
        isTrue,
      );
      expect(
        _inSheet(find.widgetWithText(FilledButton, 'Close the loop')),
        findsOneWidget,
      );
      // None of the from-scratch controls are in the way.
      expect(_inSheet(find.byType(Slider)), findsNothing);
    });

    testWidgets('closing it rides home around the way out', (tester) async {
      final h = await _openSheet(tester, points: const [_first, _second]);
      h.backend.queries.clear();

      await tester.tap(
        _inSheet(find.widgetWithText(FilledButton, 'Close the loop')),
      );
      await tester.pumpAndSettle();

      // The sheet stays open on what it made.
      expect(find.byType(SmartLoopSheet), findsOneWidget);
      expect(_inSheet(find.textContaining('up')), findsOneWidget);
      expect(
        _inSheet(find.widgetWithText(OutlinedButton, 'Another way back')),
        findsOneWidget,
      );
      expect(
        _inSheet(find.widgetWithText(FilledButton, 'Done')),
        findsOneWidget,
      );
      final planner = _container(tester).read(plannerControllerProvider);
      expect(planner.waypoints, hasLength(3));
      expect(planner.waypoints.last.pos, _first);
      expect(planner.isClosedLoop, isTrue);
      expect(planner.options.differentWayBack, isTrue);

      // Two legs: the way out, then the way home past the way out.
      expect(h.backend.queries, hasLength(2));
      expect(h.backend.queries[0].points, <LatLng>[_first, _second]);
      expect(h.backend.queries[0].nogos, isEmpty);
      expect(h.backend.queries[1].points, <LatLng>[_second, _first]);
      expect(h.backend.queries[1].nogos, isNotEmpty);
      expect(h.backend.queries[1].nogos.every((n) => n.weight != null), isTrue);
      // The two legs arrive as one route.
      expect(planner.result!.lengthM, 20000);
    });

    testWidgets('with the switch off it is one plain request', (tester) async {
      final h = await _openSheet(tester, points: const [_first, _second]);
      h.backend.queries.clear();

      await tester.tap(_inSheet(find.byType(Switch)));
      await tester.pumpAndSettle();
      await tester.tap(
        _inSheet(find.widgetWithText(FilledButton, 'Close the loop')),
      );
      await tester.pumpAndSettle();

      final planner = _container(tester).read(plannerControllerProvider);
      expect(planner.options.differentWayBack, isFalse);
      expect(h.backend.queries, hasLength(1));
      expect(h.backend.queries.single.points, <LatLng>[
        _first,
        _second,
        _first,
      ]);
    });

    testWidgets('"Another way back" redraws only the way home', (tester) async {
      final h = await _openSheet(
        tester,
        points: const [_first, _second],
        harness: PlannerHarness(backend: VariedRoutingBackend()),
      );
      await tester.tap(
        _inSheet(find.widgetWithText(FilledButton, 'Close the loop')),
      );
      await tester.pumpAndSettle();
      h.backend.queries.clear();

      await tester.tap(
        _inSheet(find.widgetWithText(OutlinedButton, 'Another way back')),
      );
      await tester.pumpAndSettle();

      final planner = _container(tester).read(plannerControllerProvider);
      expect(planner.options.returnVariant, 1);
      expect(h.backend.queries, hasLength(2));
      expect(h.backend.queries[0].alternativeIdx, 0);
      expect(h.backend.queries[1].alternativeIdx, 1);
      // Still a loop, still on the map, sheet still open.
      expect(planner.isClosedLoop, isTrue);
      expect(find.byType(SmartLoopSheet), findsOneWidget);

      // And again, one variant further.
      await tester.tap(
        _inSheet(find.widgetWithText(OutlinedButton, 'Another way back')),
      );
      await tester.pumpAndSettle();
      expect(
        _container(tester)
            .read(plannerControllerProvider)
            .options
            .returnVariant,
        2,
      );
    });

    testWidgets('turning the switch off in the result re-routes at once', (
      tester,
    ) async {
      final h = await _openSheet(tester, points: const [_first, _second]);
      await tester.tap(
        _inSheet(find.widgetWithText(FilledButton, 'Close the loop')),
      );
      await tester.pumpAndSettle();
      h.backend.queries.clear();

      await tester.tap(_inSheet(find.byType(Switch)));
      await tester.pumpAndSettle();

      expect(
        _container(tester)
            .read(plannerControllerProvider)
            .options
            .differentWayBack,
        isFalse,
      );
      expect(h.backend.queries, hasLength(1));
      expect(h.backend.queries.single.points, <LatLng>[
        _first,
        _second,
        _first,
      ]);
      // "Another way back" has nothing to redraw any more.
      expect(
        tester
            .widget<OutlinedButton>(
              _inSheet(find.widgetWithText(OutlinedButton, 'Another way back')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('reopening a closed loop lands on the result', (tester) async {
      await _openSheet(tester, points: const [_first, _second]);
      await tester.tap(
        _inSheet(find.widgetWithText(FilledButton, 'Close the loop')),
      );
      await tester.pumpAndSettle();
      await tester.tap(_inSheet(find.widgetWithText(FilledButton, 'Done')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(LabeledIconButton, 'Loop'));
      await tester.pumpAndSettle();

      expect(_inSheet(find.text('Close the loop')), findsNothing);
      expect(
        _inSheet(find.widgetWithText(OutlinedButton, 'Another way back')),
        findsOneWidget,
      );
    });
  });

  group('the bike', () {
    testWidgets('is chosen in the sheet and shared with the planner', (
      tester,
    ) async {
      final h = await _openSheet(tester, points: const [_first, _second]);

      expect(_inSheet(find.text('BIKE')), findsOneWidget);
      expect(
        _inSheet(find.widgetWithText(ChoiceChip, 'Touring')),
        findsOneWidget,
      );

      await tester.tap(_inSheet(find.widgetWithText(ChoiceChip, 'Gravel')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        _container(tester).read(plannerControllerProvider).options.profile,
        RouteProfile.gravel,
      );
      expect(h.backend.queries.last.profile, 'gravel');
    });

    testWidgets('a bare start makes the loop with the chosen bike', (
      tester,
    ) async {
      await _openSheet(tester);

      await tester.tap(_inSheet(find.widgetWithText(ChoiceChip, 'MTB')));
      await tester.pumpAndSettle();
      await _make(tester);

      expect(
        _container(tester).read(smartLoopControllerProvider).request!.profile,
        'mtb',
      );
    });

    testWidgets('changing the bike after a loop offers a fresh one', (
      tester,
    ) async {
      await _openSheet(tester);
      await _make(tester);
      expect(
        _inSheet(find.widgetWithText(FilledButton, 'Done')),
        findsOneWidget,
      );

      await tester.tap(_inSheet(find.widgetWithText(ChoiceChip, 'Road')));
      await tester.pumpAndSettle();

      expect(_inSheet(find.widgetWithText(FilledButton, 'Done')), findsNothing);
      expect(
        _inSheet(find.widgetWithText(FilledButton, 'Make a loop')),
        findsOneWidget,
      );
    });
  });

  group('a bare start', () {
    testWidgets('offers a distance and makes a loop', (tester) async {
      await _openSheet(tester);

      expect(find.text('Make a loop'), findsNWidgets(2));
      expect(find.text('Ride back to where you started.'), findsNothing);
      expect(_inSheet(find.text('30 km')), findsOneWidget);
      expect(_inSheet(find.byType(Slider)), findsOneWidget);
      expect(find.text('Different way back'), findsOneWidget);

      await tester.drag(_inSheet(find.byType(Slider)), const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(_inSheet(find.text('5 km')), findsOneWidget);

      await _make(tester);

      final state = _container(tester).read(smartLoopControllerProvider);
      expect(state.request!.targetM, 5000);
      expect(state.request!.start, _first);
      expect(state.candidates, isNotEmpty);
      // The loop is on the map before the rider has done anything else.
      expect(
        _container(tester).read(plannerControllerProvider).result,
        state.current!.result,
      );
      expect(_inSheet(find.textContaining('up')), findsOneWidget);
      expect(_inSheet(find.widgetWithText(FilledButton, 'Done')), findsOne);
      expect(
        _inSheet(find.widgetWithText(OutlinedButton, 'Another')),
        findsOne,
      );
    });

    testWidgets('the switch is BRouter\'s way round', (tester) async {
      final h = await _openSheet(tester);

      await tester.tap(_inSheet(find.byType(Switch)));
      await tester.pumpAndSettle();
      await _make(tester);

      expect(h.backend.queries.every((q) => q.roundTrip), isTrue);
      expect(h.backend.queries.every((q) => q.allowSameWayBack), isTrue);
    });

    testWidgets('"Another" shows the next loop without routing', (
      tester,
    ) async {
      final h = await _openSheet(tester);
      await _make(tester);
      final routed = h.backend.queries.length;

      await tester.tap(
        _inSheet(find.widgetWithText(OutlinedButton, 'Another')),
      );
      await tester.pumpAndSettle();

      expect(h.backend.queries, hasLength(routed));
      expect(_container(tester).read(smartLoopControllerProvider).index, 1);
    });

    testWidgets('"Done" closes the sheet and keeps the loop', (tester) async {
      await _openSheet(tester);
      await _make(tester);

      await tester.tap(_inSheet(find.widgetWithText(FilledButton, 'Done')));
      await tester.pumpAndSettle();

      expect(find.byType(SmartLoopSheet), findsNothing);
      expect(
        _container(tester).read(plannerControllerProvider).result,
        isNotNull,
      );
    });

    testWidgets('nothing routable says so', (tester) async {
      final backend = FakeRoutingBackend()
        ..error = const RoutingException(
          kind: RoutingErrorKind.noRoute,
          message: 'position not mapped',
        );
      await _openSheet(tester, harness: PlannerHarness(backend: backend));

      await _make(tester);

      expect(
        find.text('No loop found here, try another distance.'),
        findsOneWidget,
      );
    });

    testWidgets('a broken routing server is reported', (tester) async {
      final backend = FakeRoutingBackend()
        ..error = const RoutingException(
          kind: RoutingErrorKind.network,
          message: 'connection refused',
        );
      await _openSheet(tester, harness: PlannerHarness(backend: backend));

      await _make(tester);

      expect(
        find.text('Loop search failed: connection refused'),
        findsOneWidget,
      );
    });

    testWidgets('without a position it asks for one', (tester) async {
      await _openSheet(tester, points: const <LatLng>[], withPosition: false);

      expect(_inSheet(find.text('From your position')), findsOneWidget);
      await _make(tester);

      expect(
        find.text('Turn on location or tap the map to set a start.'),
        findsOneWidget,
      );
    });

    testWidgets('falls back to the map centre and says so', (tester) async {
      final h = PlannerHarness();
      h.map.center = _second;
      await _openSheet(
        tester,
        points: const <LatLng>[],
        harness: h,
        withPosition: false,
      );

      await _make(tester);

      expect(_inSheet(find.text('From the map centre')), findsOneWidget);
      expect(
        _container(tester).read(smartLoopControllerProvider).request!.start,
        _second,
      );
    });
  });

  group('imperial', () {
    testWidgets('the distance slider runs in whole miles', (tester) async {
      await _openSheet(tester, extraOverrides: [imperialUnits]);

      // 30 km is the default; the nearest stop on the mile slider is 19.
      expect(_inSheet(find.text('19 mi')), findsOneWidget);

      await tester.drag(_inSheet(find.byType(Slider)), const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(_inSheet(find.text('3 mi')), findsOneWidget);

      await _make(tester);

      final state = _container(tester).read(smartLoopControllerProvider);
      expect(state.request!.targetM, closeTo(3 * 1609.344, 0.5));
    });
  });
}
