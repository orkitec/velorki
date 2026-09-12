// Port of btools.util.CheapRuler (BRouter v1.7.10).

import 'dart:math' as math;
import 'dart:typed_data';

import '../jmath.dart';
import '../jvm.dart';

/// Cheap-Ruler Java implementation
/// See
/// https://blog.mapbox.com/fast-geodesic-approximations-with-cheap-ruler-106f229ad016
/// for more details.
///
/// Original code is at https://github.com/mapbox/cheap-ruler under ISC license.
///
/// This is implemented as a Singleton to have a unique cache for the cosine
/// values across all the code.
class CheapRuler {
  CheapRuler._();

  // Conversion constants
  static const double ilatlngToLatlng = 1e-6; // From integer to degrees
  static const int kilometersToMeters = 1000;
  static const double degToRad = math.pi / 180.0;

  // Scale cache constants
  static const int _scaleCacheLength = 1800;
  static const int _scaleCacheIncrement = 100000;

  /// _scaleCacheLength cached values between 0 and COS_CACHE_MAX_DEGREES degrees.
  static final List<Float64List> _scaleCache = _buildScaleCache();

  /// build the cache of cosine values.
  static List<Float64List> _buildScaleCache() {
    final cache = List<Float64List>.generate(
      _scaleCacheLength,
      (i) => _calcKxKyFromILat(
        i * _scaleCacheIncrement + _scaleCacheIncrement ~/ 2,
      ),
      growable: false,
    );
    return cache;
  }

  static Float64List _calcKxKyFromILat(int ilat) {
    final lat = degToRad * (ilat * ilatlngToLatlng - 90);
    final cos = JMath.cos(lat);
    final cos2 = 2 * cos * cos - 1;
    final cos3 = 2 * cos * cos2 - cos;
    final cos4 = 2 * cos * cos3 - cos2;
    final cos5 = 2 * cos * cos4 - cos3;

    // Multipliers for converting integer longitude and latitude into distance
    // (http://1.usa.gov/1Wb1bv7)
    final kxky = Float64List(2);
    kxky[0] =
        (111.41513 * cos - 0.09455 * cos3 + 0.00012 * cos5) *
        ilatlngToLatlng *
        kilometersToMeters;
    kxky[1] =
        (111.13209 - 0.56605 * cos2 + 0.0012 * cos4) *
        ilatlngToLatlng *
        kilometersToMeters;
    return kxky;
  }

  /// Calculate the degree->meter scale for given latitude
  ///
  /// Returns [lon->meter,lat->meter]
  static Float64List getLonLatToMeterScales(int ilat) {
    return _scaleCache[ilat ~/ _scaleCacheIncrement];
  }

  /// Compute the distance (in meters) between two points represented by their
  /// (integer) latitude and longitude.
  ///
  /// Integer longitude is ((longitude in degrees) + 180) * 1e6.
  /// Integer latitude is ((latitude in degrees) + 90) * 1e6.
  static double distance(int ilon1, int ilat1, int ilon2, int ilat2) {
    final kxky = getLonLatToMeterScales(shr32(ilat1 + ilat2, 1));
    final dlon = (ilon1 - ilon2) * kxky[0];
    final dlat = (ilat1 - ilat2) * kxky[1];
    return math.sqrt(dlat * dlat + dlon * dlon); // in m
  }

  static Int32List destination(
    int lon1,
    int lat1,
    double distance,
    double angle,
  ) {
    final lonlat2m = getLonLatToMeterScales(lat1);
    final lon2m = lonlat2m[0];
    final lat2m = lonlat2m[1];
    angle = 90.0 - angle;
    final st = JMath.sin(angle * math.pi / 180.0);
    final ct = JMath.cos(angle * math.pi / 180.0);

    final lon2 = d2i(0.5 + lon1 + ct * distance / lon2m);
    final lat2 = d2i(0.5 + lat1 + st * distance / lat2m);
    final ret = Int32List(2);
    ret[0] = lon2;
    ret[1] = lat2;
    return ret;
  }
}
