import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/platform_features.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/data/offline_regions_repository.dart';
import '../../map/domain/map_controller.dart';
import '../../routing_tiles/application/tile_download_controller.dart';
import '../../routing_tiles/presentation/routing_tiles_screen.dart';
import '../../shared/presentation/byte_size.dart';
import '../../shared/presentation/error_text.dart';
import '../application/area_download_activity.dart';

/// Why the area on screen cannot be downloaded, or `null` when it can: with
/// no map there is nothing to take the area from.
String? visibleAreaBlockedReason(
  AppLocalizations l10n,
  MapController? mapController,
) => mapController?.visibleBounds == null ? l10n.offlineNeedsMap : null;

/// Downloads the area [mapController] shows: one dialog for both kinds, then
/// both downloads. The offline screen's button and the not-downloaded chips
/// over the map both start it; [context] and [ref] must outlive the
/// download, so a long-lived screen's, not the chip's own.
///
/// Does nothing while a download of the area is already under way.
Future<void> downloadVisibleArea(
  BuildContext context,
  WidgetRef ref,
  MapController? mapController,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final bounds = mapController?.visibleBounds;
  if (bounds == null) {
    messenger?.showSnackBar(
      SnackBar(content: Text(visibleAreaBlockedReason(l10n, mapController)!)),
    );
    return;
  }
  if (ref.read(areaDownloadActivityProvider) != null) return;
  final starting = ref.read(areaDownloadStartingProvider.notifier)..set(true);
  try {
    await _download(context, ref, bounds, l10n, messenger);
  } finally {
    starting.set(false);
  }
}

Future<void> _download(
  BuildContext context,
  WidgetRef ref,
  BoundingBox bounds,
  AppLocalizations l10n,
  ScaffoldMessengerState? messenger,
) async {
  final mapAreas = ref.read(platformFeaturesProvider).offlineMapAreas;

  final TileDownloadPlan plan;
  try {
    plan = await planTileDownload(ref, tilesForBounds(bounds));
  } on Object catch (e) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(l10n.routingTilesManifestFailed(errorText(l10n, e))),
      ),
    );
    return;
  }
  if (plan.tooNew.isNotEmpty && plan.supported != null) {
    if (!context.mounted) return;
    await explainNewerTileFormat(
      context,
      ref,
      plan.tooNew,
      tileFormat: plan.tooNewFormat,
      appFormat: plan.supported!,
    );
  }
  if (!context.mounted) return;

  final entries = plan.entries;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.offlineDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (mapAreas) ...[
            Text(l10n.offlineDialogMap),
            const SizedBox(height: 8),
          ],
          if (entries.isEmpty)
            Text(l10n.offlineDialogRoutingPresent)
          else
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
          child: Text(l10n.offlineDialogDownload),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return;

  if (entries.isNotEmpty || plan.gazetteers.isNotEmpty) {
    await ref
        .read(tileDownloadQueueProvider.notifier)
        .enqueue(entries, gazetteersOnly: plan.gazetteers);
    // Left meanwhile (the offline screen popped): its ref is gone.
    if (!context.mounted) return;
    // The offline screen shows a failed tile in its own list; over the map
    // nothing else would say so.
    final failure = ref.read(tileDownloadQueueProvider).failure;
    if (failure != null) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            l10n.routingTilesDownloadFailed(failure.describe(l10n)),
          ),
        ),
      );
    }
  }
  if (!mapAreas) return;
  final existing = await ref.read(offlineRegionsRepositoryProvider).regions();
  final spec = OfflineRegionSpec(
    name: l10n.mapOfflineRegionName(existing.length + 1),
    bounds: bounds,
    styleUrl: ref.read(offlineStyleUrlProvider),
  );
  try {
    await ref.read(offlineDownloadControllerProvider.notifier).download(spec);
  } on Object catch (error) {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.offlineMapFailed(errorText(l10n, error)))),
    );
  }
}
