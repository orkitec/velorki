import 'dart:typed_data';

import 'lat_lng.dart';
import 'packed_track.dart';
import 'track_point.dart';

/// A compact, column-wise form of a [PackedTrack] blob for sending a track
/// somewhere (sync), not for the database.
///
/// Every value is quantized to an integer, stored as the difference from the
/// one before and written as a zigzag LEB128 varint, one column after the
/// other. Quantization: latitude and longitude 1e-7 degree, elevation
/// centimetre, speed cm/s, accuracy decimetre, time millisecond, sensors as
/// they are. [decode] gives back the current [PackedTrack] blob (a version 1
/// input comes back as version 2 with no sensor readings), and
/// `encode(decode(x))` equals `x`, so a track that went through once stays put.
///
/// Layout: byte 0 [version], byte 1 flags (bit 0: sensor columns follow), a
/// varint point count, then the columns lat, lon, elevation, time, speed,
/// accuracy and, with the flag, heart rate, cadence, power. Latitude and
/// longitude are plain deltas. The others are optional: per point a varint 0
/// is "absent", anything else is zigzag(delta from the last present value)+1.
/// The time's delta is itself a difference from the previous delta, which
/// makes a steady fix rate cost one byte.
///
/// Varints are computed with arithmetic, not bit operations, so the codec
/// behaves the same where integers are 53-bit doubles.
abstract final class CompactTrack {
  /// Format version in the first byte.
  static const int version = 1;

  static const int _sensorsFlag = 1;
  static const int _maxFloat = 10000000;
  static const int _maxPosition = 1800000000;

  /// Compacts a [PackedTrack] blob of either version.
  ///
  /// Throws [FormatException] for a blob [PackedTrack] cannot read or one
  /// holding values the quantization cannot hold (not finite, absurdly large);
  /// the caller then keeps the blob as it is.
  static Uint8List encode(Uint8List packed) {
    final points = PackedTrack.decode(packed);
    final n = points.length;
    final sensors = points.any(
      (p) => p.heartRateBpm != null || p.cadenceRpm != null || p.powerW != null,
    );
    final out = _Writer()
      ..byte(version)
      ..byte(sensors ? _sensorsFlag : 0)
      ..varint(n);

    _position(out, points.map((p) => p.pos.lat));
    _position(out, points.map((p) => p.pos.lon));
    _optional(
      out,
      points.map((p) => p.ele == null ? null : _q(p.ele!, 100)),
      1,
    );
    _optional(
      out,
      points.map((p) => p.time?.toUtc().millisecondsSinceEpoch),
      2,
    );
    _optional(
      out,
      points.map((p) => p.speedMps == null ? null : _q(p.speedMps!, 100)),
      1,
    );
    _optional(
      out,
      points.map((p) => p.accuracyM == null ? null : _q(p.accuracyM!, 10)),
      1,
    );
    if (sensors) {
      _optional(out, points.map((p) => _clampSensor(p.heartRateBpm)), 1);
      _optional(out, points.map((p) => _clampSensor(p.cadenceRpm)), 1);
      _optional(out, points.map((p) => _clampSensor(p.powerW)), 1);
    }
    return out.takeBytes();
  }

  /// The [PackedTrack] blob (current version) a [encode]d track stands for.
  ///
  /// Throws [FormatException] on a truncated blob or an unknown version.
  static Uint8List decode(Uint8List compact) {
    final r = _Reader(compact);
    final v = r.byte();
    if (v != version) {
      throw FormatException('unsupported compact track version $v');
    }
    final sensors = (r.byte() & _sensorsFlag) != 0;
    final n = r.varint();
    // Every point costs a byte in every column.
    if (n > compact.length) throw const FormatException('bad point count');

    final lat = _readPosition(r, n);
    final lon = _readPosition(r, n);
    final ele = _readOptional(r, n, 1);
    final time = _readOptional(r, n, 2);
    final speed = _readOptional(r, n, 1);
    final acc = _readOptional(r, n, 1);
    final hr = sensors ? _readOptional(r, n, 1) : null;
    final cad = sensors ? _readOptional(r, n, 1) : null;
    final pow = sensors ? _readOptional(r, n, 1) : null;

    return PackedTrack.encode([
      for (var i = 0; i < n; i++)
        TrackPoint(
          LatLng(lat[i] / 1e7, lon[i] / 1e7),
          ele: ele[i] == null ? null : ele[i]! / 100,
          time: time[i] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(time[i]!, isUtc: true),
          speedMps: speed[i] == null ? null : speed[i]! / 100,
          accuracyM: acc[i] == null ? null : acc[i]! / 10,
          heartRateBpm: hr?[i],
          cadenceRpm: cad?[i],
          powerW: pow?[i],
        ),
    ]);
  }

  // --- Columns --------------------------------------------------------------

  static int _q(double value, int scale) {
    if (!value.isFinite) throw const FormatException('value is not finite');
    final q = (value * scale).round();
    if (q.abs() > _maxFloat) throw const FormatException('value out of range');
    return q;
  }

  static int? _clampSensor(int? v) =>
      v?.clamp(0, PackedTrack.sensorAbsent - 1).toInt();

  static void _position(_Writer out, Iterable<double> degrees) {
    var prev = 0;
    for (final d in degrees) {
      if (!d.isFinite) throw const FormatException('value is not finite');
      final q = (d * 1e7).round();
      if (q.abs() > _maxPosition) {
        throw const FormatException('position out of range');
      }
      out.varint(_zigzag(q - prev));
      prev = q;
    }
  }

  static List<int> _readPosition(_Reader r, int n) {
    final values = List<int>.filled(n, 0);
    var prev = 0;
    for (var i = 0; i < n; i++) {
      prev += _unzigzag(r.varint());
      values[i] = prev;
    }
    return values;
  }

  /// [order] 1 writes the difference to the last present value, 2 the
  /// difference of the differences.
  static void _optional(_Writer out, Iterable<int?> values, int order) {
    var prev = 0;
    var prevDelta = 0;
    for (final v in values) {
      if (v == null) {
        out.varint(0);
        continue;
      }
      final delta = v - prev;
      out.varint(_zigzag(order == 2 ? delta - prevDelta : delta) + 1);
      prevDelta = delta;
      prev = v;
    }
  }

  static List<int?> _readOptional(_Reader r, int n, int order) {
    final values = List<int?>.filled(n, null);
    var prev = 0;
    var prevDelta = 0;
    for (var i = 0; i < n; i++) {
      final code = r.varint();
      if (code == 0) continue;
      final z = _unzigzag(code - 1);
      final delta = order == 2 ? z + prevDelta : z;
      prev += delta;
      prevDelta = delta;
      values[i] = prev;
    }
    return values;
  }
}

/// A compact form of a series of little-endian signed 16-bit readings with
/// one reserved "absent" value, such as a ride's temperatures in tenths of a
/// degree. Lossless: [decode] returns the bytes [encode] was given.
///
/// Layout: byte 0 [version], a varint count, then per reading a varint 0 for
/// the absent value or zigzag(delta from the last present reading)+1.
abstract final class CompactSeries {
  /// Format version in the first byte.
  static const int version = 1;

  /// The reading standing for "none".
  static const int absent = -32768;

  /// Compacts [series] (an even number of bytes).
  ///
  /// Throws [FormatException] for an odd length.
  static Uint8List encode(Uint8List series) {
    if (series.length.isOdd) throw const FormatException('odd series length');
    final data = ByteData.sublistView(series);
    final n = series.length ~/ 2;
    final out = _Writer()
      ..byte(version)
      ..varint(n);
    var prev = 0;
    for (var i = 0; i < n; i++) {
      final v = data.getInt16(i * 2, Endian.little);
      if (v == absent) {
        out.varint(0);
      } else {
        out.varint(_zigzag(v - prev) + 1);
        prev = v;
      }
    }
    return out.takeBytes();
  }

  /// The series [compact] stands for.
  ///
  /// Throws [FormatException] on a truncated blob or an unknown version.
  static Uint8List decode(Uint8List compact) {
    final r = _Reader(compact);
    final v = r.byte();
    if (v != version) throw FormatException('unsupported series version $v');
    final n = r.varint();
    if (n > compact.length) throw const FormatException('bad count');
    final out = Uint8List(n * 2);
    final data = ByteData.sublistView(out);
    var prev = 0;
    for (var i = 0; i < n; i++) {
      final code = r.varint();
      var value = absent;
      if (code != 0) {
        prev += _unzigzag(code - 1);
        value = prev;
      }
      data.setInt16(i * 2, value, Endian.little);
    }
    return out;
  }
}

int _zigzag(int n) => n >= 0 ? n * 2 : -n * 2 - 1;

int _unzigzag(int z) => z.isEven ? z ~/ 2 : -((z + 1) ~/ 2);

class _Writer {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void byte(int v) => _b.addByte(v);

  void varint(int value) {
    var v = value;
    while (v >= 128) {
      _b.addByte(v % 128 + 128);
      v ~/= 128;
    }
    _b.addByte(v);
  }

  Uint8List takeBytes() => _b.takeBytes();
}

class _Reader {
  _Reader(this._bytes);

  final Uint8List _bytes;
  int _at = 0;

  int byte() {
    if (_at >= _bytes.length) throw const FormatException('truncated');
    return _bytes[_at++];
  }

  int varint() {
    var result = 0;
    var scale = 1;
    for (var i = 0; i < 9; i++) {
      final b = byte();
      result += (b & 127) * scale;
      if (b < 128) return result;
      scale *= 128;
    }
    throw const FormatException('varint too long');
  }
}
