import 'package:flutter/material.dart';

import '../../../core/geo/power_metrics.dart';
import '../../../core/geo/ride_analysis.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'recording_format.dart';
import 'ride_zones_bar.dart';

/// How the ride's time with a power meter splits into seven zones of the
/// rider's threshold power: one stacked bar, then a row per zone.
///
/// Only built when the rider switched the power zones on, a threshold is set
/// and the ride carried a meter, so the widget itself asks no questions.
class RidePowerZones extends StatelessWidget {
  /// Creates the zones view.
  const RidePowerZones({
    required this.effort,
    required this.thresholdPowerW,
    super.key,
  });

  /// The analysed effort, whose zones were cut at [thresholdPowerW].
  final RideEffort effort;

  /// The threshold the zones are shares of, for the caption.
  final int thresholdPowerW;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final zones = effort.powerZones;
    final top = zones.length - 1;
    return RideZonesBar(
      caption: l10n.ridePowerZones(formatPower(l10n, thresholdPowerW)),
      zones: zones,
      labels: <String>[
        for (var i = 0; i < top; i++)
          l10n.rideHeartRateZoneLabel(
            i + 1,
            powerZoneBoundsPercent[i],
            powerZoneBoundsPercent[i + 1],
          ),
        // The top zone has no ceiling.
        l10n.ridePowerZoneTopLabel(top + 1, powerZoneBoundsPercent[top]),
      ],
    );
  }
}
