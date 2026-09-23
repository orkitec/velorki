import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/library/presentation/library_screen.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/domain/follow_choice.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/presentation/follow_route_picker.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../planner/support/fakes.dart' show syntheticRoute;
import 'support/pump.dart';

const LatLng _a = LatLng(48.0, 11.0);
const LatLng _b = LatLng(48.04, 11.04);

Future<SavedRoute> _saveRoute(RecordingHarness h) =>
    RouteRepository(
      h.planner.db.routesDao,
      clock: () => DateTime.utc(2026, 9, 12, 10),
    ).savePlannedRoute(
      name: 'Isar loop',
      route: syntheticRoute(),
      waypoints: const [
        Waypoint(pos: _a, kind: WaypointKind.start),
        Waypoint(pos: _b, kind: WaypointKind.end),
      ],
      options: const RoutingOptions(),
    );

RecordingSnapshot _snapshot() => RecordingSnapshot(
  rideId: 'ride-1',
  status: RecordingStatus.active,
  startedAt: DateTime.utc(2026, 9, 12, 10),
  autoPaused: false,
  distanceM: 100,
  elapsed: const Duration(minutes: 1),
  moving: const Duration(minutes: 1),
  speedMps: 5,
  avgSpeedMps: 5,
  ascentM: 0,
  descentM: 0,
  lastPosition: _a,
  accuracyM: 4,
  pointCount: 2,
  newPoints: const [_a],
);

/// The app's container, found from the app rather than the bar: the bar
/// leaves while a ride is recorded on the Record tab.
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

RecordingUiState _recording(WidgetTester tester) =>
    _container(tester).read(recordingControllerProvider);

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(NavigationDestination, label));
  await tester.pumpAndSettle();
}

/// Two points on the Plan tab, routed.
Future<void> _plan(WidgetTester tester) async {
  final planner = _container(tester).read(plannerControllerProvider.notifier);
  planner.addWaypoint(_a);
  planner.addWaypoint(_b);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String label) async {
  await tester.tap(find.byType(FollowRouteField));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(FollowRoutePicker),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with a plan the picker offers no route, the plan and the '
      'saved routes; no route records without one, the plan follows it '
      'again', (tester) async {
    final h = RecordingHarness();
    await _saveRoute(h);
    await pumpRecordingApp(tester, harness: h);
    await tester.pumpAndSettle();
    await _plan(tester);
    // The plan is followed by default: its line is on the map.
    expect(_recording(tester).follow, FollowChoice.plan);
    expect(h.map.lines[followedRouteLineId], isNotNull);
    expect(_container(tester).read(guidedRouteProvider), isNotNull);

    await tester.tap(find.byType(FollowRouteField));
    await tester.pumpAndSettle();
    final picker = find.byType(FollowRoutePicker);
    final titles = tester
        .widgetList<ListTile>(
          find.descendant(of: picker, matching: find.byType(ListTile)),
        )
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(titles.take(2), [
      l10n.recordingFollowNone,
      l10n.recordingFollowPlan,
    ]);
    expect(
      find.descendant(of: picker, matching: find.text('Isar loop')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ListTile>(
            find.descendant(
              of: picker,
              matching: find.widgetWithText(ListTile, l10n.recordingFollowPlan),
            ),
          )
          .selected,
      isTrue,
    );

    // No route, with the plan still there: nothing to follow, nothing drawn.
    await tester.tap(
      find.descendant(
        of: picker,
        matching: find.text(l10n.recordingFollowNone),
      ),
    );
    await tester.pumpAndSettle();
    expect(_recording(tester).follow, FollowChoice.none);
    expect(_recording(tester).followChosen, isTrue);
    expect(h.map.lines[followedRouteLineId], isNull);
    expect(_container(tester).read(guidedRouteProvider), isNull);
    expect(find.text(l10n.recordingFollowNone), findsOneWidget);

    // The plan again: followed, drawn, guided.
    await _pick(tester, l10n.recordingFollowPlan);
    expect(_recording(tester).follow, FollowChoice.plan);
    expect(h.map.lines[followedRouteLineId], isNotNull);
    expect(
      _container(tester).read(guidedRouteProvider)?.key,
      startsWith('plan:'),
    );

    // And no route once more, into a ride: started without a route, no
    // line under the track, nothing to guide.
    await _pick(tester, l10n.recordingFollowNone);
    await tester.tap(find.text(l10n.recordingStart));
    await tester.pumpAndSettle();
    expect(h.service.calls, contains('start(null)'));
    h.service.emit(_snapshot());
    await tester.pumpAndSettle();
    expect(_recording(tester).isRecording, isTrue);
    expect(h.map.lines[followedRouteLineId], isNull);
    expect(_container(tester).read(guidedRouteProvider), isNull);
    await unmountApp(tester);
  });

  testWidgets('arriving from a route card in the Library proposes that '
      'route, arriving from a plan proposes the plan', (tester) async {
    final h = RecordingHarness();
    final saved = await _saveRoute(h);
    await pumpRecordingApp(
      tester,
      harness: h,
      initialLocation: routeDetailLocation(saved.id),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);

    await _tapTab(tester, l10n.tabRecord);
    expect(_recording(tester).follow, FollowSaved(saved.id));
    expect(_recording(tester).followChosen, isFalse);
    expect(find.textContaining('Isar loop'), findsOneWidget);

    // Over to Plan, a plan made there, and back: the plan is proposed.
    await _tapTab(tester, l10n.tabPlan);
    await _plan(tester);
    await _tapTab(tester, l10n.tabRecord);
    expect(_recording(tester).follow, FollowChoice.plan);
    expect(find.text(l10n.recordingFollowPlan), findsOneWidget);

    // The Library's list, not a card: nothing to propose, the plan stays.
    await _tapTab(tester, l10n.tabLibrary);
    await tester.tap(find.byType(BackButton).hitTestable().first);
    await tester.pumpAndSettle();
    await _tapTab(tester, l10n.tabRecord);
    expect(_recording(tester).follow, FollowChoice.plan);
    await unmountApp(tester);
  });

  testWidgets('a pick in the picker holds against every later proposal', (
    tester,
  ) async {
    final h = RecordingHarness();
    final saved = await _saveRoute(h);
    await pumpRecordingApp(tester, harness: h);
    await tester.pumpAndSettle();
    await _plan(tester);
    await _pick(tester, l10n.recordingFollowNone);
    expect(_recording(tester).follow, FollowChoice.none);

    await _tapTab(tester, l10n.tabPlan);
    await _tapTab(tester, l10n.tabRecord);
    expect(_recording(tester).follow, FollowChoice.none);

    await _tapTab(tester, l10n.tabLibrary);
    await tester.tap(find.text('Isar loop'));
    await tester.pumpAndSettle();
    await _tapTab(tester, l10n.tabRecord);
    expect(_recording(tester).follow, FollowChoice.none);
    expect(_recording(tester).followedRouteId, isNot(saved.id));
    await unmountApp(tester);
  });

  testWidgets('while a ride runs, coming back from a route card changes '
      'nothing', (tester) async {
    final h = RecordingHarness();
    final saved = await _saveRoute(h);
    await pumpRecordingApp(tester, harness: h);
    await tester.pumpAndSettle();
    await _plan(tester);
    await tester.tap(find.text(l10n.recordingStart));
    await tester.pumpAndSettle();
    h.service.emit(_snapshot());
    await tester.pumpAndSettle();
    expect(_recording(tester).isRecording, isTrue);
    expect(_recording(tester).follow, FollowChoice.plan);

    // The bar is away during the ride; the route card is reached as the
    // system back gesture or a link would reach it, through the router.
    final router = GoRouter.of(tester.element(find.byType(RecordingScreen)));
    router.go(routeDetailLocation(saved.id));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);
    router.go(recordingRoute);
    await tester.pumpAndSettle();
    expect(_recording(tester).follow, FollowChoice.plan);
    expect(_recording(tester).followedRouteId, isNot(saved.id));
    expect(find.byType(RecordingScreen), findsOneWidget);
    await unmountApp(tester);
  });
}
