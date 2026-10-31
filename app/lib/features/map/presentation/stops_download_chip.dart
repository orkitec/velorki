import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';

/// The chip over the map while stops are switched on but the area they are
/// wanted in is not downloaded, so there are none to show: it says so, and
/// a tap downloads the area on screen, and while that runs the chip says so.
class StopsDownloadChip extends StatelessWidget {
  /// Creates the chip; [onDownload] starts the download, and [onClose], where
  /// given, puts a close button at its end. While [downloading] the chip says
  /// so, with [progress] where it is known, and a tap does nothing; the
  /// button at its end is then [onCancel]'s, which stops the download.
  const StopsDownloadChip({
    required this.onDownload,
    this.downloading = false,
    this.progress,
    this.message,
    this.onClose,
    this.onCancel,
    super.key,
  });

  /// Called by a tap.
  final VoidCallback onDownload;

  /// Whether the download is running.
  final bool downloading;

  /// How far the running download is, 0..1; `null` when it cannot say.
  final double? progress;

  /// What is missing; the stops by default. The cycle map says the same of
  /// itself.
  final String? message;

  /// Called by the close button; no close button when `null`.
  final VoidCallback? onClose;

  /// Called by the button at the chip's end while it downloads; no button
  /// then when `null`. Closing the chip would hide the only sign that the
  /// download is running, so the button stops it instead.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final onClose = downloading ? onCancel : this.onClose;
    final download = InkWell(
      onTap: downloading ? null : onDownload,
      customBorder: const StadiumBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8, onClose == null ? 16 : 4, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (downloading)
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress,
                  ),
                )
              else
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
                      downloading
                          ? l10n.mapOfflineDownloading
                          : message ?? l10n.mapStopsNotDownloaded,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (!downloading)
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
                    tooltip: downloading
                        ? l10n.routingTilesCancelDownload
                        : l10n.mapAreaHintHide,
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
