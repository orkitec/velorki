import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../core/db/database.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/map_strings.dart';
import '../../planner/presentation/route_format.dart';
import '../application/tile_download_controller.dart';
import '../data/routing_tiles_repository.dart';
import '../data/segments_manifest_service.dart';
import '../domain/routing_tile.dart';

/// Settings → Advanced → "Offline routing data", and the planner's answer to
/// a route that has no tiles.
///
/// Lists what is on the device with its size, date and state, and offers the
/// two ways of getting more: the tiles under the current map view, and the
/// tiles a route was missing ([preselected], handed in by the planner's
/// banner).
///
/// [mapController] is optional because the screen is also reachable from
/// Settings, where no map is alive; without one there is nothing to take
/// bounds from and the action says so, exactly as the offline maps screen
/// does.
class RoutingTilesScreen extends ConsumerWidget {
  /// Creates the screen.
  const RoutingTilesScreen({
    super.key,
    this.mapController,
    this.preselected = const <TileName>[],
  });

  /// The map whose visible area can be downloaded.
  final MapController? mapController;

  /// Tiles a route was missing, offered at the top of the screen.
  final List<TileName> preselected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tiles = ref.watch(routingTilesProvider);
    final queue = ref.watch(tileDownloadQueueProvider);
    final manifest = ref.watch(segmentsManifestSourceProvider);
    final isFallback = ref.watch(segmentsManifestServiceProvider).isFallback;

    ref.listen(tileDownloadQueueProvider, (previous, next) {
      final failure = next.failure;
      if (failure == null || failure == previous?.failure) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(l10n.routingTilesDownloadFailed(failure))),
      );
    });

    final rows = tiles.value ?? const <RoutingTile>[];
    final downloaded = rows.where((t) => t.isUsable).toList();
    final totalBytes = downloaded.fold<int>(0, (sum, t) => sum + t.bytes);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.routingTilesTitle)),
      body: Column(
        children: <Widget>[
          if (queue.isRunning) _QueueHeader(state: queue),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: <Widget>[
                if (isFallback) _Notice(text: l10n.routingTilesFallbackNotice),
                if (manifest.hasError)
                  _ManifestError(error: manifest.error!)
                else if (preselected.isNotEmpty)
                  _MissingTilesCard(tiles: preselected),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
                    child: Text(
                      l10n.routingTilesEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  for (final tile in rows) _TileRow(tile: tile),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    l10n.routingTilesTotal(
                      downloaded.length,
                      MapStrings.formatBytes(totalBytes),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mapController?.visibleBounds == null
                        ? l10n.routingTilesNeedsMap
                        : l10n.routingTilesDataNotice,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.download_outlined),
                    label: Text(l10n.routingTilesVisibleArea),
                    onPressed: mapController?.visibleBounds == null
                        ? null
                        : () => unawaited(_downloadVisibleArea(context, ref)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadVisibleArea(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final bounds = mapController?.visibleBounds;
    if (bounds == null) return;
    final wanted = tilesForBounds(bounds);
    if (wanted.isEmpty) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l10n.routingTilesNoneInView)));
      return;
    }
    await confirmTileDownload(context, ref, wanted);
  }
}

/// Asks whether [wanted] should be downloaded and enqueues them.
///
/// The sizes come from the manifest, so the dialog can say what a download
/// will cost before it starts. Tiles already on the device are dropped
/// silently; when nothing is left the rider is told so instead of being shown
/// an empty dialog.
Future<void> confirmTileDownload(
  BuildContext context,
  WidgetRef ref,
  List<TileName> wanted,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final SegmentsManifest manifest;
  try {
    manifest = await ref.read(segmentsManifestSourceProvider.future);
  } on Object catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.routingTilesManifestFailed(_message(e)))),
    );
    return;
  }
  final repository = await ref.read(routingTilesRepositoryProvider.future);
  final present = repository.readyTiles();
  final entries = <SegmentEntry>[
    for (final tile in wanted)
      if (!present.contains(tile))
        manifest[tile] ?? SegmentEntry(tile: tile, bytes: 0),
  ];
  if (entries.isEmpty) {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.routingTilesAllInView)),
    );
    return;
  }
  final bytes = entries.fold<int>(0, (sum, e) => sum + e.bytes);
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.routingTilesTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final entry in entries)
            Text('${entry.tile.name} · ${MapStrings.formatBytes(entry.bytes)}'),
          const SizedBox(height: 12),
          Text(l10n.routingTilesDataNotice),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            l10n.routingTilesDownloadCount(
              entries.length,
              MapStrings.formatBytes(bytes),
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed ?? false) {
    await ref.read(tileDownloadQueueProvider.notifier).enqueue(entries);
  }
}

String _message(Object error) =>
    error is SegmentsManifestException ? error.message : error.toString();

class _QueueHeader extends ConsumerWidget {
  const _QueueHeader({required this.state});

  final TileDownloadQueueState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final progress = state.progress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${state.current?.name ?? ''} · '
                  '${MapStrings.formatBytes(progress?.received ?? 0)} / '
                  '${MapStrings.formatBytes(progress?.total ?? 0)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress?.fraction),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.routingTilesCancelDownload,
            onPressed: ref.read(tileDownloadQueueProvider.notifier).cancel,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}

class _ManifestError extends ConsumerWidget {
  const _ManifestError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.routingTilesManifestFailed(_message(error)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => unawaited(
                  ref.read(segmentsManifestSourceProvider.notifier).refresh(),
                ),
                child: Text(l10n.routingTilesRetry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingTilesCard extends ConsumerWidget {
  const _MissingTilesCard({required this.tiles});

  final List<TileName> tiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final manifest = ref.watch(segmentsManifestSourceProvider).value;
    final bytes = manifest?.bytesFor(tiles) ?? 0;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.routingTilesRouteTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              tiles.map((t) => t.name).join(', '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () =>
                    unawaited(confirmTileDownload(context, ref, tiles)),
                child: Text(
                  l10n.routingTilesDownloadCount(
                    tiles.length,
                    MapStrings.formatBytes(bytes),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileRow extends ConsumerWidget {
  const _TileRow({required this.tile});

  final RoutingTile tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final label = switch (tile.state) {
      RoutingTileState.ready => l10n.routingTilesStateReady,
      RoutingTileState.stale => l10n.routingTilesStateStale,
      RoutingTileState.downloading => l10n.routingTilesStateDownloading,
      RoutingTileState.absent => l10n.routingTilesStateAbsent,
    };
    return ListTile(
      leading: const Icon(Icons.grid_on_outlined),
      title: Text(tile.name),
      subtitle: Text(
        '${MapStrings.formatBytes(tile.bytes)} · $label\n'
        '${l10n.routingTilesUpdatedAt(formatDate(l10n, tile.updatedAt))}',
      ),
      isThreeLine: true,
      trailing: tile.isDownloading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (tile.isStale)
                  TextButton(
                    onPressed: () => unawaited(
                      confirmTileDownload(context, ref, <TileName>[tile.tile]),
                    ),
                    child: Text(l10n.routingTilesUpdate),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.routingTilesDelete,
                  onPressed: () => unawaited(_confirmDelete(context, ref)),
                ),
              ],
            ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.routingTilesDeleteTitle(tile.name)),
        content: Text(l10n.routingTilesDeleteBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.routingTilesDelete),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      final repository = await ref.read(routingTilesRepositoryProvider.future);
      await repository.delete(tile.tile);
    }
  }
}
