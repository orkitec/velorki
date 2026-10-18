import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/integrations/application/strava_route_checks.dart';
import 'package:velorki/features/settings/presentation/settings_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:velorki/features/integrations/common/data/connected_accounts_repository.dart';
import 'package:velorki/features/integrations/common/data/secure_key_value_store.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/presentation/strava_brand.dart';
import 'package:velorki/features/integrations/testing/in_memory_secure_key_value_store.dart';
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
import 'package:velorki/features/navigation/presentation/cue_sheet_list.dart';
import 'package:velorki/features/weather/presentation/route_colour_choice.dart';
import 'package:velorki/features/planner/presentation/elevation_profile_chart.dart';
import 'package:velorki/features/shared/presentation/metric_chart.dart';
import 'package:fl_chart/fl_chart.dart' show LineChart;
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/subscription/application/plus_access.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/domain/route_weather_state.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/weather/presentation/route_weather_section.dart';
import 'package:velorki/features/weather/presentation/route_weather_strip.dart';
import 'package:velorki/features/weather/presentation/weather_keys.dart';
import 'package:velorki/core/geo/route_gradient.dart';
import 'package:velorki/core/files/track_exporter.dart';
import 'package:velorki/features/planner/presentation/route_stats_row.dart';
import 'package:velorki/features/planner/presentation/surface_section.dart';
import 'package:velorki/features/shared/presentation/button_menu.dart';
import 'package:velorki/features/weather/application/route_overlay.dart';

import '../../support/app.dart';
import '../../support/chart_cursor.dart';
import '../../support/format.dart';
import '../planner/support/fakes.dart';
import '../planner/support/pump.dart';
import '../../support/mock_relay.dart';
import '../weather/support/weather_fixtures.dart';

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
    expect(
      find.descendant(
        of: find.byType(CueSheetList),
        matching: find.text(l10n.cueSheetStart),
      ),
      findsOneWidget,
    );
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

  testWidgets('a tap on the profile puts the cursor and the rider badge on '
      'the route, a sweep moves them and they stay; zoomed, the handle moves '
      'the cursor; a vertical drag on it still moves the card; and the '
      'badge goes with the screen', (tester) async {
    final h = PlannerHarness();
    const start = LatLng(48, 11);
    // Four kilometres due north, a point every 100 m, climbing.
    final track = <TrackPoint>[
      for (var m = 0; m <= 4000; m += 100)
        TrackPoint(destinationPoint(start, 0, m.toDouble()), ele: 400 + m / 20),
    ];
    final saved =
        await RouteRepository(
          h.db.routesDao,
          clock: () => DateTime.utc(2026, 9, 12, 10),
        ).saveImportedRoute(
          name: 'North',
          points: track,
          source: RouteSource.importedGpx,
        );
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(saved.id),
      harness: h,
    );
    await tester.pumpAndSettle();
    final chart = find.descendant(
      of: find.byType(ElevationProfileChart),
      matching: find.byType(LineChart),
    );
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();
    Offset at(double share) {
      final rect = tester.getRect(chart);
      final left =
          rect.left +
          tester.widget<MetricChart>(find.byType(MetricChart)).leftReservedSize;
      return Offset(left + (rect.right - left) * share, rect.center.dy);
    }

    // A tap a quarter of the way, then a sweep to three quarters.
    await tester.tapAt(at(0.25));
    await tester.pump(const Duration(milliseconds: 400));
    expect(haversineMeters(h.map.routeCursor!, start), closeTo(1000, 20));
    final finger = await tester.startGesture(at(0.4));
    await tester.pump();
    for (final share in <double>[0.5, 0.6, 0.75]) {
      await finger.moveTo(at(share));
      await tester.pump();
    }
    expect(haversineMeters(h.map.routeCursor!, start), closeTo(3000, 20));
    await finger.up();
    await tester.pump(const Duration(seconds: 3));
    expect(haversineMeters(h.map.routeCursor!, start), closeTo(3000, 20));
    // The profile's handle; the weather strip under it shares the cursor.
    final handle = find.descendant(
      of: find.byType(RouteElevationProfile),
      matching: chartCursorHandles,
    );
    expect(handle, findsOneWidget);

    // Two fingers apart: the profile zooms.
    final centre = at(0.5);
    final a = await tester.createGesture();
    final b = await tester.createGesture();
    await a.down(centre - const Offset(50, 0));
    await b.down(centre + const Offset(50, 0));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-10, 0));
      await b.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 400));
    final data = tester.widget<LineChart>(chart).data;
    expect(data.maxX - data.minX, lessThan(3));
    expect(find.text(l10n.chartResetZoomRoute), findsOneWidget);

    // Zoomed, the handle drags the cursor back towards the middle; the
    // profile in the middle of the card, its handle clear of the header.
    await Scrollable.ensureVisible(tester.element(chart), alignment: 0.5);
    await tester.pumpAndSettle();
    final kmPerPixel = (data.maxX - data.minX) / (at(1).dx - at(0).dx);
    final from = haversineMeters(h.map.routeCursor!, start);
    await dragChartCursor(tester, const Offset(-40, 0), handle: handle);
    expect(
      haversineMeters(h.map.routeCursor!, start),
      closeTo(from - 40 * kmPerPixel * 1000, 20),
    );
    expect(tester.widget<LineChart>(chart).data.minX, data.minX);

    // A finger dragged down the profile, a little at a time, moves the
    // card under it rather than the profile.
    final before = tester.getRect(chart).top;
    final drag = await tester.startGesture(at(0.5));
    for (var i = 0; i < 12; i++) {
      await drag.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(chart).top, greaterThan(before + 50));
    expect(tester.widget<LineChart>(chart).data.minX, data.minX);
    expect(h.map.routeCursor, isNotNull);
    await unmountApp(tester);
    expect(h.map.routeCursor, isNull);
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

  group('sharing', () {
    const config = AppConfig(
      apiUrl: 'https://relay.test',
      stravaClientId: '1234',
      rwgpsClientId: 'abcd',
    );

    List<Override> overrides(
      List<Uri> opened, {
      Map<IntegrationService, ConnectedAccount> accounts = const {},
    }) => [
      appConfigProvider.overrideWithValue(config),
      secureKeyValueStoreProvider.overrideWithValue(
        InMemorySecureKeyValueStore(<String, String>{
          for (final entry in accounts.entries)
            ConnectedAccountsRepository.keyFor(entry.key): entry.value.encode(),
        }),
      ),
      linkOpenerProvider.overrideWithValue((url) async {
        opened.add(url);
        return true;
      }),
    ];

    Future<void> openCard(WidgetTester tester) async {
      await tester.ensureVisible(find.text(l10n.shareLinkAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.shareLinkAction));
      await tester.pumpAndSettle();
      expect(find.text(l10n.shareRouteTitle), findsOneWidget);
    }

    testWidgets('one Share button; with Ride with GPS connected its card '
        'offers Send', (tester) async {
      final h = PlannerHarness();
      final saved = await _seed(h);
      await pumpApp(
        tester,
        initialLocation: routeDetailLocation(saved.id),
        harness: h,
        extraOverrides: overrides(
          <Uri>[],
          accounts: const {
            IntegrationService.rwgps: ConnectedAccount(
              service: IntegrationService.rwgps,
              accessToken: 'rw',
            ),
          },
        ),
      );
      await tester.pumpAndSettle();

      // The separate Send and Share link buttons are one Share button now.
      expect(find.text(l10n.shareLinkAction), findsOneWidget);
      await openCard(tester);
      expect(find.text(l10n.shareRwgpsRouteBody), findsOneWidget);
      expect(find.text(l10n.shareSend), findsOneWidget);
      expect(find.text(l10n.shareStravaRouteBody), findsOneWidget);
      expect(find.text(l10n.shareLinkRowBody), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('without Ride with GPS connected the card leads to Settings', (
      tester,
    ) async {
      final h = PlannerHarness();
      final saved = await _seed(h);
      await pumpApp(
        tester,
        initialLocation: routeDetailLocation(saved.id),
        harness: h,
        extraOverrides: overrides(<Uri>[]),
      );
      await tester.pumpAndSettle();

      await openCard(tester);
      await tester.tap(find.text(l10n.shareConnect));
      await tester.pumpAndSettle();

      expect(find.text(l10n.shareRouteTitle), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('a route from Strava credits Strava, links back to it, and '
        'goes to no other service and into no link', (tester) async {
      final h = PlannerHarness();
      final opened = <Uri>[];
      final repository = RouteRepository(h.db.routesDao);
      final saved = await repository.saveImportedRoute(
        name: 'From Strava',
        points: syntheticRoute().geometry,
        source: RouteSource.strava,
      );
      await repository.markExternal(
        saved.id,
        externalIds: const <String, Object?>{'strava_route_id': '4242'},
      );
      await pumpApp(
        tester,
        initialLocation: routeDetailLocation(saved.id),
        harness: h,
        extraOverrides: overrides(
          opened,
          accounts: const {
            IntegrationService.rwgps: ConnectedAccount(
              service: IntegrationService.rwgps,
              accessToken: 'rw',
            ),
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PoweredByStrava), findsOneWidget);
      await tester.tap(find.text(l10n.rideDetailViewOnStrava));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://www.strava.com/routes/4242')]);

      await openCard(tester);
      expect(find.text(l10n.shareNotForStravaRoutes), findsNWidgets(2));
      expect(find.text(l10n.shareSend), findsNothing);
      expect(find.text(l10n.shareLinkTitle), findsNothing);
      await unmountApp(tester);
    });
  });

  testWidgets('routes from Strava the checks removed are told once', (
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RouteDetailScreen)),
    );

    container.read(stravaRoutesRemovedNoticeProvider.notifier).add(2);
    await tester.pump();

    expect(find.text(l10n.stravaRoutesRemoved(2)), findsOneWidget);
    expect(container.read(stravaRoutesRemovedNoticeProvider), 0);
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

  group('the weather on the way', () {
    Future<PlannerHarness> pumpWeather(
      WidgetTester tester, {
      required PlusAccess access,
    }) async {
      final h = PlannerHarness();
      final route = straightRoute(start: const LatLng(48, 11));
      final saved =
          await RouteRepository(
            h.db.routesDao,
            clock: () => DateTime.utc(2026, 9, 12, 10),
          ).saveImportedRoute(
            name: 'North',
            points: route.geometry,
            source: RouteSource.importedGpx,
          );
      await pumpApp(
        tester,
        initialLocation: routeDetailLocation(saved.id),
        harness: h,
        extraOverrides: [
          relayClientProvider.overrideWithValue(MockRelay().client()),
          plusAccessProvider.overrideWith((ref, feature) => access),
          routeWeatherControllerProvider.overrideWith2(
            (_) => _SavedWeather(saved.id, route),
          ),
        ],
      );
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('with Plus: the section under the profile, and the choice '
        'colours this route on the map', (tester) async {
      final h = await pumpWeather(tester, access: PlusAccess.granted);
      final title = find.text(l10n.weatherTitle.toUpperCase());
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      expect(title, findsOneWidget);
      expect(find.byType(RouteWeatherStrip), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(RouteWeatherStrip)).dy,
        greaterThan(
          tester.getBottomLeft(find.byType(ElevationProfileChart)).dy,
        ),
      );
      expect(find.textContaining(l10n.weatherDry), findsOneWidget);

      // The gradient by default: a flat road, one grey stretch.
      final colours = h.map.calls.where((c) => c.method == 'setRouteColours');
      expect(colours, isNotEmpty);
      expect(
        (colours.last.arguments.single! as List<ColouredSegment>).map(
          (s) => s.colour,
        ),
        [gradientClassColour(GradientClass.flat)],
      );
      expect(find.byType(GradientColourKey), findsOneWidget);

      final wind = find.text(l10n.weatherWind);
      await tester.ensureVisible(wind);
      await tester.pumpAndSettle();
      await tester.tap(wind);
      await tester.pumpAndSettle();
      final windCalls = h.map.calls.where((c) => c.method == 'setRouteWind');
      expect(windCalls, isNotEmpty);
      expect(
        windCalls.last.arguments.single! as List<WindSegment>,
        everyElement(
          isA<WindSegment>().having(
            (s) => s.windClass,
            'class',
            WindClassOnMap.head,
          ),
        ),
      );
      // The wind takes the gradient off.
      expect(
        h.map.calls.where((c) => c.method == 'clearRouteColours'),
        isNotEmpty,
      );
      // Under the strip, and under the choice.
      expect(find.byType(WindColourKey), findsNWidgets(2));
      expect(find.byType(GradientColourKey), findsNothing);

      // A dry ride: the rain takes the wind off and draws nothing.
      final coloured = colours.length;
      await tester.tap(find.text(l10n.weatherRain));
      await tester.pumpAndSettle();
      expect(h.map.calls.last.method, 'clearRouteWind');
      expect(
        h.map.calls.where((c) => c.method == 'setRouteColours'),
        hasLength(coloured),
      );
      expect(find.text(l10n.weatherRainNoneOnRoute), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('the page in the planner\'s order: figures, Open in '
        'planner and the actions, the departure, the colour choice and its '
        'key, the profile, then the surfaces and the weather', (tester) async {
      await pumpWeather(tester, access: PlusAccess.granted);
      // The departure is the only slider, under the actions; the weather
      // section has none of its own.
      expect(find.byType(Slider), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RouteDepartureSlider),
          matching: find.byType(Slider),
        ),
        findsOneWidget,
      );
      final order = [
        find.byType(RouteStatsRow),
        find.widgetWithText(FilledButton, l10n.routeDetailOpenInPlanner),
        find.widgetWithText(ButtonMenu<TrackFormat>, l10n.routeDetailExport),
        find.byType(RouteDepartureSlider),
        find.byType(SegmentedButton<RouteOverlay>),
        find.byType(RouteColourKey),
        find.byType(ElevationProfileChart),
        find.byType(SurfaceSection),
        find.byType(RouteWeatherStrip),
      ];
      for (var i = 1; i < order.length; i++) {
        expect(
          tester.getRect(order[i]).top,
          greaterThanOrEqualTo(tester.getRect(order[i - 1]).bottom),
          reason: '${order[i]} under ${order[i - 1]}',
        );
      }
      // Directly under the actions, and the key right under the choice.
      final actions = tester.getRect(
        find.ancestor(of: order[2], matching: find.byType(Wrap)).first,
      );
      expect(
        tester.getRect(find.byType(RouteDepartureSlider)).top - actions.bottom,
        lessThan(12),
      );
      expect(
        tester.getRect(find.byType(RouteColourKey)).top -
            tester.getRect(find.byType(SegmentedButton<RouteOverlay>)).bottom,
        lessThanOrEqualTo(8),
      );
      await unmountApp(tester);
    });

    testWidgets('the departure slider stands on the time control\'s steps '
        'and sets the step all tabs share', (tester) async {
      await pumpWeather(tester, access: PlusAccess.granted);
      final slider = find.descendant(
        of: find.byType(RouteDepartureSlider),
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(slider, findsOneWidget);
      expect(
        tester.widget<Slider>(slider).divisions,
        weatherRadarOffsets.length - 1,
      );
      final container = ProviderScope.containerOf(tester.element(slider));
      tester.widget<Slider>(slider).onChangeEnd!(
        weatherSliderIndexOf(120).toDouble(),
      );
      await tester.pump();
      expect(container.read(weatherRadarOffsetProvider), 120);
      await unmountApp(tester);
    });

    testWidgets('without Plus: the free forecast, its gusts and chance of '
        'rain locked', (tester) async {
      await pumpWeather(tester, access: PlusAccess.missing);
      // The free forecast is asked for once the route has stood a moment.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      final strip = find.byType(RouteWeatherStrip);
      await tester.ensureVisible(strip);
      await tester.pumpAndSettle();
      expect(tester.widget<RouteWeatherStrip>(strip).weather, isNotNull);
      expect(find.textContaining(l10n.weatherDry), findsOneWidget);
      expect(find.text(l10n.weatherPlusExtrasLocked), findsOneWidget);
      expect(find.text(l10n.plusFeatureWeatherBody), findsNothing);
      await unmountApp(tester);
    });
  });
}

/// The weather along a saved route, as if the relay had answered.
class _SavedWeather extends RouteWeatherController {
  _SavedWeather(this.id, this.line);

  final String id;
  final RouteResult line;

  @override
  AsyncValue<RouteWeatherState?> build(WeatherRoute key) {
    if (key != SavedWeatherRoute(id)) return const AsyncData(null);
    return AsyncData<RouteWeatherState?>(
      weatherAlong(line, earliest: DateTime.utc(2026, 10, 11, 8)),
    );
  }
}
