import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
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
    return Row(
      children: [
        Expanded(
          child: _Stat(
            icon: Icons.straighten,
            label: l10n.statDistance,
            value: formatDistance(l10n, distanceM),
          ),
        ),
        Expanded(
          child: _Stat(
            icon: Icons.trending_up,
            label: l10n.statAscent,
            value: formatHeight(l10n, ascentM),
          ),
        ),
        Expanded(
          child: _Stat(
            icon: Icons.trending_down,
            label: l10n.statDescent,
            value: formatHeight(l10n, descentM),
          ),
        ),
        Expanded(
          child: _Stat(
            icon: Icons.schedule,
            label: l10n.statDuration,
            value: formatDuration(l10n, duration),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
