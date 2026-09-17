import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/library/data/library_section.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/format.dart';
import '../planner/support/fakes.dart' show syntheticRoute;
import '../recording/support/pump.dart';

const List<Waypoint> _waypoints = [
  Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
  Waypoint(pos: LatLng(48.04, 11.04), kind: WaypointKind.end),
];

List<TrackPoint> _track() => <TrackPoint>[
  for (var i = 0; i < 60; i++)
    TrackPoint(
      LatLng(48 + i * 0.0002, 11),
      ele: 500 + (i < 30 ? i * 2.0 : (60 - i) * 2.0),
      time: DateTime.utc(2026, 9, 12, 10, 0, i),
    ),
];

Future<void> _seedRoute(RecordingHarness h) =>
    RouteRepository(
      h.planner.db.routesDao,
      clock: () => DateTime.utc(2026, 9, 12, 10),
    ).savePlannedRoute(
      name: 'Isar loop',
      route: syntheticRoute(),
      waypoints: _waypoints,
      options: const RoutingOptions(),
    );

Future<void> _seedRide(RecordingHarness h) =>
    RideRepository(h.planner.db.ridesDao).finalizeRide(
      rideId: 'ride-1',
      name: 'Morning loop',
      points: _track(),
      startedAt: DateTime.utc(2026, 9, 12, 10),
      endedAt: DateTime.utc(2026, 9, 12, 10, 0, 59),
    );

void main() {
  testWidgets('the library offers both sections and starts on routes', (
    tester,
  ) async {
    final h = RecordingHarness();
    await _seedRoute(h);
    await _seedRide(h);
    await pumpRecordingApp(tester, initialLocation: libraryRoute, harness: h);
    await tester.pumpAndSettle();

    final switcher = find.byType(SegmentedButton<LibrarySection>);
    expect(switcher, findsOneWidget);
    expect(
      find.descendant(of: switcher, matching: find.text(l10n.libraryRoutes)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: switcher, matching: find.text(l10n.libraryRides)),
      findsOneWidget,
    );

    // Nothing stored yet, so the routes half shows and the rides stay away.
    expect(find.text('Isar loop'), findsOneWidget);
    expect(find.text('Morning loop'), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('the routes section keeps its list, import buttons and menu', (
    tester,
  ) async {
    final h = RecordingHarness();
    await _seedRoute(h);
    await pumpRecordingApp(tester, initialLocation: libraryRoute, harness: h);
    await tester.pumpAndSettle();

    expect(find.text('Isar loop'), findsOneWidget);
    expect(
      find.text(
        l10n.libraryRouteSubtitle(
          testDate(DateTime.utc(2026, 9, 12, 10).toLocal()),
          testDistance(10000),
          testHeight(120),
        ),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    // The file import stays in the app bar next to the new switch. Its
    // sibling, the import-from-service menu, hides itself when no API URL is
    // configured, which is the case in tests.
    expect(find.byIcon(Icons.file_open_outlined), findsOneWidget);

    await tester.tap(find.text('Isar loop'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Isar loop'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('switching to rides lists every ride and remembers the choice', (
    tester,
  ) async {
    final h = RecordingHarness();
    await _seedRoute(h);
    await _seedRide(h);
    await pumpRecordingApp(tester, initialLocation: libraryRoute, harness: h);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.libraryRides));
    await tester.pumpAndSettle();

    expect(find.text('Morning loop'), findsOneWidget);
    expect(find.text(l10n.libraryRidesCount(1).toUpperCase()), findsOneWidget);
    expect(find.text('Isar loop'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library.section'), 'rides');

    // And back again, which forgets the choice rather than storing the
    // default.
    await tester.tap(find.text(l10n.libraryRoutes));
    await tester.pumpAndSettle();

    expect(find.text('Isar loop'), findsOneWidget);
    expect(find.text('Morning loop'), findsNothing);
    expect(prefs.getString('library.section'), isNull);
    await unmountApp(tester);
  });

  testWidgets('the stored choice is restored on the next start', (
    tester,
  ) async {
    final h = RecordingHarness();
    await _seedRoute(h);
    await _seedRide(h);
    await pumpRecordingApp(
      tester,
      initialLocation: libraryRoute,
      harness: h,
      preferences: const {'library.section': 'rides'},
    );
    await tester.pumpAndSettle();

    expect(find.text('Morning loop'), findsOneWidget);
    expect(find.text('Isar loop'), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('an empty rides section says so', (tester) async {
    await pumpRecordingApp(
      tester,
      initialLocation: libraryRoute,
      preferences: const {'library.section': 'rides'},
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.recordingNoRides), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('tapping a ride opens its detail screen', (tester) async {
    final h = RecordingHarness();
    await _seedRide(h);
    await pumpRecordingApp(
      tester,
      initialLocation: libraryRoute,
      harness: h,
      preferences: const {'library.section': 'rides'},
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Morning loop'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.statDistance.toUpperCase()), findsOneWidget);
    // Twice: the stat tile, and the column of the splits table.
    expect(find.text(l10n.statMovingTime.toUpperCase()), findsWidgets);
    expect(find.text(l10n.rideDetailExportGpx), findsWidgets);
    await unmountApp(tester);
  });
}
