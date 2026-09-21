import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import 'recording_format.dart';

/// How a ride's time splits into zones: one stacked bar, then a row per zone
/// with its label, the time in it and its share of the whole.
///
/// The heart-rate zones and the power zones are the same picture with
/// different cuts, so both are drawn here; the caller says what the zones
/// are of and how each is labelled, and this widget asks no questions.
class RideZonesBar extends StatelessWidget {
  /// Creates the bar. [labels] has one entry per zone in [zones].
  const RideZonesBar({
    required this.caption,
    required this.zones,
    required this.labels,
    super.key,
  }) : assert(zones.length == labels.length, 'one label per zone');

  /// The section caption above the bar.
  final String caption;

  /// Time in each zone, the lowest first.
  final List<Duration> zones;

  /// What each zone covers, as its row reads it.
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.velorki.accent;
    var totalMicros = 0;
    for (final zone in zones) {
      totalMicros += zone.inMicroseconds;
    }
    // Steps of the accent from a quarter to full, one per zone: the harder
    // the zone, the stronger the colour.
    final colours = <Color>[
      for (var i = 0; i < zones.length; i++)
        accent.withValues(alpha: 0.25 + 0.75 * i / (zones.length - 1)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCaption(caption),
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
            label: labels[i],
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
    // A zone the ride never reached is still listed, dimmed, so the rows
    // read the same on every ride.
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
