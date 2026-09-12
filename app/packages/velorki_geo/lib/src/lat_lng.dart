import 'dart:math' as math;

/// An immutable WGS84 coordinate in decimal degrees.
///
/// Latitude grows northwards (-90..90), longitude eastwards (-180..180).
/// Nothing is normalised on construction: the value you pass is the value you
/// get back, which keeps round trips through the packed codec exact.
class LatLng {
  /// Creates a coordinate from decimal degrees.
  const LatLng(this.lat, this.lon);

  /// Latitude in decimal degrees.
  final double lat;

  /// Longitude in decimal degrees.
  final double lon;

  /// Latitude in radians.
  double get latRad => lat * math.pi / 180.0;

  /// Longitude in radians.
  double get lonRad => lon * math.pi / 180.0;

  /// This coordinate with both components rounded to [decimals] places.
  ///
  /// Used for privacy (the assistant only ever sees a start rounded to two
  /// decimals, roughly a kilometre) and for the repeated-segment hashing in
  /// `velorki_loops`.
  LatLng round(int decimals) {
    final f = math.pow(10, decimals).toDouble();
    return LatLng((lat * f).roundToDouble() / f, (lon * f).roundToDouble() / f);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'LatLng($lat, $lon)';
}
