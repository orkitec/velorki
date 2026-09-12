// Port of btools.util.CheapAngleMeter (BRouter v1.7.10).
//
// Calculate the angle defined by 3 points
// (and deliver it's cosine on the fly)

import 'dart:math' as math;

import '../jmath.dart';
import '../jvm.dart';
import 'cheap_ruler.dart';

class CheapAngleMeter {
  double _cosangle = 0.0;

  double getCosAngle() {
    return _cosangle;
  }

  double calcAngle(int lon0, int lat0, int lon1, int lat1, int lon2, int lat2) {
    final lonlat2m = CheapRuler.getLonLatToMeterScales(lat1);
    final lon2m = lonlat2m[0];
    final lat2m = lonlat2m[1];
    final dx10 = (lon1 - lon0) * lon2m;
    final dy10 = (lat1 - lat0) * lat2m;
    final dx21 = (lon2 - lon1) * lon2m;
    final dy21 = (lat2 - lat1) * lat2m;

    final dd = math.sqrt(
      (dx10 * dx10 + dy10 * dy10) * (dx21 * dx21 + dy21 * dy21),
    );
    if (dd == 0.0) {
      _cosangle = 1.0;
      return 0.0;
    }
    var sinp = (dy10 * dx21 - dx10 * dy21) / dd;
    final cosp = (dy10 * dy21 + dx10 * dx21) / dd;
    _cosangle = cosp;

    var offset = 0.0;
    var s2 = sinp * sinp;
    if (s2 > 0.5) {
      if (sinp > 0.0) {
        offset = 90.0;
        sinp = -cosp;
      } else {
        offset = -90.0;
        sinp = cosp;
      }
      s2 = cosp * cosp;
    } else if (cosp < 0.0) {
      sinp = -sinp;
      offset = sinp > 0.0 ? -180.0 : 180.0;
    }
    return offset +
        sinp * (57.4539 + s2 * (9.57565 + s2 * (4.30904 + s2 * 2.56491)));
  }

  static double getAngle(int lon1, int lat1, int lon2, int lat2) {
    var res = 0.0;
    final double xdiff = (lat2 - lat1).toDouble();
    final double ydiff = (lon2 - lon1).toDouble();
    res = toDegrees(JMath.atan2(ydiff, xdiff));
    return res;
  }

  static double getDirection(int lon1, int lat1, int lon2, int lat2) {
    final res = getAngle(lon1, lat1, lon2, lat2);
    return normalize(res);
  }

  static double normalize(double a) {
    return a >= 360
        ? a - (360 * d2i(a / 360))
        : a < 0
        ? a - (360 * (d2i(a / 360) - 1))
        : a;
  }

  static double getDifferenceFromDirection(double b1, double b2) {
    var r = frem(b2 - b1, 360.0);
    if (r < -180.0) r += 360.0;
    if (r >= 180.0) r -= 360.0;
    return r.abs();
  }
}
