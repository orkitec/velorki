import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/offline/application/visible_area_status.dart';
import 'package:velorki/features/routing_tiles/application/tile_download_controller.dart';
import 'package:velorki/features/routing_tiles/data/tile_downloader.dart';
import 'package:velorki/features/routing_tiles/domain/routing_tile.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

const TileName _a = TileName(10, 45);
const TileName _b = TileName(15, 45);

/// Inside E10_N45 only.
const BoundingBox _inA = BoundingBox(
  south: 46,
  west: 10.5,
  north: 47,
  east: 11.5,
);

/// Across E10_N45 and E15_N45.
const BoundingBox _acrossAB = BoundingBox(
  south: 46,
  west: 14.5,
  north: 47,
  east: 15.5,
);

RoutingTile _tile(
  TileName name, {
  RoutingTileState state = RoutingTileState.ready,
}) => RoutingTile(
  tile: name,
  bytes: 10,
  updatedAt: DateTime.utc(2026, 9),
  formatVersion: '11.2',
  state: state,
);

SegmentEntry _entry(TileName name, {bool gazetteer = true}) => SegmentEntry(
  tile: name,
  bytes: 10,
  gazetteer: gazetteer
      ? GazetteerEntry(tile: name, bytes: 4, sha256: 'ab' * 32)
      : null,
);

OfflineRegionRow _region(BoundingBox box, {int? maplibreId = 1}) =>
    OfflineRegionRow(
      id: 'r',
      name: 'r',
      bboxMinLat: box.south,
      bboxMinLon: box.west,
      bboxMaxLat: box.north,
      bboxMaxLon: box.east,
      maplibreRegionId: maplibreId,
      sizeBytes: 1,
      downloadedAt: DateTime.utc(2026, 10),
    );

VisibleAreaState _state({
  BoundingBox? bounds = _inA,
  List<RoutingTile> tiles = const <RoutingTile>[],
  Set<TileName> gazetteers = const <TileName>{},
  TileDownloadQueueState queue = const TileDownloadQueueState(),
  SegmentsManifest? manifest,
  double? mapProgress,
  List<OfflineRegionRow> Function()? regions,
}) => visibleAreaStatus(
  bounds: bounds,
  tiles: tiles,
  hasGazetteer: gazetteers.contains,
  queue: queue,
  manifest: manifest,
  mapProgress: mapProgress,
  regions: regions,
).state;

void main() {
  test('nothing on the device: missing', () {
    expect(_state(), VisibleAreaState.missing);
    expect(_state(bounds: null), VisibleAreaState.missing);
  });

  test('the tile and its gazetteer on the device: downloaded', () {
    expect(
      _state(tiles: [_tile(_a)], gazetteers: {_a}),
      VisibleAreaState.downloaded,
    );
  });

  test('a tile without the gazetteer the mirror offers is missing', () {
    expect(_state(tiles: [_tile(_a)]), VisibleAreaState.missing);
    expect(
      _state(
        tiles: [_tile(_a)],
        manifest: SegmentsManifest(tiles: [_entry(_a)]),
      ),
      VisibleAreaState.missing,
    );
    // The mirror has none for it: the tile alone is everything.
    expect(
      _state(
        tiles: [_tile(_a)],
        manifest: SegmentsManifest(tiles: [_entry(_a, gazetteer: false)]),
      ),
      VisibleAreaState.downloaded,
    );
  });

  test('partly downloaded: missing', () {
    expect(
      _state(bounds: _acrossAB, tiles: [_tile(_a)], gazetteers: {_a}),
      VisibleAreaState.missing,
    );
  });

  test('a tile the mirror does not offer does not count', () {
    expect(
      _state(
        bounds: _acrossAB,
        tiles: [_tile(_a)],
        gazetteers: {_a},
        manifest: SegmentsManifest(tiles: [_entry(_a)]),
      ),
      VisibleAreaState.downloaded,
    );
    // A view of nothing the mirror has is not downloaded either.
    expect(
      _state(manifest: SegmentsManifest(tiles: [_entry(_b)])),
      VisibleAreaState.missing,
    );
  });

  test('a tile the mirror has rebuilt makes it an update', () {
    final status = visibleAreaStatus(
      bounds: _acrossAB,
      tiles: [
        _tile(_a),
        _tile(_b, state: RoutingTileState.stale),
      ],
      hasGazetteer: (_) => true,
      queue: const TileDownloadQueueState(),
    );
    expect(status.state, VisibleAreaState.update);
    expect(status.stale, [_b]);
  });

  test('a running download for the view is busy, with its progress', () {
    final status = visibleAreaStatus(
      bounds: _inA,
      tiles: const <RoutingTile>[],
      hasGazetteer: (_) => false,
      queue: const TileDownloadQueueState(
        current: _a,
        progress: TileDownloadProgress(tile: _a, received: 5, total: 10),
      ),
    );
    expect(status.state, VisibleAreaState.busy);
    expect(status.progress, 0.5);
    // A download elsewhere leaves this view's state alone.
    expect(
      _state(
        tiles: [_tile(_a)],
        gazetteers: {_a},
        queue: const TileDownloadQueueState(current: _b),
      ),
      VisibleAreaState.downloaded,
    );
    expect(_state(mapProgress: 0), VisibleAreaState.busy);
  });

  test('where the platform keeps map areas, one has to cover the view', () {
    final tiles = [_tile(_a)];
    expect(
      _state(tiles: tiles, gazetteers: {_a}, regions: () => const []),
      VisibleAreaState.missing,
    );
    expect(
      _state(tiles: tiles, gazetteers: {_a}, regions: () => [_region(_inA)]),
      VisibleAreaState.downloaded,
    );
    // Not finished yet, or too small for the view.
    expect(
      _state(
        tiles: tiles,
        gazetteers: {_a},
        regions: () => [_region(_inA, maplibreId: null)],
      ),
      VisibleAreaState.missing,
    );
    expect(
      _state(
        tiles: tiles,
        gazetteers: {_a},
        regions: () => [
          _region(
            const BoundingBox(south: 46, west: 10.5, north: 46.5, east: 11.5),
          ),
        ],
      ),
      VisibleAreaState.missing,
    );
  });
}
