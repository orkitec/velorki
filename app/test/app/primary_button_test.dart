import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../features/planner/support/fakes.dart';
import '../features/planner/support/pump.dart';
import '../support/app.dart';

void main() {
  testWidgets('Save on Plan, Start ride on Record and Open in planner on a '
      'route card are pills of one height', (tester) async {
    final h = PlannerHarness();
    final saved =
        await RouteRepository(
          h.db.routesDao,
          clock: () => DateTime.utc(2026, 9, 12, 10),
        ).savePlannedRoute(
          name: 'Isar loop',
          route: syntheticRoute(),
          waypoints: const [
            Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
            Waypoint(pos: LatLng(48.04, 11.04), kind: WaypointKind.end),
          ],
          options: const RoutingOptions(),
        );
    await pumpApp(tester, initialLocation: plannerRoute, harness: h);
    await tester.pumpAndSettle();

    double heightOf(String label) =>
        tester.getSize(find.widgetWithText(FilledButton, label)).height;
    expect(heightOf(l10n.plannerSave), primaryButtonHeight);

    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabRecord),
    );
    await tester.pumpAndSettle();
    expect(heightOf(l10n.recordingStart), primaryButtonHeight);

    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go(routeDetailLocation(saved.id));
    await tester.pumpAndSettle();
    expect(heightOf(l10n.routeDetailOpenInPlanner), primaryButtonHeight);
    // And it is in view at the card's resting height, above the surfaces.
    final open = tester.getRect(
      find.widgetWithText(FilledButton, l10n.routeDetailOpenInPlanner),
    );
    expect(
      open.bottom,
      lessThan(tester.getSize(find.byType(NavigationBar)).height + 2000),
    );
    await unmountApp(tester);
  });
}
