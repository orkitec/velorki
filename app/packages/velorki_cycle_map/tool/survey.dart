// Reads a box out of an rd5 tile and prints what the cycle map finds, with
// timings: `dart run tool/survey.dart <rd5> <lon> <lat> [km]`.
import 'dart:io';
import 'dart:math' as math;

import 'package:velorki_cycle_map/velorki_cycle_map.dart';

void main(List<String> args) {
  final lookups = File(
    '${File(Platform.script.toFilePath()).parent.parent.parent.parent.path}'
    '/assets/brouter/profiles/lookups.dat',
  ).readAsLinesSync();
  final reader = Rd5CellReader(lookups);
  final tile = reader.open(File(args[0]));
  final lon = double.parse(args[1]);
  final lat = double.parse(args[2]);
  final km = args.length > 3 ? double.parse(args[3]) : 5.0;
  final div = reader.divisor(tile);
  final dLat = km / 2 / 111.32;
  final dLon = km / 2 / (111.32 * math.cos(lat * math.pi / 180));
  int idx(double deg, double off) => ((deg + off) * div).floor();
  for (var rep = 0; rep < 3; rep++) {
    final sw = Stopwatch()..start();
    var lines = 0, points = 0, barriers = 0, cells = 0, bytes = 0;
    final grades = [0, 0, 0, 0];
    final kinds = <String, int>{};
    for (var x = idx(lon - dLon, 180); x <= idx(lon + dLon, 180); x++) {
      for (var y = idx(lat - dLat, 90); y <= idx(lat + dLat, 90); y++) {
        final cell = reader.readCell(tile, x, y);
        cells++;
        lines += cell.lineCount;
        points += cell.pointCount;
        barriers += cell.barrierCount;
        bytes += cell.byteSize;
        for (final g in cell.climbGrades) {
          grades[g]++;
        }
        for (final a in cell.attrs) {
          final at = CycleAttrs(a);
          void count(String k) => kinds[k] = (kinds[k] ?? 0) + 1;
          count(at.kind.name);
          if (at.track != 0) count('track');
          if (at.lane != 0) count('lane');
          if (at.contraflow) count('contraflow');
          if (at.routes != 0) count('route');
          if (at.unpaved) count('unpaved');
          if (at.rough) count('rough');
          if (at.mtbScale != null) count('mtb');
        }
      }
    }
    if (rep == 2) {
      print(
        '$cells cells, $lines lines, $points points, $barriers barriers, '
        '${bytes >> 10} KB, ${sw.elapsedMilliseconds} ms, '
        '${reader.descriptionCount} descriptions',
      );
      print(kinds);
      print('climbs by grade class 1/2/3: ${grades.sublist(1)}');
    }
  }
  tile.close();
}
