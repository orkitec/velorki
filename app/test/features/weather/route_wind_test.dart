import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/geo/route_gradient.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/map/testing/fake_map_controller.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/application/planner_map_binding.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/planner_state.dart';
import 'package:velorki/features/map/data/rain_legend.dart';
import 'package:velorki/features/weather/application/route_colouring.dart';
import 'package:velorki/features/weather/application/route_overlay.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/application/route_wind.dart';
import 'package:velorki/features/weather/domain/route_sampling.dart';
import 'package:velorki/features/weather/domain/route_weather_state.dart';
import 'package:velorki/features/weather/presentation/route_weather_strip.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/fakes.dart';
import 'support/weather_fixtures.dart';

final DateTime _departure = DateTime.utc(2026, 10, 11, 8);

/// The weather on [route] heading north: the wind from the north (ahead)
/// on the first [headCells] cells, from the south (behind) after them, and
/// nothing at all for the cells in [missing].
RouteWeatherState _weather(
  RouteResult route, {
  int headCells = 2,
  Set<int> missing = const <int>{},
  double Function(int cell, int hour)? precip,
  int? precipProb = 60,
}) {
  final samples = sampleRoute(route, typicalSpeedKmh: 18);
  final cells = cellsFor(samples);
  final window = requestWindow(
    _departure,
    samples.last.offset,
    sliderSpan: departureSpan,
  );
  final forecast = WeatherForecast(
    cells: [
      for (var c = 0; c < cells.cells.length; c++)
        WeatherCellForecast(
          source: 'metno',
          hours: missing.contains(c)
              ? const <WeatherHour>[]
              : hours(
                  window.from,
                  window.hours,
                  (t, i) => hour(
                    t,
                    windDir: c < headCells ? 0 : 180,
                    precip: precip?.call(c, i) ?? (i.isEven ? 1.5 : 0),
                    precipProb: precipProb,
                  ),
                ),
        ),
    ],
    sources: const [metno],
  );
  return RouteWeatherState.evaluated(
    departure: _departure,
    earliestDeparture: _departure,
    window: window,
    forecast: forecast,
    samples: samples,
    cells: cells,
  );
}

/// The wind on [geometry] as the map draws it.
List<WindSegment> windSegments(
  List<TrackPoint> geometry,
  RouteWeatherState weather,
) => routeColouringFor(
  geometry,
  AsyncData<RouteWeatherState?>(weather),
  RouteOverlay.wind,
).lines.wind;

/// The rain on [geometry] as the map draws it.
List<ColouredSegment> rainSegments(
  List<TrackPoint> geometry,
  RouteWeatherState weather,
) => routeColouringFor(
  geometry,
  AsyncData<RouteWeatherState?>(weather),
  RouteOverlay.rain,
).lines.colours;

/// What the map draws on [geometry] for [overlay].
RouteColourLines lines(
  List<TrackPoint>? geometry,
  AsyncValue<RouteWeatherState?> weather,
  RouteOverlay? overlay,
) => routeColouringFor(geometry, weather, overlay).lines;

void main() {
  final route = straightRoute(lengthM: 12000);

  group('windSegments', () {
    test('splits the route where the wind changes, end to end', () {
      final segments = windSegments(route.geometry, _weather(route));
      expect(segments.map((s) => s.windClass), [
        WindClassOnMap.head,
        WindClassOnMap.tail,
      ]);
      expect(segments.first.points.first, route.positions.first);
      expect(segments.last.points.last, route.positions.last);
      // The two meet where the one ends and the other begins.
      expect(segments.first.points.last, segments.last.points.first);
    });

    test('leaves a gap where a sample has no weather', () {
      final weather = _weather(route, headCells: 99, missing: {1});
      final segments = windSegments(route.geometry, weather);
      expect(segments.length, greaterThan(1));
      expect(segments.every((s) => s.windClass == WindClassOnMap.head), isTrue);
      expect(segments.first.points.last, isNot(segments[1].points.first));
    });

    test('draws nothing on a route the weather is not for', () {
      final other = straightRoute(lengthM: 8000);
      expect(windSegments(other.geometry, _weather(route)), isEmpty);
    });
  });

  group('rainSegments', () {
    test('colours the wet stretches in the rain map\'s colours and leaves '
        'the dry ones', () {
      // No rain on the first two cells, 0.5 mm/h then 4 mm/h after.
      final weather = _weather(
        route,
        precipProb: null,
        precip: (c, _) => c < 2 ? 0 : (c < 4 ? 0.5 : 4),
      );
      final segments = rainSegments(route.geometry, weather);
      expect(segments.map((s) => s.colour), [
        rainClassColour(dwdRadarClassOf(0.5)),
        rainClassColour(dwdRadarClassOf(4)),
      ]);
      // The DWD radar's own colours: 0.4–1 mm dark green, 3–5 mm yellow-green.
      expect(segments.first.colour, 0x019934);
      expect(segments.last.colour, 0xCCE601);
      expect(segments.last.points.last, route.positions.last);
      // The dry start is not drawn.
      expect(segments.first.points.first, isNot(route.positions.first));
    });

    test('a few hundredths of a mm are no rain; a likely shower is the '
        'lightest class', () {
      final drizzle = _weather(route, precipProb: null, precip: (_, _) => 0.1);
      expect(rainSegments(route.geometry, drizzle), isEmpty);
      final likely = _weather(route, precipProb: 70, precip: (_, _) => 0);
      expect(rainSegments(route.geometry, likely).map((s) => s.colour), [
        rainClassColour(0),
      ]);
    });

    test('the strengths span the legend, lightest first', () {
      final all = [
        for (final strength in RainStrength.values)
          ...rainStrengthClasses(strength),
      ];
      expect(all, List<int>.generate(dwdRadarLegend.classCount, (k) => k));
      expect(rainClassColour(0), 0x33FFFF);
    });
  });

  group('routeColouringFor', () {
    final data = AsyncData<RouteWeatherState?>(_weather(route));
    test('only with a choice and a forecast for the route', () {
      final line = route.geometry;
      expect(lines(line, data, RouteOverlay.wind).wind, isNotEmpty);
      expect(lines(line, data, RouteOverlay.wind).colours, isEmpty);
      expect(lines(line, data, RouteOverlay.rain).colours, isNotEmpty);
      expect(lines(line, data, RouteOverlay.rain).wind, isEmpty);
      expect(lines(line, data, null), RouteColourLines.none);
      expect(lines(null, data, RouteOverlay.wind), RouteColourLines.none);
      expect(
        lines(
          line,
          const AsyncLoading<RouteWeatherState?>(),
          RouteOverlay.wind,
        ),
        RouteColourLines.none,
      );
      expect(
        lines(
          line,
          const AsyncData<RouteWeatherState?>(null),
          RouteOverlay.rain,
        ),
        RouteColourLines.none,
      );
    });
  });

  group('the gradient', () {
    test('needs no weather and runs the whole route', () {
      final drawn = lines(
        route.geometry,
        const AsyncLoading<RouteWeatherState?>(),
        RouteOverlay.gradient,
      );
      expect(drawn.wind, isEmpty);
      expect(drawn.colours.map((s) => s.colour), [
        gradientClassColour(GradientClass.flat),
      ]);
      expect(drawn.colours.single.points.first, route.positions.first);
      expect(drawn.colours.single.points.last, route.positions.last);
    });

    test('changes colour where the road starts to climb', () {
      // Flat for 2 km, then 8 % up for 2 km.
      final geometry = <TrackPoint>[
        for (var d = 0.0; d <= 4000; d += 50)
          TrackPoint(
            destinationPoint(const LatLng(50, 8), 0, d),
            ele: 100 + (d > 2000 ? (d - 2000) * 0.08 : 0),
          ),
      ];
      final colouring = routeColouringFor(
        geometry,
        const AsyncData<RouteWeatherState?>(null),
        RouteOverlay.gradient,
      );
      // The few metres where the window straddles the corner and reads a
      // moderate climb are folded into a neighbour.
      expect(colouring.colours.map((r) => r.key), [
        gradientClassColour(GradientClass.flat),
        gradientClassColour(GradientClass.steep),
      ]);
      expect(colouring.colours.last.endM, closeTo(4000, 1));
      expect(colouring.colours[1].startM, closeTo(2000, 50));
      // The map has the same stretches, end to end.
      expect(colouring.lines.colours, hasLength(2));
      expect(
        colouring.lines.colours.first.points.last,
        colouring.lines.colours[1].points.first,
      );
    });

    test('a route without heights has no gradient', () {
      final bare = straightRoute(ele: null);
      expect(
        lines(
          bare.geometry,
          const AsyncData<RouteWeatherState?>(null),
          RouteOverlay.gradient,
        ),
        RouteColourLines.none,
      );
    });
  });

  group('PlannerMapBinding', () {
    late ProviderContainer container;
    late FakeMapController map;
    late PlannerMapBinding binding;
    RouteOverlay? overlay;
    RouteResult? shown;
    AsyncValue<RouteWeatherState?> weather = const AsyncData(null);

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          routingBackendProvider.overrideWithValue(FakeRoutingBackend()),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      map = FakeMapController();
      overlay = null;
      shown = route;
      weather = AsyncData<RouteWeatherState?>(_weather(route));
      binding =
          PlannerMapBinding(
              map: map,
              planner: container.read(plannerControllerProvider.notifier),
            )
            ..routeColours = () =>
                routeColouringFor(shown?.geometry, weather, overlay).lines;
      binding.attach();
    });

    test('draws the wind only while it is chosen', () async {
      await binding.sync(const PlannerState());
      expect(map.routeWind, isEmpty);
      expect(map.routeWindCalls, isEmpty);
      expect(map.routeColourCalls, isEmpty);

      overlay = RouteOverlay.wind;
      await binding.syncColours();
      expect(map.routeWind.map((s) => s.windClass), [
        WindClassOnMap.head,
        WindClassOnMap.tail,
      ]);

      // Unchanged: not written again.
      await binding.syncColours();
      expect(map.routeWindCalls, hasLength(1));

      overlay = null;
      await binding.syncColours();
      expect(map.routeWind, isEmpty);
      expect(map.routeColourCalls, isEmpty);
    });

    test(
      'the choice moves between the wind and the rain, and colouring off takes '
      'either off',
      () async {
        overlay = RouteOverlay.wind;
        await binding.syncColours();
        expect(map.routeWind, isNotEmpty);
        expect(map.routeColours, isEmpty);

        overlay = RouteOverlay.rain;
        await binding.syncColours();
        expect(map.routeWind, isEmpty);
        expect(map.routeColours, isNotEmpty);

        overlay = null;
        await binding.syncColours();
        expect(map.routeWind, isEmpty);
        expect(map.routeColours, isEmpty);
        expect(map.routeColourCalls.last, isEmpty);
      },
    );

    test('takes the weather off when the route changes', () async {
      overlay = RouteOverlay.rain;
      await binding.syncColours();
      expect(map.routeColours, isNotEmpty);

      // A new route: its weather is on its way.
      shown = straightRoute(lengthM: 8000);
      weather = const AsyncLoading<RouteWeatherState?>();
      await binding.sync(const PlannerState());
      expect(map.routeColours, isEmpty);
    });

    test('draws the gradient through the coloured stretches, and colouring off '
        'takes it off', () async {
      overlay = RouteOverlay.gradient;
      await binding.syncColours();
      expect(map.routeWind, isEmpty);
      expect(map.routeColours.map((s) => s.colour), [
        gradientClassColour(GradientClass.flat),
      ]);

      overlay = null;
      await binding.syncColours();
      expect(map.routeColours, isEmpty);
    });

    test('a cleared binding takes the weather with it', () async {
      overlay = RouteOverlay.wind;
      await binding.syncColours();
      await binding.clear();
      expect(map.routeWind, isEmpty);
    });
  });

  testWidgets('the strip paints gaps and the placeholder without trouble', (
    tester,
  ) async {
    final weather = _weather(route, missing: {0, 2});
    for (final data in [weather.weather, null]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: RouteWeatherStrip(
                weather: data,
                semanticsLabel: 'weather',
                maxTempLabel: '13 °C',
                minTempLabel: '12 °C',
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
    expect(weather.weather.weather.where((w) => w == null), isNotEmpty);
  });
}
