import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';

/// What a sensor figure reads while nothing is reporting it.
const String absentSensorValue = '—';

/// A heart rate, or [absentSensorValue] when no sensor is reporting one.
String formatHeartRate(AppLocalizations l10n, int? bpm) =>
    bpm == null ? absentSensorValue : l10n.unitBpm('$bpm');

/// A cadence, or [absentSensorValue] when no sensor is reporting one.
///
/// Zero is a figure, not an absence: a rider freewheeling downhill pedals at
/// nothing and the tile should say so.
String formatCadence(AppLocalizations l10n, int? rpm) =>
    rpm == null ? absentSensorValue : l10n.unitRpm('$rpm');

/// A power, or [absentSensorValue] when no sensor is reporting one.
String formatPower(AppLocalizations l10n, int? watts) =>
    watts == null ? absentSensorValue : l10n.unitWatts('$watts');

/// A speed, in the rider's own units with one decimal.
String formatSpeed(
  AppLocalizations l10n,
  units.UnitSystem system,
  double metersPerSecond,
) => formatMeasure(l10n, units.formatSpeed(system, metersPerSecond));

/// How long a split is, as its own label: `1 km`, or `0.4 km` for the
/// remainder at the end of a ride.
///
/// Not [formatDistance]: that one drops below a kilometre into metres, and a
/// splits table that reads `1.0 km`, `1.0 km`, `400 m` is unreadable.
String formatSplitLength(
  AppLocalizations l10n,
  units.UnitSystem system,
  double meters,
) {
  final value = units.distanceToDisplay(system, meters);
  final rounded = (value * 10).round() / 10;
  final decimals = rounded == rounded.roundToDouble() ? 0 : 1;
  final number = formatNumber(l10n, rounded, decimals: decimals);
  return system == units.UnitSystem.metric
      ? l10n.unitKm(number)
      : l10n.unitMi(number);
}

/// A split's moving time, rounded to the second it is shown in.
///
/// The figure is cut at the split boundary, so it lands a few microseconds
/// either side of a round second; `2:59` for a kilometre ridden in three
/// minutes flat would be a lie the arithmetic did not intend.
Duration roundedSplitTime(Duration time) =>
    Duration(seconds: (time.inMilliseconds / 1000).round());

/// A running stopwatch: `mm:ss` below an hour, `h:mm:ss` above it.
///
/// Digits rather than words on purpose — this one changes every second and has
/// to stay the same width while it does.
String formatClock(Duration duration) {
  final seconds = duration.isNegative ? 0 : duration.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = rest.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}
