import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/geo/ride_analysis.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import 'recording_format.dart';

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
    final theme = Theme.of(context);
    final accent = theme.velorki.accent;
    final zones = effort.heartRateZones;
    final totalMicros = effort.heartRateTime.inMicroseconds;
    // Five steps of the accent from a quarter to full: the harder the zone,
    // the stronger the colour.
    final colours = <Color>[
      for (var i = 0; i < zones.length; i++)
        accent.withValues(alpha: 0.25 + 0.75 * i / (zones.length - 1)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCaption(l10n.rideHeartRateZones(maxHeartRateBpm)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                for (var i = 0; i < zones.length; i++)
                  if (zones[i] > Duration.zero)
                    Expanded(
                      // Milliseconds rather than microseconds: a flex is an
                      // int, and a five hour ride in microseconds is more
                      // than a layout wants to weigh.
                      flex: zones[i].inMilliseconds.clamp(1, 1 << 30),
                      child: ColoredBox(color: colours[i]),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < zones.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _ZoneRow(
            colour: colours[i],
            label: l10n.rideHeartRateZoneLabel(
              i + 1,
              heartRateZoneBoundsPercent[i],
              heartRateZoneBoundsPercent[i + 1],
            ),
            time: zones[i],
            percent: totalMicros <= 0
                ? 0
                : (zones[i].inMicroseconds * 100 / totalMicros).round(),
          ),
        ],
      ],
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.colour,
    required this.label,
    required this.time,
    required this.percent,
  });

  final Color colour;
  final String label;
  final Duration time;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A zone the ride never reached is still listed, dimmed, so the five
    // rows read the same on every ride.
    final empty = time <= Duration.zero;
    final textColour = empty ? scheme.onSurfaceVariant : scheme.onSurface;
    final style = theme.textTheme.bodyMedium?.copyWith(color: textColour);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: empty ? colour.withValues(alpha: 0.3) : colour,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: style)),
        Text(formatClock(time), style: style),
        SizedBox(
          width: 56,
          child: Text(
            l10n.rideHeartRateZoneShare(percent),
            style: style,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
