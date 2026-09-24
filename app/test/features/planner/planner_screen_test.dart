import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/map/presentation/visible_map_padding.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';

import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/presentation/elevation_profile_chart.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/planner/presentation/waypoint_edit_sheet.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/planner/presentation/surface_stats_bar.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/application/nav_bar_docking.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/format.dart';
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

TextField _nameField(WidgetTester tester) => tester.widget<TextField>(
  find.widgetWithText(TextField, l10n.plannerPointName),
);

void main() {
  testWidgets('the empty state explains the first gesture', (tester) async {
    await pumpScreen(tester, const PlannerScreen());

    expect(find.text(l10n.plannerEmptyState), findsOneWidget);
    expect(find.text(l10n.commonSave), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text(l10n.commonSave),
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

    final save = find.widgetWithText(FilledButton, l10n.commonSave);
    final rect = tester.getRect(save);
    expect(rect.bottom, lessThanOrEqualTo(2400));
    expect(rect.top, greaterThanOrEqualTo(0));
    // Inside the sheet at its resting height, and hittable.
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(rect.top, greaterThan(2400 * (1 - sheet.initialChildSize)));
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text(l10n.plannerSaveDialogTitle), findsOneWidget);
  });

  testWidgets('tapping the map twice plots a route with stats', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());

    await _plotRoute(tester, h);

    expect(find.text(testDistance(10000)), findsOneWidget);
    expect(find.text(testHeight(120)), findsOneWidget);
    expect(find.text(testHeight(80)), findsOneWidget);
    // 10 km at the trekking profile's 18 km/h.
    expect(
      find.text(testDuration(const Duration(minutes: 33))),
      findsOneWidget,
    );
    expect(find.byType(ElevationProfileChart), findsOneWidget);
    expect(find.byType(SurfaceStatsBar), findsOneWidget);
    expect(
      find.textContaining(
        l10n.labelWithPercent(l10n.surfacePaved, testPercent(0.6)),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        l10n.labelWithPercent(l10n.surfaceUnpaved, testPercent(0.4)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('switching the profile re-routes and changes the estimate', (
    tester,
  ) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);

    await tester.tap(find.widgetWithText(ChoiceChip, l10n.profileFastbike));
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
    expect(
      find.text(l10n.plannerRoutingFailed('position not mapped')),
      findsWidgets,
    );
  });

  testWidgets('without a routing server the planner points at Settings', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: PlannerHarness(withRoutingBackend: false),
    );

    expect(find.text(l10n.plannerNoRoutingServer), findsOneWidget);
  });

  testWidgets('undo, reverse and clear drive the plan', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);

    await tester.tap(
      find.widgetWithText(LabeledIconButton, l10n.plannerReverse),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(h.backend.queries.last.points, [_b, _a]);

    final routed = h.backend.queries.length;
    await tester.tap(find.widgetWithText(LabeledIconButton, l10n.commonUndo));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    // The plan is back the way round it was, and the route with it: an
    // undo puts back what it recorded rather than asking for it again.
    expect(h.map.waypoints.map((w) => w.position), [_a, _b]);
    expect(h.backend.queries.length, routed);

    await tester.tap(find.widgetWithText(LabeledIconButton, l10n.plannerClear));
    await tester.pumpAndSettle();
    expect(find.text(l10n.plannerEmptyState), findsOneWidget);
    expect(h.map.lines, isEmpty);
  });

  testWidgets('alternatives are fetched on request and selectable', (
    tester,
  ) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    h.backend.byAlternative[1] = syntheticRoute(lengthM: 11000);
    await _plotRoute(tester, h);

    await tester.tap(
      find.widgetWithText(LabeledIconButton, l10n.plannerVariants),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(ChoiceChip, l10n.plannerMainRoute),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(ChoiceChip, l10n.plannerAlternativeIndex(1)),
      findsOneWidget,
    );

    await tester.tap(
      find.widgetWithText(ChoiceChip, l10n.plannerAlternativeIndex(1)),
    );
    await tester.pumpAndSettle();

    expect(find.text(testDistance(11000)), findsOneWidget);
  });

  testWidgets('saving asks for a name and writes a library row', (
    tester,
  ) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);

    await tester.tap(find.text(l10n.commonSave));
    await tester.pumpAndSettle();

    expect(find.text(l10n.plannerSaveDialogTitle), findsOneWidget);
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
        matching: find.widgetWithText(FilledButton, l10n.commonSave),
      ),
    );
    await tester.pumpAndSettle();

    final rows = await h.db.routesDao.allRoutes();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Isar loop');
    expect(rows.single.distanceM, 10000);
    expect(find.text(l10n.plannerRouteSaved), findsOneWidget);
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
    // Into the middle of the map between the chrome and the sheet at rest,
    // where the sheet goes for the place, clear of the column at the right.
    final element = tester.element(find.byType(PlannerScreen));
    final height = MediaQuery.sizeOf(element).height;
    expect(
      h.map.movedPadding!.bottom,
      closeTo(sheetRestingExtent(height) * height + 24, 1e-6),
    );
    expect(h.map.movedPadding!.right, mapControlsWidth(element) + 24);
    expect(h.map.movedPadding!.top, greaterThan(100));
    expect(find.text(l10n.plannerSetAsStart), findsOneWidget);
    // The found place is pinned until the rider decides what it is.
    expect(h.map.searchPin, const LatLng(48.1374, 11.5755));

    await tester.tap(find.text(l10n.plannerSetAsStart));
    await tester.pumpAndSettle();

    expect(h.map.waypoints.single.position, const LatLng(48.1374, 11.5755));
    expect(find.text(l10n.plannerSetAsStart), findsNothing);
    expect(h.map.searchPin, isNull, reason: 'it is a waypoint now');
  });

  testWidgets('tapping a marker offers to remove the point', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);
    expect(h.map.waypoints, hasLength(2));

    h.map.onWaypointTapped!(1);
    await tester.pumpAndSettle();

    // The name field opens with the point's number, there being no name.
    expect(find.byType(WaypointEditSheet), findsOneWidget);
    expect(_nameField(tester).controller!.text, '2');
    await tester.tap(find.text(l10n.plannerRemovePoint));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.map.waypoints, hasLength(1));
    expect(find.byType(WaypointEditSheet), findsNothing);
  });

  testWidgets('a marker\'s sheet gives the point a name, a kind and a note '
      'on Done, and the marker wears the name', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);
    expect(h.map.waypoints.map((w) => w.label), [null, null]);

    h.map.onWaypointTapped!(1);
    await tester.pumpAndSettle();
    expect(find.byType(WaypointEditSheet), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, l10n.plannerPointName),
      'Bakery',
    );
    await tester.tap(find.text(l10n.poiKindFood));
    await tester.enterText(
      find.widgetWithText(TextField, l10n.plannerPointNote),
      'Croissants before the climb',
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonDone));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    final point = container.read(plannerControllerProvider).waypoints[1];
    expect(point.name, 'Bakery');
    expect(point.poiKind, PoiKind.food);
    expect(point.note, 'Croissants before the climb');
    // On the map the marker says the name; the plan was not routed again.
    expect(h.map.waypoints.map((w) => w.label), [null, 'Bakery']);
    expect(h.backend.callCount, 1);

    // Tapped again, the sheet opens pre-filled; a pull down keeps it so.
    h.map.onWaypointTapped!(1);
    await tester.pumpAndSettle();
    expect(_nameField(tester).controller!.text, 'Bakery');
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, l10n.plannerPointNote),
          )
          .controller!
          .text,
      'Croissants before the climb',
    );
    await tester.enterText(
      find.widgetWithText(TextField, l10n.plannerPointName),
      'Not this',
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(WaypointEditSheet), findsNothing);
    expect(
      container.read(plannerControllerProvider).waypoints[1].name,
      'Bakery',
    );
  });

  testWidgets('a number left in the name field names nothing, and Done '
      'without a change is no undo step', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    final undos = container.read(plannerControllerProvider).undoStack.length;

    h.map.onWaypointTapped!(1);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonDone));
    await tester.pumpAndSettle();
    final state = container.read(plannerControllerProvider);
    expect(state.waypoints[1].name, isNull);
    expect(state.undoStack.length, undos);
    expect(h.map.waypoints.map((w) => w.label), [null, null]);
  });

  testWidgets('a point flips to the side of the route and back, and the map '
      'draws it as a place', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);
    expect(h.map.waypoints, hasLength(2));
    expect(h.map.pois, isEmpty);

    h.map.onWaypointTapped!(1);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, l10n.plannerPointName),
      'Castle',
    );
    await tester.tap(find.text(l10n.plannerPointBeside));
    await tester.pumpAndSettle();
    // A place has no order to be moved in.
    expect(find.text(l10n.plannerVisitEarlier), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonDone));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.map.waypoints, hasLength(1));
    expect(h.map.pois.single.name, 'Castle');
    expect(h.map.pois.single.position, _b);

    // Tapped again, it goes back on the route.
    h.map.onPoiTapped!(0);
    await tester.pumpAndSettle();
    expect(_nameField(tester).controller!.text, 'Castle');
    await tester.tap(find.text(l10n.plannerPointOnRoute));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonDone));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.map.pois, isEmpty);
    expect(h.map.waypoints, hasLength(2));
    expect(h.map.waypoints.last.label, 'Castle');
  });

  testWidgets('holding the map opens the sheet for a new place there, and '
      'Done marks it', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);

    h.map.onLongPress!(const LatLng(48.1, 11.1));
    await tester.pumpAndSettle();

    expect(find.byType(WaypointEditSheet), findsOneWidget);
    expect(_nameField(tester).controller!.text, '', reason: 'a new place');
    expect(find.text(l10n.plannerVisitEarlier), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, l10n.plannerPointName),
      'Fountain',
    );
    await tester.tap(find.text(l10n.poiKindWater));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonDone));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.map.waypoints, hasLength(2), reason: 'the route is untouched');
    expect(h.map.pois.single.name, 'Fountain');
    expect(h.map.pois.single.position, const LatLng(48.1, 11.1));
    expect(h.map.pois.single.kind, MapPoiKind.water);
  });

  testWidgets('the sheet for a place beside the route opens on its side of '
      'the switch, with an empty name and no turn to choose', (tester) async {
    await tester.pumpWidget(
      testApp(
        home: Scaffold(
          body: WaypointEditSheet(
            index: 0,
            count: 1,
            initial: const WaypointDetails(beside: true),
            onSwap: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_nameField(tester).controller!.text, '');
    expect(find.text(l10n.poiKindTurn), findsNothing);
    expect(find.text(l10n.poiKindGeneric), findsOneWidget);
    expect(find.text(l10n.plannerVisitEarlier), findsNothing);
    expect(find.text(l10n.plannerVisitLater), findsNothing);
    expect(find.text(l10n.plannerRemovePoint), findsOneWidget);
  });

  testWidgets('a turn flipped to the side of the route stops being a turn', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        home: Scaffold(
          body: WaypointEditSheet(
            index: 0,
            count: 1,
            initial: const WaypointDetails(
              poiKind: PoiKind.turn,
              turn: TurnKind.left,
            ),
            onSwap: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.plannerTurnDirection), findsOneWidget);

    await tester.tap(find.text(l10n.plannerPointBeside));
    await tester.pumpAndSettle();

    expect(find.text(l10n.poiKindTurn), findsNothing);
    expect(find.text(l10n.plannerTurnDirection), findsNothing);
  });

  testWidgets('the type tiles keep every label on one line at phone width, '
      'in English and in German', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final locale in const [Locale('en'), Locale('de')]) {
      await tester.pumpWidget(
        testApp(
          locale: locale,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PoiKindTiles(
                selected: PoiKind.generic,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final strings = lookupAppLocalizations(locale);
      for (final kind in PoiKind.values) {
        final label = poiKindLabel(strings, kind);
        final text = tester.widget<Text>(find.text(label));
        expect(text.maxLines, 1, reason: '$locale $label');
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '$locale $label overflows its tile',
        );
      }
    }
  });

  testWidgets('the type tiles are a four by four grid at every width, all '
      'the same size, nothing to scroll', (tester) async {
    Future<List<Rect>> tiles(double width) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        testApp(
          home: Scaffold(
            body: PoiKindTiles(selected: PoiKind.food, onSelected: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return [
        for (final kind in PoiKind.values)
          tester.getRect(
            find.ancestor(
              of: find.text(poiKindLabel(l10n, kind)),
              matching: find.byType(InkWell),
            ),
          ),
      ];
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Sixteen kinds, four to a row, four rows — the same block whatever the
    // sheet is wide.
    for (final width in <double>[390, 340]) {
      final grid = await tiles(width);
      expect(grid, hasLength(PoiKind.values.length));
      expect(
        grid.map((r) => r.top.round()).toSet(),
        hasLength(4),
        reason: 'rows at $width',
      );
      expect(
        grid.map((r) => r.left.round()).toSet(),
        hasLength(4),
        reason: 'columns at $width',
      );
      expect(grid.map((r) => r.width.round()).toSet(), hasLength(1));
      expect(grid.every((r) => r.right <= width), isTrue);
    }
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('the sheet has one resting height, with or without variants', (
    tester,
  ) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    DraggableScrollableSheet sheet() => tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    final screenHeight = MediaQuery.sizeOf(
      tester.element(find.byType(PlannerScreen)),
    ).height;
    // The height the Record tab rests at too, so a tab change never moves
    // the sheet.
    final resting = sheetRestingExtent(screenHeight);
    expect(sheet().initialChildSize, resting);
    // Two resting heights a chip row apart made a pull down from the top
    // and a pull up from the handle settle at different places.
    expect(sheet().snapSizes, [resting]);

    // A route and then its variants: the sheet neither grows nor snaps
    // somewhere else, the chips have their row already.
    h.backend.byAlternative[1] = syntheticRoute(lengthM: 11000);
    await _plotRoute(tester, h);
    expect(sheet().initialChildSize, resting);
    expect(sheet().snapSizes, [resting]);
    await tester.tap(
      find.widgetWithText(LabeledIconButton, l10n.plannerVariants),
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(ChoiceChip, l10n.plannerMainRoute),
      findsOneWidget,
    );
    expect(sheet().initialChildSize, resting);
    expect(sheet().snapSizes, [resting]);
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
    OutlinedButton button(String label) => tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, label),
    );
    // The last point cannot go later.
    expect(button(l10n.plannerVisitLater).onPressed, isNull);
    // A name typed before the swap travels with the point.
    await tester.enterText(
      find.widgetWithText(TextField, l10n.plannerPointName),
      'Lake',
    );
    await tester.tap(find.text(l10n.plannerVisitEarlier));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // Swapped at once, the sheet still open and now at the first place.
    expect(h.map.waypoints[0].position, second);
    expect(h.map.waypoints[1].position, first);
    expect(find.byType(WaypointEditSheet), findsOneWidget);
    expect(_nameField(tester).controller!.text, 'Lake');
    expect(button(l10n.plannerVisitEarlier).onPressed, isNull);
    expect(button(l10n.plannerVisitLater).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, l10n.commonDone));
    await tester.pumpAndSettle();
    expect(h.map.waypoints.map((w) => w.label), ['Lake', null]);
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

    await tester.tap(find.text(l10n.plannerRideFromPosition));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.map.waypoints, hasLength(2));
    expect(h.map.waypoints.first.position, const LatLng(48.0, 11.0));
    expect(h.map.waypoints.last.position, const LatLng(48.1374, 11.5755));
    expect(h.map.waypoints.last.label, 'Munich');
    expect(find.text(l10n.plannerRideFromPosition), findsNothing);
  });

  testWidgets('clearing the search forgets the searched place', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());

    await tester.enterText(find.byType(TextField).first, 'munich');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bavaria, Germany'));
    await tester.pumpAndSettle();
    expect(h.map.searchPin, isNotNull);
    expect(find.text(l10n.plannerRideFromPosition), findsOneWidget);

    // The field's own clear button drops the place and its two actions.
    await tester.tap(find.byTooltip(l10n.searchClear));
    await tester.pumpAndSettle();
    expect(h.map.searchPin, isNull);
    expect(find.text(l10n.plannerRideFromPosition), findsNothing);
    expect(find.text(l10n.plannerSetAsStart), findsNothing);

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
    // The measured chrome replaces the estimate with a short glide.
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    double controlsTop() =>
        container.read(mapControlsTopProvider).animation.value;
    final before = controlsTop();

    await tester.enterText(find.byType(TextField).first, 'munich');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bavaria, Germany'));
    await tester.pumpAndSettle();

    // The two action buttons add a row above the chips; the column must
    // not sit on the chips because of it.
    expect(controlsTop(), greaterThan(before + 30));

    await tester.tap(find.byTooltip(l10n.searchClear));
    await tester.pumpAndSettle();
    expect(controlsTop(), closeTo(before, 0.5));
  });

  testWidgets(
    'pulled all the way down, the sheet docks in the navigation bar',
    (tester) async {
      await pumpScreen(tester, const PlannerScreen());
      DockingSheetShell shell() =>
          tester.widget<DockingSheetShell>(find.byType(DockingSheetShell));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlannerScreen)),
      );
      expect(shell().docks, isTrue);
      expect(shell().docked, 0);
      expect(container.read(navBarDockingProvider), isEmpty);

      // A drag on the handle is a drag on the sheet: all the way down it
      // folds into the bar, and the bar is told.
      await tester.dragFrom(
        tester.getCenter(find.byType(SheetHandle)),
        const Offset(0, 1500),
      );
      await tester.pumpAndSettle();
      expect(shell().docked, 1);
      expect(container.read(navBarDockingProvider), {plannerRoute});
      expect(find.byType(SheetHandle), findsOneWidget);
      expectNoClippedText(tester);

      // Dragging the handle up brings the sheet back, and the bar its corners.
      await tester.dragFrom(
        tester.getCenter(find.byType(SheetHandle)),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(shell().docked, 0);
      expect(container.read(navBarDockingProvider), isEmpty);
      expect(find.text(l10n.plannerEmptyState), findsOneWidget);
    },
  );

  testWidgets('a docked sheet rises to rest when its tab comes back', (
    tester,
  ) async {
    await pumpScreen(tester, const PlannerScreen());
    DockingSheetShell shell() =>
        tester.widget<DockingSheetShell>(find.byType(DockingSheetShell));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    final resting = tester
        .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
        .initialChildSize;
    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, 1500),
    );
    await tester.pumpAndSettle();
    expect(shell().docked, 1);
    expect(container.read(navBarDockingProvider), {plannerRoute});

    // Away to Record and back: the sheet comes up from the bar to rest.
    container.read(activeTabProvider.notifier).show(recordingRoute);
    await tester.pump();
    container.read(activeTabProvider.notifier).show(plannerRoute);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(shell().docked, lessThan(1));
    await tester.pumpAndSettle();
    expect(shell().extent, closeTo(resting, 0.001));
    expect(shell().docked, 0);
    expect(container.read(navBarDockingProvider), isEmpty);

    // At rest already: nothing moves.
    container.read(activeTabProvider.notifier).show(recordingRoute);
    await tester.pump();
    container.read(activeTabProvider.notifier).show(plannerRoute);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(shell().extent, closeTo(resting, 0.001));
    await tester.pumpAndSettle();
    expect(shell().extent, closeTo(resting, 0.001));
  });

  testWidgets('a plan that changes while the tab is away is drawn whole, '
      'and fitted, when the tab comes back', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    expect(h.map.onTap, isNotNull);

    // Record comes up: nothing of the plan stays on the shared map, and
    // taps there are not the planner's any more.
    container.read(activeTabProvider.notifier).show(recordingRoute);
    await tester.pump();
    expect(h.map.onTap, isNull);
    expect(h.map.waypoints, isEmpty);

    // A route loaded from the library while the tab is away is not drawn
    // yet: the map is the other tab's.
    final before = h.map.calls.length;
    container.read(plannerControllerProvider.notifier).addWaypoint(_a);
    container.read(plannerControllerProvider.notifier).addWaypoint(_b);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(h.map.calls.length, before);
    expect(h.map.lines, isEmpty);

    // Back on Plan: markers, line, and the camera fitted to a route that
    // arrived whole.
    container.read(activeTabProvider.notifier).show(plannerRoute);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(h.map.waypoints, hasLength(2));
    expect(h.map.lines, isNotEmpty);
    expect(h.map.fittedBounds, isNotNull);
    expect(h.map.onTap, isNotNull);
  });

  testWidgets('the sheet parks under the keyboard while searching', (
    tester,
  ) async {
    await pumpScreen(tester, const PlannerScreen());
    final sheet = find.byType(DraggableScrollableSheet);
    final headline = find.text(l10n.plannerEmptyState);
    expect(headline, findsOneWidget);
    final screenHeight = tester.getSize(find.byType(PlannerScreen)).height;
    final restingTop = tester.getTopLeft(headline).dy;
    expect(restingTop, lessThan(screenHeight * 0.7));

    // Focusing the field drops the sheet to its handle before the keyboard
    // shows: the headline is off the bottom edge.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
    // The sheet is at its handle: the headline sits below the sheet's top
    // edge, under the handle strip.
    final parkedTop =
        screenHeight *
        (1 - tester.widget<DraggableScrollableSheet>(sheet).minChildSize);
    expect(tester.getTopLeft(headline).dy, greaterThan(parkedTop + 20));
    expect(tester.getTopLeft(headline).dy, greaterThan(restingTop + 200));

    // The keyboard comes and goes; the screen never shrinks, so the map
    // under it keeps its full height.
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(PlannerScreen)).height,
      closeTo(screenHeight, 0.5),
    );
    // The sheet is at its handle: the headline sits below the sheet's top
    // edge, under the handle strip.
    expect(tester.getTopLeft(headline).dy, greaterThan(parkedTop + 20));
    expect(tester.getTopLeft(headline).dy, greaterThan(restingTop + 200));

    // Once the keyboard is gone the sheet is back where it was.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(headline).dy, closeTo(restingTop, 0.5));

    // The field kept its focus; the keyboard coming back parks it again.
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    await tester.pumpAndSettle();
    // The sheet is at its handle: the headline sits below the sheet's top
    // edge, under the handle strip.
    expect(tester.getTopLeft(headline).dy, greaterThan(parkedTop + 20));
    expect(tester.getTopLeft(headline).dy, greaterThan(restingTop + 200));
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

      final labels = [
        for (final profile in RouteProfile.values) profileLabel(l10n, profile),
      ];
      for (final label in labels) {
        expect(
          find.widgetWithText(ChoiceChip, label),
          findsOneWidget,
          reason: 'at $width dp',
        );
      }

      // The five chips share the search field's width: the first starts
      // where it starts, the last ends where it ends, and no label is cut.
      final search = tester.getRect(find.byType(SearchField));
      final first = tester.getRect(
        find.widgetWithText(ChoiceChip, l10n.profileTrekking),
      );
      final last = tester.getRect(
        find.widgetWithText(ChoiceChip, l10n.profileShortest),
      );
      expect(first.left, closeTo(search.left, 0.5), reason: 'at $width dp');
      expect(last.right, closeTo(search.right, 0.5), reason: 'at $width dp');
      for (final label in labels) {
        final chipWidget = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, label),
        );
        final painter = TextPainter(
          text: TextSpan(text: label, style: chipWidget.labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final chip = tester.getRect(find.widgetWithText(ChoiceChip, label));
        final drawn = tester.getRect(
          find.descendant(
            of: find.widgetWithText(ChoiceChip, label),
            matching: find.text(label),
          ),
        );
        // The label is inside its chip, and it got there by fitting or by a
        // gentle shrink — not by being cut (`expectNoClippedText`) and not by
        // being squeezed to a fifth of its size.
        expect(
          drawn.width,
          lessThanOrEqualTo(chip.width - 8),
          reason: '$label does not fit its chip at $width dp',
        );
        expect(
          drawn.width,
          greaterThanOrEqualTo(painter.width * 0.8),
          reason: '$label is shrunk too far to read at $width dp',
        );
      }

      await unmountApp(tester);
    }
  });

  testWidgets('a point of the turn kind takes a direction, which its '
      'marker and the plan keep', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    await _plotRoute(tester, h);
    h.map.onWaypointTapped!(1);
    await tester.pumpAndSettle();
    // No direction to choose until the kind is a turn.
    expect(find.byType(TurnDirectionChips), findsNothing);
    await tester.ensureVisible(find.text(l10n.poiKindTurn));
    await tester.tap(find.text(l10n.poiKindTurn));
    await tester.pumpAndSettle();
    expect(find.byType(TurnDirectionChips), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, l10n.navTurnRight));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, l10n.plannerPointName),
      'Right at the barn',
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonDone));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    final point = container.read(plannerControllerProvider).waypoints[1];
    expect(point.poiKind, PoiKind.turn);
    expect(point.turn, TurnKind.right);
    expect(point.name, 'Right at the barn');
    expect(h.map.waypoints.map((w) => w.label), [null, 'Right at the barn']);

    // Opened again, the direction is the one chosen.
    h.map.onWaypointTapped!(1);
    await tester.pumpAndSettle();
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, l10n.navTurnRight),
    );
    expect(chip.selected, isTrue);
  });
}
