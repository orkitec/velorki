import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/db/tables/routes.dart';
import 'package:velorki/core/geo/track_surface.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/application/track_surface_service.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/planner/presentation/elevation_profile_chart.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/weather/application/route_overlay.dart';
import 'package:velorki/features/weather/presentation/route_colour_choice.dart';
import 'package:velorki/features/weather/presentation/weather_keys.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../planner/support/fakes.dart';
import '../planner/support/pump.dart';
import 'support/weather_fixtures.dart';

const RoutingDecision _covered = RoutingDecision(
  source: RoutingSource.local,
  requiredTiles: <TileName>[TileName(10, 45)],
  missingTiles: <TileName>[],
);

/// [route] with the router's messages: the first 6 km a paved street, then
/// 1 km of cycleway, then 3 km on a primary road.
RouteResult _withMessages(RouteResult route) => RouteResult(
  geometry: route.geometry,
  lengthM: route.lengthM,
  ascentM: route.ascentM,
  descentM: route.descentM,
  messages: [
    syntheticMessage(route.geometry.first.pos, 6000, const {
      'highway': 'residential',
      'surface': 'asphalt',
    }),
    syntheticMessage(route.geometry.first.pos, 1000, const {
      'highway': 'cycleway',
    }),
    syntheticMessage(route.geometry.last.pos, 3000, const {
      'highway': 'primary',
    }),
  ],
  raw: const <String, dynamic>{},
);

int _rgb(Color colour) => colour.toARGB32() & 0xFFFFFF;

/// The colours of the stretches last drawn on [map].
List<int> _drawn(TestMapController map) {
  final calls = map.calls.where(
    (c) => c.method == 'setRouteColours' || c.method == 'clearRouteColours',
  );
  if (calls.isEmpty || calls.last.method != 'setRouteColours') {
    return const <int>[];
  }
  return [
    for (final s in calls.last.arguments.single! as List<ColouredSegment>)
      s.colour,
  ];
}

List<Color> _bandColours(WidgetTester tester) => [
  for (final b
      in tester
          .widget<ElevationProfileChart>(find.byType(ElevationProfileChart))
          .bands)
    b.colour,
];

Future<void> _chooseSurface(WidgetTester tester) async {
  final segment = find.descendant(
    of: find.byType(SegmentedButton<RouteOverlay>),
    matching: find.text(l10n.surfaceTitle),
  );
  await tester.ensureVisible(segment);
  await tester.pumpAndSettle();
  await tester.tap(segment);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('on the Plan tab the surface colours the route on the map and '
      'under the profile, one colour per stretch by precedence', (
    tester,
  ) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    final route = _withMessages(straightRoute(start: const LatLng(48, 11)));
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)))
        .read(plannerControllerProvider.notifier)
        .loadComputedRoute(
          result: route,
          waypoints: [
            Waypoint(pos: route.geometry.first.pos),
            Waypoint(pos: route.geometry.last.pos),
          ],
          options: RoutingOptions(),
        );
    await tester.pumpAndSettle();
    await _chooseSurface(tester);

    final theme = Theme.of(tester.element(find.byType(RouteColourChoice)));
    final expected = [
      theme.velorki.accent,
      theme.colorScheme.secondary,
      theme.colorScheme.error,
    ];
    expect(_drawn(h.map), expected.map(_rgb));
    expect(_bandColours(tester), expected);
    final bands = tester
        .widget<ElevationProfileChart>(find.byType(ElevationProfileChart))
        .bands;
    expect(bands.first.start, 0);
    expect(bands[1].start, closeTo(6000, 30));
    expect(bands.last.end, closeTo(10000, 30));
    expect(find.byType(SurfaceColourKey), findsOneWidget);
  });

  testWidgets('a change of theme redraws the surface on the map in the new '
      'colours', (tester) async {
    final themed = ValueNotifier<ThemeData>(buildLightTheme());
    addTearDown(themed.dispose);
    final h = await pumpScreen(
      tester,
      ValueListenableBuilder<ThemeData>(
        valueListenable: themed,
        builder: (_, theme, child) => Theme(data: theme, child: child!),
        child: const Scaffold(
          resizeToAvoidBottomInset: false,
          body: PlannerScreen(),
        ),
      ),
    );
    final route = _withMessages(straightRoute(start: const LatLng(48, 11)));
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)))
        .read(plannerControllerProvider.notifier)
        .loadComputedRoute(
          result: route,
          waypoints: [
            Waypoint(pos: route.geometry.first.pos),
            Waypoint(pos: route.geometry.last.pos),
          ],
          options: RoutingOptions(),
        );
    await tester.pumpAndSettle();
    await _chooseSurface(tester);
    expect(_drawn(h.map).first, _rgb(buildLightTheme().velorki.accent));

    final dark = buildDarkTheme(AccentPreset.ember);
    themed.value = dark;
    await tester.pumpAndSettle();
    expect(_drawn(h.map), [
      _rgb(dark.velorki.accent),
      _rgb(dark.colorScheme.secondary),
      _rgb(dark.colorScheme.error),
    ]);
  });

  testWidgets('a route on the Plan tab with no way to match it colours '
      'nothing and says there are no surface figures', (tester) async {
    final h = await pumpScreen(tester, const PlannerScreen());
    final route = straightRoute(start: const LatLng(48, 11));
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)))
        .read(plannerControllerProvider.notifier)
        .loadComputedRoute(
          result: route,
          waypoints: [
            Waypoint(pos: route.geometry.first.pos),
            Waypoint(pos: route.geometry.last.pos),
          ],
          options: RoutingOptions(),
        );
    await tester.pumpAndSettle();
    await _chooseSurface(tester);

    expect(_drawn(h.map), isEmpty);
    expect(_bandColours(tester), isEmpty);
    expect(
      find.descendant(
        of: find.byType(RouteColourKey),
        matching: find.text(l10n.surfaceUnavailable),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a route read from a file is matched against the tiles on its '
      'Library page and coloured by what it lies on', (tester) async {
    final h = PlannerHarness();
    final track = syntheticRoute(withMessages: false).geometry;
    final saved = await RouteRepository(h.db.routesDao).saveImportedRoute(
      name: 'From a file',
      points: track,
      source: RouteSource.importedGpx,
    );
    // The router follows it over 60 % asphalt, then 40 % gravel track.
    final matcher = TrackSurfaceService(
      local: FakeRoutingBackend(
        result: syntheticRoute(lengthM: saved.distanceM),
      ),
      decide: (_) => _covered,
    );
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(saved.id),
      harness: h,
      extraOverrides: [trackSurfaceServiceProvider.overrideWithValue(matcher)],
    );
    await tester.pumpAndSettle();
    await _chooseSurface(tester);

    final theme = Theme.of(tester.element(find.byType(RouteColourChoice)));
    final expected = [theme.velorki.accent, theme.colorScheme.tertiary];
    expect(_bandColours(tester), expected);
    expect(_drawn(h.map), expected.map(_rgb));
    expect(find.byType(SurfaceColourKey), findsOneWidget);
    await unmountApp(tester);
  });
}
