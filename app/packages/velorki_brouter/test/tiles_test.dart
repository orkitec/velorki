import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

List<String> names(List<TileName> tiles) =>
    tiles.map((t) => t.name).toList(growable: false);

void main() {
  group('TileName.of', () {
    test('floors to the 5 degree grid', () {
      expect(TileName.of(47.3, 12.8).name, 'E10_N45');
      expect(TileName.of(45.0, 10.0).name, 'E10_N45');
      expect(TileName.of(49.999999, 14.999999).name, 'E10_N45');
    });

    test('an exact multiple of 5 belongs to the tile that starts there', () {
      // The half-open convention: lon 15 is the first metre of E15, not the
      // last of E10.
      expect(TileName.of(45.0, 15.0).name, 'E15_N45');
      expect(TileName.of(50.0, 10.0).name, 'E10_N50');
    });

    test('negative coordinates round towards the south-west', () {
      expect(TileName.of(-7.5, -2.3).name, 'W5_S10');
      expect(TileName.of(-10.0, -5.0).name, 'W5_S10');
      expect(TileName.of(-0.1, -0.1).name, 'W5_S5');
    });

    test('zero is the positive hemisphere', () {
      expect(TileName.of(0, 0).name, 'E0_N0');
      expect(TileName.of(2.5, 0).name, 'E0_N0');
      expect(TileName.of(0, 2.5).name, 'E0_N0');
      expect(TileName.of(-0.000001, 0).name, 'E0_S5');
      expect(TileName.of(0, -0.000001).name, 'W5_N0');
    });

    test('Madeira and south-west Iceland are the oracle tiles', () {
      expect(TileName.of(32.65, -16.92).name, 'W20_N30');
      expect(TileName.of(64.1, -21.9).name, 'W25_N60');
    });

    test('the poles and the antimeridian stay inside the grid', () {
      expect(TileName.of(90, 180).name, 'E175_N85');
      expect(TileName.of(-90, -180).name, 'W180_S90');
    });

    test('fromLatLng agrees with of', () {
      expect(TileName.fromLatLng(const LatLng(47.3, 12.8)).name, 'E10_N45');
    });

    test('rejects a non-finite coordinate', () {
      expect(() => TileName.of(double.nan, 0), throwsArgumentError);
      expect(() => TileName.of(0, double.infinity), throwsArgumentError);
    });
  });

  group('TileName parsing and shape', () {
    test('round trips through its name', () {
      for (final name in const ['E10_N45', 'W5_S10', 'E0_N0', 'W180_S90']) {
        expect(TileName.parse(name).name, name);
      }
    });

    test('parses a file name', () {
      expect(TileName.parse('W20_N30.rd5'), const TileName(-20, 30));
      expect(TileName.tryParse('w20_n30.RD5'), const TileName(-20, 30));
    });

    test('rejects what is not a tile', () {
      for (final s in const [
        '',
        'manifest.json',
        'E10_N45.rd5.part',
        'E11_N45',
        'E10_N46',
        'E185_N45',
        'E10_N90',
        'N45_E10',
        'E10-N45',
      ]) {
        expect(TileName.tryParse(s), isNull, reason: s);
      }
      expect(() => TileName.parse('nope'), throwsFormatException);
    });

    test('fileName, bounds and contains', () {
      const tile = TileName(-20, 30);
      expect(tile.fileName, 'W20_N30.rd5');
      expect(
        tile.bounds,
        const BoundingBox(south: 30, west: -20, north: 35, east: -15),
      );
      expect(tile.contains(const LatLng(32.65, -16.92)), isTrue);
      expect(tile.contains(const LatLng(30, -20)), isTrue);
      // half-open: the north and east edges belong to the next tile
      expect(tile.contains(const LatLng(35, -17)), isFalse);
      expect(tile.contains(const LatLng(32, -15)), isFalse);
    });

    test('equality, hashing and ordering', () {
      expect(const TileName(-20, 30), const TileName(-20, 30));
      expect(
        const TileName(-20, 30).hashCode,
        const TileName(-20, 30).hashCode,
      );
      expect({
        const TileName(-20, 30),
        TileName.parse('W20_N30'),
      }, hasLength(1));
      final sorted = <TileName>[
        const TileName(10, 45),
        const TileName(5, 45),
        const TileName(0, 40),
      ]..sort();
      expect(names(sorted), ['E0_N40', 'E5_N45', 'E10_N45']);
      expect(const TileName(-20, 30).toString(), 'W20_N30');
    });
  });

  group('tilesForBounds', () {
    test('a box inside one tile needs that one tile', () {
      expect(
        names(
          tilesForBounds(
            const BoundingBox(
              south: 32.6,
              west: -17.0,
              north: 32.8,
              east: -16.7,
            ),
          ),
        ),
        ['W20_N30'],
      );
    });

    test('spans a grid, south to north and west to east', () {
      expect(
        names(
          tilesForBounds(
            const BoundingBox(south: 44, west: 8, north: 51, east: 12),
          ),
        ),
        ['E5_N40', 'E10_N40', 'E5_N45', 'E10_N45', 'E5_N50', 'E10_N50'],
      );
    });

    test('an edge exactly on a multiple of 5 pulls in the next tile', () {
      // A waypoint at lon 10 lives in E10, so a box ending there needs it.
      expect(
        names(
          tilesForBounds(
            const BoundingBox(south: 45, west: 5, north: 45, east: 10),
          ),
        ),
        ['E5_N45', 'E10_N45'],
      );
      expect(
        names(
          tilesForBounds(
            const BoundingBox(south: 45, west: 5, north: 45, east: 9.999999),
          ),
        ),
        ['E5_N45'],
      );
    });

    test('a degenerate box on the grid needs exactly one tile', () {
      expect(
        names(
          tilesForBounds(
            const BoundingBox(south: 45, west: 10, north: 45, east: 10),
          ),
        ),
        ['E10_N45'],
      );
    });

    test('crosses the equator and the prime meridian', () {
      expect(
        names(
          tilesForBounds(
            const BoundingBox(south: -3, west: -3, north: 3, east: 3),
          ),
        ),
        ['W5_S5', 'E0_S5', 'W5_N0', 'E0_N0'],
      );
    });

    test('negative boxes', () {
      expect(
        names(
          tilesForBounds(
            const BoundingBox(south: -12, west: -8, north: -6, east: -4),
          ),
        ),
        ['W10_S15', 'W5_S15', 'W10_S10', 'W5_S10'],
      );
    });

    test('the poles clamp instead of producing N90', () {
      final north = tilesForBounds(
        const BoundingBox(south: 86, west: 0, north: 90, east: 4),
      );
      expect(names(north), ['E0_N85']);
      final south = tilesForBounds(
        const BoundingBox(south: -90, west: 0, north: -87, east: 4),
      );
      expect(names(south), ['E0_S90']);
    });
  });

  group('tilesForRoute', () {
    test('a short route gets the 10 km minimum expansion', () {
      // Funchal to Machico, 15 km apart: 20 % is 3 km, so the 10 km floor
      // applies. Both ends are far from a tile edge, so it stays one tile.
      expect(
        names(
          tilesForRoute(const [LatLng(32.65, -16.92), LatLng(32.72, -16.77)]),
        ),
        ['W20_N30'],
      );
    });

    test('near a tile edge the expansion reaches over it', () {
      // The W15 boundary is at lon -15. Five kilometres west of it the 10 km
      // margin crosses it; twenty kilometres west of it, it does not.
      expect(
        names(
          tilesForRoute(const [LatLng(32.6, -15.08), LatLng(32.7, -15.05)]),
        ),
        ['W20_N30', 'W15_N30'],
      );
      expect(
        names(
          tilesForRoute(const [LatLng(32.6, -15.25), LatLng(32.7, -15.21)]),
        ),
        ['W20_N30'],
      );
    });

    test('a long route gets 20 % of its diagonal', () {
      // Munich to Hamburg: a 610 km diagonal, so the margin is 122 km, which
      // is what pulls in E5_N45 and E5_N50 west of both cities.
      final tiles = tilesForRoute(const [
        LatLng(48.137, 11.575),
        LatLng(53.551, 9.993),
      ]);
      expect(names(tiles), ['E5_N45', 'E10_N45', 'E5_N50', 'E10_N50']);
    });

    test('the expansion is configurable', () {
      expect(
        names(
          tilesForRoute(const [
            LatLng(32.6, -15.25),
            LatLng(32.7, -15.21),
          ], minExpandMeters: 1000),
        ),
        ['W20_N30'],
      );
    });

    test('a single point still yields its tile', () {
      expect(names(tilesForRoute(const [LatLng(32.65, -16.92)])), ['W20_N30']);
    });

    test('no points, no tiles', () {
      expect(tilesForRoute(const []), isEmpty);
    });
  });
}
