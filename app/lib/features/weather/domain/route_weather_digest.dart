import 'dart:math' as math;

import 'route_weather.dart';

/// The share of the route, by distance, one kind of wind must blow on for
/// the digest to name it ("mostly tailwind"); under it the wind is mixed.
const double dominantWindShare = 0.5;

/// Rain under this, in mm/h, everywhere it falls on the way is light rain:
/// the DWD radar's three lightest classes.
const double lightRainMm = 1;

/// A gust this strong, in m/s, is named: a strong breeze, force 6, where a
/// rider starts to be pushed about.
const double namedGustMs = 10;

/// How the wind meets the rider over the route, in a word.
enum DigestWind {
  /// A headwind on at least [dominantWindShare] of the way.
  headwind,

  /// A tailwind on at least [dominantWindShare] of the way.
  tailwind,

  /// A crosswind on at least [dominantWindShare] of the way.
  crosswind,

  /// Calm air on at least [dominantWindShare] of the way.
  calm,

  /// No kind of wind on as much as [dominantWindShare] of it.
  mixed,
}

/// Where the rain starts.
class DigestRain {
  /// Creates the rain.
  const DigestRain({
    required this.at,
    required this.distanceM,
    required this.light,
  });

  /// When the rider gets to the first wet stretch, UTC.
  final DateTime at;

  /// How far along the route that stretch is.
  final double distanceM;

  /// Whether every wet stretch has less than [lightRainMm] an hour.
  final bool light;
}

/// The route's weather in the few facts the line over the strip says.
///
/// Read off the samples with weather only: a sample the forecast had nothing
/// for neither counts for a kind of wind nor makes the ride dry or wet.
class RouteWeatherDigest {
  /// Creates the digest.
  const RouteWeatherDigest({
    this.wind,
    this.rain,
    this.minTemp,
    this.maxTemp,
    this.gustMs,
  });

  /// Sums up [route].
  ///
  /// Each sample stands for half the way to each neighbour, so a stretch
  /// counts for its length, not for how many samples lie on it. The rain is
  /// the first sample that is [SampleWeather.wet]: at least
  /// [wetPrecipMm] an hour, or a rain chance of at least [wetProbability]
  /// percent; a few hundredths of a mm make no rain.
  factory RouteWeatherDigest.of(RouteWeather route) {
    final samples = route.samples;
    final distances = [for (final s in samples) s.distanceM];
    final byClass = <WindClass, double>{};
    var covered = 0.0;
    double? minTemp;
    double? maxTemp;
    double? gust;
    SampleWeather? firstWet;
    var wettest = 0.0;
    for (final (i, w) in route.weather.indexed) {
      if (w == null || i >= samples.length) continue;
      final weight = _weight(distances, i);
      covered += weight;
      byClass[w.windClass] = (byClass[w.windClass] ?? 0) + weight;
      minTemp = minTemp == null ? w.temp : math.min(minTemp, w.temp);
      maxTemp = maxTemp == null ? w.temp : math.max(maxTemp, w.temp);
      if (w.gust case final g?) gust = gust == null ? g : math.max(gust, g);
      if (w.wet) {
        firstWet ??= w;
        wettest = math.max(wettest, w.precipMm);
      }
    }
    if (minTemp == null) return const RouteWeatherDigest();

    DigestWind wind;
    if (covered <= 0) {
      // A route of one point: its one sample's wind.
      final only = route.weather.firstWhere((w) => w != null)!;
      wind = _digestOf(only.windClass);
    } else {
      final (top, share) = byClass.entries
          .map((e) => (e.key, e.value / covered))
          .reduce((a, b) => b.$2 > a.$2 ? b : a);
      wind = share >= dominantWindShare ? _digestOf(top) : DigestWind.mixed;
    }
    return RouteWeatherDigest(
      wind: wind,
      rain: firstWet == null
          ? null
          : DigestRain(
              at: firstWet.at,
              distanceM: firstWet.distanceM,
              light: wettest < lightRainMm,
            ),
      minTemp: minTemp,
      maxTemp: maxTemp,
      gustMs: gust != null && gust >= namedGustMs ? gust : null,
    );
  }

  /// How the wind meets the rider; `null` when no sample has weather.
  final DigestWind? wind;

  /// Where the rain starts; `null` for a dry ride.
  final DigestRain? rain;

  /// The lowest temperature on the way, °C.
  final double? minTemp;

  /// The highest temperature on the way, °C.
  final double? maxTemp;

  /// The strongest gust, m/s, when it is at least [namedGustMs].
  final double? gustMs;

  /// Whether the forecast had nothing for the ride.
  bool get isEmpty => wind == null;

  static DigestWind _digestOf(WindClass c) => switch (c) {
    WindClass.headwind => DigestWind.headwind,
    WindClass.tailwind => DigestWind.tailwind,
    WindClass.crosswind => DigestWind.crosswind,
    WindClass.calm => DigestWind.calm,
  };

  /// The distance sample [i] of [at] stands for: half the way to each
  /// neighbour.
  static double _weight(List<double> at, int i) =>
      ((i + 1 < at.length ? at[i + 1] : at[i]) - (i > 0 ? at[i - 1] : at[i])) /
      2;
}
