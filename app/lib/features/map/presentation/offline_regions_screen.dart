import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../shared/presentation/placeholder_body.dart';
import '../data/map_preferences.dart';
import '../data/offline_regions_repository.dart';
import '../domain/map_controller.dart';
import 'map_strings.dart';

/// Downloaded map areas: list, delete, and download the area the map is
/// currently showing.
///
/// [mapController] is optional because the screen is also reachable from
/// Settings, where no map is alive. Without one there is nothing to take
/// bounds from, and the download action explains that instead of guessing.
class OfflineRegionsScreen extends ConsumerWidget {
  const OfflineRegionsScreen({super.key, this.mapController});

  final MapController? mapController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regions = ref.watch(offlineRegionsProvider);
    final progress = ref.watch(offlineDownloadControllerProvider);
    final cyclosmActive = ref.watch(cyclosmOverlayProvider);
    final bounds = mapController?.visibleBounds;

    // The OSMF tile policy forbids bulk downloading CyclOSM tiles, so the
    // action is off while the overlay is on, whatever the map shows.
    final String? blockedReason = cyclosmActive
        ? MapStrings.downloadBlockedByCyclosm
        : bounds == null
        ? MapStrings.downloadNeedsMap
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text(MapStrings.offlineRegionsTitle)),
      body: Column(
        children: <Widget>[
          if (progress != null)
            LinearProgressIndicator(
              value: progress.fraction == 0 ? null : progress.fraction,
              minHeight: 6,
              borderRadius: BorderRadius.zero,
            ),
          Expanded(
            child: regions.when(
              data: (rows) => rows.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: rows.length,
                      itemBuilder: (context, i) => _RegionTile(row: rows[i]),
                    ),
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              error: (error, _) => Center(child: Text('$error')),
            ),
          ),
          _BottomBar(
            note: blockedReason,
            action: FilledButton.icon(
              icon: const Icon(Icons.download_outlined),
              label: Text(
                progress == null
                    ? MapStrings.downloadVisibleArea
                    : MapStrings.downloading,
              ),
              onPressed: blockedReason != null || progress != null
                  ? null
                  : () => unawaited(_download(context, ref)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final bounds = mapController?.visibleBounds;
    if (bounds == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final existing = await ref.read(offlineRegionsRepositoryProvider).regions();
    final spec = OfflineRegionSpec(
      name: '${MapStrings.regionNameDefault} ${existing.length + 1}',
      bounds: bounds,
      styleUrl: ref.read(offlineStyleUrlProvider),
    );
    try {
      await ref.read(offlineDownloadControllerProvider.notifier).download(spec);
    } on Object catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text('${MapStrings.downloadFailed} $error')),
      );
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const PlaceholderBody(
    icon: Icons.download_for_offline_outlined,
    message: MapStrings.offlineRegionsEmpty,
  );
}

/// The primary action, held above the system inset by a hairline.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.action, this.note});

  final Widget action;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = this.note;
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
              if (note != null) ...<Widget>[
                Text(note, style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
              ],
              action,
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionTile extends ConsumerWidget {
  const _RegionTile({required this.row});

  final OfflineRegionRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      // Every region in this list is on the device already.
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          Icons.offline_pin_outlined,
          size: 22,
          color: theme.velorki.success,
        ),
      ),
      title: Text(row.name, style: theme.textTheme.titleMedium),
      subtitle: Text(
        MapStrings.formatBytes(row.sizeBytes),
        style: theme.textTheme.labelMedium,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: MapStrings.deleteRegion,
        onPressed: () => unawaited(_confirmDelete(context, ref)),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(MapStrings.deleteRegionTitle),
        content: const Text(MapStrings.deleteRegionBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(MapStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(MapStrings.deleteRegion),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(offlineRegionsRepositoryProvider).delete(row.id);
    }
  }
}
