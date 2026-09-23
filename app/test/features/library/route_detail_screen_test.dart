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
import 'package:velorki/core/links/link_opener.dart';
import 'package:velorki/features/library/presentation/route_detail_screen.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';

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

    // The cue sheet is under the profile in the card: the turn with the
    // author's words, the points with theirs; a tap opens the note and
    // moves the map.
    expect(find.text(l10n.elevationTitle.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.cueSheetTitle.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.cueSheetStart), findsOneWidget);
    expect(h.map.waypoints, hasLength(2), reason: 'start and finish drawn');
    expect(find.text('Right at the barn'), findsOneWidget);
    expect(find.text('All riders must dismount'), findsNothing);
    await tester.ensureVisible(find.text('Dismount'));
    await tester.pumpAndSettle();
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

  testWidgets('an imported route says where it came from, opens its link, '
      'takes a description, and lists the points of interest off its '
      'track', (tester) async {
    final h = PlannerHarness();
    final opened = <Uri>[];
    final repository = RouteRepository(
      h.db.routesDao,
      clock: () => DateTime.utc(2026, 9, 12, 10),
    );
    final saved = await repository.saveImportedRoute(
      name: 'Ride Queens',
      points: syntheticRoute().geometry,
      source: RouteSource.importedGpx,
      link: 'https://ridewithgps.com/routes/1',
      creator: 'Garmin Connect',
      pois: const <RoutePoi>[
        // On the line: the cue sheet's, not the list's.
        RoutePoi(pos: LatLng(48.02, 11.02), name: 'Water', kind: PoiKind.water),
        // Five kilometres east of it: the list's.
        RoutePoi(
          pos: LatLng(48.02, 11.09),
          name: 'Café',
          description: 'Cake',
          kind: PoiKind.food,
        ),
      ],
    );
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(saved.id),
      harness: h,
      extraOverrides: [
        linkOpenerProvider.overrideWithValue((url) async {
          opened.add(url);
          return true;
        }),
      ],
    );
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.cardImportedFromBy('GPX', 'Garmin Connect')),
      findsOneWidget,
    );
    expect(find.text('https://ridewithgps.com/routes/1'), findsOneWidget);
    await tester.ensureVisible(find.text('https://ridewithgps.com/routes/1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('https://ridewithgps.com/routes/1'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://ridewithgps.com/routes/1')]);

    // The points off the track, with their kind and note; the one on it
    // is on the cue sheet instead.
    await tester.ensureVisible(find.text(l10n.routeDetailPois.toUpperCase()));
    await tester.pumpAndSettle();
    expect(find.text('Café'), findsOneWidget);
    expect(find.text('${l10n.poiKindFood} · Cake'), findsOneWidget);
    expect(find.text(l10n.cueSheetTitle.toUpperCase()), findsOneWidget);

    // A description typed here is kept.
    await tester.ensureVisible(find.text(l10n.routeDetailAddDescription));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.routeDetailAddDescription));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Flat and fast',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, l10n.commonSave),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      (await repository.routeById(saved.id))!.description,
      'Flat and fast',
    );
    expect(find.text('Flat and fast'), findsWidgets);
    await unmountApp(tester);
  });

  testWidgets('a route planned here has no source line', (tester) async {
    final h = PlannerHarness();
    final saved = await _seed(h);
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(saved.id),
      harness: h,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(l10n.cardImportedFrom('')), findsNothing);
    expect(find.text(l10n.routeDetailAddLink), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('a route card opened from the list on a fresh start draws its '
      'line, not only its points', (tester) async {
    tester.view.physicalSize = const Size(3000, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    final h = PlannerHarness();
    // Like the phone's data: an imported GPX route of a thousand points
    // with seventeen points of interest on the track and no turns.
    final track = <TrackPoint>[
      for (var i = 0; i < 1026; i++)
        TrackPoint(LatLng(48 + i * 0.0002, 11 + (i.isEven ? 0 : 0.0001))),
    ];
    await RouteRepository(
      h.db.routesDao,
      clock: () => DateTime.utc(2026, 9, 12, 10),
    ).saveImportedRoute(
      name: 'Long tour',
      points: track,
      source: RouteSource.importedGpx,
      pois: [
        for (var i = 1; i <= 17; i++)
          RoutePoi(
            pos: track[i * 60].pos,
            name: 'Stop $i',
            kind: PoiKind.water,
          ),
      ],
    );
    await pumpApp(tester, initialLocation: plannerRoute, harness: h);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabLibrary),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Long tour'));
    await tester.pumpAndSettle();

    expect(h.map.pois, hasLength(17));
    expect(h.map.lines[libraryRouteLineId], hasLength(1026));
    // The card rests: the route above it is what it was opened for.
    final shell = tester.widget<DockingSheetShell>(
      find.byType(DockingSheetShell),
    );
    expect(shell.extent, closeTo(sheetRestingExtent(2000), 0.001));
    await unmountApp(tester);
  });

  testWidgets('the line is drawn once per route version, a redraw waits '
      'for the draw before it, and a map that was not ready is drawn '
      'again once', (tester) async {
    final h = PlannerHarness();
    final repository = RouteRepository(
      h.db.routesDao,
      clock: () => DateTime.utc(2026, 9, 12, 10),
    );
    final saved = await repository.saveImportedRoute(
      name: 'Once',
      points: syntheticRoute().geometry,
      source: RouteSource.importedGpx,
    );
    // The map is still loading its style when the card opens.
    h.map.ready = false;
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(saved.id),
      harness: h,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    int lineWrites() => h.map.calls
        .where((c) => c.method == 'setRouteLine')
        .where((c) => c.arguments.first == libraryRouteLineId)
        .length;
    // Drawn, remembered by the map for when it is ready; the layers mixin
    // may have asked for a full redraw once on top, never a race.
    final drawn = lineWrites();
    expect(drawn, inInclusiveRange(1, 2));
    expect(h.map.lines[libraryRouteLineId], isNotNull);

    // Ready a moment later: one more draw, no more than that.
    h.map.ready = true;
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(lineWrites(), drawn + 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(lineWrites(), drawn + 1);

    // A new version of the route (its description) draws once more; the
    // same version again does not.
    // A later clock: the version is the route's updatedAt.
    await RouteRepository(
      h.db.routesDao,
      clock: () => DateTime.utc(2026, 9, 12, 11),
    ).setDescription(saved.id, 'Changed');
    await tester.pumpAndSettle();
    expect(lineWrites(), drawn + 2);
    await tester.pumpAndSettle();
    expect(lineWrites(), drawn + 2);
    await unmountApp(tester);
  });
}
