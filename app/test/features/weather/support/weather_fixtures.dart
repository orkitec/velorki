import 'dart:typed_data';

import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki/features/map/domain/wind_field.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart'
    show departureSpan;
import 'package:velorki/features/weather/data/dwd_route_forecast.dart';
import 'package:velorki/features/weather/domain/route_sampling.dart';
import 'package:velorki/features/weather/domain/route_weather_state.dart';

/// A route from [start] straight along [bearingDeg] for [lengthM] metres,
/// a point every [stepM], with [times] when given (seconds per point).
RouteResult straightRoute({
  LatLng start = const LatLng(50, 8),
  double bearingDeg = 0,
  double lengthM = 10000,
  double stepM = 500,
  double? ele = 120,
  List<double> Function(int points)? times,
}) {
  final geometry = <TrackPoint>[];
  for (var d = 0.0; d <= lengthM + 1e-6; d += stepM) {
    geometry.add(TrackPoint(destinationPoint(start, bearingDeg, d), ele: ele));
  }
  return RouteResult(
    geometry: geometry,
    lengthM: lengthM,
    ascentM: 0,
    descentM: 0,
    messages: const [],
    raw: const {},
    times: times?.call(geometry.length) ?? const <double>[],
  );
}

/// An hour of weather with everything but [t] defaulted.
WeatherHour hour(
  DateTime t, {
  double temp = 12,
  double wind = 5,
  int windDir = 0,
  double? gust,
  double precip = 0,
  int? precipProb,
  int? cloud,
}) => WeatherHour(
  t: t,
  temp: temp,
  wind: wind,
  windDir: windDir,
  gust: gust,
  precip: precip,
  precipProb: precipProb,
  cloud: cloud,
);

/// [count] hours from [from], each made by [at] from its index.
List<WeatherHour> hours(
  DateTime from,
  int count, [
  WeatherHour Function(DateTime t, int i)? at,
]) => [
  for (var i = 0; i < count; i++)
    (at ?? (t, _) => hour(t))(from.add(Duration(hours: i)), i),
];

/// The MET Norway source as the relay names it.
const WeatherSource metno = WeatherSource(
  id: 'metno',
  name: 'MET Norway',
  url: 'https://www.met.no/en',
  licence: 'Weather data from MET Norway, CC BY 4.0 and NLOD 2.0.',
);

/// The same [hours] for each of [cells] cells, from MET Norway.
WeatherForecast uniformForecast(int cells, List<WeatherHour> hours) =>
    WeatherForecast(
      cells: [
        for (var i = 0; i < cells; i++)
          WeatherCellForecast(source: 'metno', hours: hours),
      ],
      sources: const [metno],
    );

/// A forecast along [route] for a departure at [earliest]: 12 °C rising by
/// a degree an hour, a breeze from the north, and rain from 14:00 UTC.
RouteWeatherState weatherAlong(
  RouteResult route, {
  required DateTime earliest,
}) {
  final samples = sampleRoute(route, typicalSpeedKmh: 18);
  final cells = cellsFor(samples);
  final window = requestWindow(
    earliest,
    samples.last.offset,
    sliderSpan: departureSpan,
  );
  return RouteWeatherState.evaluated(
    departure: earliest,
    earliestDeparture: earliest,
    window: window,
    forecast: uniformForecast(
      cells.cells.length,
      hours(
        window.from,
        window.hours,
        (t, i) => hour(t, temp: 12.0 + i, precip: t.hour >= 14 ? 2 : 0),
      ),
    ),
    samples: samples,
    cells: cells,
  );
}

/// The free forecast's service, answering every grid with the same values
/// everywhere: a wind of [u] east and [v] north (from the north by
/// default, a headwind on a route north), [rain] mm (or [rainAt] the grid's
/// hour) and [temp] °C, or nothing at all while [down].
class FakeDwdClient implements DwdForecastClient {
  /// Creates the service.
  FakeDwdClient({
    this.u = 0,
    this.v = -5,
    this.rain = 0,
    this.rainAt,
    this.temp = 12,
    this.down = false,
    this.missing,
  });

  final double u;
  final double v;
  final double rain;

  /// ICON-EU's rain of the hour up to the time asked for, in place of
  /// [rain].
  final double Function(DateTime time)? rainAt;

  /// The temperature 2 m up, °C.
  final double temp;
  final bool down;

  /// The hours the service has nothing for, if any.
  final bool Function(DateTime time)? missing;

  /// The grids asked for: coverage and hour.
  final List<(String, DateTime)> requests = <(String, DateTime)>[];

  @override
  Future<DateTime?> newestRun(String coverageId) async =>
      down ? null : DateTime.utc(2026, 10, 11);

  @override
  Future<WcsGrid?> grid(
    String coverageId,
    BoundingBox box,
    DateTime time,
    DateTime run, {
    int bands = 1,
  }) async {
    requests.add((coverageId, time));
    if (down || (missing?.call(time) ?? false)) return null;
    return _loaded[_key(coverageId, box, time, run)] = _gridOf(
      coverageId,
      box,
      time,
      run,
      bands,
    );
  }

  /// The grids answered, as the real client keeps them.
  final Map<String, WcsGrid> _loaded = <String, WcsGrid>{};

  static String _key(
    String coverageId,
    BoundingBox box,
    DateTime time,
    DateTime run,
  ) =>
      '$coverageId|${box.south},${box.west},${box.north},${box.east}|'
      '${time.toIso8601String()}|${run.toIso8601String()}';

  @override
  DateTime? knownRun(String coverageId) =>
      down ? null : DateTime.utc(2026, 10, 11);

  @override
  WcsGrid? loadedGrid(
    String coverageId,
    BoundingBox box,
    DateTime time,
    DateTime run,
  ) => _loaded[_key(coverageId, box, time, run)];

  WcsGrid _gridOf(
    String coverageId,
    BoundingBox box,
    DateTime time,
    DateTime run,
    int bands,
  ) {
    // The global rain is a sum from the run's start: [rain] an hour.
    final value = switch (coverageId) {
      dwdRainGlobalCoverage => rain * time.difference(run).inHours,
      dwdTemperatureCoverage => temp,
      _ => rainAt?.call(time) ?? rain,
    };
    Float32List filled(double x) => Float32List(4)..fillRange(0, 4, x);
    return WcsGrid(
      lon0: box.west,
      lat0: box.north,
      lonStep: box.east - box.west,
      latStep: box.south - box.north,
      columns: 2,
      rows: 2,
      bands: bands == 2
          ? <Float32List>[filled(u), filled(v)]
          : <Float32List>[filled(value)],
    );
  }
}
