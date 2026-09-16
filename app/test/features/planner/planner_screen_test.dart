import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';

import 'package:velorki/features/planner/presentation/elevation_profile_chart.dart';
import 'package:velorki/features/map/presentation/map_chrome.dart';
import 'package:velorki/features/planner/presentation/planner_map_host.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/planner/presentation/surface_stats_bar.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../assistant/support/fakes.dart';
import 'support/fakes.dart';
import 'support/pump.dart';

const LatLng _a = LatLng(48.0, 11.0);
const LatLng _b = LatLng(48.2, 11.2);

Future<void> _plotRoute(WidgetTester tester, PlannerHarness h) async {
  h.map.onTap!(_a);
  h.map.onTap!(_b);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the empty state explains the first gesture', (tester) async {
    await pumpScreen(tester, const PlannerScreen());

    expect(find.text('Tap the map to set a start.'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Save'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('Save stays above the fold of the sheet on a 1080x2400 screen', (
    tester,
  ) async {
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      surfaceSize: const Size(1080, 2400),
    );
    await _plotRoute(tester, h);

    final save = find.widgetWithText(FilledButton, 'Save');
    final rect = tester.getRect(save);
    expect(rect.bottom, lessThanOrEqualTo(2400));
    expect(rect.top, greaterThanOrEqualTo(0));
    // Inside the sheet, which starts at 66 % of the height, and hittable.
    expect(rect.top, greaterThan(2400 * 0.6));
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Save route'), findsOneWidget);
  });

  testWidgets('tapping the map twice plots a route with stats', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());

    await _plotRoute(tester, h);

    expect(find.text('10.0 km'), findsOneWidget);
    expect(find.text('120 m'), findsOneWidget);
    expect(find.text('80 m'), findsOneWidget);
    // 10 km at the trekking profile's 18 km/h.
    expect(find.text('33 min'), findsOneWidget);
    expect(find.byType(ElevationProfileChart), findsOneWidget);
    expect(find.byType(SurfaceStatsBar), findsOneWidget);
    expect(find.textContaining('Paved 60%'), findsOneWidget);
    expect(find.textContaining('Unpaved 40%'), findsOneWidget);
  });

  testWidgets('switching the profile re-routes and changes the estimate', (
    tester,
  ) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Road'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.backend.queries.last.profile, 'fastbike');
    // 10 km at 25 km/h.
    expect(find.text('24 min'), findsOneWidget);
  });

  testWidgets('a routing failure is shown as a snack bar', (tester) async {
    final backend = FakeRoutingBackend()
      ..error = const RoutingException(
        kind: RoutingErrorKind.noRoute,
        message: 'position not mapped',
      );
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: PlannerHarness(backend: backend),
    );

    await _plotRoute(tester, h);

    // Once in the sheet, once as the snack bar.
    expect(find.text('Routing failed: position not mapped'), findsWidgets);
  });

  testWidgets('without a routing server the planner points at Settings', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: PlannerHarness(withRoutingBackend: false),
    );

    expect(
      find.text(
        'No routing server configured, set one in Settings → '
        'Advanced.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('undo, reverse and clear drive the plan', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);

    await tester.tap(find.widgetWithText(LabeledIconButton, 'Reverse'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(h.backend.queries.last.points, [_b, _a]);

    await tester.tap(find.widgetWithText(LabeledIconButton, 'Undo'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(h.backend.queries.last.points, [_a, _b]);

    await tester.tap(find.widgetWithText(LabeledIconButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Tap the map to set a start.'), findsOneWidget);
    expect(h.map.lines, isEmpty);
  });

  testWidgets('alternatives are fetched on request and selectable', (
    tester,
  ) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    h.backend.byAlternative[1] = syntheticRoute(lengthM: 11000);
    await _plotRoute(tester, h);

    await tester.tap(find.widgetWithText(LabeledIconButton, 'Variants'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Main'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Alt 1'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Alt 1'));
    await tester.pumpAndSettle();

    expect(find.text('11.0 km'), findsOneWidget);
  });

  testWidgets('saving asks for a name and writes a library row', (
    tester,
  ) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Save route'), findsOneWidget);
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<TextField>(field).controller!.text,
      startsWith('Route '),
    );

    await tester.enterText(field, 'Isar loop');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Save'),
      ),
    );
    await tester.pumpAndSettle();

    final rows = await h.db.routesDao.allRoutes();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Isar loop');
    expect(rows.single.distanceM, 10000);
    expect(find.text('Route saved'), findsOneWidget);
  });

  testWidgets('a searched place becomes the start of an empty plan', (
    tester,
  ) async {
    final h = await pumpScreen(tester, const PlannerScreen());

    await tester.enterText(find.byType(TextField).first, 'munich');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Munich'), findsWidgets);
    await tester.tap(find.text('Bavaria, Germany'));
    await tester.pumpAndSettle();

    expect(h.map.movedTo, const LatLng(48.1374, 11.5755));
    expect(find.text('Start here'), findsOneWidget);
    // The found place is pinned until the rider decides what it is.
    expect(h.map.searchPin, const LatLng(48.1374, 11.5755));

    await tester.tap(find.text('Start here'));
    await tester.pumpAndSettle();

    expect(h.map.waypoints.single.position, const LatLng(48.1374, 11.5755));
    expect(find.text('Start here'), findsNothing);
    expect(h.map.searchPin, isNull, reason: 'it is a waypoint now');
  });

  testWidgets('tapping a marker offers to remove the point', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);
    expect(h.map.waypoints, hasLength(2));

    h.map.onWaypointTapped!(1);
    await tester.pumpAndSettle();

    expect(find.text('Point 2'), findsOneWidget);
    await tester.tap(find.text('Remove point'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.map.waypoints, hasLength(1));
    expect(find.text('Remove point'), findsNothing);
  });

  testWidgets('the sheet has one resting height without variants', (
    tester,
  ) async {
    await pumpScreen(tester, const PlannerScreen());
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    // Two resting heights a chip row apart made a pull down from the top
    // and a pull up from the handle settle at different places.
    expect(sheet.snapSizes, hasLength(1));
    expect(sheet.snapSizes!.single, sheet.initialChildSize);
  });

  testWidgets('a point can be visited earlier or later from its sheet', (
    tester,
  ) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);
    final first = h.map.waypoints[0].position;
    final second = h.map.waypoints[1].position;

    h.map.onWaypointTapped!(1);
    await tester.pumpAndSettle();
    // The last point cannot go later.
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Visit later'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Visit earlier'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.map.waypoints[0].position, second);
    expect(h.map.waypoints[1].position, first);
  });

  testWidgets('a searched place is the destination from my position', (
    tester,
  ) async {
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      extraOverrides: [
        locationPermissionGatewayProvider.overrideWithValue(
          const GrantedLocationPermission(),
        ),
        positionSourceProvider.overrideWithValue(
          const FixedPositionSource(LatLng(48.0, 11.0)),
        ),
      ],
    );

    await tester.enterText(find.byType(TextField).first, 'munich');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bavaria, Germany'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('From my position'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.map.waypoints, hasLength(2));
    expect(h.map.waypoints.first.position, const LatLng(48.0, 11.0));
    expect(h.map.waypoints.last.position, const LatLng(48.1374, 11.5755));
    expect(h.map.waypoints.last.label, 'Munich');
    expect(find.text('From my position'), findsNothing);
  });

  testWidgets('clearing the search forgets the searched place', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());

    await tester.enterText(find.byType(TextField).first, 'munich');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bavaria, Germany'));
    await tester.pumpAndSettle();
    expect(h.map.searchPin, isNotNull);
    expect(find.text('From my position'), findsOneWidget);

    // The field's own clear button drops the place and its two actions.
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(h.map.searchPin, isNull);
    expect(find.text('From my position'), findsNothing);
    expect(find.text('Start here'), findsNothing);

    // Typing over a picked place forgets it too.
    await tester.enterText(find.byType(TextField).first, 'munich');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bavaria, Germany'));
    await tester.pumpAndSettle();
    expect(h.map.searchPin, isNotNull);
    await tester.enterText(find.byType(TextField).first, 'munic');
    await tester.pump();
    expect(h.map.searchPin, isNull);
  });

  testWidgets('the control column moves down under the place actions', (
    tester,
  ) async {
    await pumpScreen(tester, const PlannerScreen());
    MapChromeInsets chrome() =>
        tester.widget<MapChromeInsets>(find.byType(MapChromeInsets).first);
    final before = chrome().controlsTop!;

    await tester.enterText(find.byType(TextField).first, 'munich');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bavaria, Germany'));
    await tester.pumpAndSettle();

    // The two action buttons add a row above the chips; the column must
    // not sit on the chips because of it.
    expect(chrome().controlsTop!, greaterThan(before + 30));

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(chrome().controlsTop!, closeTo(before, 0.5));
  });

  testWidgets('the sheet parks under the keyboard while searching', (
    tester,
  ) async {
    await pumpScreen(tester, const PlannerScreen());
    final sheet = find.byType(DraggableScrollableSheet);
    final headline = find.text('Tap the map to set a start.');
    expect(headline, findsOneWidget);
    final screenHeight = tester.getSize(find.byType(PlannerScreen)).height;
    final restingTop = tester.getTopLeft(headline).dy;
    expect(restingTop, lessThan(screenHeight * 0.7));

    // Focusing the field drops the sheet to its handle before the keyboard
    // shows: the headline is off the bottom edge. The map keeps its full
    // size underneath.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
    expect(tester.getTopLeft(headline).dy, greaterThan(screenHeight * 0.9));
    expect(
      tester.getSize(find.byType(PlannerMapHost)).height,
      closeTo(screenHeight, 0.5),
    );

    // The keyboard comes and goes; the map never shrinks.
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(PlannerMapHost)).height,
      closeTo(screenHeight, 0.5),
    );
    expect(tester.getTopLeft(headline).dy, greaterThan(screenHeight * 0.9));

    // Once the keyboard is gone the sheet is back where it was.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(headline).dy, closeTo(restingTop, 0.5));

    // The field kept its focus; the keyboard coming back parks it again.
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(headline).dy, greaterThan(screenHeight * 0.9));
  });

  testWidgets('a searched place is appended once a plan exists', (
    tester,
  ) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);

    await tester.enterText(find.byType(TextField).first, 'munich');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bavaria, Germany'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.map.waypoints, hasLength(3));
    expect(h.map.waypoints.last.position, const LatLng(48.1374, 11.5755));
    expect(h.map.waypoints.last.label, 'Munich');
  });

  // Last on purpose: it swaps the test font for the real one, which every
  // test after it in this file would then lay out with.
  testWidgets('the five profile chips span the search field', (tester) async {
    // The stand-in font of a widget test gives every glyph a full em, so the
    // chips would never fit on any width. Measure with the font the app ships.
    final manrope = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope-Bold.ttf'));
    await manrope.load();

    for (final width in <double>[360.0, 390.0]) {
      await pumpScreen(
        tester,
        const PlannerScreen(),
        surfaceSize: Size(width, 780),
      );

      for (final label in ['Touring', 'Road', 'Gravel', 'MTB', 'Direct']) {
        expect(
          find.widgetWithText(ChoiceChip, label),
          findsOneWidget,
          reason: 'at $width dp',
        );
      }

      // The five chips share the search field's width: the first starts
      // where it starts, the last ends where it ends, and no label is cut.
      final search = tester.getRect(find.byType(SearchField));
      final first = tester.getRect(find.widgetWithText(ChoiceChip, 'Touring'));
      final last = tester.getRect(find.widgetWithText(ChoiceChip, 'Direct'));
      expect(first.left, closeTo(search.left, 0.5), reason: 'at $width dp');
      expect(last.right, closeTo(search.right, 0.5), reason: 'at $width dp');
      for (final label in ['Touring', 'Road', 'Gravel', 'MTB', 'Direct']) {
        final chipWidget = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, label),
        );
        final painter = TextPainter(
          text: TextSpan(text: label, style: chipWidget.labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final chip = tester.getRect(find.widgetWithText(ChoiceChip, label));
        expect(
          painter.width,
          lessThanOrEqualTo(chip.width - 8),
          reason: '$label does not fit its chip at $width dp',
        );
      }

      await unmountApp(tester);
    }
  });
}
