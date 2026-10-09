// Steep length per area for a climb rule, to tune ClimbRule against cities
// that are flat, hilly, steep, and full of high-rises:
// dart run tool/climb_eval.dart
//   [smooth measureSmooth window minLength minRise detectGrade]
import 'dart:io';
import 'dart:math' as math;

import 'package:velorki_cycle_map/velorki_cycle_map.dart';

const areas = <(String, String, double, double)>[
  ('Midtown NYC (flat, high-rises)', 'W75_N40', -73.99, 40.75),
  ('Downtown NYC (flat, high-rises)', 'W75_N40', -74.01, 40.71),
  ('Cologne (flat)', 'E5_N50', 6.96, 50.94),
  ('SF downtown (high-rises + hills)', 'W125_N35', -122.40, 37.79),
  ('Washington Heights (hilly)', 'W75_N40', -73.937, 40.852),
  ('SF Noe Valley (steep)', 'W125_N35', -122.44, 37.755),
  ('Wuppertal (hilly)', 'E5_N50', 7.15, 51.26),
  ('Lausanne (steep)', 'E5_N45', 6.633, 46.52),
  ('Funchal (steep)', 'W20_N30', -16.91, 32.65),
];

void main(List<String> a) {
  final home = Platform.environment['HOME'];
  final reader = Rd5CellReader(
    File('../../assets/brouter/profiles/lookups.dat').readAsLinesSync(),
  );
  if (a.length >= 6) {
    reader.climbRule = ClimbRule(
      smoothMetres: double.parse(a[0]),
      measureSmoothMetres: double.parse(a[1]),
      windowMetres: double.parse(a[2]),
      minLengthMetres: double.parse(a[3]),
      minRiseMetres: double.parse(a[4]),
      detectGrade: double.parse(a[5]),
    );
  }
  for (final (name, tileName, lon, lat) in areas) {
    final path = tileName == 'W20_N30'
        ? '../../../tools/brouter-oracle/tiles/W20_N30.rd5'
        : '$home/.cache/velorki-tiles/$tileName.rd5';
    final tile = reader.open(File(path));
    final x = ((lon + 180) * 32).floor();
    final y = ((lat + 90) * 32).floor();
    final metres = [0.0, 0.0, 0.0, 0.0];
    for (var dx = 0; dx < 2; dx++) {
      for (var dy = 0; dy < 2; dy++) {
        final c = reader.readCell(tile, x + dx, y + dy, climbs: true);
        for (var i = 0; i < c.climbCount; i++) {
          var d = 0.0;
          for (var p = c.climbStarts[i] + 1; p < c.climbStarts[i + 1]; p++) {
            final ex =
                (c.climbCoords[p * 2] - c.climbCoords[p * 2 - 2]) *
                0.11132 *
                math.cos(lat * math.pi / 180);
            final ey =
                (c.climbCoords[p * 2 + 1] - c.climbCoords[p * 2 - 1]) *
                0.110574;
            d += math.sqrt(ex * ex + ey * ey);
          }
          metres[c.climbGrades[i]] += d;
        }
      }
    }
    tile.close();
    String km(double m) => (m / 1000).toStringAsFixed(1).padLeft(5);
    print(
      '${name.padRight(34)} km  6%+:${km(metres[1])}  10%+:${km(metres[2])}  15%+:${km(metres[3])}',
    );
  }
}
