import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';

/// The chip over the planner's map while the router keeps off stretches the
/// rider asked it to avoid: it says how many, with a dot in the colour of
/// their dashed lines, and lets them all be ridden again.
///
/// It shows for exactly as long as those lines do.
class AvoidedStretchesChip extends StatelessWidget {
  /// Creates the chip for [count] stretches; [onClear] lets the router back
  /// onto them.
  const AvoidedStretchesChip({
    required this.count,
    required this.onClear,
    super.key,
  });

  /// How many stretches are avoided.
  final int count;

  /// Called by the chip's button.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return GlassPanel(
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The colour of the dashed lines on the map.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 10),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.plannerAvoiding(count),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: onClear,
                child: Text(l10n.plannerAvoidClear),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
