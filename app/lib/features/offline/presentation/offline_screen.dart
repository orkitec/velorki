import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/platform_features.dart';
import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/data/offline_regions_repository.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/offline_regions_screen.dart';
import '../../routing_tiles/application/tile_download_controller.dart';
import '../../routing_tiles/data/routing_tiles_repository.dart';
import '../../routing_tiles/presentation/routing_tiles_screen.dart';
import '../../shared/presentation/byte_size.dart';
import '../../shared/presentation/wide_panel.dart';
import 'download_visible_area.dart';

/// Everything a ride without a signal needs, in one place: the map to look
/// at and the routing data routes are computed from. One button downloads
/// both for the area the map shows; each kind has its own screen behind
/// "Manage" for the details.
///
/// [mapController] is the live map the screen was opened from. Without one
/// (from Settings) the download is off and the screen says why.
class OfflineScreen extends ConsumerWidget {
  /// Creates the screen.
  const OfflineScreen({super.key, this.mapController});

  /// The map whose visible area can be downloaded.
  final MapController? mapController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final regions = ref.watch(offlineRegionsProvider).value ?? const [];
    final tiles = ref.watch(routingTilesProvider).value ?? const [];
    final queue = ref.watch(tileDownloadQueueProvider);
    final mapProgress = ref.watch(offlineDownloadControllerProvider);
    // A browser keeps no map packs: only the routing data is offered there.
    final mapAreas = ref.watch(platformFeaturesProvider).offlineMapAreas;

    final regionBytes = regions.fold<int>(0, (sum, r) => sum + r.sizeBytes);
    final now = DateTime.now();
    final refreshDue = regions
        .where((r) => OfflineRegionsRepository.isRefreshDue(r, now))
        .length;
    final downloaded = tiles.where((t) => t.isUsable).toList();
    final tileBytes = downloaded.fold<int>(0, (sum, t) => sum + t.bytes);
    final stale = tiles.where((t) => t.isStale).length;

    // The map pack is built from the base style, so the CyclOSM overlay
    // never comes along and does not have to block the download.
    final String? blockedReason = visibleAreaBlockedReason(l10n, mapController);
    final busy = mapProgress != null || queue.isRunning;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.offlineTitle)),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              children: <Widget>[
                Text(l10n.offlineIntro, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                if (mapAreas) ...[
                  _KindCard(
                    icon: Icons.map_outlined,
                    title: l10n.offlineMapsTitle,
                    source: l10n.offlineMapsSource,
                    summary: l10n.offlineMapsSummary(
                      regions.length,
                      formatBytes(regionBytes),
                    ),
                    hint: refreshDue == 0
                        ? null
                        : l10n.offlineMapsRefreshHint(refreshDue),
                    progress: mapProgress == null
                        ? null
                        : _Progress(
                            label: l10n.offlineMapDownloading,
                            fraction: mapProgress.fraction,
                          ),
                    onManage: () => Navigator.of(context).push(
                      ColumnPageRoute<void>(
                        builder: (_) =>
                            OfflineRegionsScreen(mapController: mapController),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _KindCard(
                  icon: Icons.grid_on_outlined,
                  title: l10n.offlineRoutingTitle,
                  source: l10n.offlineRoutingSource,
                  summary: l10n.routingTilesTotal(
                    downloaded.length,
                    formatBytes(tileBytes),
                  ),
                  hint: stale == 0 ? null : l10n.routingTilesUpdatesHint(stale),
                  progress: queue.isRunning
                      ? _Progress(
                          label: l10n.offlineRoutingDownloading(
                            queue.current!.name,
                          ),
                          fraction: queue.progress?.fraction ?? 0,
                        )
                      : null,
                  onManage: () => Navigator.of(context).push(
                    ColumnPageRoute<void>(
                      builder: (_) =>
                          RoutingTilesScreen(mapController: mapController),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _BottomBar(
            note: blockedReason ?? l10n.routingTilesDataNotice,
            action: FilledButton.icon(
              icon: const Icon(Icons.download_outlined),
              label: Text(
                busy ? l10n.mapOfflineDownloading : l10n.offlineDownloadVisible,
              ),
              onPressed: blockedReason != null || busy
                  ? null
                  : () => unawaited(
                      downloadVisibleArea(context, ref, mapController),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Progress {
  const _Progress({required this.label, required this.fraction});
  final String label;
  final double fraction;
}

/// One of the two kinds: what it is, where it comes from, what is on the
/// device, and the way to its own screen.
class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.icon,
    required this.title,
    required this.source,
    required this.summary,
    required this.onManage,
    this.hint,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String source;
  final String summary;
  final String? hint;
  final _Progress? progress;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = this.progress;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.velorki.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: onManage,
                  child: Text(l10n.offlineManage),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(source, style: theme.textTheme.bodySmall),
            ),
            const SizedBox(height: 10),
            Text(
              summary,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (hint != null)
              Text(
                hint!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.velorki.warning,
                ),
              ),
            if (progress != null) ...<Widget>[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(progress.label, style: theme.textTheme.labelMedium),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress.fraction == 0 ? null : progress.fraction,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.action, required this.note});

  final Widget action;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(note, style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              action,
            ],
          ),
        ),
      ),
    );
  }
}
