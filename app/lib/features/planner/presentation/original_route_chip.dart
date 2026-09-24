import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';

/// The chip over the planner's map while a route read from a file is not the
/// file's route any more: it says so, with a dot in the colour of the faint
/// line the file drew, and offers to put the file's route back.
///
/// It shows for exactly as long as that faint line does.
class OriginalRouteChip extends StatelessWidget {
  /// Creates the chip; [onRestore] puts the file's route back.
  const OriginalRouteChip({required this.onRestore, super.key});

  /// Called by Restore.
  final VoidCallback onRestore;

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
              // The colour of the faint line on the map.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.5,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 10),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.plannerDiffersFromFile,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: onRestore,
                child: Text(l10n.plannerRestoreOriginal),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
