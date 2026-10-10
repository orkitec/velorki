import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

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
