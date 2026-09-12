import 'dart:math' as math;

import 'geodesy.dart';
import 'lat_lng.dart';

/// An axis-aligned latitude/longitude rectangle.
///
/// The box does not wrap the antimeridian: [west] is always `<=` [east]. That
/// is good enough for route and ride extents, which never span half the globe,
/// and keeps [contains] and [intersects] trivial.
class BoundingBox {
  /// Creates a box from its edges.
  const BoundingBox({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  /// The smallest box containing every point of [points].
  ///
  /// Throws [ArgumentError] when [points] is empty.
  factory BoundingBox.fromPoints(Iterable<LatLng> points) {
    if (points.isEmpty) {
      throw ArgumentError.value(points, 'points', 'must not be empty');
    }
    var south = double.infinity;
    var west = double.infinity;
    var north = double.negativeInfinity;
    var east = double.negativeInfinity;
    for (final p in points) {
      if (p.lat < south) south = p.lat;
      if (p.lat > north) north = p.lat;
      if (p.lon < west) west = p.lon;
      if (p.lon > east) east = p.lon;
    }
    return BoundingBox(south: south, west: west, north: north, east: east);
  }

  /// Southern edge in decimal degrees.
  final double south;

  /// Western edge in decimal degrees.
  final double west;

  /// Northern edge in decimal degrees.
  final double north;

  /// Eastern edge in decimal degrees.
  final double east;

  /// Height of the box in degrees of latitude.
  double get latSpan => north - south;

  /// Width of the box in degrees of longitude.
  double get lonSpan => east - west;

  /// The centre of the box.
  LatLng get center => LatLng((south + north) / 2, (west + east) / 2);

  /// The south-west corner.
  LatLng get southWest => LatLng(south, west);

  /// The north-east corner.
  LatLng get northEast => LatLng(north, east);

  /// Whether [p] lies inside the box (edges included).
  bool contains(LatLng p) =>
      p.lat >= south && p.lat <= north && p.lon >= west && p.lon <= east;

  /// Whether this box and [other] share at least an edge point.
  bool intersects(BoundingBox other) =>
      south <= other.north &&
      north >= other.south &&
      west <= other.east &&
      east >= other.west;

  /// This box grown by [meters] on every side.
  ///
  /// The longitude growth is scaled by the cosine of the latitude closest to
  /// the pole, so the box really covers [meters] everywhere inside it. Edges
  /// are clamped to the valid coordinate range.
  BoundingBox expandMeters(double meters) {
    final dLat = meters / earthRadiusMeters * 180.0 / math.pi;
    final worstLat = math.max(south.abs(), north.abs());
    final cos = math.max(math.cos(worstLat * math.pi / 180.0), 1e-6);
    final dLon = dLat / cos;
    return BoundingBox(
      south: math.max(-90.0, south - dLat),
      north: math.min(90.0, north + dLat),
      west: math.max(-180.0, west - dLon),
      east: math.min(180.0, east + dLon),
    );
  }

  /// This box grown by [f] times its own size on every side.
  ///
  /// `expandFraction(0.1)` on a 1° tall box adds 0.1° top and bottom. A
  /// degenerate (point or line) box grows by [f] degrees in that axis so the
  /// result still has area.
  BoundingBox expandFraction(double f) {
    final dLat = latSpan == 0 ? f : latSpan * f;
    final dLon = lonSpan == 0 ? f : lonSpan * f;
    return BoundingBox(
      south: math.max(-90.0, south - dLat),
      north: math.min(90.0, north + dLat),
      west: math.max(-180.0, west - dLon),
      east: math.min(180.0, east + dLon),
    );
  }

  /// The smallest box containing both this box and [other].
  BoundingBox union(BoundingBox other) => BoundingBox(
    south: math.min(south, other.south),
    west: math.min(west, other.west),
    north: math.max(north, other.north),
    east: math.max(east, other.east),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoundingBox &&
          other.south == south &&
          other.west == west &&
          other.north == north &&
          other.east == east;

  @override
  int get hashCode => Object.hash(south, west, north, east);

  @override
  String toString() => 'BoundingBox(s: $south, w: $west, n: $north, e: $east)';
}
