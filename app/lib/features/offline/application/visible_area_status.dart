import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/db/database.dart';
import '../../routing_tiles/application/tile_download_controller.dart';
import '../../routing_tiles/domain/routing_tile.dart';

/// Where the area the map shows stands with the offline data, which is what
/// the map's download button shows.
enum VisibleAreaState {
  /// Something the area needs is not on the device, or it cannot be told:
  /// the button opens the download.
  missing,

  /// Everything is on the device, but the mirror has rebuilt some of its
  /// tiles since: the button offers the update.
  update,

  /// A download is running for the area.
  busy,

  /// Nothing is left to fetch for the area.
  downloaded,
}

/// The state of the visible area, with what its button needs.
class VisibleAreaStatus {
  /// Creates the status.
  const VisibleAreaStatus(
    this.state, {
    this.stale = const <TileName>[],
    this.progress,
  });

  /// Where the area stands.
  final VisibleAreaState state;

  /// The tiles in view with an update on the mirror, for
  /// [VisibleAreaState.update].
  final List<TileName> stale;

  /// How far the running download is, 0..1, while [VisibleAreaState.busy];
  /// `null` when it cannot say.
  final double? progress;
}

/// Works out [VisibleAreaStatus] for [bounds] from what the device already
/// knows: the tile rows, the gazetteer files beside them, the download queue
/// and, where the platform keeps map areas, the stored [regions]. Nothing
/// is fetched.
///
/// [manifest] is the mirror's, when it has been read this session: with it
/// a tile the mirror does not offer (open sea) and a gazetteer the mirror
/// has none of do not count as missing. Without it every tile in view is
/// wanted with its gazetteer, so a view is never called downloaded when it
/// is not.
///
/// [regions] reads the stored map areas, `null` on a platform without them
/// (a browser). It is only called once the routing data is all there, so a
/// view with tiles missing never has them read.
VisibleAreaStatus visibleAreaStatus({
  required BoundingBox? bounds,
  required List<RoutingTile> tiles,
  required bool Function(TileName tile) hasGazetteer,
  required TileDownloadQueueState queue,
  SegmentsManifest? manifest,
  double? mapProgress,
  List<OfflineRegionRow> Function()? regions,
}) {
  if (mapProgress != null) {
    return VisibleAreaStatus(
      VisibleAreaState.busy,
      progress: mapProgress > 0 ? mapProgress : null,
    );
  }
  const missing = VisibleAreaStatus(VisibleAreaState.missing);
  if (bounds == null) return missing;
  final wanted = tilesForBounds(bounds);
  if (queue.isRunning &&
      wanted.any((t) => t == queue.current || queue.queued.contains(t))) {
    return VisibleAreaStatus(
      VisibleAreaState.busy,
      progress: queue.progress?.fraction,
    );
  }
  final index = manifest?.byTile;
  final offered = index == null
      ? wanted
      : wanted.where(index.containsKey).toList();
  // Nothing the mirror has here: there is nothing to download, and the
  // download says so when tapped.
  if (offered.isEmpty) return missing;

  final usable = <TileName, RoutingTile>{
    for (final tile in tiles)
      if (tile.isUsable) tile.tile: tile,
  };
  // Every tile looked up before any gazetteer file is: a view with a tile
  // missing is answered without touching the disk.
  if (!offered.every(usable.containsKey)) return missing;
  final stale = <TileName>[];
  for (final name in offered) {
    final gazetteerOffered = index == null || index[name]?.gazetteer != null;
    if (gazetteerOffered && !hasGazetteer(name)) return missing;
    if (usable[name]!.isStale) stale.add(name);
  }
  if (regions != null && !regions().any((r) => _covers(r, bounds))) {
    return missing;
  }
  if (stale.isNotEmpty) {
    return VisibleAreaStatus(VisibleAreaState.update, stale: stale);
  }
  return const VisibleAreaStatus(VisibleAreaState.downloaded);
}

/// Whether the finished map area [region] holds all of [view]. A little
/// slack, so that the view a download was started from still counts after
/// the camera has settled a hair differently.
bool _covers(OfflineRegionRow region, BoundingBox view) {
  if (region.maplibreRegionId == null) return false;
  final slackLat = view.latSpan * 0.02;
  final slackLon = view.lonSpan * 0.02;
  return region.bboxMinLat <= view.south + slackLat &&
      region.bboxMaxLat >= view.north - slackLat &&
      region.bboxMinLon <= view.west + slackLon &&
      region.bboxMaxLon >= view.east - slackLon;
}
