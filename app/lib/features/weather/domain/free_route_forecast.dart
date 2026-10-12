import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

import '../../map/domain/wind_field.dart';
import 'route_sampling.dart';
import 'route_weather.dart';

// The free forecast along a route, put together on the phone from the DWD's
// model grids (see `dwd_route_forecast.dart` for what they are).
//
// Each sample takes the hour its moment falls in, as the wind map takes the
// hour of "Now": the wind at that full hour, and the rain of that hour (the
// hour from it to the next). Both are interpolated bilinearly between the
// four grid points around the sample, as the wind map's arrows are; not in
// time, as the grids are hourly and the route's colours do not need more.
//
// Every grid is asked for over the same box: the route's samples within
// [freeForecastSpan], [freeForecastMargin] around them and snapped out to
// [freeForecastSnap]. So the grid of an hour serves every departure the
// time control can set (they are fetched ahead, and a drag colours the
// route from them), and a route moved a little asks for the same boxes
// again. A long ride asks for its whole extent every hour; the grids are
// small (a few thousand values for a day's ride).

/// How far beyond the samples a grid's box reaches, in degrees: two cells
/// of the coarse model, so every sample has grid points around it.
const double freeForecastMargin = 0.5;

/// The steps a box's edges are put on, in degrees.
const double freeForecastSnap = 0.5;

/// How far ahead the free forecast is asked for: samples later than this
/// after the departure are left without weather.
const Duration freeForecastSpan = Duration(hours: 72);

/// Which rain a route is coloured by for free.
enum FreeRain {
  /// ICON-EU's rain of each hour, at the end of that hour.
  europe,

  /// The global model's rain summed from its run's start: an hour's rain
  /// is the difference of the sums at its start and its end.
  global,
}

/// The requests the free forecast of a route makes: the box of each hour's
/// wind grid and of each rain grid, by the full UTC hour asked for.
class FreeForecastPlan {
  /// Creates the plan.
  const FreeForecastPlan({
    required this.hours,
    required this.rain,
    required this.wind,
    required this.rainGrids,
  });

  /// The full UTC hour each sample takes its weather from; `null` beyond
  /// [freeForecastSpan].
  final List<DateTime?> hours;

  /// Which rain is asked for.
  final FreeRain rain;

  /// The wind grids, by their hour.
  final Map<DateTime, BoundingBox> wind;

  /// The rain grids, by their hour.
  final Map<DateTime, BoundingBox> rainGrids;
}

/// The plan for [samples] of a ride leaving at [departure]: ICON-EU's rain
/// where every sample lies inside [europe], the global model's elsewhere.
FreeForecastPlan planFreeForecast(
  List<RouteWeatherSample> samples,
  DateTime departure, {
  required BoundingBox europe,
}) {
  final last = departure.add(freeForecastSpan);
  final hours = <DateTime?>[
    for (final s in samples)
      departure.add(s.offset).isAfter(last)
          ? null
          : floorToUtcHour(departure.add(s.offset)),
  ];
  final inEurope = samples.every(
    (s) =>
        s.position.lat > europe.south + 0.125 &&
        s.position.lat < europe.north - 0.125 &&
        s.position.lon > europe.west + 0.125 &&
        s.position.lon < europe.east - 0.125,
  );
  final rain = inEurope ? FreeRain.europe : FreeRain.global;
  final windHours = <DateTime>{};
  final rainHours = <DateTime>{};
  final points = <LatLng>[];
  for (final (i, s) in samples.indexed) {
    final h = hours[i];
    if (h == null) continue;
    points.add(s.position);
    windHours.add(h);
    rainHours.add(h.add(const Duration(hours: 1)));
    if (rain == FreeRain.global) rainHours.add(h);
  }
  final box = points.isEmpty ? null : _boxAround(points);
  return FreeForecastPlan(
    hours: List<DateTime?>.unmodifiable(hours),
    rain: rain,
    wind: {for (final h in windHours) h: box!},
    rainGrids: {for (final h in rainHours) h: box!},
  );
}

/// [points] with [freeForecastMargin] around them, snapped out to
/// [freeForecastSnap].
BoundingBox _boxAround(List<LatLng> points) {
  final box = BoundingBox.fromPoints(points);
  double down(double v) =>
      ((v - freeForecastMargin) / freeForecastSnap).floorToDouble() *
      freeForecastSnap;
  double up(double v) =>
      ((v + freeForecastMargin) / freeForecastSnap).ceilToDouble() *
      freeForecastSnap;
  return BoundingBox(
    south: math.max(-90, down(box.south)),
    west: math.max(-180, down(box.west)),
    north: math.min(90, up(box.north)),
    east: math.min(180, up(box.east)),
  );
}

/// The weather [plan] gives each of [samples], from the grids fetched:
/// [wind] the u/v grid of an hour, [rain] the rain grid of an hour, each
/// `null` where it could not be had. A sample is `null` (a gap) where its
/// wind or its rain is missing. The free forecast has no temperature, no
/// gusts and no chance of rain.
List<SampleWeather?> freeSampleWeather(
  List<RouteWeatherSample> samples,
  FreeForecastPlan plan,
  DateTime departure, {
  required WcsGrid? Function(DateTime hour) wind,
  required WcsGrid? Function(DateTime hour) rain,
}) => <SampleWeather?>[
  for (final (i, s) in samples.indexed)
    _sampleWeather(s, plan.hours[i], plan.rain, departure, wind, rain),
];

SampleWeather? _sampleWeather(
  RouteWeatherSample sample,
  DateTime? hour,
  FreeRain kind,
  DateTime departure,
  WcsGrid? Function(DateTime hour) windAt,
  WcsGrid? Function(DateTime hour) rainAt,
) {
  if (hour == null) return null;
  final lat = sample.position.lat;
  final lon = sample.position.lon;
  final uv = windAt(hour)?.sampleBands(lat, lon);
  if (uv == null || uv.length < 2) return null;
  final next = hour.add(const Duration(hours: 1));
  final double precip;
  switch (kind) {
    case FreeRain.europe:
      final value = rainAt(next)?.sampleBands(lat, lon)?.first;
      if (value == null) return null;
      precip = math.max(0, value);
    case FreeRain.global:
      final start = rainAt(hour)?.sampleBands(lat, lon)?.first;
      final end = rainAt(next)?.sampleBands(lat, lon)?.first;
      if (start == null || end == null) return null;
      precip = hourlyRain(start, end);
  }
  final blowing = windDirectionSpeed(uv[0], uv[1]);
  final from = (blowing.dir + 180) % 360;
  final onRoute = windOnRoute(blowing.ms, from, sample.bearingDeg);
  return SampleWeather(
    distanceM: sample.distanceM,
    at: departure.toUtc().add(sample.offset),
    temp: null,
    windMs: blowing.ms,
    windFromDeg: from,
    precipMm: precip,
    headwindMs: onRoute.headwind,
    crosswindMs: onRoute.crosswind,
    windClass: onRoute.windClass,
  );
}

/// The rain in mm of the hour between two sums of the global model's
/// `TOTPREC`, [atStart] and [atEnd], from the same run: their difference,
/// never below nothing (the sums are packed and can step back a hair).
double hourlyRain(double atStart, double atEnd) => math.max(0, atEnd - atStart);
