import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/db/tables/routes.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/format.dart';
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
  testWidgets('an imported route shows its points of interest on the map', (
    tester,
  ) async {
    final h = PlannerHarness();
    final saved =
        await RouteRepository(
          h.db.routesDao,
          clock: () => DateTime.utc(2026, 9, 12, 10),
        ).saveImportedRoute(
          name: 'Ride Queens',
          points: syntheticRoute().geometry,
          source: RouteSource.importedGpx,
          pois: const <RoutePoi>[
            RoutePoi(
              pos: LatLng(48.01, 11.01),
              name: 'Dismount',
              description: 'All riders must dismount',
              kind: PoiKind.danger,
            ),
            RoutePoi(
              pos: LatLng(48.02, 11.02),
              name: 'Water',
              kind: PoiKind.water,
            ),
          ],
          turns: const <TurnHint>[
            TurnHint(
              pointIndex: 1,
              kind: TurnKind.right,
              note: 'Right at the barn',
            ),
          ],
        );
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(saved.id),
      harness: h,
    );
    await tester.pumpAndSettle();

    expect(h.map.pois.map((p) => p.name), ['Dismount', 'Water']);
    expect(h.map.pois.first.kind, MapPoiKind.danger);

    // The cue sheet is the second page under the map: the turn with the
    // author's words, the points with theirs; a tap opens the note and
    // moves the map.
    expect(find.text(l10n.cueSheetTitle.toUpperCase()), findsNothing);
    await tester.fling(
      find.text(l10n.statDistance.toUpperCase()),
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
    expect(find.text(l10n.cueSheetStart), findsOneWidget);
    expect(h.map.waypoints, hasLength(2), reason: 'start and finish drawn');
    expect(find.text('Right at the barn'), findsOneWidget);
    expect(find.text('All riders must dismount'), findsNothing);
    await tester.tap(find.text('Dismount'));
    await tester.pumpAndSettle();
    expect(find.text('All riders must dismount'), findsOneWidget);
    expect(h.map.calls.where((c) => c.method == 'moveTo'), hasLength(1));
    await unmountApp(tester);
  });

  testWidgets('a deleted route says so instead of crashing', (tester) async {
    await pumpApp(tester, initialLocation: routeDetailLocation('gone'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.routeDetailNotFound), findsOneWidget);
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

    await tester.tap(find.text(l10n.routeDetailOpenInPlanner));
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
    expect(find.text(testDistance(10000)), findsOneWidget);
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
    expect(
      find.textContaining(
        l10n.labelWithPercent(l10n.surfaceBusy, testPercent(0)),
      ),
      findsOneWidget,
    );
    await unmountApp(tester);
  });
}
