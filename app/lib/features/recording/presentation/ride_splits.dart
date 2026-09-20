// Material exports a `Split` animation curve nobody here wants; the splits of
// a ride are what this file is about.
import 'package:flutter/material.dart' hide Split;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/geo/ride_analysis.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import 'recording_format.dart';

/// The kilometres (or miles) of a ride, one row each: how long, how long it
/// took, how fast, and how much of it went uphill.
///
/// Behind every row is a bar as wide as that split was fast relative to the
/// fastest one, so the shape of the ride is readable without reading a single
/// figure.
class RideSplitsTable extends ConsumerWidget {
  /// Creates the table.
  const RideSplitsTable({
    required this.splits,
    required this.splitLengthM,
    super.key,
  });

  /// The splits, in riding order.
  final List<Split> splits;

  /// How long a whole split is, for the caption.
  final double splitLengthM;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final system = ref.watch(unitSystemProvider);
    if (splits.isEmpty) return const SizedBox.shrink();

    var fastest = 0.0;
    for (final split in splits) {
      if (split.avgSpeedMps > fastest) fastest = split.avgSpeedMps;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCaption(
          l10n.rideSplitsEvery(formatSplitLength(l10n, system, splitLengthM)),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _SplitRow(
            split: SectionCaption(l10n.rideSplitColumn),
            time: SectionCaption(l10n.statMovingTime),
            speed: SectionCaption(l10n.statAvgSpeed),
            ascent: SectionCaption(l10n.statAscent),
          ),
        ),
        const SizedBox(height: 4),
        for (final split in splits)
          _SplitBar(
            // A split nobody moved in has no bar at all rather than a full one.
            fraction: fastest <= 0 ? 0 : split.avgSpeedMps / fastest,
            child: _SplitRow(
              split: Text(
                formatSplitLength(l10n, system, split.distanceM),
                style: theme.textTheme.statMedium,
              ),
              time: Text(
                formatClock(roundedSplitTime(split.movingTime)),
                style: theme.textTheme.statMedium,
              ),
              speed: Text(
                formatSpeed(l10n, system, split.avgSpeedMps),
                style: theme.textTheme.statMedium,
              ),
              ascent: Text(
                formatHeight(l10n, system, split.ascentM),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The four columns, shared by the header and the rows so they line up.
class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.split,
    required this.time,
    required this.speed,
    required this.ascent,
  });

  final Widget split;
  final Widget time;
  final Widget speed;
  final Widget ascent;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(flex: 3, child: split),
      Expanded(
        flex: 3,
        child: Align(alignment: Alignment.centerRight, child: time),
      ),
      Expanded(
        flex: 4,
        child: Align(alignment: Alignment.centerRight, child: speed),
      ),
      Expanded(
        flex: 3,
        child: Align(alignment: Alignment.centerRight, child: ascent),
      ),
    ],
  );
}

/// One row with its speed bar behind it.
class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.fraction, required this.child});

  /// How fast this split was against the fastest one, 0 to 1.
  final double fraction;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).velorki;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0.02, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: child,
          ),
        ],
      ),
    );
  }
}
