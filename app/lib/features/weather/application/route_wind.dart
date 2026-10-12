import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../map/data/rain_legend.dart';
import '../../map/domain/map_controller.dart';
import '../domain/route_weather.dart';
import '../domain/route_weather_state.dart';
import 'route_overlay.dart';

/// How far the route may be from the samples' length, in metres, for the
/// weather to count as the weather of that route.
const double _sameRouteToleranceM = 1;

/// The wind on the route along [positions], for the map: one segment per
/// run of samples with the same [WindClass], each sample standing for the
/// route halfway to its neighbours. Samples without weather leave a gap.
/// Empty when [weather] was not worked out for this route (a route that
/// changed since, or another alternative).
List<WindSegment> windSegments(
  List<LatLng> positions,
  RouteWeatherState weather,
) => <WindSegment>[
  for (final (points, windClass) in _runs(
    positions,
    weather,
    (w) => w.windClass,
  ))
    WindSegment(points: points, windClass: mapWindClass(windClass)),
];

/// The rain on the route along [positions], for the map, the way
/// [windSegments] cuts the wind: one segment per run of samples in the same
/// class of the DWD radar's legend ([rainClassOnRoute]), drawn in that
/// class's colour, so the route reads like the rain map. A dry stretch is
/// left as it is.
List<RainSegment> rainSegments(
  List<LatLng> positions,
  RouteWeatherState weather,
) => <RainSegment>[
  for (final (points, k) in _runs(positions, weather, rainClassOnRoute))
    RainSegment(points: points, colour: rainClassColour(k)),
];

/// The class of the DWD radar's legend ([dwdRadarLegend]) the rain of [w]
/// falls in, `null` for a dry stretch: only a [SampleWeather.wet] one is
/// rain, as the section's line and the strip's bars say, so a few
/// hundredths of a mm do not colour the route. A stretch wet by its chance
/// alone, its amount under the legend's lightest class, is the lightest.
int? rainClassOnRoute(SampleWeather w) =>
    w.wet ? math.max(0, dwdRadarClassOf(w.precipMm)) : null;

/// The colour (0xRRGGBB) of the DWD radar's class [k].
int rainClassColour(int k) =>
    dwdRadarLegend.colours[dwdRadarLegend.classOf.indexOf(k)];

/// How hard it rains, as the map's key names it.
enum RainStrength {
  /// Under 2 mm an hour: the DWD radar's four lightest classes.
  light,

  /// 2 to 7.5 mm an hour.
  moderate,

  /// 7.5 mm an hour and more.
  heavy,
}

/// The DWD radar's classes each [RainStrength] spans, lightest first.
List<int> rainStrengthClasses(RainStrength strength) => switch (strength) {
  RainStrength.light => const <int>[0, 1, 2, 3],
  RainStrength.moderate => const <int>[4, 5, 6],
  RainStrength.heavy => <int>[
    for (var k = 7; k < dwdRadarLegend.classCount; k++) k,
  ],
};

/// The runs of samples with the same [keyOf], each with the part of the
/// route along [positions] it stands for; a sample without weather, or
/// whose key is `null`, leaves a gap.
List<(List<LatLng>, K)> _runs<K extends Object>(
  List<LatLng> positions,
  RouteWeatherState weather,
  K? Function(SampleWeather w) keyOf,
) {
  final samples = weather.samples;
  final values = weather.weather.weather;
  if (samples.isEmpty || positions.length < 2) return const [];
  final cumulative = cumulativeDistancesMeters(positions);
  final total = cumulative.last;
  if ((samples.last.distanceM - total).abs() > _sameRouteToleranceM) {
    return const [];
  }
  K? keyAt(int i) {
    final w = i < values.length ? values[i] : null;
    return w == null ? null : keyOf(w);
  }

  final runs = <(List<LatLng>, K)>[];
  var i = 0;
  while (i < samples.length) {
    final key = keyAt(i);
    if (key == null) {
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < samples.length && keyAt(j + 1) == key) {
      j++;
    }
    final from = i == 0
        ? 0.0
        : (samples[i - 1].distanceM + samples[i].distanceM) / 2;
    final to = j == samples.length - 1
        ? total
        : (samples[j].distanceM + samples[j + 1].distanceM) / 2;
    final points = _slice(positions, cumulative, from, to);
    if (points.length >= 2) runs.add((points, key));
    i = j + 1;
  }
  return runs;
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

/// The weather to draw on the route along [positions]: what [overlay]
/// chooses, nothing while it is off, while [weather] is on its way or
/// failed, or when it is not this route's.
RouteWeatherLines routeWeatherLinesFor(
  List<LatLng>? positions,
  AsyncValue<RouteWeatherState?> weather,
  RouteOverlay overlay,
) {
  if (overlay == RouteOverlay.off ||
      positions == null ||
      weather.isLoading ||
      weather.hasError) {
    return RouteWeatherLines.none;
  }
  final value = weather.value;
  if (value == null) return RouteWeatherLines.none;
  return switch (overlay) {
    RouteOverlay.off => RouteWeatherLines.none,
    RouteOverlay.wind => RouteWeatherLines(
      wind: windSegments(positions, value),
    ),
    RouteOverlay.rain => RouteWeatherLines(
      rain: rainSegments(positions, value),
    ),
  };
}
