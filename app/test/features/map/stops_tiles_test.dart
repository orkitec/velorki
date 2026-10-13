import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/domain/stops_tiles.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  group('the grid the stops are loaded by', () {
    test('is one level coarser than the map, within its bounds', () {
      expect(stopsTileZoom(5), stopsTileMinZoom);
      expect(stopsTileZoom(11), 10);
      expect(stopsTileZoom(12.5), 11);
      expect(stopsTileZoom(13.9), 12);
      expect(stopsTileZoom(14), 13);
      // A map asked for 14 that settles a hair below it.
      expect(stopsTileZoom(13.9993), 13);
      expect(stopsTileZoom(18), stopsTileMaxZoom);
    });

    test('a square is where the web map grid puts it', () {
      // Funchal at zoom 13.
      final tiles = tilesCovering(
        const BoundingBox(
          south: 32.6475,
          west: -16.9105,
          north: 32.6475,
          east: -16.9105,
        ),
        13,
      );
      expect(tiles, {const StopsTile(13, 3711, 3309)});
      final box = tiles.single.box;
      expect(box.west, lessThanOrEqualTo(-16.9105));
      expect(box.east, greaterThan(-16.9105));
      expect(box.south, lessThanOrEqualTo(32.6475));
      expect(box.north, greaterThan(32.6475));
      expect(box.east - box.west, closeTo(360 / 8192, 1e-12));
    });

    test('a box is covered by every square it touches, and the squares '
        'meet edge to edge', () {
      const area = BoundingBox(
        south: 47.99,
        west: 10.985,
        north: 48.03,
        east: 11.045,
      );
      final tiles = tilesCovering(area, 13).toList()..sort();
      expect(tiles, hasLength(6));
      for (final tile in tiles) {
        final box = tile.box;
        expect(box.north, greaterThan(area.south));
        expect(box.south, lessThan(area.north));
        expect(box.east, greaterThan(area.west));
        expect(box.west, lessThan(area.east));
        final east = StopsTile(13, tile.x + 1, tile.y).box;
        expect(east.west, box.east);
        final south = StopsTile(13, tile.x, tile.y + 1).box;
        expect(south.north, closeTo(box.south, 1e-12));
      }
      // Sorted north to south, then west to east.
      expect(tiles.first.y, lessThan(tiles.last.y));
    });

    test('a square\'s own box is covered by that square alone', () {
      const tile = StopsTile(12, 1850, 1680);
      final box = tile.box;
      const inset = 1e-9;
      final inside = BoundingBox(
        south: box.south + inset,
        west: box.west + inset,
        north: box.north - inset,
        east: box.east - inset,
      );
      expect(tilesCovering(inside, 12), {tile});
    });

    test('a box over the antimeridian wraps round', () {
      final tiles = tilesCovering(
        const BoundingBox(
          south: -17,
          west: 179.99,
          north: -16.99,
          east: 180.01,
        ),
        10,
      );
      expect(tiles.map((t) => t.x).toSet(), {1023, 0});
    });

    test('squares are equal by their place in the grid', () {
      expect(const StopsTile(13, 1, 2), const StopsTile(13, 1, 2));
      expect(const StopsTile(13, 1, 2), isNot(const StopsTile(12, 1, 2)));
      // Built apart, as the controller builds them.
      final x = int.parse('1');
      expect({const StopsTile(13, 1, 2), StopsTile(13, x, 2)}, hasLength(1));
    });
  });
}
