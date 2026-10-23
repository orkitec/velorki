import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A ride of [count] one-second fixes with GPS-like noise.
List<TrackPoint> simulatedRide(int count, {int seed = 1, bool sensors = true}) {
  final rnd = Random(seed);
  var lat = 48.1;
  var lon = 11.5;
  var heading = 0.0;
  final start = DateTime.utc(2026, 9, 12, 6);
  return [
    for (var i = 0; i < count; i++)
      () {
        heading += (rnd.nextDouble() - 0.5) * 0.2;
        lat += cos(heading) * 5e-5 + (rnd.nextDouble() - 0.5) * 4e-6;
        lon += sin(heading) * 7e-5 + (rnd.nextDouble() - 0.5) * 4e-6;
        return TrackPoint(
          LatLng(lat, lon),
          ele: 500 + 80 * sin(i / 900) + rnd.nextDouble() * 1.5,
          time: start.add(
            Duration(seconds: i, milliseconds: i % 7 == 0 ? 3 : 0),
          ),
          speedMps: 6 + rnd.nextDouble() * 4,
          accuracyM: 3 + rnd.nextInt(6).toDouble(),
          heartRateBpm: sensors ? 120 + rnd.nextInt(40) : null,
          cadenceRpm: sensors ? rnd.nextInt(100) : null,
          powerW: sensors ? rnd.nextInt(300) : null,
        );
      }(),
  ];
}

Uint8List gz(Uint8List b) => Uint8List.fromList(gzip.encode(b));

void main() {
  group('CompactTrack', () {
    test('round trips within the quantization', () {
      final points = simulatedRide(500);
      final packed = PackedTrack.encode(points);
      final back = PackedTrack.decode(
        CompactTrack.decode(CompactTrack.encode(packed)),
      );
      expect(back, hasLength(points.length));
      for (var i = 0; i < points.length; i++) {
        final a = points[i];
        final b = back[i];
        expect(b.lat, closeTo(a.lat, 5e-8));
        expect(b.lon, closeTo(a.lon, 5e-8));
        expect(b.ele, closeTo(a.ele!, 0.0051));
        expect(b.time, a.time);
        expect(b.speedMps, closeTo(a.speedMps!, 0.0051));
        expect(b.accuracyM, closeTo(a.accuracyM!, 0.051));
        expect(b.heartRateBpm, a.heartRateBpm);
        expect(b.cadenceRpm, a.cadenceRpm);
        expect(b.powerW, a.powerW);
      }
    });

    test('absent values stay absent, zero sensor readings stay zero', () {
      final points = [
        const TrackPoint(LatLng(1, 2)),
        TrackPoint(
          const LatLng(-1.5, -2.5),
          ele: -12.34,
          time: DateTime.utc(2026),
          cadenceRpm: 0,
          powerW: 0,
        ),
        const TrackPoint(LatLng(-1.5, -2.5), speedMps: 0, accuracyM: 0),
        const TrackPoint(LatLng(0, 0), heartRateBpm: 65534),
      ];
      final back = PackedTrack.decode(
        CompactTrack.decode(CompactTrack.encode(PackedTrack.encode(points))),
      );
      expect(back[0].ele, isNull);
      expect(back[0].time, isNull);
      expect(back[0].speedMps, isNull);
      expect(back[0].accuracyM, isNull);
      expect(back[0].heartRateBpm, isNull);
      expect(back[1].ele, closeTo(-12.34, 0.006));
      expect(back[1].time, DateTime.utc(2026));
      expect(back[1].speedMps, isNull);
      expect(back[1].heartRateBpm, isNull);
      expect(back[1].cadenceRpm, 0);
      expect(back[1].powerW, 0);
      expect(back[2].speedMps, 0);
      expect(back[2].accuracyM, 0);
      expect(back[3].heartRateBpm, 65534);
    });

    test('a track without sensors writes no sensor columns', () {
      final packed = PackedTrack.encode(simulatedRide(100, sensors: false));
      final compact = CompactTrack.encode(packed);
      expect(compact[1] & 1, 0);
      expect(PackedTrack.decode(CompactTrack.decode(compact)), hasLength(100));
    });

    test('an empty track', () {
      final packed = PackedTrack.encode(const []);
      final back = CompactTrack.decode(CompactTrack.encode(packed));
      expect(back, packed);
      expect(PackedTrack.decode(back), isEmpty);
    });

    test('encoding a decoded track gives the same bytes', () {
      final packed = PackedTrack.encode(simulatedRide(2000, seed: 5));
      final once = CompactTrack.encode(packed);
      final decoded = CompactTrack.decode(once);
      expect(CompactTrack.encode(decoded), once);
      expect(CompactTrack.decode(CompactTrack.encode(decoded)), decoded);
    });

    test('a version 1 blob comes back as version 2 without sensors', () {
      final points = simulatedRide(50, sensors: false);
      final v1 = Uint8List(1 + points.length * PackedTrack.bytesPerPointV1);
      v1[0] = PackedTrack.versionWithoutSensors;
      final data = ByteData.sublistView(v1);
      for (var i = 0; i < points.length; i++) {
        final at = 1 + i * PackedTrack.bytesPerPointV1;
        final p = points[i];
        data
          ..setFloat64(at, p.lat, Endian.little)
          ..setFloat64(at + 8, p.lon, Endian.little)
          ..setFloat32(at + 16, p.ele!, Endian.little)
          ..setInt64(at + 20, p.time!.millisecondsSinceEpoch, Endian.little)
          ..setFloat32(at + 28, p.speedMps!, Endian.little)
          ..setFloat32(at + 32, p.accuracyM!, Endian.little);
      }
      final back = CompactTrack.decode(CompactTrack.encode(v1));
      expect(back[0], PackedTrack.version);
      final decoded = PackedTrack.decode(back);
      expect(decoded, hasLength(50));
      expect(decoded[10].heartRateBpm, isNull);
      expect(decoded[10].lat, closeTo(points[10].lat, 5e-8));
    });

    test('what cannot be compacted or read throws', () {
      expect(
        () => CompactTrack.encode(Uint8List.fromList([9, 1, 2])),
        throwsFormatException,
      );
      expect(() => CompactTrack.encode(Uint8List(0)), throwsFormatException);
      expect(
        () => CompactTrack.encode(
          PackedTrack.encode([const TrackPoint(LatLng(double.nan, 1))]),
        ),
        throwsFormatException,
      );
      final good = CompactTrack.encode(PackedTrack.encode(simulatedRide(20)));
      expect(
        () => CompactTrack.decode(good.sublist(0, good.length - 5)),
        throwsFormatException,
      );
      expect(
        () => CompactTrack.decode(Uint8List.fromList([7, 0, 0])),
        throwsFormatException,
      );
    });

    test('a day-long ride is far smaller than the packed blob', () {
      final packed = PackedTrack.encode(simulatedRide(86400));
      final compact = CompactTrack.encode(packed);
      final gzCompact = gz(compact).length;
      final gzOld = gz(
        Uint8List.fromList(
          utf8.encode(jsonEncode({'g': base64Encode(packed)})),
        ),
      ).length;
      expect(gzCompact, lessThan(1000 * 1000));
      expect(gzCompact, lessThan(gzOld ~/ 3));
    });
  });

  group('CompactSeries', () {
    Uint8List series(List<int> v) {
      final d = ByteData(v.length * 2);
      for (var i = 0; i < v.length; i++) {
        d.setInt16(i * 2, v[i], Endian.little);
      }
      return d.buffer.asUint8List();
    }

    test('round trips exactly, absent included', () {
      final s = series([215, 216, -32768, -32768, 217, -5, 32767, -32767, 0]);
      expect(CompactSeries.decode(CompactSeries.encode(s)), s);
    });

    test('empty and odd', () {
      expect(CompactSeries.decode(CompactSeries.encode(Uint8List(0))), isEmpty);
      expect(() => CompactSeries.encode(Uint8List(3)), throwsFormatException);
    });

    test('a slow temperature is about a byte a reading', () {
      final s = series([for (var i = 0; i < 86400; i++) 150 + i ~/ 5000]);
      expect(CompactSeries.encode(s).length, lessThan(86400 * 2 ~/ 2 + 10));
    });
  });
}
