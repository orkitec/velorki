import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/fakes.dart';
import '../planner/support/pump.dart';

const List<Waypoint> _waypoints = [
  Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
  Waypoint(pos: LatLng(48.04, 11.04), kind: WaypointKind.end),
];

Future<SavedRoute> _seed(PlannerHarness h) =>
    RouteRepository(
      h.db.routesDao,
      clock: () => DateTime.utc(2026, 9, 12, 10),
    ).savePlannedRoute(
      name: 'Ammersee',
      route: syntheticRoute(),
      waypoints: _waypoints,
      options: const RoutingOptions(
        profile: RouteProfile.mtb,
        alternativeIdx: 1,
      ),
    );

void main() {
  testWidgets('a deleted route says so instead of crashing', (tester) async {
    await pumpApp(tester, initialLocation: routeDetailLocation('gone'));
    await tester.pumpAndSettle();

    expect(find.text('This route no longer exists.'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('opening in the planner restores waypoints and options', (
    tester,
  ) async {
    final h = PlannerHarness();
    final saved = await _seed(h);
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(saved.id),
      harness: h,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open in planner'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NavigationBar)),
    );
    final state = container.read(plannerControllerProvider);
    expect(state.positions, [_waypoints[0].pos, _waypoints[1].pos]);
    expect(state.options.profile, RouteProfile.mtb);
    expect(state.options.alternativeIdx, 1);
    expect(state.savedRouteId, saved.id);
    expect(state.result!.lengthM, 10000);
    // The stored route is shown as it was saved, without asking the server.
    expect(h.backend.callCount, 0);

    // It is drawn on the planner's map through the binding.
    expect(h.map.waypoints, hasLength(2));
    expect(find.text('10.0 km'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('the saved surface statistics survive the round trip', (
    tester,
  ) async {
    final h = PlannerHarness();
    final saved = await _seed(h);
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(saved.id),
      harness: h,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Paved 60%'), findsOneWidget);
    expect(find.textContaining('Unpaved 40%'), findsOneWidget);
    expect(find.textContaining('Busy roads 0%'), findsOneWidget);
    await unmountApp(tester);
  });
}
