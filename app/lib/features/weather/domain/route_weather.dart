import 'dart:math' as math;

import 'package:velorki_api/velorki_api.dart'
    show WeatherCellForecast, WeatherForecast, WeatherSource;

import 'route_sampling.dart';

/// Below this mean wind, in m/s, the wind is [WindClass.calm] whichever way
/// it blows: a light air, about force 1.
const double calmWindMs = 1.5;

/// Rain this heavy, in mm/h, or at least [wetProbability] percent likely,
/// makes a stretch wet.
const double wetPrecipMm = 0.2;

/// See [wetPrecipMm].
const double wetProbability = 50;

/// How the wind meets the rider.
///
/// Apart from [calm], the class is the sector the wind comes from relative
/// to the way the route heads: within 60° of straight ahead is a [headwind]
/// (its component against the rider is at least half the wind), within 60°
/// of straight behind a [tailwind], and the two 60° sectors in between
/// [crosswind].
enum WindClass {
  /// Under [calmWindMs].
  calm,

  /// From ahead.
  headwind,

  /// From behind.
  tailwind,

  /// From the side.
  crosswind,
}

/// The weather at one sample, at the time the rider gets there.
class SampleWeather {
  /// Creates the weather.
  const SampleWeather({
    required this.distanceM,
    required this.at,
    required this.temp,
    required this.windMs,
    required this.windFromDeg,
    required this.precipMm,
    required this.headwindMs,
    required this.crosswindMs,
    required this.windClass,
    this.gust,
    this.precipProb,
    this.cloud,
  });

  /// How far along the route.
  final double distanceM;

  /// When the rider gets there, UTC.
  final DateTime at;

  /// Air temperature, °C.
  final double temp;

  /// Mean wind, m/s.
  final double windMs;

  /// Degrees the wind comes from.
  final double windFromDeg;

  /// Strongest gust in m/s, when the source has gusts.
  final double? gust;

  /// Precipitation, mm/h.
  final double precipMm;

  /// Probability of precipitation in percent, when the source has one.
  final double? precipProb;

  /// Cloud cover in percent, when the source has one.
  final double? cloud;

  /// The wind's component against the rider, m/s: positive from ahead,
  /// negative from behind.
  final double headwindMs;

  /// The wind's component across the route, m/s, whichever side.
  final double crosswindMs;

  /// How the wind meets the rider.
  final WindClass windClass;

  /// Whether this stretch is likely to be ridden in the rain.
  bool get wet =>
      precipMm >= wetPrecipMm || (precipProb ?? 0) >= wetProbability;

  @override
  String toString() =>
      'SampleWeather(${distanceM.round()} m at $at: ${temp.toStringAsFixed(1)} °C, '
      'wind ${windMs.toStringAsFixed(1)} from ${windFromDeg.round()}° '
      '(${windClass.name}), rain $precipMm)';
}

/// The wind of [windMs] from [windFromDeg] met by a rider heading
/// [bearingDeg]: its headwind and crosswind components and its class.
({double headwind, double crosswind, WindClass windClass}) windOnRoute(
  double windMs,
  double windFromDeg,
  double bearingDeg,
) {
  final angle = (windFromDeg - bearingDeg) * math.pi / 180;
  final headwind = windMs * math.cos(angle);
  final crosswind = (windMs * math.sin(angle)).abs();
  final windClass = windMs < calmWindMs
      ? WindClass.calm
      : headwind >= 0.5 * windMs
      ? WindClass.headwind
      : headwind <= -0.5 * windMs
      ? WindClass.tailwind
      : WindClass.crosswind;
  return (headwind: headwind, crosswind: crosswind, windClass: windClass);
}

/// The weather along the route for one departure time.
class RouteWeather {
  /// Creates the result.
  const RouteWeather({
    required this.departure,
    required this.samples,
    required this.weather,
    required this.sources,
  });

  /// When the rider leaves.
  final DateTime departure;

  /// Where along the route the weather was looked up.
  final List<RouteWeatherSample> samples;

  /// The weather at each of [samples], same length; `null` where the
  /// forecast had nothing for that place at that time (the UI shows a gap).
  final List<SampleWeather?> weather;

  /// The sources of the weather shown, for the attribution.
  final List<WeatherSource> sources;

  /// Whether every sample has weather.
  bool get complete => weather.every((w) => w != null);
}

/// The weather [forecast] gives each of [samples] for a ride leaving at
/// [departure]; `sampleToCell[i]` is the index of sample `i`'s cell in
/// [forecast]'s cells.
RouteWeather evaluate(
  WeatherForecast forecast,
  List<RouteWeatherSample> samples,
  List<int> sampleToCell,
  DateTime departure,
) {
  final used = <String>{};
  final weather = <SampleWeather?>[];
  for (final (i, sample) in samples.indexed) {
    final cellIndex = i < sampleToCell.length ? sampleToCell[i] : -1;
    final cell = cellIndex >= 0 && cellIndex < forecast.cells.length
        ? forecast.cells[cellIndex]
        : null;
    final at = departure.toUtc().add(sample.offset);
    final value = cell == null ? null : _weatherAt(cell, sample, at);
    if (value != null && cell!.source != null) used.add(cell.source!);
    weather.add(value);
  }
  return RouteWeather(
    departure: departure,
    samples: samples,
    weather: List<SampleWeather?>.unmodifiable(weather),
    sources: List<WeatherSource>.unmodifiable(
      forecast.sources.where((s) => used.contains(s.id)),
    ),
  );
}

/// [cell]'s weather at [at], interpolated between its hours; `null` when
/// [at] lies outside them.
SampleWeather? _weatherAt(
  WeatherCellForecast cell,
  RouteWeatherSample sample,
  DateTime at,
) {
  final hours = cell.hours;
  if (hours.isEmpty) return null;
  if (at.isBefore(hours.first.t) || at.isAfter(hours.last.t)) return null;
  var i = 0;
  while (i + 1 < hours.length && !hours[i + 1].t.isAfter(at)) {
    i++;
  }
  final a = hours[i];
  final b = i + 1 < hours.length ? hours[i + 1] : a;
  final span = b.t.difference(a.t).inMicroseconds;
  final t = span > 0 ? at.difference(a.t).inMicroseconds / span : 0.0;

  double lerp(double x, double y) => x + (y - x) * t;
  double? lerpOpt(num? x, num? y) => x == null
      ? null
      : y == null
      ? x.toDouble()
      : lerp(x.toDouble(), y.toDouble());

  final windMs = lerp(a.wind, b.wind);
  final windFrom = _lerpDegrees(a.windDir, b.windDir, t);
  final wind = windOnRoute(windMs, windFrom, sample.bearingDeg);
  return SampleWeather(
    distanceM: sample.distanceM,
    at: at,
    temp: lerp(a.temp, b.temp),
    windMs: windMs,
    windFromDeg: windFrom,
    gust: lerpOpt(a.gust, b.gust),
    precipMm: lerp(a.precip, b.precip),
    precipProb: lerpOpt(a.precipProb, b.precipProb),
    cloud: lerpOpt(a.cloud, b.cloud),
    headwindMs: wind.headwind,
    crosswindMs: wind.crosswind,
    windClass: wind.windClass,
  );
}

/// The direction [t] of the way from [a] to [b] along the shorter arc.
double _lerpDegrees(int a, int b, double t) {
  final delta = ((b - a + 540) % 360) - 180;
  return (a + delta * t + 360) % 360;
}

/// What the route's weather comes to, in a few figures.
class RouteWeatherSummary {
  /// Creates the summary.
  const RouteWeatherSummary({
    required this.headwindShare,
    required this.tailwindShare,
    required this.crosswindShare,
    required this.calmShare,
    required this.totalPrecipMm,
    required this.sources,
    this.minTemp,
    this.maxTemp,
    this.firstRainM,
    this.maxGustMs,
  });

  /// The share of the route's distance ridden into a headwind, 0 to 1.
  ///
  /// Each sample stands for half the distance to its neighbours; samples
  /// without weather count for no class, so the shares then add up to less
  /// than one.
  final double headwindShare;

  /// The share ridden with a tailwind.
  final double tailwindShare;

  /// The share ridden in a crosswind.
  final double crosswindShare;

  /// The share ridden in calm air.
  final double calmShare;

  /// The lowest temperature on the way, °C.
  final double? minTemp;

  /// The highest temperature on the way, °C.
  final double? maxTemp;

  /// Where the rain starts: the first sample that is [SampleWeather.wet];
  /// `null` for a dry ride.
  final double? firstRainM;

  /// The strongest gust on the way, m/s, when the sources have gusts.
  final double? maxGustMs;

  /// The rain the rider rides through, mm: each sample's rate for the time
  /// spent on its share of the route.
  final double totalPrecipMm;

  /// The sources of the figures.
  final List<WeatherSource> sources;

  /// Sums up [route].
  factory RouteWeatherSummary.of(RouteWeather route) {
    final weights = _distanceWeights(route.samples);
    final hours = _timeWeights(route.samples);
    var total = 0.0;
    final byClass = <WindClass, double>{};
    double? minTemp;
    double? maxTemp;
    double? firstRain;
    double? maxGust;
    var precip = 0.0;
    for (final (i, w) in route.weather.indexed) {
      total += weights[i];
      if (w == null) continue;
      byClass[w.windClass] = (byClass[w.windClass] ?? 0) + weights[i];
      minTemp = minTemp == null ? w.temp : math.min(minTemp, w.temp);
      maxTemp = maxTemp == null ? w.temp : math.max(maxTemp, w.temp);
      if (firstRain == null && w.wet) firstRain = w.distanceM;
      if (w.gust != null) {
        maxGust = maxGust == null ? w.gust : math.max(maxGust, w.gust!);
      }
      precip += w.precipMm * hours[i];
    }
    double share(WindClass c) => total > 0 ? (byClass[c] ?? 0) / total : 0;
    return RouteWeatherSummary(
      headwindShare: share(WindClass.headwind),
      tailwindShare: share(WindClass.tailwind),
      crosswindShare: share(WindClass.crosswind),
      calmShare: share(WindClass.calm),
      minTemp: minTemp,
      maxTemp: maxTemp,
      firstRainM: firstRain,
      maxGustMs: maxGust,
      totalPrecipMm: precip,
      sources: route.sources,
    );
  }
}

/// The distance each sample stands for: half of the way to each neighbour.
List<double> _distanceWeights(List<RouteWeatherSample> samples) =>
    _halfway(samples.map((s) => s.distanceM).toList(growable: false));

/// The hours each sample stands for, the same way.
List<double> _timeWeights(List<RouteWeatherSample> samples) => _halfway(
  samples
      .map((s) => s.offset.inMicroseconds / Duration.microsecondsPerHour)
      .toList(growable: false),
);

List<double> _halfway(List<double> at) => <double>[
  for (var i = 0; i < at.length; i++)
    ((i + 1 < at.length ? at[i + 1] : at[i]) - (i > 0 ? at[i - 1] : at[i])) / 2,
];

/// What a kilometre ridden in the rain costs in [departureScore], in the
/// units a kilometre against 1 m/s of headwind costs: one kilometre of rain
/// weighs as much as a kilometre into a 10 m/s wind.
const double rainWeight = 10;

/// What a kilometre against 1 m/s of headwind costs in [departureScore].
const double headwindWeight = 1;

/// How unpleasant [route] is, lower being better:
/// [rainWeight] × the expected wet kilometres + [headwindWeight] × the
/// headwind (m/s) summed over the kilometres it blows on. A tailwind does not
/// earn anything back: a rider loses more to a headwind than they gain from
/// the same wind behind. A stretch counts as wet with the certainty of its
/// rain chance, or fully when it is [SampleWeather.wet] by its amount.
/// `null` when a sample has no weather: such a departure is not comparable.
double? departureScore(RouteWeather route) {
  final weights = _distanceWeights(route.samples);
  var score = 0.0;
  for (final (i, w) in route.weather.indexed) {
    if (w == null) return null;
    final km = weights[i] / 1000;
    final wetness = w.precipMm >= wetPrecipMm ? 1.0 : (w.precipProb ?? 0) / 100;
    score += rainWeight * wetness * km;
    score += headwindWeight * math.max(0, w.headwindMs) * km;
  }
  return score;
}

/// How much lower a later departure's [departureScore] must be before it is
/// worth suggesting over the one the rider has: a fifth. Below that, waiting
/// buys too little to be worth the advice.
const double bestDepartureGain = 0.2;

/// A score this low is a ride with next to no rain or headwind: nothing to
/// improve on, whatever comes later.
const double negligibleScore = 0.5;

/// The departure between [from] and [from] + [within], in [step]s, with the
/// lowest [departureScore], the earliest of equals, among those [usable]
/// allows (all, without it). [current] (the rider's departure) is returned
/// instead unless the best scores at least [bestDepartureGain] lower than it,
/// or when it is already [negligibleScore]. `null` when no departure has
/// weather for the whole route.
DateTime? bestDeparture(
  WeatherForecast forecast,
  List<RouteWeatherSample> samples,
  List<int> sampleToCell, {
  required DateTime from,
  Duration within = const Duration(hours: 12),
  Duration step = const Duration(minutes: 30),
  DateTime? current,
  bool Function(DateTime departure)? usable,
}) {
  assert(step > Duration.zero, 'step must move forward');
  double? scoreAt(DateTime departure) =>
      departureScore(evaluate(forecast, samples, sampleToCell, departure));
  DateTime? best;
  double? bestScore;
  for (
    var departure = from;
    !departure.isAfter(from.add(within));
    departure = departure.add(step)
  ) {
    if (usable != null && !usable(departure)) continue;
    final score = scoreAt(departure);
    if (score != null && (bestScore == null || score < bestScore - 1e-9)) {
      best = departure;
      bestScore = score;
    }
  }
  if (current == null) return best;
  final currentScore = scoreAt(current);
  if (currentScore == null) return best ?? current;
  if (best == null || bestScore == null) return current;
  if (currentScore <= negligibleScore) return current;
  return bestScore <= currentScore * (1 - bestDepartureGain) ? best : current;
}
