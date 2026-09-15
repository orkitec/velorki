import 'package:intl/intl.dart';

import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import '../domain/route_profile.dart';

/// A distance for the stats row, in the rider's own units.
String formatDistance(
  AppLocalizations l10n,
  units.UnitSystem system,
  double meters,
) => formatMeasure(l10n, units.formatDistance(system, meters));

/// A height, in whole metres or whole feet.
String formatHeight(
  AppLocalizations l10n,
  units.UnitSystem system,
  double meters,
) => formatMeasure(l10n, units.formatElevation(system, meters));

/// A converted figure with its translated unit around it.
String formatMeasure(AppLocalizations l10n, units.Measure measure) {
  final value = formatNumber(l10n, measure.value, decimals: measure.decimals);
  return switch (measure.unit) {
    units.MeasureUnit.meters => l10n.unitM(value),
    units.MeasureUnit.kilometers => l10n.unitKm(value),
    units.MeasureUnit.feet => l10n.unitFt(value),
    units.MeasureUnit.miles => l10n.unitMi(value),
    units.MeasureUnit.kilometersPerHour => l10n.unitKmh(value),
    units.MeasureUnit.milesPerHour => l10n.unitMph(value),
  };
}

/// A riding time, in hours and minutes.
String formatDuration(AppLocalizations l10n, Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 60) return l10n.valueMinutes(minutes);
  return l10n.valueHoursMinutes(minutes ~/ 60, minutes % 60);
}

/// A share of the route, as a whole-number percentage.
String formatPercent(AppLocalizations l10n, double share) =>
    NumberFormat.percentPattern(l10n.localeName).format(share.clamp(0.0, 1.0));

/// A date, in the locale's medium format.
String formatDate(AppLocalizations l10n, DateTime date) =>
    DateFormat.yMMMd(l10n.localeName).format(date);

/// A number with [decimals] decimal places in the locale's notation.
String formatNumber(AppLocalizations l10n, double value, {int decimals = 1}) {
  final format = NumberFormat.decimalPatternDigits(
    locale: l10n.localeName,
    decimalDigits: decimals,
  );
  return format.format(value);
}

/// The localised name of a routing profile.
String profileLabel(AppLocalizations l10n, RouteProfile profile) =>
    switch (profile) {
      RouteProfile.trekking => l10n.profileTrekking,
      RouteProfile.fastbike => l10n.profileFastbike,
      RouteProfile.gravel => l10n.profileGravel,
      RouteProfile.mtb => l10n.profileMtb,
      RouteProfile.shortest => l10n.profileShortest,
    };
