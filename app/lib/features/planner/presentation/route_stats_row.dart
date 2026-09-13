import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import 'route_format.dart';

/// Distance, ascent, descent and estimated time, side by side.
class RouteStatsRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StatRow(
      children: [
        StatTile(
          label: l10n.statDistance,
          value: formatDistance(l10n, distanceM),
          emphasize: true,
        ),
        StatTile(label: l10n.statAscent, value: formatHeight(l10n, ascentM)),
        StatTile(label: l10n.statDescent, value: formatHeight(l10n, descentM)),
        StatTile(
          label: l10n.statDuration,
          value: formatDuration(l10n, duration),
        ),
      ],
    );
  }
}
