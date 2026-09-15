import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import 'route_format.dart';

/// Distance, ascent, descent and estimated time, side by side.
class RouteStatsRow extends ConsumerWidget {
  /// Creates the row.
  const RouteStatsRow({
    required this.distanceM,
    required this.ascentM,
    required this.descentM,
    required this.duration,
    super.key,
  });

  /// Route length in metres.
  final double distanceM;

  /// Metres climbed.
  final double ascentM;

  /// Metres descended.
  final double descentM;

  /// Estimated riding time.
  final Duration duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = ref.watch(unitSystemProvider);
    return StatRow(
      children: [
        StatTile(
          label: l10n.statDistance,
          value: formatDistance(l10n, units, distanceM),
          emphasize: true,
        ),
        StatTile(
          label: l10n.statAscent,
          value: formatHeight(l10n, units, ascentM),
        ),
        StatTile(
          label: l10n.statDescent,
          value: formatHeight(l10n, units, descentM),
        ),
        StatTile(
          label: l10n.statDuration,
          value: formatDuration(l10n, duration),
        ),
      ],
    );
  }
}
