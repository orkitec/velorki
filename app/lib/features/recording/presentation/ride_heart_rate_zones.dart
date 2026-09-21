import 'package:flutter/material.dart';

import '../../../core/geo/ride_analysis.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'ride_zones_bar.dart';

/// The lower bound of each zone as a share of the maximum heart rate. Zone 1
/// takes everything below 60 %, so its label's 50 is the customary one, not a
/// cut.
const List<int> heartRateZoneBoundsPercent = <int>[50, 60, 70, 80, 90, 100];

/// How the ride's time with a heart rate splits into five zones of the
/// rider's maximum: one stacked bar, then a row per zone.
///
/// Only built when the rider switched the zones on and a maximum is known,
/// so the widget itself asks no questions.
class RideHeartRateZones extends StatelessWidget {
  /// Creates the zones view.
  const RideHeartRateZones({
    required this.effort,
    required this.maxHeartRateBpm,
    super.key,
  });

  /// The analysed effort, whose zones were cut at [maxHeartRateBpm].
  final RideEffort effort;

  /// The maximum the zones are shares of, for the caption.
  final int maxHeartRateBpm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final zones = effort.heartRateZones;
    return RideZonesBar(
      caption: l10n.rideHeartRateZones(maxHeartRateBpm),
      zones: zones,
      labels: <String>[
        for (var i = 0; i < zones.length; i++)
          l10n.rideHeartRateZoneLabel(
            i + 1,
            heartRateZoneBoundsPercent[i],
            heartRateZoneBoundsPercent[i + 1],
          ),
      ],
    );
  }
}
