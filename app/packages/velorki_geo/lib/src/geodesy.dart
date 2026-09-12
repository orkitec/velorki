import 'dart:math' as math;

import 'lat_lng.dart';

/// Mean Earth radius in metres (IUGG mean radius R1), the value BRouter and
/// most OSM tooling use for great-circle distances.
const double earthRadiusMeters = 6371008.8;

double _deg(double rad) => rad * 180.0 / math.pi;

double _rad(double deg) => deg * math.pi / 180.0;

/// Great-circle distance between [a] and [b] in metres (haversine formula).
double haversineMeters(LatLng a, LatLng b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final lat1 = _rad(a.lat);
  final lat2 = _rad(b.lat);
  final sinDLat = math.sin(dLat / 2);
  final sinDLon = math.sin(dLon / 2);
  final h =
      sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;
  return 2 * earthRadiusMeters * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Initial great-circle bearing from [a] to [b], in degrees clockwise from
/// north, normalised to `[0, 360)`.
double bearingDegrees(LatLng a, LatLng b) {
  final lat1 = _rad(a.lat);
  final lat2 = _rad(b.lat);
  final dLon = _rad(b.lon - a.lon);
  final y = math.sin(dLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  final deg = _deg(math.atan2(y, x));
  return (deg + 360.0) % 360.0;
}

/// The point reached from [from] by travelling [meters] along the great circle
/// with initial bearing [bearingDeg] (degrees clockwise from north).
///
/// Longitude is normalised to `[-180, 180)`.
LatLng destinationPoint(LatLng from, double bearingDeg, double meters) {
  final delta = meters / earthRadiusMeters;
  final theta = _rad(bearingDeg);
  final lat1 = _rad(from.lat);
  final lon1 = _rad(from.lon);

  final sinLat2 =
      math.sin(lat1) * math.cos(delta) +
      math.cos(lat1) * math.sin(delta) * math.cos(theta);
  final lat2 = math.asin(math.min(1.0, math.max(-1.0, sinLat2)));
  final lon2 =
      lon1 +
      math.atan2(
        math.sin(theta) * math.sin(delta) * math.cos(lat1),
        math.cos(delta) - math.sin(lat1) * sinLat2,
      );
  final lonDeg = ((_deg(lon2) + 540.0) % 360.0) - 180.0;
  return LatLng(_deg(lat2), lonDeg);
}

/// Total length of the polyline [points] in metres. Fewer than two points
/// means zero length.
double polylineLengthMeters(List<LatLng> points) {
  var sum = 0.0;
  for (var i = 1; i < points.length; i++) {
    sum += haversineMeters(points[i - 1], points[i]);
  }
  return sum;
}

/// Distance from the first point to each point of [points], in metres.
///
/// The returned list has the same length as [points] and starts with `0.0`.
List<double> cumulativeDistancesMeters(List<LatLng> points) {
  final out = List<double>.filled(points.length, 0.0);
  var sum = 0.0;
  for (var i = 1; i < points.length; i++) {
    sum += haversineMeters(points[i - 1], points[i]);
    out[i] = sum;
  }
  return out;
}
