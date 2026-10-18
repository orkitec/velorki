import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../app/platform_features.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/byte_size.dart';
import '../../shared/presentation/error_text.dart';
import '../../shared/presentation/wide_panel.dart';
import '../application/tile_download_controller.dart';
import '../data/segments_manifest_service.dart';
import 'routing_tiles_screen.dart';

/// What the planner shows when the on-device engine has no coverage and there
/// is no routing server to fall back to.
///
/// The composite backend then fails with [RoutingErrorKind.missingTiles] and
/// names the tiles; this turns that into the one action that helps, with the
/// download size taken from the manifest. Where there is no routing server
/// at all ([PlatformFeatures.routingServer], the browser) the tiles are
/// fetched at once instead, with their progress; the planner routes again
/// when they are in ([_FetchingTiles]).
class MissingTilesBanner extends ConsumerWidget {
  /// Creates the banner for [tiles].
  const MissingTilesBanner({required this.tiles, super.key});

  /// The tiles the route needs and the device does not have.
  final List<TileName> tiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(platformFeaturesProvider).routingServer) {
      return _FetchingTiles(tiles: tiles);
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final manifest = ref.watch(segmentsManifestSourceProvider).value;
    final bytes = manifest?.bytesFor(tiles) ?? 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.download_for_offline_outlined,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.plannerMissingTiles,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(
                  ColumnPageRoute<void>(
                    builder: (_) => RoutingTilesScreen(preselected: tiles),
                  ),
                ),
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
    );
  }
}

/// The tiles a route needs, being fetched: queued as soon as the manifest
/// names them, with the download's progress, or what went wrong and a way
/// to try again.
class _FetchingTiles extends ConsumerStatefulWidget {
  const _FetchingTiles({required this.tiles});

  final List<TileName> tiles;

  @override
  ConsumerState<_FetchingTiles> createState() => _FetchingTilesState();
}

class _FetchingTilesState extends ConsumerState<_FetchingTiles> {
  /// The tiles last queued, so a rebuild does not queue them again; a new
  /// set (another route) or a retry does.
  Set<TileName> _queued = const <TileName>{};

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      segmentsManifestSourceProvider,
      (_, next) => _fetch(next.value),
      fireImmediately: true,
    );
  }

  @override
  void didUpdateWidget(_FetchingTiles oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fetch(ref.read(segmentsManifestSourceProvider).value);
  }

  void _fetch(SegmentsManifest? manifest, {bool again = false}) {
    if (manifest == null) return;
    final wanted = widget.tiles.toSet();
    if (!again &&
        wanted.length == _queued.length &&
        wanted.containsAll(_queued)) {
      return;
    }
    _queued = wanted;
    final entries = <SegmentEntry>[
      for (final tile in widget.tiles) ?manifest[tile],
    ];
    // After this frame: queueing changes the queue's state, which this
    // very build may be reading.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || entries.isEmpty) return;
      unawaited(ref.read(tileDownloadQueueProvider.notifier).enqueue(entries));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final manifest = ref.watch(segmentsManifestSourceProvider);
    final queue = ref.watch(tileDownloadQueueProvider);
    final mine = widget.tiles.toSet();
    final running = queue.current != null && mine.contains(queue.current);
    final failure = running ? null : queue.failure;

    final String text;
    VoidCallback? retry;
    if (manifest.hasError) {
      text = l10n.routingTilesManifestFailed(errorText(l10n, manifest.error!));
      retry = () => unawaited(
        ref.read(segmentsManifestSourceProvider.notifier).refresh(),
      );
    } else if (failure != null) {
      text = l10n.routingTilesDownloadFailed(failure.describe(l10n));
      retry = () => _fetch(manifest.value, again: true);
    } else {
      text = l10n.plannerFetchingTiles(
        formatBytes(manifest.value?.bytesFor(widget.tiles) ?? 0),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  retry == null
                      ? Icons.download_for_offline_outlined
                      : Icons.error_outline,
                  size: 22,
                  color: retry == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
              ],
            ),
            const SizedBox(height: 14),
            if (retry == null)
              LinearProgressIndicator(
                value: running ? queue.progress?.fraction : null,
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: retry,
                  child: Text(l10n.routingTilesRetry),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
