import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

/// The coarsest grid the stops in the area are loaded by.
const int stopsTileMinZoom = 10;

/// The finest grid the stops in the area are loaded by.
const int stopsTileMaxZoom = 13;

/// The grid the stops in the area are loaded by at map zoom [mapZoom]: one
/// level coarser than the map's own, so a phone's screen and its margin span
/// a handful of squares at any zoom. It changes where the map's whole zoom
/// changes, which is where the bubbles are gathered anew anyway.
int stopsTileZoom(double mapZoom) =>
    ((mapZoom + 0.01).floor() - 1).clamp(stopsTileMinZoom, stopsTileMaxZoom);

/// One square of the web map grid the stops in the area are loaded by:
/// what it holds depends on where it lies, never on where the camera is.
final class StopsTile implements Comparable<StopsTile> {
  /// The square [x] from the west and [y] from the north at [zoom].
  const StopsTile(this.zoom, this.x, this.y);

  /// The grid's level: 2^zoom squares across the world.
  final int zoom;

  /// Columns from the antimeridian eastwards.
  final int x;

  /// Rows from the north edge of the map southwards.
  final int y;

  /// The ground the square covers.
  BoundingBox get box {
    final n = 1 << zoom;
    double lat(int row) =>
        math.atan(_sinh(math.pi * (1 - 2 * row / n))) * 180 / math.pi;
    return BoundingBox(
      south: lat(y + 1),
      west: x / n * 360 - 180,
      north: lat(y),
      east: (x + 1) / n * 360 - 180,
    );
  }

  static double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

  @override
  int compareTo(StopsTile other) {
    if (zoom != other.zoom) return zoom.compareTo(other.zoom);
    if (y != other.y) return y.compareTo(other.y);
    return x.compareTo(other.x);
  }

  @override
  bool operator ==(Object other) =>
      other is StopsTile && other.zoom == zoom && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(zoom, x, y);

  @override
  String toString() => 'StopsTile($zoom/$x/$y)';
}

/// Every square of the grid at [zoom] that [box] touches. A box reaching
/// past the antimeridian wraps round to the squares on the other side.
Set<StopsTile> tilesCovering(BoundingBox box, int zoom) {
  final n = 1 << zoom;
  int column(double lon) => ((lon + 180) / 360 * n).floor();
  int row(double lat) {
    final rad = lat.clamp(-85.0511, 85.0511) * math.pi / 180;
    final y = (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2;
    return (y * n).floor().clamp(0, n - 1);
  }

  final west = column(box.west);
  final east = math.min(column(box.east), west + n - 1);
  final north = row(box.north);
  final south = row(box.south);
  return <StopsTile>{
    for (var y = north; y <= south; y++)
      for (var x = west; x <= east; x++) StopsTile(zoom, x % n, y),
  };
}
