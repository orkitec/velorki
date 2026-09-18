import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Values chosen to be exactly representable as float32 so round trips are
/// bit-exact rather than merely close.
final full = TrackPoint(
  const LatLng(48.137213456, 11.575612789),
  ele: 512.5,
  time: DateTime.utc(2026, 9, 12, 7, 30, 15, 250),
  speedMps: 6.25,
  accuracyM: 3.5,
  heartRateBpm: 142,
  cadenceRpm: 0,
  powerW: 215,
);

final bare = TrackPoint(const LatLng(-33.8688, 151.2093));

/// A version 1 blob built by hand, so the decoder is tested against the bytes
/// an older build wrote rather than against today's encoder.
Uint8List v1Blob(List<TrackPoint> points) {
  final bytes = Uint8List(1 + points.length * PackedTrack.bytesPerPointV1);
  bytes[0] = PackedTrack.versionWithoutSensors;
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < points.length; i++) {
    final at = 1 + i * PackedTrack.bytesPerPointV1;
    final p = points[i];
    data
      ..setFloat64(at, p.pos.lat, Endian.little)
      ..setFloat64(at + 8, p.pos.lon, Endian.little)
      ..setFloat32(at + 16, p.ele ?? double.nan, Endian.little)
      ..setInt64(
        at + 20,
        p.time?.toUtc().millisecondsSinceEpoch ?? 0,
        Endian.little,
      )
      ..setFloat32(at + 28, p.speedMps ?? double.nan, Endian.little)
      ..setFloat32(at + 32, p.accuracyM ?? double.nan, Endian.little);
  }
  return bytes;
}

void main() {
  group('encode/decode', () {
    test('layout is a header byte plus 42 bytes per point', () {
      expect(PackedTrack.bytesPerPoint, 42);
      expect(PackedTrack.bytesPerPointV1, 36);
      expect(PackedTrack.headerLength, 1);
      final bytes = PackedTrack.encode([full, bare]);
      expect(bytes.length, 1 + 2 * 42);
      expect(bytes.first, PackedTrack.version);
      expect(PackedTrack.version, 2);
    });

    test('bytesPerPointOf knows both versions and nothing else', () {
      expect(PackedTrack.bytesPerPointOf(1), 36);
      expect(PackedTrack.bytesPerPointOf(2), 42);
      expect(() => PackedTrack.bytesPerPointOf(3), throwsFormatException);
      expect(PackedTrack.supportsVersion(1), isTrue);
      expect(PackedTrack.supportsVersion(2), isTrue);
      expect(PackedTrack.supportsVersion(0), isFalse);
    });

    test('round trips a fully populated point bit-exactly', () {
      final out = PackedTrack.decode(PackedTrack.encode([full]));
      expect(out, hasLength(1));
      expect(out.single, full);
      expect(out.single.pos.lat, full.pos.lat);
      expect(out.single.pos.lon, full.pos.lon);
      expect(out.single.time, full.time);
      expect(out.single.heartRateBpm, 142);
      expect(out.single.powerW, 215);
    });

    test('round trips absent fields as null', () {
      final out = PackedTrack.decode(PackedTrack.encode([bare]));
      expect(out.single, bare);
      expect(out.single.ele, isNull);
      expect(out.single.time, isNull);
      expect(out.single.speedMps, isNull);
      expect(out.single.accuracyM, isNull);
      expect(out.single.heartRateBpm, isNull);
      expect(out.single.cadenceRpm, isNull);
      expect(out.single.powerW, isNull);
    });

    test('a sensor reading of zero survives as zero, not as absent', () {
      final coasting = TrackPoint(
        const LatLng(47, 8),
        cadenceRpm: 0,
        powerW: 0,
        heartRateBpm: 0,
      );
      final out = PackedTrack.decode(PackedTrack.encode([coasting])).single;
      expect(out.cadenceRpm, 0);
      expect(out.powerW, 0);
      expect(out.heartRateBpm, 0);
    });

    test('an absurd reading is clamped short of the absent marker', () {
      final silly = TrackPoint(const LatLng(47, 8), powerW: 999999);
      final out = PackedTrack.decode(PackedTrack.encode([silly])).single;
      expect(out.powerW, PackedTrack.sensorAbsent - 1);
    });

    test('round trips a mixed list in order', () {
      final points = [
        full,
        bare,
        TrackPoint(const LatLng(0, 0), ele: -8.25),
        TrackPoint(const LatLng(90, 180), time: DateTime.utc(1999, 12, 31)),
      ];
      expect(PackedTrack.decode(PackedTrack.encode(points)), points);
    });

    test('an empty track is a lone header byte', () {
      final bytes = PackedTrack.encode(const []);
      expect(bytes, hasLength(1));
      expect(PackedTrack.decode(bytes), isEmpty);
    });

    test('timestamps come back in UTC', () {
      final local = TrackPoint(
        const LatLng(48.0, 11.0),
        time: DateTime.utc(2026, 1, 2, 3, 4, 5).toLocal(),
      );
      final out = PackedTrack.decode(PackedTrack.encode([local])).single;
      expect(out.time!.isUtc, isTrue);
      expect(out.time!.isAtSameMomentAs(local.time!), isTrue);
    });

    test('rejects an empty blob and an unknown version', () {
      expect(() => PackedTrack.decode(Uint8List(0)), throwsFormatException);
      final bad = PackedTrack.encode([full])..[0] = 99;
      expect(() => PackedTrack.decode(bad), throwsFormatException);
    });
  });

  group('version 1 blobs', () {
    // Everything but the sensors: a point written before version 2 existed.
    final withoutSensors = TrackPoint(
      full.pos,
      ele: full.ele,
      time: full.time,
      speedMps: full.speedMps,
      accuracyM: full.accuracyM,
    );

    test('decode reads a hand-built version 1 blob', () {
      final bytes = v1Blob([withoutSensors, bare]);
      expect(bytes.length, 1 + 2 * 36);

      final out = PackedTrack.decode(bytes);

      expect(out, [withoutSensors, bare]);
      expect(out.first.heartRateBpm, isNull);
      expect(out.first.cadenceRpm, isNull);
      expect(out.first.powerW, isNull);
    });

    test('pointCount counts version 1 records', () {
      expect(PackedTrack.pointCount(v1Blob([withoutSensors, bare])), 2);
    });

    test('a partial trailing version 1 record is ignored', () {
      final bytes = v1Blob([withoutSensors, bare]);
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 5);
      expect(PackedTrack.decode(truncated), [withoutSensors]);
      expect(PackedTrack.pointCount(truncated), 1);
    });

    test('headerless records can be read in version 1', () {
      final bytes = Uint8List.sublistView(v1Blob([withoutSensors]), 1);
      final out = PackedTrack.decodePoints(
        bytes,
        hasHeader: false,
        recordVersion: PackedTrack.versionWithoutSensors,
      );
      expect(out.single, withoutSensors);
    });
  });

  group('journal use', () {
    test('encodePoint is one headerless record', () {
      expect(PackedTrack.encodePoint(full), hasLength(42));
      final decoded = PackedTrack.decodePoints(
        PackedTrack.encodePoint(full),
        hasHeader: false,
      );
      expect(decoded.single, full);
    });

    test('appending records reproduces the whole track', () {
      final points = [full, bare, full.copyWith(ele: 600.0)];
      final journal = BytesBuilder()..add(PackedTrack.header());
      for (final p in points) {
        journal.add(PackedTrack.encodePoint(p));
      }
      final bytes = journal.toBytes();
      expect(bytes.length, 1 + 3 * 42);
      expect(PackedTrack.decode(bytes), points);
      expect(PackedTrack.pointCount(bytes), 3);
    });

    test('encodePoints matches repeated encodePoint', () {
      final many = PackedTrack.encodePoints([full, bare]);
      final one = BytesBuilder()
        ..add(PackedTrack.encodePoint(full))
        ..add(PackedTrack.encodePoint(bare));
      expect(many, one.toBytes());
    });

    test('a partial trailing record is ignored', () {
      final points = [full, bare];
      final complete = PackedTrack.encode(points);
      for (final missing in [1, 7, 41]) {
        final truncated = Uint8List.sublistView(
          complete,
          0,
          complete.length - missing,
        );
        final decoded = PackedTrack.decode(truncated);
        expect(decoded, [full], reason: 'dropping $missing bytes');
        expect(PackedTrack.pointCount(truncated), 1);
      }
    });

    test('a header-only truncated journal decodes to nothing', () {
      final truncated = Uint8List.sublistView(
        PackedTrack.encode([full]),
        0,
        20,
      );
      expect(PackedTrack.decode(truncated), isEmpty);
      expect(PackedTrack.pointCount(truncated), 0);
    });
  });

  group('TrackPoint', () {
    test('equality, hashCode and accessors', () {
      expect(full, full.copyWith());
      expect(full.hashCode, full.copyWith().hashCode);
      expect(full, isNot(full.copyWith(ele: 1.0)));
      expect(full, isNot(full.copyWith(heartRateBpm: 90)));
      expect(full.lat, full.pos.lat);
      expect(full.lon, full.pos.lon);
      expect(full.toString(), contains('TrackPoint'));
      expect(full.toString(), contains('hr: 142'));
    });

    test('hasSensors is true only when a reading is present', () {
      expect(full.hasSensors, isTrue);
      expect(bare.hasSensors, isFalse);
      expect(bare.copyWith(cadenceRpm: 0).hasSensors, isTrue);
    });
  });
}
