import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../map/domain/map_controller.dart';
import '../domain/route_weather.dart';
import '../domain/route_weather_state.dart';

/// How far the route may be from the samples' length, in metres, for the
/// weather to count as the weather of that route.
const double _sameRouteToleranceM = 1;

/// The wind on [route], for the map: one segment per run of samples with the
/// same [WindClass], each sample standing for the route halfway to its
/// neighbours. Samples without weather leave a gap. Empty when [weather] was
/// not worked out for [route] (a route that changed since, or another
/// alternative).
List<WindSegment> windSegments(RouteResult route, RouteWeatherState weather) {
  final samples = weather.samples;
  final values = weather.weather.weather;
  final positions = route.positions;
  if (samples.isEmpty || positions.length < 2) return const <WindSegment>[];
  final cumulative = cumulativeDistancesMeters(positions);
  final total = cumulative.last;
  if ((samples.last.distanceM - total).abs() > _sameRouteToleranceM) {
    return const <WindSegment>[];
  }

  final segments = <WindSegment>[];
  var i = 0;
  while (i < samples.length) {
    final w = i < values.length ? values[i] : null;
    if (w == null) {
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < samples.length &&
        j + 1 < values.length &&
        values[j + 1]?.windClass == w.windClass) {
      j++;
    }
    final from = i == 0
        ? 0.0
        : (samples[i - 1].distanceM + samples[i].distanceM) / 2;
    final to = j == samples.length - 1
        ? total
        : (samples[j].distanceM + samples[j + 1].distanceM) / 2;
    final points = _slice(positions, cumulative, from, to);
    if (points.length >= 2) {
      segments.add(
        WindSegment(points: points, windClass: mapWindClass(w.windClass)),
      );
    }
    i = j + 1;
  }
  return segments;
}

/// [WindClass] as the map knows it.
WindClassOnMap mapWindClass(WindClass windClass) => switch (windClass) {
  WindClass.headwind => WindClassOnMap.head,
  WindClass.crosswind => WindClassOnMap.cross,
  WindClass.tailwind => WindClassOnMap.tail,
  WindClass.calm => WindClassOnMap.calm,
};

/// The part of [line] from [from] to [to] metres along it.
List<LatLng> _slice(
  List<LatLng> line,
  List<double> cumulative,
  double from,
  double to,
) {
  if (to <= from) return const <LatLng>[];
  LatLng at(double d) {
    var k = 0;
    while (k + 2 < cumulative.length && cumulative[k + 1] < d) {
      k++;
    }
    final span = cumulative[k + 1] - cumulative[k];
    final t = span > 0 ? ((d - cumulative[k]) / span).clamp(0.0, 1.0) : 0.0;
    final a = line[k];
    final b = line[k + 1];
    return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
  }

  return <LatLng>[
    at(from),
    for (var k = 0; k < line.length; k++)
      if (cumulative[k] > from && cumulative[k] < to) line[k],
    at(to),
  ];
}

/// The wind to draw on [route]: none while [on] is off, while [weather] is
/// on its way or failed, or when it is not [route]'s.
List<WindSegment> routeWindFor(
  RouteResult? route,
  AsyncValue<RouteWeatherState?> weather, {
  required bool on,
}) {
  if (!on || route == null || weather.isLoading || weather.hasError) {
    return const <WindSegment>[];
  }
  final value = weather.value;
  if (value == null) return const <WindSegment>[];
  return windSegments(route, value);
}
