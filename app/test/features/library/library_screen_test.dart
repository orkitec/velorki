import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/application/planner_map_binding.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/format.dart';
import '../planner/support/fakes.dart';
import '../planner/support/pump.dart';

const List<Waypoint> _waypoints = [
  Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
  Waypoint(pos: LatLng(48.04, 11.04), kind: WaypointKind.end),
];

Future<SavedRoute> _seed(
  PlannerHarness h, {
  String name = 'Isar loop',
  double lengthM = 10000,
  RouteProfile profile = RouteProfile.trekking,
}) =>
    RouteRepository(
      h.db.routesDao,
      clock: () => DateTime.utc(2026, 9, 12, 10),
    ).savePlannedRoute(
      name: name,
      route: syntheticRoute(lengthM: lengthM),
      waypoints: _waypoints,
      options: RoutingOptions(profile: profile),
    );

void main() {
  testWidgets('an empty library explains itself', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining(l10n.libraryEmpty), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('saved routes are listed with date, distance and ascent', (
    tester,
  ) async {
    final h = PlannerHarness();
    await _seed(h);
    await pumpApp(tester, harness: h);
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
    await unmountApp(tester);
  });

  testWidgets('the menu deletes a route and the snack bar undoes it', (
    tester,
  ) async {
    final h = PlannerHarness();
    await _seed(h);
    await pumpApp(tester, harness: h);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonDelete));
    await tester.pumpAndSettle();

    expect(find.text('Isar loop'), findsNothing);
    expect(find.text(l10n.libraryRouteDeleted('Isar loop')), findsOneWidget);

    await tester.tap(find.text(l10n.commonUndo));
    await tester.pumpAndSettle();

    expect(find.text('Isar loop'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('swiping a row away deletes it', (tester) async {
    final h = PlannerHarness();
    await _seed(h);
    await pumpApp(tester, harness: h);
    await tester.pumpAndSettle();

    await tester.drag(find.text('Isar loop'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(await h.db.routesDao.allRoutes(), isEmpty);
    await unmountApp(tester);
  });

  testWidgets('renaming writes the new name', (tester) async {
    final h = PlannerHarness();
    await _seed(h);
    await pumpApp(tester, harness: h);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonRename));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Ammersee',
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonSave));
    await tester.pumpAndSettle();

    expect(find.text('Ammersee'), findsOneWidget);
    expect((await h.db.routesDao.allRoutes()).single.name, 'Ammersee');
    await unmountApp(tester);
  });

  testWidgets('tapping a route opens its detail screen', (tester) async {
    final h = PlannerHarness();
    final saved = await _seed(h, profile: RouteProfile.gravel);
    await pumpApp(tester, harness: h);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Isar loop'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Isar loop'), findsOneWidget);
    expect(find.text(testDistance(10000)), findsOneWidget);
    expect(find.text(testHeight(120)), findsOneWidget);
    expect(find.text(testHeight(80)), findsOneWidget);
    // 10 km at the gravel profile's 16 km/h.
    expect(
      find.text(testDuration(const Duration(minutes: 37))),
      findsOneWidget,
    );
    expect(find.textContaining(l10n.profileGravel), findsWidgets);

    // The preview is drawn through the map contract, bounds included.
    expect(h.map.lines[mainRouteLineId], hasLength(saved.geometry.length));
    expect(h.map.fittedBounds, isNotNull);

    expect(find.text(l10n.routeDetailOpenInPlanner), findsOneWidget);
    // The export menu itself is covered by
    // test/features/import_export/route_export_test.dart.
    expect(
      find.widgetWithText(OutlinedButton, l10n.routeDetailExport),
      findsOneWidget,
    );
    await unmountApp(tester);
  });
}
