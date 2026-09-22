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

import '../../support/app.dart';
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
    expect(h.map.onPoiTapped, isNull);

    // Plan's own layers went on unhindered.
    expect(h.map.onTap, isNotNull);

    await _tapTab(tester, l10n.tabLibrary);
    expect(find.byType(RideDetailScreen), findsOneWidget);
    expect(h.map.trackSegments, isNotEmpty);
    // Fitted again: the camera may have moved on the other tab.
    expect(h.map.calls.where((c) => c.method == 'fitBounds').length, fits + 1);
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
}
