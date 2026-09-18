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
/// records, little-endian. Version 2 records are 42 bytes; version 1 records
/// are the first 36 of them and carry no sensor values:
///
/// | offset | type  | field                                   |
/// |--------|-------|-----------------------------------------|
/// | 0      | f64   | latitude, degrees                       |
/// | 8      | f64   | longitude, degrees                      |
/// | 16     | f32   | elevation, metres (NaN = absent)        |
/// | 20     | i64   | time, ms since epoch (0 = absent)       |
/// | 28     | f32   | speed, m/s (NaN = absent)               |
/// | 32     | f32   | accuracy, metres (NaN = absent)         |
/// | 36     | u16   | heart rate, bpm (0xFFFF = absent)       |
/// | 38     | u16   | cadence, rpm (0xFFFF = absent)          |
/// | 40     | u16   | power, watts (0xFFFF = absent)          |
///
/// The sensor fields use `0xFFFF` rather than zero as their absent marker,
/// because a cadence or a power of zero is a reading a freewheeling rider
/// really produces.
///
/// Both versions decode; only version 2 is written. Timestamps are stored in
/// UTC. The epoch instant itself cannot be represented, which no GPS fix ever
/// is.
abstract final class PackedTrack {
  /// Format version written into the header byte.
  static const int version = 2;

  /// The first format version, without the sensor fields. Still decoded: old
  /// rides and journals from an interrupted ride carry it.
  static const int versionWithoutSensors = 1;

  /// Size of the header in bytes.
  static const int headerLength = 1;

  /// Size of one packed point in bytes, in the current [version].
  ///
  /// Note: f64 + f64 + f32 + i64 + f32 + f32 is 36 bytes, not the 32 quoted in
  /// the architecture notes; the field list wins over the arithmetic slip.
  /// Version 2 adds three `u16` sensor fields on top of those 36.
  static const int bytesPerPoint = 42;

  /// Size of one packed point in [versionWithoutSensors].
  static const int bytesPerPointV1 = 36;

  /// Value a sensor field holds when the point carries no such reading.
  static const int sensorAbsent = 0xFFFF;

  /// Size of one packed point in the format [version].
  ///
  /// Throws [FormatException] for a version this codec cannot read, which is
  /// how a journal or a blob from a newer build is recognised.
  static int bytesPerPointOf(int version) => switch (version) {
    versionWithoutSensors => bytesPerPointV1,
    PackedTrack.version => bytesPerPoint,
    _ => throw FormatException('unsupported packed track version $version'),
  };

  /// Whether [version] is a format this codec can read.
  static bool supportsVersion(int version) =>
      version == versionWithoutSensors || version == PackedTrack.version;

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

  /// Decodes a versioned blob produced by [encode], of either format version.
  ///
  /// Throws [FormatException] on an empty blob or an unknown version byte.
  static List<TrackPoint> decode(Uint8List bytes) =>
      decodePoints(bytes, hasHeader: true);

  /// Decodes [bytes] into points.
  ///
  /// With `hasHeader: true` (the default) the first byte must be a known
  /// format version and the record size follows from it. Without a header the
  /// records are read in [version] — the format [encodePoint] writes — unless
  /// another one is given as [recordVersion]. A trailing partial record — the
  /// usual state of a journal file after a crash mid-write — is ignored.
  static List<TrackPoint> decodePoints(
    Uint8List bytes, {
    bool hasHeader = true,
    int recordVersion = version,
  }) {
    var offset = 0;
    var format = recordVersion;
    if (hasHeader) {
      if (bytes.isEmpty) {
        throw const FormatException('packed track is empty, expected a header');
      }
      format = bytes[0];
      offset = headerLength;
    }
    final size = bytesPerPointOf(format);
    final count = (bytes.length - offset) ~/ size;
    if (count <= 0) return const <TrackPoint>[];
    final data = ByteData.sublistView(bytes);
    return List<TrackPoint>.generate(
      count,
      (i) => _readPoint(data, offset + i * size, format),
      growable: false,
    );
  }

  /// Number of whole records in [bytes], ignoring a trailing partial record.
  ///
  /// With a header the record size comes from the version byte; without one it
  /// comes from [recordVersion].
  static int pointCount(
    Uint8List bytes, {
    bool hasHeader = true,
    int recordVersion = version,
  }) {
    if (hasHeader && bytes.isEmpty) return 0;
    final format = hasHeader ? bytes[0] : recordVersion;
    if (!supportsVersion(format)) return 0;
    final offset = hasHeader ? headerLength : 0;
    final count = (bytes.length - offset) ~/ bytesPerPointOf(format);
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
    data.setUint16(at + 36, _sensor(p.heartRateBpm), Endian.little);
    data.setUint16(at + 38, _sensor(p.cadenceRpm), Endian.little);
    data.setUint16(at + 40, _sensor(p.powerW), Endian.little);
  }

  static TrackPoint _readPoint(ByteData data, int at, int format) {
    final lat = data.getFloat64(at, Endian.little);
    final lon = data.getFloat64(at + 8, Endian.little);
    final ele = data.getFloat32(at + 16, Endian.little);
    final timeMs = data.getInt64(at + 20, Endian.little);
    final speed = data.getFloat32(at + 28, Endian.little);
    final acc = data.getFloat32(at + 32, Endian.little);
    final sensors = format != versionWithoutSensors;
    return TrackPoint(
      LatLng(lat, lon),
      ele: ele.isNaN ? null : ele,
      time: timeMs == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true),
      speedMps: speed.isNaN ? null : speed,
      accuracyM: acc.isNaN ? null : acc,
      heartRateBpm: sensors
          ? _reading(data.getUint16(at + 36, Endian.little))
          : null,
      cadenceRpm: sensors
          ? _reading(data.getUint16(at + 38, Endian.little))
          : null,
      powerW: sensors ? _reading(data.getUint16(at + 40, Endian.little)) : null,
    );
  }

  /// A sensor value as it is stored: clamped into the `u16` range, with
  /// [sensorAbsent] standing for "no reading".
  static int _sensor(int? value) {
    if (value == null) return sensorAbsent;
    if (value < 0) return 0;
    // 0xFFFF is the absent marker, so a reading that high is stored one short
    // of it rather than read back as nothing.
    return value >= sensorAbsent ? sensorAbsent - 1 : value;
  }

  static int? _reading(int raw) => raw == sensorAbsent ? null : raw;
}
