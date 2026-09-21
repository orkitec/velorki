import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/geo/climbs.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import 'recording_format.dart';
import 'ride_splits.dart';

/// The climbs of a ride, one row each: where it started, how long, how much
/// it gained and how steep; underneath, quieter, how long it took, how many
/// metres an hour that was, and what the heart and the meter read on it.
///
/// Behind every row is a bar as high as that climb's ascent relative to the
/// biggest one, so the big climb of the day stands out without reading a
/// figure.
class RideClimbsTable extends ConsumerWidget {
  /// Creates the table.
  const RideClimbsTable({required this.climbs, super.key});

  /// The climbs, in riding order.
  final List<RideClimb> climbs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final system = ref.watch(unitSystemProvider);
    if (climbs.isEmpty) return const SizedBox.shrink();

    var highest = 0.0;
    for (final climb in climbs) {
      if (climb.ascentM > highest) highest = climb.ascentM;
    }
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCaption(l10n.rideClimbs),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _ClimbRow(
            start: SectionCaption(l10n.rideClimbStartColumn),
            length: SectionCaption(l10n.rideClimbLengthColumn),
            ascent: SectionCaption(l10n.statAscent),
            grade: SectionCaption(l10n.rideClimbGradeColumn),
          ),
        ),
        const SizedBox(height: 4),
        for (final climb in climbs)
          RideRowBar(
            fraction: highest <= 0 ? 0 : climb.ascentM / highest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ClimbRow(
                  start: Text(
                    l10n.rideClimbAt(
                      formatDistance(l10n, system, climb.startM),
                    ),
                    style: theme.textTheme.statMedium,
                  ),
                  length: Text(
                    formatDistance(l10n, system, climb.lengthM),
                    style: theme.textTheme.statMedium,
                  ),
                  ascent: Text(
                    formatHeight(l10n, system, climb.ascentM),
                    style: theme.textTheme.statMedium,
                  ),
                  grade: Text(
                    formatGrade(l10n, climb.avgGradePercent),
                    style: theme.textTheme.statMedium,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    formatClock(roundedSplitTime(climb.movingTime)),
                    l10n.rideClimbVam(
                      formatNumber(l10n, climb.vamMPerHour, decimals: 0),
                    ),
                    if (climb.avgHeartRateBpm != null)
                      formatHeartRate(l10n, climb.avgHeartRateBpm),
                    if (climb.avgPowerW != null)
                      formatPower(l10n, climb.avgPowerW),
                  ].join(' · '),
                  style: quiet,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The four columns, shared by the header and the rows so they line up.
class _ClimbRow extends StatelessWidget {
  const _ClimbRow({
    required this.start,
    required this.length,
    required this.ascent,
    required this.grade,
  });

  final Widget start;
  final Widget length;
  final Widget ascent;
  final Widget grade;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(flex: 4, child: start),
      Expanded(
        flex: 3,
        child: Align(alignment: Alignment.centerRight, child: length),
      ),
      Expanded(
        flex: 3,
        child: Align(alignment: Alignment.centerRight, child: ascent),
      ),
      Expanded(
        flex: 3,
        child: Align(alignment: Alignment.centerRight, child: grade),
      ),
    ],
  );
}
