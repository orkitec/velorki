import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/library/presentation/library_screen.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/presentation/ride_detail_screen.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';

import '../../support/app.dart';
import '../planner/support/fakes.dart';
import '../recording/support/pump.dart';

List<TrackPoint> _track() => <TrackPoint>[
  for (var i = 0; i < 60; i++)
    TrackPoint(
      LatLng(48 + i * 0.0002, 11),
      ele: 500 + (i < 30 ? i * 2.0 : (60 - i) * 2.0),
      time: DateTime.utc(2026, 9, 12, 10, 0, i),
    ),
];

Future<void> _seedRide(RecordingHarness h) =>
    RideRepository(h.planner.db.ridesDao).finalizeRide(
      rideId: 'ride-1',
      name: 'Morning loop',
      points: _track(),
      startedAt: DateTime.utc(2026, 9, 12, 10),
      endedAt: DateTime.utc(2026, 9, 12, 10, 0, 59),
    );

/// [count] planned routes in the library.
Future<void> _seedRoutes(RecordingHarness h, int count) async {
  final repository = RouteRepository(h.planner.db.routesDao);
  for (var i = 0; i < count; i++) {
    await repository.savePlannedRoute(
      name: 'Route ${i + 1}',
      route: syntheticRoute(),
      waypoints: const [
        Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
        Waypoint(pos: LatLng(48.04, 11.04), kind: WaypointKind.end),
      ],
      options: const RoutingOptions(),
    );
  }
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(NavigationDestination, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a deep link to a ride opens its card on the Library tab', (
    tester,
  ) async {
    final h = RecordingHarness();
    await _seedRide(h);
    await pumpRecordingApp(
      tester,
      initialLocation: rideDetailLocation('ride-1'),
      harness: h,
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    expect(container.read(activeTabProvider), libraryRoute);
    expect(find.byType(RideDetailScreen), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('Morning loop'), findsOneWidget);
    expect(find.byType(DockingSheetShell), findsOneWidget);
    // The track is on the shared map, fitted above the card.
    expect(h.map.trackSegments, isNotEmpty);
    expect(h.map.fittedBounds, isNotNull);
    final height = MediaQuery.sizeOf(tester.element(find.byType(LibraryScreen)))
        .height;
    expect(
      h.map.fittedPadding!.bottom,
      greaterThan(sheetRestingExtent(height) * height),
    );

    // The arrow brings the list up in the same card, and the track goes.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(RideDetailScreen), findsNothing);
    expect(find.text(l10n.libraryRides), findsOneWidget);
    expect(h.map.trackSegments, isEmpty);
    expect(h.map.calls.last.method, isNot('fitBounds'));
    await unmountApp(tester);
  });

  testWidgets('the ride card takes its track off the shared map when the tab '
      'is left, and puts it back on return', (tester) async {
    final h = RecordingHarness();
    await _seedRide(h);
    await pumpRecordingApp(
      tester,
      initialLocation: rideDetailLocation('ride-1'),
      harness: h,
    );
    await tester.pumpAndSettle();
    expect(h.map.trackSegments, isNotEmpty);
    final fits = h.map.calls.where((c) => c.method == 'fitBounds').length;

    await _tapTab(tester, l10n.tabPlan);
    expect(h.map.trackSegments, isEmpty);
    final cleared = h.map.calls.where((c) => c.method == 'setTrackLine').last;
    expect(cleared.arguments.single, isEmpty);
    // The ride's places are off the map too.
    expect(h.map.pois, isEmpty);

    // Plan's own layers went on unhindered, its own handlers with them.
    expect(h.map.onTap, isNotNull);
    expect(h.map.onPoiTapped, isNotNull);

    await _tapTab(tester, l10n.tabLibrary);
    expect(find.byType(RideDetailScreen), findsOneWidget);
    expect(h.map.trackSegments, isNotEmpty);
    // Fitted again: the camera may have moved on the other tab.
    expect(h.map.calls.where((c) => c.method == 'fitBounds').length, fits + 1);
    await unmountApp(tester);
  });

  testWidgets('the ride card scrolls to its bottom at the resting height '
      'without moving the sheet', (tester) async {
    tester.view.physicalSize = const Size(3000, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    final h = RecordingHarness();
    await _seedRide(h);
    await pumpRecordingApp(
      tester,
      initialLocation: rideDetailLocation('ride-1'),
      harness: h,
    );
    await tester.pumpAndSettle();
    DockingSheetShell shell() =>
        tester.widget<DockingSheetShell>(find.byType(DockingSheetShell));
    final resting = shell().extent;

    // The export buttons are the last thing on the card, well below the
    // fold; scrolling the card's content reaches them with the card at rest,
    // and the header stays pinned above it.
    final export = find.widgetWithText(
      OutlinedButton,
      l10n.rideDetailExportGpx,
    );
    expect(tester.getRect(export).top, greaterThan(2000));
    await tester.scrollUntilVisible(
      export,
      300,
      scrollable: find
          .ancestor(
            of: find.text(l10n.statDistance.toUpperCase()).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(export).bottom, lessThan(2000));
    expect(shell().extent, closeTo(resting, 0.001));
    expect(find.text('Morning loop'), findsOneWidget);
    expect(tester.getRect(find.byType(BackButton)).top, greaterThan(0));
    await unmountApp(tester);
  });

  testWidgets('the system back on a card goes to the list', (tester) async {
    final h = RecordingHarness();
    await _seedRide(h);
    await pumpRecordingApp(
      tester,
      initialLocation: rideDetailLocation('ride-1'),
      harness: h,
    );
    await tester.pumpAndSettle();

    final router = GoRouter.of(tester.element(find.byType(LibraryScreen)));
    await router.routerDelegate.popRoute();
    await tester.pumpAndSettle();

    expect(find.byType(RideDetailScreen), findsNothing);
    expect(find.text(l10n.libraryRides), findsOneWidget);
    expect(router.state.matchedLocation, libraryRoute);
    await unmountApp(tester);
  });

  testWidgets('the Library card docks in the bar and rises again when the tab '
      'comes back', (tester) async {
    tester.view.physicalSize = const Size(3000, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpRecordingApp(tester, initialLocation: libraryRoute);
    await tester.pumpAndSettle();
    FloatingNavigationBar bar() => tester.widget<FloatingNavigationBar>(
      find.byType(FloatingNavigationBar),
    );
    DockingSheetShell shell() =>
        tester.widget<DockingSheetShell>(find.byType(DockingSheetShell));
    final resting = shell().extent;
    expect(bar().docked, isFalse);

    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, 1500),
    );
    await tester.pumpAndSettle();
    expect(bar().docked, isTrue);
    expect(shell().docked, 1);

    // Plan has its own sheet at rest: round bar there.
    await _tapTab(tester, l10n.tabPlan);
    expect(bar().docked, isFalse);

    // Back on the Library the docked card rises to its resting height.
    await _tapTab(tester, l10n.tabLibrary);
    expect(bar().docked, isFalse);
    expect(shell().extent, closeTo(resting, 0.001));
    await unmountApp(tester);
  });

  group('the list card\'s height on arrival', () {
    DockingSheetShell shell(WidgetTester tester) =>
        tester.widget<DockingSheetShell>(find.byType(DockingSheetShell));
    double maxExtent(WidgetTester tester) => tester
        .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
        .maxChildSize;

    testWidgets('three routes: the card arrives open to the top', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(3000, 6000);
      addTearDown(tester.view.resetPhysicalSize);
      final h = RecordingHarness();
      await _seedRoutes(h, 3);
      await pumpRecordingApp(tester, initialLocation: plannerRoute, harness: h);
      await tester.pumpAndSettle();
      await _tapTab(tester, l10n.tabLibrary);
      expect(shell(tester).extent, closeTo(maxExtent(tester), 0.001));
      expect(find.text('Route 3'), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('two routes: the card rests', (tester) async {
      tester.view.physicalSize = const Size(3000, 6000);
      addTearDown(tester.view.resetPhysicalSize);
      final h = RecordingHarness();
      await _seedRoutes(h, 2);
      await pumpRecordingApp(tester, initialLocation: plannerRoute, harness: h);
      await tester.pumpAndSettle();
      await _tapTab(tester, l10n.tabLibrary);
      expect(shell(tester).extent, closeTo(sheetRestingExtent(2000), 0.001));
      await unmountApp(tester);
    });

    testWidgets('dragged by the rider, the card comes back to where they '
        'left it', (tester) async {
      tester.view.physicalSize = const Size(3000, 6000);
      addTearDown(tester.view.resetPhysicalSize);
      final h = RecordingHarness();
      await _seedRoutes(h, 3);
      await pumpRecordingApp(tester, initialLocation: plannerRoute, harness: h);
      await tester.pumpAndSettle();
      await _tapTab(tester, l10n.tabLibrary);
      expect(shell(tester).extent, closeTo(maxExtent(tester), 0.001));

      // Down from the top, short of docking.
      await tester.dragFrom(
        tester.getCenter(find.byType(SheetHandle)),
        const Offset(0, 900),
      );
      await tester.pumpAndSettle();
      final left = shell(tester).extent;
      expect(left, lessThan(maxExtent(tester) - 0.1));
      expect(left, greaterThan(0.2));

      await _tapTab(tester, l10n.tabPlan);
      await _tapTab(tester, l10n.tabLibrary);
      expect(shell(tester).extent, closeTo(left, 0.01));
      // Switching the segment moves nothing either.
      await tester.tap(find.text(l10n.libraryRides));
      await tester.pumpAndSettle();
      expect(shell(tester).extent, closeTo(left, 0.01));
      await unmountApp(tester);
    });

    testWidgets('a deep link to a route card rests, whatever the list '
        'holds', (tester) async {
      tester.view.physicalSize = const Size(3000, 6000);
      addTearDown(tester.view.resetPhysicalSize);
      final h = RecordingHarness();
      await _seedRoutes(h, 3);
      final routes = await h.planner.db.routesDao.allRoutes();
      await pumpRecordingApp(
        tester,
        initialLocation: routeDetailLocation(routes.first.id),
        harness: h,
      );
      await tester.pumpAndSettle();
      expect(shell(tester).extent, closeTo(sheetRestingExtent(2000), 0.001));
      await unmountApp(tester);
    });
  });

  testWidgets('a ride card opened from the list on a fresh start draws its '
      'track', (tester) async {
    tester.view.physicalSize = const Size(3000, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    final h = RecordingHarness();
    await _seedRide(h);
    await pumpRecordingApp(tester, initialLocation: plannerRoute, harness: h);
    await tester.pumpAndSettle();
    await _tapTab(tester, l10n.tabLibrary);
    await tester.tap(find.text(l10n.libraryRides));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morning loop'));
    await tester.pumpAndSettle();
    expect(find.byType(RideDetailScreen), findsOneWidget);
    expect(h.map.trackSegments, isNotEmpty);
    expect(
      h.map.trackSegments.expand((s) => s.points).length,
      greaterThanOrEqualTo(60),
    );
    await unmountApp(tester);
  });
}
