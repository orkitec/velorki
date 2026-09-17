import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/byte_size.dart';
import '../data/segments_manifest_service.dart';
import 'routing_tiles_screen.dart';

/// What the planner shows when the on-device engine has no coverage and there
/// is no routing server to fall back to.
///
/// The composite backend then fails with [RoutingErrorKind.missingTiles] and
/// names the tiles; this turns that into the one action that helps, with the
/// download size taken from the manifest.
class MissingTilesBanner extends ConsumerWidget {
  /// Creates the banner for [tiles].
  const MissingTilesBanner({required this.tiles, super.key});

  /// The tiles the route needs and the device does not have.
  final List<TileName> tiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  MaterialPageRoute<void>(
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
