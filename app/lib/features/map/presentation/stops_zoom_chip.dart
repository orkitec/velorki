import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';

/// The chip over the map while stops are switched on but the map is zoomed
/// out too far to show them: it says so, and a tap zooms in to where they
/// show.
class StopsZoomChip extends StatelessWidget {
  /// Creates the chip; [onZoomIn] zooms the map in.
  const StopsZoomChip({required this.onZoomIn, super.key});

  /// Called by a tap.
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return GlassPanel(
      radius: 22,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onZoomIn,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.zoom_in_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l10n.mapStopsZoomIn,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
