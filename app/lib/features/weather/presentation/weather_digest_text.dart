import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';
import '../domain/route_weather_digest.dart';

/// Rain this close to the start, in metres, starts "from the start": the
/// first sample after the start is 2 km on.
const double rainAtStartM = 1000;

/// What the line over the weather strip says of [digest], fact by fact:
/// the rain first when there is any, since it changes a ride most, then the
/// wind, the temperature and a strong gust; the temperature and the gust only
/// where the forecast has them (the free one has no gusts, and a temperature
/// grid it could not load leaves none). Empty when the forecast had nothing
/// for the ride. [clock] writes a time of day the way the phone
/// does.
List<String> weatherDigestParts(
  AppLocalizations l10n,
  units.UnitSystem system,
  RouteWeatherDigest digest, {
  required String Function(DateTime at) clock,
}) {
  final wind = digest.wind;
  if (wind == null) return const <String>[];
  final rain = digest.rain;
  final lo = digest.minTemp;
  final hi = digest.maxTemp;
  return <String>[
    if (rain == null)
      l10n.weatherDry
    else if (rain.distanceM < rainAtStartM)
      rain.light
          ? l10n.weatherLightRainLikelyAtStart
          : l10n.weatherRainLikelyAtStart
    else
      (rain.light
          ? l10n.weatherLightRainLikelyFrom
          : l10n.weatherRainLikelyFrom)(
        clock(rain.at),
        formatDistance(l10n, system, rain.distanceM),
      ),
    switch (wind) {
      DigestWind.headwind => l10n.weatherMostlyHeadwind,
      DigestWind.tailwind => l10n.weatherMostlyTailwind,
      DigestWind.crosswind => l10n.weatherMostlyCrosswind,
      DigestWind.calm => l10n.weatherMostlyCalm,
      DigestWind.mixed => l10n.weatherMixedWind,
    },
    if (lo != null && hi != null) weatherTemperatureText(l10n, system, lo, hi),
    if (digest.gustMs case final gust?)
      l10n.weatherGusts(formatMeasure(l10n, units.formatSpeed(system, gust))),
  ];
}

/// The temperatures from [lo] to [hi] °C, "12–17 °C", or one figure when
/// they round to the same.
String weatherTemperatureText(
  AppLocalizations l10n,
  units.UnitSystem system,
  double lo,
  double hi,
) {
  final low = units.temperatureIn(system, lo).round();
  final high = units.temperatureIn(system, hi).round();
  if (low == high) return formatTemperature(l10n, system, hi);
  return l10n.weatherTemperatureRange(
    '$low',
    formatTemperature(l10n, system, hi),
  );
}
