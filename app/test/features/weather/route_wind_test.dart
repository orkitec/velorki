import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/map/testing/fake_map_controller.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/application/planner_map_binding.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/planner_state.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/application/route_wind.dart';
import 'package:velorki/features/weather/domain/route_sampling.dart';
import 'package:velorki/features/weather/domain/route_weather_state.dart';
import 'package:velorki/features/weather/presentation/route_weather_strip.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

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
                    precip: i.isEven ? 1.5 : 0,
                    precipProb: 60,
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

void main() {
  final route = straightRoute(lengthM: 12000);

  group('windSegments', () {
    test('splits the route where the wind changes, end to end', () {
      final segments = windSegments(route, _weather(route));
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
      final segments = windSegments(route, weather);
      expect(segments.length, greaterThan(1));
      expect(segments.every((s) => s.windClass == WindClassOnMap.head), isTrue);
      expect(segments.first.points.last, isNot(segments[1].points.first));
    });

    test('draws nothing on a route the weather is not for', () {
      final other = straightRoute(lengthM: 8000);
      expect(windSegments(other, _weather(route)), isEmpty);
    });
  });

  group('routeWindFor', () {
    final data = AsyncData<RouteWeatherState?>(_weather(route));
    test('only with the switch on and a forecast for the route', () {
      expect(routeWindFor(route, data, on: true), isNotEmpty);
      expect(routeWindFor(route, data, on: false), isEmpty);
      expect(routeWindFor(null, data, on: true), isEmpty);
      expect(
        routeWindFor(route, const AsyncLoading<RouteWeatherState?>(), on: true),
        isEmpty,
      );
      expect(
        routeWindFor(
          route,
          const AsyncData<RouteWeatherState?>(null),
          on: true,
        ),
        isEmpty,
      );
    });
  });

  group('PlannerMapBinding', () {
    late ProviderContainer container;
    late FakeMapController map;
    late PlannerMapBinding binding;
    var on = false;
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
      on = false;
      shown = route;
      weather = AsyncData<RouteWeatherState?>(_weather(route));
      binding = PlannerMapBinding(
        map: map,
        planner: container.read(plannerControllerProvider.notifier),
      )..routeWind = () => routeWindFor(shown, weather, on: on);
      binding.attach();
    });

    test('draws the wind only with the switch on', () async {
      await binding.sync(const PlannerState());
      expect(map.routeWind, isEmpty);
      expect(map.routeWindCalls, isEmpty);

      on = true;
      await binding.syncWind();
      expect(map.routeWind.map((s) => s.windClass), [
        WindClassOnMap.head,
        WindClassOnMap.tail,
      ]);

      // Unchanged: not written again.
      await binding.syncWind();
      expect(map.routeWindCalls, hasLength(1));

      on = false;
      await binding.syncWind();
      expect(map.routeWind, isEmpty);
    });

    test('takes the wind off when the route changes', () async {
      on = true;
      await binding.syncWind();
      expect(map.routeWind, isNotEmpty);

      // A new route: its weather is on its way.
      shown = straightRoute(lengthM: 8000);
      weather = const AsyncLoading<RouteWeatherState?>();
      await binding.sync(const PlannerState());
      expect(map.routeWind, isEmpty);
    });

    test('a cleared binding takes the wind with it', () async {
      on = true;
      await binding.syncWind();
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
