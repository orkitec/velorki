import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

/// The edge length of one BRouter segment file, in degrees.
const int tileSizeDeg = 5;

/// The name of one BRouter rd5 segment tile, e.g. `E10_N45` or `W5_S10`.
///
/// BRouter cuts the planet into 5° × 5° tiles named after their south-west
/// corner: `lon0 = floor(lon / 5) * 5`, `lat0 = floor(lat / 5) * 5`, written
/// as the hemisphere letter plus the absolute value. Zero counts as the
/// positive hemisphere, so the tile at the intersection of the equator and
/// the prime meridian is `E0_N0`.
///
/// A tile covers the **half-open** box `[lon0, lon0 + 5) × [lat0, lat0 + 5)`:
/// a point at exactly lon 10 belongs to `E10_*`, not to `E5_*`. [bounds] is
/// the closed box of the same area, which is what a map overlay wants.
class TileName implements Comparable<TileName> {
  /// Creates a tile from its south-west corner, both multiples of 5.
  const TileName(this.lon0, this.lat0)
    : assert(
        lon0 % tileSizeDeg == 0 && lat0 % tileSizeDeg == 0,
        'tile origins are multiples of 5 degrees',
      ),
      assert(
        lon0 >= -180 && lon0 < 180 && lat0 >= -90 && lat0 < 90,
        'tile origin out of range',
      );

  /// The tile containing the coordinate ([lat], [lon] in decimal degrees).
  factory TileName.of(double lat, double lon) {
    if (!lat.isFinite || !lon.isFinite) {
      throw ArgumentError('not a finite coordinate: $lat, $lon');
    }
    final lat0 = math.min(85, math.max(-90, _floorToTile(lat)));
    final lon0 = math.min(175, math.max(-180, _floorToTile(lon)));
    return TileName(lon0, lat0);
  }

  /// The tile containing [p].
  factory TileName.fromLatLng(LatLng p) => TileName.of(p.lat, p.lon);

  /// Parses `E10_N45`, `W5_S10` or the file name `E10_N45.rd5`.
  ///
  /// Throws [FormatException] on anything else, including origins that are
  /// not multiples of 5 or lie outside the coordinate range.
  factory TileName.parse(String s) {
    final t = tryParse(s);
    if (t == null) throw FormatException('not a BRouter tile name', s);
    return t;
  }

  /// Like [TileName.parse] but returns `null` instead of throwing.
  static TileName? tryParse(String s) {
    var name = s.trim();
    if (name.toLowerCase().endsWith('.rd5')) {
      name = name.substring(0, name.length - 4);
    }
    final m = _namePattern.firstMatch(name);
    if (m == null) return null;
    final lon =
        int.parse(m.group(2)!) * (m.group(1)!.toUpperCase() == 'W' ? -1 : 1);
    final lat =
        int.parse(m.group(4)!) * (m.group(3)!.toUpperCase() == 'S' ? -1 : 1);
    if (lon % tileSizeDeg != 0 || lat % tileSizeDeg != 0) return null;
    if (lon < -180 || lon >= 180 || lat < -90 || lat >= 90) return null;
    return TileName(lon, lat);
  }

  static final RegExp _namePattern = RegExp(
    r'^([EWew])(\d{1,3})_([NSns])(\d{1,2})$',
  );

  /// Longitude of the south-west corner, a multiple of 5 in `[-180, 180)`.
  final int lon0;

  /// Latitude of the south-west corner, a multiple of 5 in `[-90, 90)`.
  final int lat0;

  /// The tile name as BRouter writes it, e.g. `W5_S10`.
  String get name =>
      '${lon0 < 0 ? 'W' : 'E'}${lon0.abs()}_${lat0 < 0 ? 'S' : 'N'}${lat0.abs()}';

  /// The segment file name, e.g. `W5_S10.rd5`.
  String get fileName => '$name.rd5';

  /// The offline gazetteer file name, e.g. `W5_S10.gaz`.
  String get gazetteerFileName => '$name.gaz';

  /// The area the tile covers, as a closed box.
  BoundingBox get bounds => BoundingBox(
    south: lat0.toDouble(),
    west: lon0.toDouble(),
    north: (lat0 + tileSizeDeg).toDouble(),
    east: (lon0 + tileSizeDeg).toDouble(),
  );

  /// Whether [p] falls into this tile, with BRouter's half-open edges.
  bool contains(LatLng p) =>
      p.lat >= lat0 &&
      p.lat < lat0 + tileSizeDeg &&
      p.lon >= lon0 &&
      p.lon < lon0 + tileSizeDeg;

  @override
  int compareTo(TileName other) => lat0 == other.lat0
      ? lon0.compareTo(other.lon0)
      : lat0.compareTo(other.lat0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileName && other.lon0 == lon0 && other.lat0 == lat0;

  @override
  int get hashCode => Object.hash(lon0, lat0);

  @override
  String toString() => name;
}

/// Every tile that intersects [bounds], ordered south to north, west to east.
///
/// The box edges are inclusive, so a box whose east edge is exactly a multiple
/// of 5 also needs the tile starting there — a waypoint on that meridian lives
/// in it. Boxes are clamped to the valid coordinate range; the antimeridian is
/// not wrapped (a box from 170° E to −170° E is read as spanning the globe,
/// which is not a case bike routing produces).
List<TileName> tilesForBounds(BoundingBox bounds) {
  final lat0 = math.max(-90, _floorToTile(bounds.south));
  final lat1 = math.min(85, _floorToTile(bounds.north));
  final lon0 = math.max(-180, _floorToTile(bounds.west));
  final lon1 = math.min(175, _floorToTile(bounds.east));
  if (lat1 < lat0 || lon1 < lon0) return const <TileName>[];

  final out = <TileName>[];
  for (var lat = lat0; lat <= lat1; lat += tileSizeDeg) {
    for (var lon = lon0; lon <= lon1; lon += tileSizeDeg) {
      out.add(TileName(lon, lat));
    }
  }
  return out;
}

/// The tiles on-device routing needs for a route through [points].
///
/// This is the rule of the plan: take the bounding box of the waypoints and
/// expand it by `max(minExpandMeters, expandFraction × diagonal)` — 10 km or
/// 20 % of the diagonal by default — because BRouter's search leaves the
/// direct corridor, and a missing tile is not an error but empty land, which
/// would silently produce a detour or no route at all.
///
/// Returns an empty list for an empty [points] list.
List<TileName> tilesForRoute(
  List<LatLng> points, {
  double expandFraction = 0.2,
  double minExpandMeters = 10000,
}) {
  if (points.isEmpty) return const <TileName>[];
  final box = BoundingBox.fromPoints(points);
  final diagonal = haversineMeters(box.southWest, box.northEast);
  final expand = math.max(minExpandMeters, expandFraction * diagonal);
  return tilesForBounds(box.expandMeters(expand));
}

int _floorToTile(double v) => (v / tileSizeDeg).floor() * tileSizeDeg;
