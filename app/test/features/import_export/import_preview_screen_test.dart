import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/import_export/data/track_decoder.dart';
import 'package:velorki/features/import_export/domain/imported_track.dart';
import 'package:velorki/features/import_export/presentation/import_file_action.dart';
import 'package:velorki/features/import_export/presentation/import_preview_screen.dart';
import 'package:velorki/features/planner/application/planner_map_binding.dart';
import 'package:velorki/features/map/domain/map_controller.dart';

import '../../support/app.dart';
import '../../support/format.dart';
import '../planner/support/pump.dart';
import 'support/fixtures.dart';

ImportCandidate _candidate(String fixture, {String? sourceHint}) =>
    decodeCandidate(
      fixtureBytes(fixture),
      fileName: fixture,
      sourceHint: sourceHint,
    );

void main() {
  testWidgets('a route with a cue sheet lists it; a line takes the map '
      'there, a marker tap selects the line', (tester) async {
    final candidate = _candidate('ridewithgps.gpx');
    final h = await pumpScreen(
      tester,
      ImportPreviewScreen(candidate: candidate),
    );
    await tester.pumpAndSettle();

    // The cue sheet is the third page under the map: the file, its
    // profile, then the sheet.
    expect(find.text(l10n.cueSheetTitle.toUpperCase()), findsNothing);
    await tester.fling(
      find.text(l10n.importSummary('GPX', 3)),
      const Offset(-300, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.elevationTitle.toUpperCase()), findsOneWidget);
    await tester.fling(
      find.text(l10n.elevationTitle.toUpperCase()),
      const Offset(-300, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.cueSheetTitle.toUpperCase()), findsOneWidget);
    expect(find.text('Turn left onto Widenmayerstraße'), findsOneWidget);
    expect(find.text('Trinkwasser'), findsOneWidget);
    // The file's own "Start of route" cue is the start line, once.
    expect(find.text(l10n.cueSheetStart), findsOneWidget);
    expect(find.text('Start of route'), findsNothing);
    expect(h.map.turnMarkers, hasLength(2));
    expect(h.map.pois, hasLength(1));
    expect(h.map.waypoints.map((w) => w.kind), [
      MapWaypointKind.start,
      MapWaypointKind.end,
    ]);

    await tester.tap(find.text('Turn left onto Widenmayerstraße'));
    await tester.pumpAndSettle();
    final moves = h.map.calls.where((c) => c.method == 'moveTo').toList();
    expect(moves, hasLength(1));
    expect(
      moves.single.arguments[1],
      isNull,
      reason: 'the zoom is the rider\'s',
    );
    // Selected, the line opens with the plain manoeuvre under the words.
    expect(find.text(l10n.navTurnLeft), findsOneWidget);

    // The other way round: a tap on the water fountain's marker, from the
    // profile page, brings the cue sheet back up with the line selected.
    await tester.fling(
      find.text(l10n.cueSheetTitle.toUpperCase()),
      const Offset(300, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.cueSheetTitle.toUpperCase()), findsNothing);
    h.map.onPoiTapped!(0);
    await tester.pumpAndSettle();
    expect(find.text(l10n.cueSheetTitle.toUpperCase()), findsOneWidget);
    expect(h.map.calls.where((c) => c.method == 'moveTo'), hasLength(2));
    expect(
      find.text(l10n.navTurnLeft),
      findsNothing,
      reason: 'selection moved',
    );

    await unmountApp(tester);
  });

  testWidgets('a route file is previewed and drawn on the map', (tester) async {
    final candidate = _candidate('route.gpx');
    final h = await pumpScreen(
      tester,
      ImportPreviewScreen(candidate: candidate),
    );
    await tester.pumpAndSettle();

    // Name, format and point count.
    expect(
      tester
          .widget<TextField>(
            find.ancestor(
              of: find.text('Starnberger See loop'),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      'Starnberger See loop',
    );
    expect(find.text(l10n.importSummary('GPX', 4)), findsOneWidget);
    expect(find.text(l10n.importNoTime), findsOneWidget);

    // The preview is drawn through the map contract, bounds included.
    expect(h.map.lines[mainRouteLineId], hasLength(4));
    // The file's one waypoint is on the map as a point of interest.
    expect(h.map.pois, hasLength(1));
    expect(h.map.fittedBounds, isNotNull);
    expect(h.map.fittedBounds!.south, closeTo(47.998, 1e-9));

    // Route is preselected because there are no timestamps.
    final toggle = tester.widget<SegmentedButton<ImportKind>>(
      find.byType(SegmentedButton<ImportKind>),
    );
    expect(toggle.selected, {ImportKind.route});
    await unmountApp(tester);
  });

  testWidgets('a timed file preselects Ride and shows the time span', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      ImportPreviewScreen(candidate: _candidate('komoot.gpx')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.importSummary('GPX', 3)), findsOneWidget);
    expect(
      find.textContaining(
        testDate(DateTime.utc(2024, 6, 12, 16, 4, 41).toLocal()),
      ),
      findsOneWidget,
    );
    final toggle = tester.widget<SegmentedButton<ImportKind>>(
      find.byType(SegmentedButton<ImportKind>),
    );
    expect(toggle.selected, {ImportKind.ride});
    await unmountApp(tester);
  });

  testWidgets('saving as a route writes it and opens the detail screen', (
    tester,
  ) async {
    final h = PlannerHarness();
    await pumpApp(tester, harness: h);
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go(importRoute, extra: _candidate('route.gpx'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, l10n.commonSave));
    await tester.pumpAndSettle();

    final rows = await h.db.routesDao.allRoutes();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Starnberger See loop');
    expect(rows.single.source, RouteSource.importedGpx);

    // It landed on the route's detail screen.
    expect(find.widgetWithText(AppBar, 'Starnberger See loop'), findsOneWidget);
    expect(
      find.text(l10n.importSavedRoute('Starnberger See loop')),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets('the toggle overrides the suggestion and writes a ride', (
    tester,
  ) async {
    final h = PlannerHarness();
    await pumpApp(tester, harness: h);
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go(importRoute, extra: _candidate('route.gpx'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.importKindRide));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonSave));
    await tester.pumpAndSettle();

    expect(await h.db.routesDao.allRoutes(), isEmpty);
    final rides = await h.db.ridesDao.allRides();
    expect(rides, hasLength(1));
    expect(rides.single.name, 'Starnberger See loop');
    // It landed on the ride's detail screen, under the Record tab.
    expect(find.widgetWithText(AppBar, 'Starnberger See loop'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('an edited name is what gets saved', (tester) async {
    final h = PlannerHarness();
    await pumpApp(tester, harness: h);
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go(importRoute, extra: _candidate('route.gpx'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Sunday tour');
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonSave));
    await tester.pumpAndSettle();

    expect((await h.db.routesDao.allRoutes()).single.name, 'Sunday tour');
    await unmountApp(tester);
  });

  testWidgets('/import without a file says so instead of crashing', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: importRoute);
    await tester.pumpAndSettle();

    expect(find.text(l10n.importNothing), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('the library action picks a file and opens the preview', (
    tester,
  ) async {
    final h = PlannerHarness();
    await pumpApp(
      tester,
      harness: h,
      extraOverrides: [
        trackFilePickerProvider.overrideWithValue(
          () async =>
              PickedFile(name: 'route.gpx', bytes: fixtureBytes('route.gpx')),
        ),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.libraryImportFile));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Import'), findsOneWidget);
    expect(find.text(l10n.importSummary('GPX', 4)), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('picking something that is not a track reports it', (
    tester,
  ) async {
    await pumpApp(
      tester,
      extraOverrides: [
        trackFilePickerProvider.overrideWithValue(
          () async => PickedFile(
            name: 'holiday.jpg',
            bytes: Uint8List.fromList(List<int>.filled(64, 0x42)),
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.libraryImportFile));
    await tester.pumpAndSettle();

    expect(find.text(l10n.importFailedUnknown), findsOneWidget);
    expect(find.widgetWithText(AppBar, l10n.tabLibrary), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('cancelling the picker does nothing', (tester) async {
    await pumpApp(
      tester,
      extraOverrides: [
        trackFilePickerProvider.overrideWithValue(() async => null),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.libraryImportFile));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, l10n.tabLibrary), findsOneWidget);
    await unmountApp(tester);
  });
}
