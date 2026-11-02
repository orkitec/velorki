import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/platform_features.dart';
import '../../../core/db/database.dart';
import '../../map/data/offline_regions_repository.dart';
import '../../map/domain/map_controller.dart';
import '../../routing_tiles/application/tile_download_controller.dart';
import '../../routing_tiles/data/routing_tiles_repository.dart';
import '../../routing_tiles/data/segments_manifest_service.dart';
import '../../routing_tiles/domain/routing_tile.dart';
import 'visible_area_status.dart';

/// [visibleAreaStatus] for the area [map] shows, over what [ref] watches:
/// the tiles, the queue, the map areas and the manifest of this session.
///
/// Read in `build`; the camera's resting is what tells a widget to build
/// again, since the bounds are not watched.
VisibleAreaStatus watchVisibleAreaStatus(WidgetRef ref, MapController? map) {
  final mapAreas = ref.watch(platformFeaturesProvider).offlineMapAreas;
  final repository = ref.watch(routingTilesRepositoryProvider).value;
  return visibleAreaStatus(
    bounds: map?.visibleBounds,
    tiles: ref.watch(routingTilesProvider).value ?? const <RoutingTile>[],
    hasGazetteer: (tile) =>
        repository?.gazetteerFileFor(tile).existsSync() ?? false,
    queue: ref.watch(tileDownloadQueueProvider),
    // Only a manifest already read this session: the status never asks the
    // mirror itself. The camera's next rest picks one up.
    manifest: ref.exists(segmentsManifestSourceProvider)
        ? ref.watch(segmentsManifestSourceProvider).value
        : null,
    mapProgress: mapAreas
        ? ref.watch(offlineDownloadControllerProvider)?.fraction
        : null,
    // Watched only when asked, once the routing data is all there: a map
    // with nothing downloaded keeps no watch on the map areas.
    regions: mapAreas
        ? () =>
              ref.watch(offlineRegionsProvider).value ??
              const <OfflineRegionRow>[]
        : null,
  );
}
