import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../app/app_config.dart';
import '../../../app/theme.dart';
import '../../../core/links/link_opener.dart';
import '../../../core/db/database.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/domain/map_controller.dart';
import '../../shared/presentation/byte_size.dart';
import '../../planner/presentation/route_format.dart';
import '../../shared/presentation/placeholder_body.dart';
import '../application/tile_download_controller.dart';
import '../data/rd5_format_support.dart';
import '../data/routing_tiles_repository.dart';
import '../data/segments_manifest_service.dart';
import '../domain/rd5_format.dart';
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
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              children: <Widget>[
                _Notice(text: l10n.routingTilesSearchHint),
                if (isFallback) _Notice(text: l10n.routingTilesFallbackNotice),
                if (manifest.hasError)
                  _ManifestError(error: manifest.error!)
                else if (preselected.isNotEmpty)
                  _MissingTilesCard(tiles: preselected),
                if (rows.isEmpty)
                  PlaceholderBody(
                    icon: Icons.grid_on_outlined,
                    message: l10n.routingTilesEmpty,
                  )
                else
                  for (final tile in rows) _TileRow(tile: tile),
              ],
            ),
          ),
          _BottomBar(
            total: l10n.routingTilesTotal(
              downloaded.length,
              formatBytes(totalBytes),
            ),
            note: mapController?.visibleBounds == null
                ? l10n.routingTilesNeedsMap
                : l10n.routingTilesDataNotice,
            action: FilledButton.icon(
              icon: const Icon(Icons.download_outlined),
              label: Text(l10n.routingTilesVisibleArea),
              onPressed: mapController?.visibleBounds == null
                  ? null
                  : () => unawaited(_downloadVisibleArea(context, ref)),
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
/// What a download of [wanted] would fetch: the tiles not yet on the device
/// that this build can read, and those it cannot. Throws
/// [SegmentsManifestException] when the mirror cannot be read.
class TileDownloadPlan {
  /// Creates the plan.
  const TileDownloadPlan({
    required this.entries,
    required this.tooNew,
    required this.manifest,
    required this.supported,
  });

  /// Tiles to fetch.
  final List<SegmentEntry> entries;

  /// Tiles in a format newer than this build reads.
  final List<SegmentEntry> tooNew;

  /// The mirror's manifest the plan was made from.
  final SegmentsManifest manifest;

  /// The format this build reads, or `null` when unknown.
  final Rd5Format? supported;

  /// How many bytes [entries] add up to.
  int get bytes => entries.fold<int>(0, (sum, e) => sum + e.bytes);

  /// The format of the first tile in [tooNew], for the explanation.
  String get tooNewFormat => tooNew.isEmpty
      ? ''
      : tooNew.first.formatVersion ?? manifest.formatVersion ?? '';
}

/// Works out what downloading [wanted] means. Tiles already on the device are
/// dropped silently.
Future<TileDownloadPlan> planTileDownload(
  WidgetRef ref,
  List<TileName> wanted,
) async {
  final manifest = await ref.read(segmentsManifestSourceProvider.future);
  final repository = await ref.read(routingTilesRepositoryProvider.future);
  final supported = await ref.read(supportedRd5FormatProvider.future);
  final present = repository.readyTiles();
  final entries = <SegmentEntry>[];
  final tooNew = <SegmentEntry>[];
  for (final tile in wanted) {
    if (present.contains(tile)) continue;
    final entry = manifest[tile] ?? SegmentEntry(tile: tile, bytes: 0);
    final version = entry.formatVersion ?? manifest.formatVersion;
    final readable = supported?.canReadVersion(version) ?? true;
    (readable ? entries : tooNew).add(entry);
  }
  return TileDownloadPlan(
    entries: entries,
    tooNew: tooNew,
    manifest: manifest,
    supported: supported,
  );
}

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
  final TileDownloadPlan plan;
  try {
    plan = await planTileDownload(ref, wanted);
  } on Object catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.routingTilesManifestFailed(_message(e)))),
    );
    return;
  }
  final entries = plan.entries;
  if (plan.tooNew.isNotEmpty && plan.supported != null) {
    if (!context.mounted) return;
    await explainNewerTileFormat(
      context,
      ref,
      plan.tooNew,
      tileFormat: plan.tooNewFormat,
      appFormat: plan.supported!,
    );
    if (entries.isEmpty || !context.mounted) return;
  }
  if (entries.isEmpty) {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.routingTilesAllInView)),
    );
    return;
  }
  final bytes = plan.bytes;
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
            Text('${entry.tile.name} · ${formatBytes(entry.bytes)}'),
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
            l10n.routingTilesDownloadCount(entries.length, formatBytes(bytes)),
          ),
        ),
      ],
    ),
  );
  if (confirmed ?? false) {
    await ref.read(tileDownloadQueueProvider.notifier).enqueue(entries);
  }
}

/// One sentence for a mirror failure.
String manifestFailureMessage(Object error) =>
    error is SegmentsManifestException ? error.message : error.toString();

String _message(Object error) => manifestFailureMessage(error);

/// The store page of this build, or empty when none is configured. Each
/// platform has its own listing, so its own key.
String storeUrlFor(AppConfig config) => switch (defaultTargetPlatform) {
  TargetPlatform.iOS || TargetPlatform.macOS => config.storeUrlIos,
  TargetPlatform.android => config.storeUrlAndroid,
  _ => '',
};

/// Tells the rider that [entries] are written in a format this build cannot
/// read, and offers the store when the build knows its page there.
Future<void> explainNewerTileFormat(
  BuildContext context,
  WidgetRef ref,
  List<SegmentEntry> entries, {
  required String tileFormat,
  required Rd5Format appFormat,
}) async {
  final l10n = AppLocalizations.of(context);
  final storeUrl = storeUrlFor(ref.read(appConfigProvider));
  final openStore = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.routingTilesNeedsAppTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final entry in entries) Text(entry.tile.name),
          const SizedBox(height: 12),
          Text(l10n.routingTilesNeedsAppBody(tileFormat, appFormat.toString())),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.routingTilesNeedsAppDismiss),
        ),
        if (storeUrl.isNotEmpty)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.routingTilesOpenStore),
          ),
      ],
    ),
  );
  if (openStore ?? false) {
    await ref.read(linkOpenerProvider)(Uri.parse(storeUrl));
  }
}

class _QueueHeader extends ConsumerWidget {
  const _QueueHeader({required this.state});

  final TileDownloadQueueState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = state.progress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${state.current?.name ?? ''} · '
                  '${formatBytes(progress?.received ?? 0)} / '
                  '${formatBytes(progress?.total ?? 0)}',
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress?.fraction,
                    minHeight: 6,
                  ),
                ),
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Card(
        color: theme.colorScheme.errorContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: theme.colorScheme.error.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Not a SectionCaption: the wording is a sentence, not a label.
              Text(
                l10n.routingTilesRouteTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                tiles.map((t) => t.name).join(', '),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: () =>
                      unawaited(confirmTileDownload(context, ref, tiles)),
                  child: Text(
                    l10n.routingTilesDownloadCount(
                      tiles.length,
                      formatBytes(bytes),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.velorki;
    // A newer build on the mirror that this app could not read: the update
    // is the app's, not the tile's.
    final manifest = ref.watch(segmentsManifestSourceProvider).value;
    final supported = ref.watch(supportedRd5FormatProvider).value;
    final needsApp =
        tile.isStale &&
        supported != null &&
        !supported.canReadVersion(
          manifest?[tile.tile]?.formatVersion ?? manifest?.formatVersion,
        );
    final label = switch (tile.state) {
      RoutingTileState.ready => l10n.routingTilesStateReady,
      RoutingTileState.stale =>
        needsApp ? l10n.routingTilesStateNeedsApp : l10n.routingTilesStateStale,
      RoutingTileState.downloading => l10n.routingTilesStateDownloading,
      RoutingTileState.absent => l10n.routingTilesStateAbsent,
    };
    // The state is read from the colour first and the word second.
    final stateColor = switch (tile.state) {
      RoutingTileState.ready => colors.success,
      RoutingTileState.stale => colors.warning,
      RoutingTileState.downloading => colors.accent,
      RoutingTileState.absent => scheme.onSurfaceVariant,
    };
    final stateIcon = switch (tile.state) {
      RoutingTileState.ready => Icons.download_done_rounded,
      RoutingTileState.stale =>
        needsApp ? Icons.system_update_alt_rounded : Icons.update_rounded,
      RoutingTileState.downloading => Icons.downloading_rounded,
      RoutingTileState.absent => Icons.grid_on_outlined,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: _TileIcon(icon: stateIcon, color: stateColor),
      title: Text(tile.name, style: theme.textTheme.titleMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              Text(formatBytes(tile.bytes), style: theme.textTheme.labelMedium),
              Text(
                '  ·  ',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.outline,
                ),
              ),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: stateColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            l10n.routingTilesUpdatedAt(formatDate(l10n, tile.updatedAt)),
            style: theme.textTheme.bodySmall,
          ),
        ],
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
                if (tile.isStale && !needsApp)
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

/// The rounded square holding a tile's state icon.
class _TileIcon extends StatelessWidget {
  const _TileIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, size: 22, color: color),
  );
}

/// The summary and the primary action, held above the system inset by a
/// hairline.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.total,
    required this.note,
    required this.action,
  });

  final String total;
  final String note;
  final Widget action;

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
              Text(total, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
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
