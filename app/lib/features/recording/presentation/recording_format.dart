import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';

/// A speed, in the rider's own units with one decimal.
String formatSpeed(
  AppLocalizations l10n,
  units.UnitSystem system,
  double metersPerSecond,
) => formatMeasure(l10n, units.formatSpeed(system, metersPerSecond));

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
