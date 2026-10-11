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

/// The chip over the map while stops are switched on but the area they are
/// wanted in is not downloaded, so there are none to show: it says so, and
/// a tap opens the download for the area on screen.
class StopsDownloadChip extends StatelessWidget {
  /// Creates the chip; [onDownload] opens the download, and [onClose], where
  /// given, puts a close button at its end.
  const StopsDownloadChip({
    required this.onDownload,
    this.message,
    this.onClose,
    super.key,
  });

  /// Called by a tap.
  final VoidCallback onDownload;

  /// What is missing; the stops by default. The cycle map says the same of
  /// itself.
  final String? message;

  /// Called by the close button; no close button when `null`.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final onClose = this.onClose;
    final download = InkWell(
      onTap: onDownload,
      customBorder: const StadiumBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8, onClose == null ? 16 : 4, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              // The action beside the message where there is room, on
              // a line of its own under it where there is not: a long
              // word such as "Herunterladen" beside it squeezed the
              // message into a column of letters.
              Flexible(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      message ?? l10n.mapStopsNotDownloaded,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      l10n.mapStopsDownload,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return GlassPanel(
      radius: 22,
      child: Material(
        type: MaterialType.transparency,
        child: onClose == null
            ? download
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: download),
                  IconButton(
                    onPressed: onClose,
                    tooltip: l10n.mapAreaHintHide,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: theme.colorScheme.onSurfaceVariant,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
      ),
    );
  }
}
