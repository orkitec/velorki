import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../map/presentation/map_strings.dart';
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
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.download_for_offline_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.plannerMissingTiles,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
