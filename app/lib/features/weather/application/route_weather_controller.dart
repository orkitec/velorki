import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../core/l10n/localized_text.dart';
import '../../../core/l10n/relay_error_text.dart';
import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/domain/route_profile.dart';
import '../domain/route_sampling.dart';
import '../domain/route_weather.dart';
import '../domain/sun.dart';
import '../domain/route_weather_state.dart';

part 'route_weather_controller.g.dart';

final Logger _log = Logger('RouteWeather');

/// How long the route has to stay put before its weather is asked for:
/// a dragged waypoint routes many times a second.
const Duration weatherDebounce = Duration(seconds: 1);

/// How long an answer is reused for the same cells and hours.
const Duration weatherCacheTtl = Duration(minutes: 30);

/// How far past the first departure the rider can move it without another
/// request.
const Duration departureSpan = Duration(hours: 24);

/// The clock the departure and the cache are measured against.
///
/// A provider so tests can wind it forward without waiting.
@Riverpod(keepAlive: true)
DateTime Function() weatherClock(Ref ref) => DateTime.now;

/// Why the weather could not be shown.
enum WeatherFailure {
  /// The rider does not hold Velorki Plus.
  notEntitled,

  /// Too many requests; try again later.
  rateLimited,

  /// The relay or its forecast services failed or could not be reached.
  relay,
}

/// A failure of the weather request, in words the rider reads.
class WeatherProblem implements LocalizedException {
  /// Creates the problem.
  const WeatherProblem(this.failure, this.text, {this.retryAfterS});

  /// What kind of failure it is.
  final WeatherFailure failure;

  /// What the rider reads.
  final LocalizedText text;

  /// How long to wait, from a `rate_limited` error.
  final int? retryAfterS;

  @override
  String describe(AppLocalizations l10n) => text(l10n);

  @override
  String toString() =>
      'WeatherProblem(${failure.name}: ${text(englishLocalizations)})';
}

/// Maps a relay failure onto a [WeatherProblem].
WeatherProblem weatherProblemFor(RelayException e) => WeatherProblem(
  switch (e.error.code) {
    RelayErrorCode.notEntitled => WeatherFailure.notEntitled,
    RelayErrorCode.rateLimited => WeatherFailure.rateLimited,
    _ => WeatherFailure.relay,
  },
  (l10n) => relayErrorText(l10n, e.error),
  retryAfterS: e.error.retryAfterS,
);

/// The weather along the route on the Plan tab, for the time the rider
/// gets to each part of it.
///
/// `data(null)` while there is no route, no relay in this build, or no
/// Velorki Plus: nothing is asked of the relay for a rider without it. A new
/// route is asked about [weatherDebounce] after it stops changing, and only
/// the answer to the latest request is shown. Answers are kept for
/// [weatherCacheTtl], so going back to a route asks nothing. Moving the
/// departure inside the hours fetched is worked out on the phone.
@Riverpod(keepAlive: true)
class RouteWeatherController extends _$RouteWeatherController {
  Timer? _debounce;

  /// Bumped by every change that makes an answer on its way stale.
  int _generation = 0;

  /// The departure the rider picked; `null` for "as soon as possible".
  DateTime? _departure;

  final Map<String, _CachedForecast> _cache = <String, _CachedForecast>{};

  @override
  AsyncValue<RouteWeatherState?> build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _generation++;
    });
    ref.listen(
      plannerControllerProvider.select((s) => s.result),
      (_, _) => _changed(),
    );
    ref.listen(
      plannerControllerProvider.select((s) => s.options.profile),
      (_, _) => _changed(),
    );
    // Bought meanwhile: a "part of Velorki Plus" error is not true any
    // more, and the weather is asked for at once.
    ref.listen(plusFeatureProvider(PlusFeature.weather), (_, _) => _changed());
    ref.listen(relayClientProvider, (_, _) => _changed());
    if (_inputs() == null) return const AsyncData<RouteWeatherState?>(null);
    final generation = _generation;
    _debounce = Timer(weatherDebounce, () => unawaited(_fetch(generation)));
    return const AsyncLoading<RouteWeatherState?>();
  }

  /// The route, its profile and the relay, or `null` when nothing is to be
  /// asked.
  ({RouteResult route, RouteProfile profile, RelayClient relay})? _inputs() {
    final relay = ref.read(relayClientProvider);
    if (relay == null) return null;
    if (!ref.read(plusFeatureProvider(PlusFeature.weather))) return null;
    final planner = ref.read(plannerControllerProvider);
    final route = planner.result;
    if (route == null || route.geometry.length < 2) return null;
    return (route: route, profile: planner.options.profile, relay: relay);
  }

  void _changed() {
    _debounce?.cancel();
    _generation++;
    if (_inputs() == null) {
      state = const AsyncData<RouteWeatherState?>(null);
      return;
    }
    state = const AsyncLoading<RouteWeatherState?>();
    final generation = _generation;
    _debounce = Timer(weatherDebounce, () => unawaited(_fetch(generation)));
  }

  /// Asks for the weather again at once, after a failure.
  void retry() {
    if (_inputs() == null) return;
    _debounce?.cancel();
    final generation = ++_generation;
    state = const AsyncLoading<RouteWeatherState?>();
    unawaited(_fetch(generation));
  }

  /// Moves the departure to [time].
  ///
  /// Inside the hours already fetched this is worked out on the phone;
  /// outside them the forecast is asked for again.
  void setDeparture(DateTime time) {
    _departure = time;
    final current = state.value;
    if (current != null && current.covers(time)) {
      state = AsyncData<RouteWeatherState?>(current.withDeparture(time));
      return;
    }
    if (_inputs() == null) return;
    _debounce?.cancel();
    final generation = ++_generation;
    state = const AsyncLoading<RouteWeatherState?>();
    unawaited(_fetch(generation));
  }

  /// The departure within [departureSpan] of the earliest one with the
  /// least rain and headwind on the way (see [departureScore]); `null`
  /// without a forecast, or when none covers the whole route.
  DateTime? suggestBestDeparture() {
    final current = state.value;
    if (current == null) return null;
    final start = current.samples.first.position;
    final rideTime = current.samples.last.offset;
    return bestDeparture(
      current.forecast,
      current.samples,
      current.cells.sampleToCell,
      from: current.earliestDeparture,
      within: departureSpan,
      current: current.departure,
      // Only rides that start and end in daylight: the calmest hour is often
      // the middle of the night, which is no advice for a rider.
      usable: (departure) =>
          inDaylight(departure, departure.add(rideTime), start.lat, start.lon),
    );
  }

  Future<void> _fetch(int generation) async {
    final inputs = _inputs();
    if (inputs == null || generation != _generation) return;
    final now = ref.read(weatherClockProvider)();
    final earliest = defaultDeparture(now);
    // A departure the rider picked that has passed meanwhile is now.
    final picked = _departure;
    final departure = picked == null || picked.isBefore(earliest)
        ? earliest
        : picked;
    final samples = sampleRoute(
      inputs.route,
      typicalSpeedKmh: inputs.profile.typicalSpeedKmh,
    );
    final cells = cellsFor(samples);
    final window = requestWindow(
      departure,
      samples.last.offset,
      sliderSpan: departureSpan,
    );
    final key = _keyFor(cells.cells, window);

    var forecast = _cached(key, cells.cells, now);
    if (forecast == null) {
      try {
        forecast = await inputs.relay.routeWeather(
          from: window.from,
          hours: window.hours,
          cells: cells.cells,
        );
      } on RelayException catch (e, st) {
        if (!_current(generation)) return;
        state = AsyncError<RouteWeatherState?>(weatherProblemFor(e), st);
        return;
      } on RelayFormatException catch (e, st) {
        _log.warning('the weather answer did not parse', e, st);
        if (!_current(generation)) return;
        state = AsyncError<RouteWeatherState?>(
          WeatherProblem(
            WeatherFailure.relay,
            (l10n) => relayCodeText(l10n, RelayErrorCode.upstreamError),
          ),
          st,
        );
        return;
      }
      if (!_current(generation)) return;
      _cache[key] = _CachedForecast(
        at: ref.read(weatherClockProvider)(),
        cells: <WeatherRequestCell, WeatherCellForecast>{
          for (final (i, cell) in cells.cells.indexed)
            if (i < forecast.cells.length) cell: forecast.cells[i],
        },
        sources: forecast.sources,
      );
    }
    state = AsyncData<RouteWeatherState?>(
      RouteWeatherState.evaluated(
        departure: departure,
        earliestDeparture: earliest,
        window: window,
        forecast: forecast,
        samples: samples,
        cells: cells,
      ),
    );
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  /// The cached answer for [cells] in [key], in [cells]' order, unless it is
  /// older than [weatherCacheTtl].
  WeatherForecast? _cached(
    String key,
    List<WeatherRequestCell> cells,
    DateTime now,
  ) {
    _cache.removeWhere((_, c) => now.difference(c.at) >= weatherCacheTtl);
    final hit = _cache[key];
    if (hit == null) return null;
    return WeatherForecast(
      cells: <WeatherCellForecast>[
        for (final cell in cells)
          hit.cells[cell] ??
              const WeatherCellForecast(source: null, hours: <WeatherHour>[]),
      ],
      sources: hit.sources,
    );
  }

  /// The cache key: the cells in a fixed order, and the hours.
  static String _keyFor(List<WeatherRequestCell> cells, WeatherWindow window) {
    final sorted = [for (final c in cells) '${c.lat},${c.lon},${c.alt}']
      ..sort();
    return '${window.from.toIso8601String()}/${window.hours}|${sorted.join(';')}';
  }
}

/// One answer kept for reuse.
class _CachedForecast {
  const _CachedForecast({
    required this.at,
    required this.cells,
    required this.sources,
  });

  /// When it was fetched.
  final DateTime at;

  /// The forecast of each cell.
  final Map<WeatherRequestCell, WeatherCellForecast> cells;

  /// The sources the answer named.
  final List<WeatherSource> sources;
}
