import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_api/velorki_api.dart'
    show WeatherForecast, WeatherSource;
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../map/domain/wind_field.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/data/route_repository.dart';
import '../data/dwd_route_forecast.dart';
import '../domain/free_route_forecast.dart';
import '../domain/route_sampling.dart';
import '../domain/route_weather.dart';
import '../domain/route_weather_digest.dart';
import '../domain/route_weather_state.dart';
import 'route_colouring.dart';
import 'route_weather_controller.dart';

part 'free_route_weather.g.dart';

/// The attribution the free forecast is shown with.
const String dwdAttribution = 'Deutscher Wetterdienst (CC BY 4.0)';

/// The DWD as the source of the free forecast, for the attribution.
const WeatherSource dwdIconSource = WeatherSource(
  id: 'dwd_icon',
  name: 'Deutscher Wetterdienst',
  url: 'https://www.dwd.de',
  licence: dwdAttribution,
);

/// The free forecast could not be had: the service did not answer, or
/// answered with nothing for the route.
class FreeForecastUnavailable implements Exception {
  /// Creates the failure.
  const FreeForecastUnavailable();

  @override
  String toString() => 'FreeForecastUnavailable';
}

Duration? _noRetry(int retryCount, Object error) => null;

/// The profile's speed the ride time along [route] is worked out with.
@riverpod
double? weatherRouteSpeed(Ref ref, WeatherRoute route) => switch (route) {
  PlannerWeatherRoute() => ref.watch(
    plannerControllerProvider.select((s) => s.options.profile.typicalSpeedKmh),
  ),
  SavedWeatherRoute(:final id) => ref.watch(
    savedRouteProvider(id).select((r) => r.value?.profile.typicalSpeedKmh),
  ),
};

/// The wind and the rain along [route] from the free forecast (the DWD's
/// ICON models, see `dwd_route_forecast.dart`), for a ride leaving now,
/// in the shape the relay's forecast has, so the route is coloured from
/// either the same way. Without temperatures, gusts or rain chances.
///
/// `null` while there is no route. Asked for [weatherDebounce] after the
/// route stops changing; the grids are kept by the client, so going back
/// to a route, or the next rebuild, asks nothing again. Fails with
/// [FreeForecastUnavailable] when no sample has weather, and is not
/// retried by itself: the next change of the route asks again, and so does
/// picking the wind or the rain again, as nothing watches it in between.
@Riverpod(retry: _noRetry)
Future<RouteWeatherState?> freeRouteWeather(Ref ref, WeatherRoute route) async {
  final geometry = ref.watch(weatherRouteGeometryProvider(route));
  final speed = ref.watch(weatherRouteSpeedProvider(route));
  if (geometry == null || geometry.length < 2 || speed == null) return null;
  // A dragged waypoint routes many times a second.
  await Future<void>.delayed(weatherDebounce);
  if (!ref.mounted) return null;
  final client = ref.read(dwdForecastClientProvider);
  final now = ref.read(weatherClockProvider)().toUtc();
  final positions = geometry.map((p) => p.pos).toList(growable: false);
  final samples = sampleRoute(
    RouteResult(
      geometry: geometry,
      lengthM: cumulativeDistancesMeters(positions).last,
      ascentM: 0,
      descentM: 0,
      messages: const <SegmentMessage>[],
      raw: const <String, dynamic>{},
    ),
    typicalSpeedKmh: speed,
  );
  final plan = planFreeForecast(samples, now, europe: dwdRainEuArea);
  final rainCoverage = plan.rain == FreeRain.europe
      ? dwdRainEuCoverage
      : dwdRainGlobalCoverage;
  final (windRun, rainRun) = await (
    client.newestRun(dwdWindCoverage),
    client.newestRun(rainCoverage),
  ).wait;
  if (windRun == null || rainRun == null) {
    throw const FreeForecastUnavailable();
  }
  Future<Map<DateTime, WcsGrid?>> fetch(
    String coverage,
    Map<DateTime, BoundingBox> boxes,
    DateTime run,
    int bands,
  ) async {
    final entries = boxes.entries.toList(growable: false);
    final grids = await Future.wait([
      for (final e in entries)
        client.grid(coverage, e.value, e.key, run, bands: bands),
    ]);
    return {for (final (i, e) in entries.indexed) e.key: grids[i]};
  }

  final (wind, rain) = await (
    fetch(dwdWindCoverage, plan.wind, windRun, 2),
    fetch(rainCoverage, plan.rainGrids, rainRun, 1),
  ).wait;
  if (!ref.mounted) return null;
  final weather = freeSampleWeather(
    samples,
    plan,
    now,
    wind: (hour) => wind[hour],
    rain: (hour) => rain[hour],
  );
  if (!weather.any((w) => w != null)) throw const FreeForecastUnavailable();
  final routeWeather = RouteWeather(
    departure: now,
    samples: samples,
    weather: List<SampleWeather?>.unmodifiable(weather),
    sources: const <WeatherSource>[dwdIconSource],
  );
  return RouteWeatherState(
    departure: now,
    earliestDeparture: now,
    window: (from: floorToUtcHour(now), hours: plan.wind.length),
    forecast: const WeatherForecast(
      cells: [],
      sources: <WeatherSource>[dwdIconSource],
    ),
    samples: samples,
    cells: const WeatherCells([], []),
    weather: routeWeather,
    summary: RouteWeatherSummary.of(routeWeather),
    digest: RouteWeatherDigest.of(routeWeather),
  );
}
