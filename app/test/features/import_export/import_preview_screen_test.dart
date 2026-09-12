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

import '../planner/support/pump.dart';
import 'support/fixtures.dart';

ImportCandidate _candidate(String fixture, {String? sourceHint}) =>
    decodeCandidate(
      fixtureBytes(fixture),
      fileName: fixture,
      sourceHint: sourceHint,
    );

void main() {
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
    expect(find.text('GPX · 4 points'), findsOneWidget);
    expect(find.text('The file carries no timestamps.'), findsOneWidget);

    // The preview is drawn through the map contract, bounds included.
    expect(h.map.lines[mainRouteLineId], hasLength(4));
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

    expect(find.text('GPX · 3 points'), findsOneWidget);
    expect(find.textContaining('Jun 12, 2024'), findsOneWidget);
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

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final rows = await h.db.routesDao.allRoutes();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Starnberger See loop');
    expect(rows.single.source, RouteSource.importedGpx);

    // It landed on the route's detail screen.
    expect(find.widgetWithText(AppBar, 'Starnberger See loop'), findsOneWidget);
    expect(
      find.text('Starnberger See loop added to the library'),
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

    await tester.tap(find.text('Ride'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
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
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect((await h.db.routesDao.allRoutes()).single.name, 'Sunday tour');
    await unmountApp(tester);
  });

  testWidgets('/import without a file says so instead of crashing', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: importRoute);
    await tester.pumpAndSettle();

    expect(find.text('There is nothing to import.'), findsOneWidget);
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

    await tester.tap(find.byTooltip('Import file'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Import'), findsOneWidget);
    expect(find.text('GPX · 4 points'), findsOneWidget);
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

    await tester.tap(find.byTooltip('Import file'));
    await tester.pumpAndSettle();

    expect(find.text('That is not a GPX or FIT file.'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
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

    await tester.tap(find.byTooltip('Import file'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
    await unmountApp(tester);
  });
}
