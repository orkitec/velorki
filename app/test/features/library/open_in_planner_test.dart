import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/db/tables/routes.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/planner/domain/shape_points.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../planner/support/fakes.dart';
import '../planner/support/pump.dart';

const LatLng _a = LatLng(48.0, 11.0);
const LatLng _b = LatLng(48.1, 11.1);
const LatLng _c = LatLng(48.2, 11.2);

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(NavigationDestination, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a three-point route saved from Plan comes back whole from '
      'the Library, via point and details included', (tester) async {
    final h = await pumpApp(tester, initialLocation: plannerRoute);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NavigationBar)),
    );
    final planner = container.read(plannerControllerProvider.notifier);
    // A route that runs through all three points, so each of them is beside
    // the line and earns a line on the card's cue sheet.
    h.backend.result = syntheticRoute(points: 25);

    // Three taps on the map, a name and a note on the middle one.
    h.map.onTap!(_a);
    h.map.onTap!(_b);
    h.map.onTap!(_c);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    planner.setWaypointDetails(
      1,
      name: 'Bakery',
      poiKind: PoiKind.food,
      note: 'Croissants',
    );
    await tester.pumpAndSettle();
    expect(h.map.waypoints, hasLength(3));

    await tester.tap(find.widgetWithText(FilledButton, l10n.plannerSave));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Three points',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, l10n.commonSave),
      ),
    );
    await tester.pumpAndSettle();

    // Another plan in between, so the reload has something to restore.
    planner.clear();
    await tester.pumpAndSettle();
    expect(h.map.waypoints, isEmpty);

    await _tapTab(tester, l10n.tabLibrary);
    await tester.tap(find.text('Three points'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l10n.routeDetailOpenInPlanner));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.routeDetailOpenInPlanner));
    await tester.pumpAndSettle();

    expect(container.read(activeTabProvider), plannerRoute);
    final waypoints = container.read(plannerControllerProvider).waypoints;
    expect(waypoints.map((w) => w.pos), [_a, _b, _c]);
    expect(waypoints[1].name, 'Bakery');
    expect(waypoints[1].poiKind, PoiKind.food);
    expect(waypoints[1].note, 'Croissants');
    // Drawn on the shared map: three markers, the named one labelled.
    expect(h.map.waypoints.map((w) => w.position), [_a, _b, _c]);
    expect(h.map.waypoints.map((w) => w.label), [null, 'Bakery', null]);
    expect(h.backend.callCount, 1, reason: 'the stored route is shown as is');

    // Details on the route as stored need no Save: name the start, leave
    // for the Library, and the card already lists it, note and all.
    planner.setWaypointDetails(0, name: 'Home', note: 'Start here');
    await tester.pumpAndSettle();
    await _tapTab(tester, l10n.tabLibrary);
    await tester.tap(find.text('Three points'));
    await tester.pumpAndSettle();
    // The cue sheet names the points; a tap on a line shows its note.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Bakery'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Start here'), findsOneWidget);
    await tester.tap(find.text('Bakery'));
    await tester.pumpAndSettle();
    expect(find.text('Croissants'), findsOneWidget);

    await tester.ensureVisible(find.text(l10n.routeDetailOpenInPlanner));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.routeDetailOpenInPlanner));
    await tester.pumpAndSettle();
    final again = container.read(plannerControllerProvider).waypoints;
    expect(again.map((w) => w.name), ['Home', 'Bakery', null]);
    expect(again.map((w) => w.note), ['Start here', 'Croissants', null]);
    expect(h.map.waypoints.map((w) => w.label), ['Home', 'Bakery', null]);
    expect(h.backend.callCount, 1, reason: 'nothing routed for details');
    await unmountApp(tester);
  });

  testWidgets('an imported route opens in the planner with shape points '
      'along its track', (tester) async {
    final h = PlannerHarness();
    final track = <TrackPoint>[
      for (var i = 0; i < 200; i++)
        TrackPoint(
          LatLng(48 + i * 0.0005, 11 + (i.isEven ? 0 : 0.003) * (i % 3)),
        ),
    ];
    final saved =
        await RouteRepository(
          h.db.routesDao,
          clock: () => DateTime.utc(2026, 9, 12, 10),
        ).saveImportedRoute(
          name: 'Imported course',
          points: track,
          source: RouteSource.importedGpx,
        );
    expect(saved.waypoints, hasLength(2));
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(saved.id),
      harness: h,
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(l10n.routeDetailOpenInPlanner));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.routeDetailOpenInPlanner));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NavigationBar)),
    );
    final waypoints = container.read(plannerControllerProvider).waypoints;
    expect(waypoints.length, greaterThan(2));
    expect(waypoints.length, lessThanOrEqualTo(maxShapePoints + 2));
    expect(waypoints.first.pos, track.first.pos);
    expect(waypoints.last.pos, track.last.pos);
    expect(h.map.waypoints, hasLength(waypoints.length));
    expect(h.backend.callCount, 0, reason: 'nothing routed on opening');
    await unmountApp(tester);
  });
}
