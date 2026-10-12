import 'dart:math' as math;

import '../../map/data/rain_legend.dart';
import '../../map/domain/map_controller.dart';
import '../domain/route_weather.dart';
import '../domain/route_weather_state.dart';
import 'route_colouring.dart';

/// How far the route may be from the samples' length, in metres, for the
/// weather to count as the weather of that route.
const double _sameRouteToleranceM = 1;

/// The wind on a route [totalM] long, in metres along it: one run per run
/// of samples with the same [WindClass], each sample standing for the route
/// halfway to its neighbours. Samples without weather leave a gap. Empty
/// when [weather] was not worked out for this route (a route that changed
/// since, or another alternative).
List<RouteRun<WindClassOnMap>> windRuns(
  double totalM,
  RouteWeatherState weather,
) => <RouteRun<WindClassOnMap>>[
  for (final run in _runs(totalM, weather, (w) => w.windClass))
    (startM: run.startM, endM: run.endM, key: mapWindClass(run.key)),
];

/// The rain on a route [totalM] long, the way [windRuns] cuts the wind: one
/// run per run of samples in the same class of the DWD radar's legend
/// ([rainClassOnRoute]), keyed by that class's colour (0xRRGGBB), so the
/// route reads like the rain map. A dry stretch has no run.
List<RouteRun<int>> rainRuns(double totalM, RouteWeatherState weather) =>
    <RouteRun<int>>[
      for (final run in _runs(totalM, weather, rainClassOnRoute))
        (startM: run.startM, endM: run.endM, key: rainClassColour(run.key)),
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

/// The runs of samples with the same [keyOf], each with the stretch of a
/// route [totalM] long it stands for; a sample without weather, or whose
/// key is `null`, leaves a gap.
List<RouteRun<K>> _runs<K extends Object>(
  double totalM,
  RouteWeatherState weather,
  K? Function(SampleWeather w) keyOf,
) {
  final samples = weather.samples;
  final values = weather.weather.weather;
  if (samples.isEmpty || totalM <= 0) return const [];
  if ((samples.last.distanceM - totalM).abs() > _sameRouteToleranceM) {
    return const [];
  }
  K? keyAt(int i) {
    final w = i < values.length ? values[i] : null;
    return w == null ? null : keyOf(w);
  }

  final runs = <RouteRun<K>>[];
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
        ? totalM
        : (samples[j].distanceM + samples[j + 1].distanceM) / 2;
    if (to > from) runs.add((startM: from, endM: to, key: key));
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
