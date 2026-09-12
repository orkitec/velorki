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
);

final bare = TrackPoint(const LatLng(-33.8688, 151.2093));

void main() {
  group('encode/decode', () {
    test('layout is a header byte plus 36 bytes per point', () {
      expect(PackedTrack.bytesPerPoint, 36);
      expect(PackedTrack.headerLength, 1);
      final bytes = PackedTrack.encode([full, bare]);
      expect(bytes.length, 1 + 2 * 36);
      expect(bytes.first, PackedTrack.version);
      expect(PackedTrack.version, 1);
    });

    test('round trips a fully populated point bit-exactly', () {
      final out = PackedTrack.decode(PackedTrack.encode([full]));
      expect(out, hasLength(1));
      expect(out.single, full);
      expect(out.single.pos.lat, full.pos.lat);
      expect(out.single.pos.lon, full.pos.lon);
      expect(out.single.time, full.time);
    });

    test('round trips absent fields as null', () {
      final out = PackedTrack.decode(PackedTrack.encode([bare]));
      expect(out.single, bare);
      expect(out.single.ele, isNull);
      expect(out.single.time, isNull);
      expect(out.single.speedMps, isNull);
      expect(out.single.accuracyM, isNull);
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

  group('journal use', () {
    test('encodePoint is one headerless record', () {
      expect(PackedTrack.encodePoint(full), hasLength(36));
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
      expect(bytes.length, 1 + 3 * 36);
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
      for (final missing in [1, 7, 35]) {
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
      expect(full.lat, full.pos.lat);
      expect(full.lon, full.pos.lon);
      expect(full.toString(), contains('TrackPoint'));
    });
  });
}
