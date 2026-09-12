// Port of btools.router.AreaInfo (BRouter v1.7.10).

import 'dart:typed_data';

import '../expressions/b_expression_context.dart';
import '../jfloat.dart';
import '../jvm.dart';
import 'osm_nogo_polygon.dart';

class AreaInfo {
  static const int resultTypeNone = 0;
  static const int resultTypeElev50 = 1;
  static const int resultTypeGreen = 4;
  static const int resultTypeRiver = 5;

  int direction;
  int numForest = -1;
  int numRiver = -1;

  OsmNogoPolygon? polygon;

  int ways = 0;
  int greenWays = 0;
  int riverWays = 0;
  double elevStart = 0;
  int elev50 = 0;

  AreaInfo(int dir) : direction = dir;

  void checkAreaInfo(BExpressionContext expctxWay, double elev, Uint8List ab) {
    ways++;

    final test = elevStart - elev;
    if (test.abs() < 50) elev50++;

    final ld2 = expctxWay.createNewLookupData()!;
    expctxWay.decodeInto(ld2, false, ab);

    if (numForest != -1 && ld2[numForest] > 1) {
      greenWays++;
    }

    if (numRiver != -1 && ld2[numRiver] > 1) {
      riverWays++;
    }
  }

  int getElev50Weight() {
    if (ways == 0) return 0;
    return d2i(elev50 * 100.0 / ways);
  }

  int getGreen() {
    if (ways == 0) return 0;
    return d2i(greenWays * 100.0 / ways);
  }

  int getRiver() {
    if (ways == 0) return 0;
    return d2i(riverWays * 100.0 / ways);
  }

  @override
  String toString() {
    final sb = StringBuffer();
    sb.write('Area $direction ${javaDoubleToString(elevStart)}m ways $ways');
    if (ways > 0) {
      sb.write('\nArea ways <50m  $elev50 ${getElev50Weight()}%');
      sb.write('\nArea ways green $greenWays ${getGreen()}%');
      sb.write('\nArea ways river $riverWays ${getRiver()}%');
    }
    return sb.toString();
  }
}
