# velorki_geo

Geometry primitives shared by every other Velorki package: coordinates,
great-circle maths, bounding boxes, track points and the packed track codec.

Pure Dart, no Flutter dependency, no third-party dependencies, tested on the
desktop VM.

## Public API

```dart
class LatLng {
  const LatLng(double lat, double lon);
  final double lat, lon;
  double get latRad, lonRad;
  LatLng round(int decimals);          // privacy rounding, segment hashing
}

const double earthRadiusMeters = 6371008.8;
double haversineMeters(LatLng a, LatLng b);
double bearingDegrees(LatLng a, LatLng b);            // 0..360, clockwise from north
LatLng destinationPoint(LatLng from, double bearingDeg, double meters);
double polylineLengthMeters(List<LatLng> points);
List<double> cumulativeDistancesMeters(List<LatLng> points);

class BoundingBox {
  const BoundingBox({required double south, west, north, east});
  factory BoundingBox.fromPoints(Iterable<LatLng> points);
  double get latSpan, lonSpan;
  LatLng get center, southWest, northEast;
  bool contains(LatLng p);
  bool intersects(BoundingBox other);
  BoundingBox expandMeters(double meters);
  BoundingBox expandFraction(double f);
  BoundingBox union(BoundingBox other);
}

class TrackPoint {
  const TrackPoint(LatLng pos, {double? ele, DateTime? time,
                                double? speedMps, double? accuracyM});
  double get lat, lon;
  TrackPoint copyWith({...});
}

abstract final class PackedTrack {
  static const int version = 1;
  static const int headerLength = 1;
  static const int bytesPerPoint = 36;
  static Uint8List header();
  static Uint8List encode(List<TrackPoint> points);          // header + records
  static Uint8List encodePoint(TrackPoint point);            // one record
  static Uint8List encodePoints(List<TrackPoint> points);    // records, no header
  static List<TrackPoint> decode(Uint8List bytes);
  static List<TrackPoint> decodePoints(Uint8List bytes, {bool hasHeader = true});
  static int pointCount(Uint8List bytes, {bool hasHeader = true});
}
```

## Packed track format

One blob per route or ride goes into Drift instead of a row-per-point table,
and the same record layout is appended to the recording journal
(`<appSupport>/recording/<rideId>.vtj`), so a crash loses at most the
unflushed tail. Decoding ignores a trailing partial record.

Header: one byte, the format version (`1`). Then, little-endian:

| offset | type | field                               |
|--------|------|-------------------------------------|
| 0      | f64  | latitude, degrees                   |
| 8      | f64  | longitude, degrees                  |
| 16     | f32  | elevation, metres (NaN = absent)    |
| 20     | i64  | time, ms since epoch (0 = absent)   |
| 28     | f32  | speed, m/s (NaN = absent)           |
| 32     | f32  | accuracy, metres (NaN = absent)     |

**36 bytes per point, not 32.** The architecture notes quote "lat f64, lon
f64, ele f32, timeMs i64, speed f32, acc f32 = 32 B/point"; those field widths
add up to 36. The field list wins, so 10 000 points are 360 KB, not 320 KB.

Timestamps are stored in UTC and come back as UTC. The Unix epoch instant
itself is not representable (it encodes as "absent"), which no GPS fix ever is.

## Bounding boxes

`BoundingBox` deliberately does not wrap the antimeridian (`west <= east`
always), which keeps `contains`/`intersects` trivial and is enough for route
and ride extents. `expandMeters` scales the longitude growth by the cosine of
the latitude nearest the pole, so the box really covers the requested distance
everywhere inside it, and clamps to the valid coordinate range.
