import 'package:velorki/core/units/units.dart' as units;
import 'package:velorki/features/planner/presentation/route_format.dart' as fmt;
import 'package:velorki/features/recording/presentation/recording_format.dart'
    as rec;

import 'app.dart';

export 'package:velorki/core/units/units.dart' show UnitSystem;

/// Figures as the screens write them, in the locale under test.
///
/// German puts a comma where English puts a point and its own word around the
/// unit, so a widget test that wants "the plotted distance is on the screen"
/// asks for it here instead of hard-coding `10.0 km`.

/// A distance, in kilometres unless [system] says otherwise.
String testDistance(
  double meters, {
  units.UnitSystem system = units.UnitSystem.metric,
}) => fmt.formatDistance(l10n, system, meters);

/// A height, in metres unless [system] says otherwise.
String testHeight(
  double meters, {
  units.UnitSystem system = units.UnitSystem.metric,
}) => fmt.formatHeight(l10n, system, meters);

/// A speed, in km/h unless [system] says otherwise.
String testSpeed(
  double metersPerSecond, {
  units.UnitSystem system = units.UnitSystem.metric,
}) => fmt.formatMeasure(l10n, units.formatSpeed(system, metersPerSecond));

/// A riding time, in hours and minutes.
String testDuration(Duration duration) => fmt.formatDuration(l10n, duration);

/// A date, in the locale's medium format.
String testDate(DateTime date) => fmt.formatDate(l10n, date);

/// A plain number with [decimals] decimal places.
String testNumber(double value, {int decimals = 1}) =>
    fmt.formatNumber(l10n, value, decimals: decimals);

/// A share of the route, as the locale writes a percentage.
String testPercent(double share) => fmt.formatPercent(l10n, share);

/// A split's length, as the splits table writes it.
String testSplitLength(
  double meters, {
  units.UnitSystem system = units.UnitSystem.metric,
}) => rec.formatSplitLength(l10n, system, meters);

/// A ride's intensity, as the tile writes the ratio.
String testIntensity(double ratio) => rec.formatIntensity(l10n, ratio);

/// A grade, as the climbs table writes it.
String testGrade(double percent) => rec.formatGrade(l10n, percent);
