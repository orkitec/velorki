import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_api/velorki_api.dart'
    show WeatherForecast, WeatherSource;
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../map/data/weather_map_preferences.dart';
import '../../map/domain/weather_map.dart' show weatherRadarOffsets;
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

/// The line each free forecast was worked out for, so that while the next
/// one for the same line loads (another departure, another speed) the
/// route keeps its colours ([routeColourWeatherProvider]).
final Expando<List<TrackPoint>> freeForecastGeometry =
    Expando<List<TrackPoint>>('freeForecastGeometry');

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

/// [route]'s line as the free forecast samples it, at its profile's
/// speed; `null` while there is no route.
@riverpod
List<RouteWeatherSample>? freeRouteSamples(Ref ref, WeatherRoute route) {
  final geometry = ref.watch(weatherRouteGeometryProvider(route));
  final speed = ref.watch(weatherRouteSpeedProvider(route));
  if (geometry == null || geometry.length < 2 || speed == null) return null;
  final positions = geometry.map((p) => p.pos).toList(growable: false);
  return sampleRoute(
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
}

/// The wind and the rain along [route] from the free forecast (the DWD's
/// ICON models, see `dwd_route_forecast.dart`), for a ride leaving when the
/// time control says ([weatherRadarOffsetProvider], see [departureAfter]):
/// each sample takes the hour the rider gets there. In the shape the
/// relay's forecast has, so the route is coloured from either the same way.
/// Without temperatures, gusts or rain chances.
///
/// `null` while there is no route. Asked for [weatherDebounce] after the
/// route or the control stops changing; the control is set only when its
/// slider is let go (while it is dragged the route is coloured from the
/// grids already loaded, [freeWeatherFromLoaded]). The client keeps the
/// grids, so a grid fetched ahead ([FreeForecastPrefetch]) or before is
/// not asked for again. Fails with [FreeForecastUnavailable] when no
/// sample has weather, and is not retried by itself: the next change of
/// the route asks again, and so does picking the wind or the rain again,
/// as nothing watches it in between.
@Riverpod(retry: _noRetry)
Future<RouteWeatherState?> freeRouteWeather(Ref ref, WeatherRoute route) async {
  final geometry = ref.watch(weatherRouteGeometryProvider(route));
  final samples = ref.watch(freeRouteSamplesProvider(route));
  final offset = ref.watch(weatherRadarOffsetProvider);
  if (geometry == null || samples == null) return null;
  // A dragged waypoint routes many times a second.
  await Future<void>.delayed(weatherDebounce);
  if (!ref.mounted) return null;
  final client = ref.read(dwdForecastClientProvider);
  final now = ref.read(weatherClockProvider)();
  final departure = departureAfter(now, offset);
  final plan = planFreeForecast(samples, departure, europe: dwdRainEuArea);
  final (windRun, rainRun) = await (
    client.newestRun(dwdWindCoverage),
    client.newestRun(_rainCoverage(plan)),
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
    fetch(_rainCoverage(plan), plan.rainGrids, rainRun, 1),
  ).wait;
  if (!ref.mounted) return null;
  final state = _freeState(
    samples,
    plan,
    departure,
    now,
    wind: (hour) => wind[hour],
    rain: (hour) => rain[hour],
  );
  if (state == null) throw const FreeForecastUnavailable();
  freeForecastGeometry[state] = geometry;
  return state;
}

String _rainCoverage(FreeForecastPlan plan) =>
    plan.rain == FreeRain.europe ? dwdRainEuCoverage : dwdRainGlobalCoverage;

/// [plan]'s weather for [samples] leaving at [departure], from the grids
/// [wind] and [rain] give; `null` when no sample has weather.
RouteWeatherState? _freeState(
  List<RouteWeatherSample> samples,
  FreeForecastPlan plan,
  DateTime departure,
  DateTime now, {
  required WcsGrid? Function(DateTime hour) wind,
  required WcsGrid? Function(DateTime hour) rain,
}) {
  final weather = freeSampleWeather(
    samples,
    plan,
    departure,
    wind: wind,
    rain: rain,
  );
  if (!weather.any((w) => w != null)) return null;
  final routeWeather = RouteWeather(
    departure: departure,
    samples: samples,
    weather: List<SampleWeather?>.unmodifiable(weather),
    sources: const <WeatherSource>[dwdIconSource],
  );
  return RouteWeatherState(
    departure: departure,
    earliestDeparture: departureAfter(now, 0),
    window: (from: floorToUtcHour(departure), hours: plan.wind.length),
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

/// The free forecast for [samples] leaving [offsetMinutes] after [now],
/// worked out at once from the grids [client] has already loaded, for the
/// route's colours while the time control is dragged; `null` while any
/// grid it needs has not come (the route then keeps the colours it has).
RouteWeatherState? freeWeatherFromLoaded(
  DwdForecastClient client,
  List<RouteWeatherSample> samples,
  DateTime now,
  int offsetMinutes,
) {
  final departure = departureAfter(now, offsetMinutes);
  final plan = planFreeForecast(samples, departure, europe: dwdRainEuArea);
  final rainCoverage = _rainCoverage(plan);
  final windRun = client.knownRun(dwdWindCoverage);
  final rainRun = client.knownRun(rainCoverage);
  if (windRun == null || rainRun == null) return null;
  final wind = <DateTime, WcsGrid>{};
  for (final e in plan.wind.entries) {
    final grid = client.loadedGrid(dwdWindCoverage, e.value, e.key, windRun);
    if (grid == null) return null;
    wind[e.key] = grid;
  }
  final rain = <DateTime, WcsGrid>{};
  for (final e in plan.rainGrids.entries) {
    final grid = client.loadedGrid(rainCoverage, e.value, e.key, rainRun);
    if (grid == null) return null;
    rain[e.key] = grid;
  }
  return _freeState(
    samples,
    plan,
    departure,
    now,
    wind: (hour) => wind[hour],
    rain: (hour) => rain[hour],
  );
}

/// The free forecast's grids fetched ahead, for every hour the time
/// control can reach plus the ride, while [route] is coloured by the wind
/// or the rain from it (watched by `routeColourWeatherProvider`), so a drag
/// of the control colours the route from them without a request per step.
/// [weatherDebounce] after the route stops changing; the hours nearest now
/// first; the client runs a few at once ([dwdMaxConcurrent]) and keeps
/// them. Counts the grids that have come, so what colours from them is
/// worked out again as they do.
@riverpod
class FreeForecastPrefetch extends _$FreeForecastPrefetch {
  @override
  int build(WeatherRoute route) {
    final samples = ref.watch(freeRouteSamplesProvider(route));
    if (samples == null) return 0;
    var live = true;
    final timer = Timer(
      weatherDebounce,
      () => unawaited(_fetch(samples, () => live)),
    );
    ref.onDispose(() {
      live = false;
      timer.cancel();
    });
    return 0;
  }

  Future<void> _fetch(
    List<RouteWeatherSample> samples,
    bool Function() live,
  ) async {
    final client = ref.read(dwdForecastClientProvider);
    final now = ref.read(weatherClockProvider)();
    final wind = <DateTime, BoundingBox>{};
    final rain = <DateTime, BoundingBox>{};
    String? rainCoverage;
    for (final step in weatherRadarOffsets) {
      final plan = planFreeForecast(
        samples,
        departureAfter(now, step),
        europe: dwdRainEuArea,
      );
      rainCoverage = _rainCoverage(plan);
      wind.addAll(plan.wind);
      rain.addAll(plan.rainGrids);
    }
    final (windRun, rainRun) = await (
      client.newestRun(dwdWindCoverage),
      client.newestRun(rainCoverage!),
    ).wait;
    if (!live() || windRun == null || rainRun == null) return;
    // In time order, the steps nearest now first.
    final hours = <DateTime>{...wind.keys, ...rain.keys}.toList()..sort();
    await Future.wait([
      for (final hour in hours)
        ...[
          if (wind[hour] case final box?)
            client.grid(dwdWindCoverage, box, hour, windRun, bands: 2),
          if (rain[hour] case final box?)
            client.grid(rainCoverage, box, hour, rainRun),
        ].map(
          (f) => f.then((_) {
            if (live()) state++;
          }),
        ),
    ]);
  }
}
