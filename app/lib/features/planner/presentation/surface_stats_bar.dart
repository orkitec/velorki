import 'package:flutter/material.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import 'route_format.dart';

/// What the route is made of: a paved/unpaved/unknown bar plus chips for the
/// shares that overlap it (bike infrastructure, busy roads).
class SurfaceStatsBar extends StatelessWidget {
  /// Creates the bar.
  const SurfaceStatsBar({required this.stats, super.key});

  /// The shares to show, `null` when the routing answer carried no way tags.
  final SurfaceStats? stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = stats;
    if (s == null || s.totalLengthM <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(l10n.surfaceUnavailable, style: theme.textTheme.bodySmall),
      );
    }

    final segments = <(String, double, Color)>[
      for (final (kind, share) in [
        (SurfaceKind.paved, s.pavedShare),
        (SurfaceKind.unpaved, s.unpavedShare),
        (SurfaceKind.unknown, s.unknownShare),
      ])
        (surfaceKindLabel(l10n, kind), share, surfaceKindColour(theme, kind)),
    ];
    final total = segments.fold<double>(0, (sum, e) => sum + e.$2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCaption(l10n.surfaceTitle),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: total <= 0
                ? ColoredBox(color: theme.colorScheme.outlineVariant)
                : Row(
                    children: [
                      for (final (label, share, color) in segments)
                        if (share > 0)
                          Expanded(
                            flex: (share * 1000).round().clamp(1, 1000),
                            child: Semantics(
                              label: label,
                              child: ColoredBox(color: color),
                            ),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final (label, share, color) in segments)
              _ShareChip(label: label, share: share, color: color),
            _ShareChip(
              label: surfaceKindLabel(l10n, SurfaceKind.bikeInfrastructure),
              // Stored before the share existed: the old, looser count.
              share: s.bikeInfrastructureShare ?? s.cyclewayShare,
              color: surfaceKindColour(theme, SurfaceKind.bikeInfrastructure),
            ),
            _ShareChip(
              label: surfaceKindLabel(l10n, SurfaceKind.busy),
              share: s.busyShare,
              color: surfaceKindColour(theme, SurfaceKind.busy),
            ),
          ],
        ),
      ],
    );
  }
}

/// The colour [kind] is drawn in, in the Surface section and on the route
/// coloured by its surface alike.
Color surfaceKindColour(ThemeData theme, SurfaceKind kind) => switch (kind) {
  SurfaceKind.paved => theme.velorki.accent,
  SurfaceKind.unpaved => theme.colorScheme.tertiary,
  SurfaceKind.unknown => theme.colorScheme.outlineVariant,
  SurfaceKind.bikeInfrastructure => theme.colorScheme.secondary,
  SurfaceKind.busy => theme.colorScheme.error,
};

/// What [kind] is called, in the Surface section and in the key to the
/// route coloured by its surface alike.
String surfaceKindLabel(AppLocalizations l10n, SurfaceKind kind) =>
    switch (kind) {
      SurfaceKind.paved => l10n.surfacePaved,
      SurfaceKind.unpaved => l10n.surfaceUnpaved,
      SurfaceKind.unknown => l10n.surfaceUnknown,
      SurfaceKind.bikeInfrastructure => l10n.surfaceBikeInfrastructure,
      SurfaceKind.busy => l10n.surfaceBusy,
    };

/// One legend entry: the colour of a share and how much of the route it is.
class _ShareChip extends StatelessWidget {
  const _ShareChip({
    required this.label,
    required this.share,
    required this.color,
  });

  final String label;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // A dot and a word: a Material chip would add a box around every share
    // and turn the legend into five buttons that do nothing.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          l10n.labelWithPercent(label, formatPercent(l10n, share)),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
