import 'dart:typed_data';

import 'lat_lng.dart';
import 'track_point.dart';

/// Binary codec for a list of [TrackPoint]s.
///
/// One packed blob per route or ride is stored in Drift instead of a
/// row-per-point table, and the very same record layout is appended to the
/// recording journal (`<appSupport>/recording/<rideId>.vtj`) so a crash never
/// loses more than the unflushed tail.
///
/// Layout: a one-byte version header ([version]) followed by fixed-size
/// records of [bytesPerPoint] bytes, little-endian:
///
/// | offset | type  | field                                   |
/// |--------|-------|-----------------------------------------|
/// | 0      | f64   | latitude, degrees                       |
/// | 8      | f64   | longitude, degrees                      |
/// | 16     | f32   | elevation, metres (NaN = absent)        |
/// | 20     | i64   | time, ms since epoch (0 = absent)       |
/// | 28     | f32   | speed, m/s (NaN = absent)               |
/// | 32     | f32   | accuracy, metres (NaN = absent)         |
///
/// Timestamps are stored in UTC. The epoch instant itself cannot be
/// represented, which no GPS fix ever is.
abstract final class PackedTrack {
  /// Format version written into the header byte.
  static const int version = 1;

  /// Size of the header in bytes.
  static const int headerLength = 1;

  /// Size of one packed point in bytes.
  ///
  /// Note: f64 + f64 + f32 + i64 + f32 + f32 is 36 bytes, not the 32 quoted in
  /// the architecture notes; the field list wins over the arithmetic slip.
  static const int bytesPerPoint = 36;

  /// The header bytes of a fresh blob or journal file.
  static Uint8List header() => Uint8List.fromList(const [version]);

  /// Encodes [points] into a versioned blob.
  static Uint8List encode(List<TrackPoint> points) {
    final bytes = Uint8List(headerLength + points.length * bytesPerPoint);
    bytes[0] = version;
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < points.length; i++) {
      _writePoint(data, headerLength + i * bytesPerPoint, points[i]);
    }
    return bytes;
  }

  /// Encodes a single point into exactly [bytesPerPoint] bytes, without a
  /// header. This is the record appended to the recording journal.
  static Uint8List encodePoint(TrackPoint point) {
    final bytes = Uint8List(bytesPerPoint);
    _writePoint(ByteData.sublistView(bytes), 0, point);
    return bytes;
  }

  /// Encodes [points] without a header, for appending to an existing journal.
  static Uint8List encodePoints(List<TrackPoint> points) {
    final bytes = Uint8List(points.length * bytesPerPoint);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < points.length; i++) {
      _writePoint(data, i * bytesPerPoint, points[i]);
    }
    return bytes;
  }

  /// Decodes a versioned blob produced by [encode].
  ///
  /// Throws [FormatException] on an empty blob or an unknown version byte.
  static List<TrackPoint> decode(Uint8List bytes) =>
      decodePoints(bytes, hasHeader: true);

  /// Decodes [bytes] into points.
  ///
  /// With `hasHeader: true` (the default) the first byte must be a known
  /// format version. A trailing partial record — the usual state of a journal
  /// file after a crash mid-write — is ignored.
  static List<TrackPoint> decodePoints(
    Uint8List bytes, {
    bool hasHeader = true,
  }) {
    var offset = 0;
    if (hasHeader) {
      if (bytes.isEmpty) {
        throw const FormatException('packed track is empty, expected a header');
      }
      if (bytes[0] != version) {
        throw FormatException(
          'unsupported packed track version ${bytes[0]}, expected $version',
        );
      }
      offset = headerLength;
    }
    final count = (bytes.length - offset) ~/ bytesPerPoint;
    if (count <= 0) return const <TrackPoint>[];
    final data = ByteData.sublistView(bytes);
    return List<TrackPoint>.generate(
      count,
      (i) => _readPoint(data, offset + i * bytesPerPoint),
      growable: false,
    );
  }

  /// Number of whole records in [bytes], ignoring a trailing partial record.
  static int pointCount(Uint8List bytes, {bool hasHeader = true}) {
    final offset = hasHeader ? headerLength : 0;
    final count = (bytes.length - offset) ~/ bytesPerPoint;
    return count < 0 ? 0 : count;
  }

  static void _writePoint(ByteData data, int at, TrackPoint p) {
    data.setFloat64(at, p.pos.lat, Endian.little);
    data.setFloat64(at + 8, p.pos.lon, Endian.little);
    data.setFloat32(at + 16, p.ele ?? double.nan, Endian.little);
    data.setInt64(
      at + 20,
      p.time?.toUtc().millisecondsSinceEpoch ?? 0,
      Endian.little,
    );
    data.setFloat32(at + 28, p.speedMps ?? double.nan, Endian.little);
    data.setFloat32(at + 32, p.accuracyM ?? double.nan, Endian.little);
  }

  static TrackPoint _readPoint(ByteData data, int at) {
    final lat = data.getFloat64(at, Endian.little);
    final lon = data.getFloat64(at + 8, Endian.little);
    final ele = data.getFloat32(at + 16, Endian.little);
    final timeMs = data.getInt64(at + 20, Endian.little);
    final speed = data.getFloat32(at + 28, Endian.little);
    final acc = data.getFloat32(at + 32, Endian.little);
    return TrackPoint(
      LatLng(lat, lon),
      ele: ele.isNaN ? null : ele,
      time: timeMs == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true),
      speedMps: speed.isNaN ? null : speed,
      accuracyM: acc.isNaN ? null : acc,
    );
  }
}
