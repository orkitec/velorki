import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// Prefixed: the FIT profile has a `File` type of its own, which would hide
// `dart:io`'s.
import 'package:fit_sdk/fit_sdk.dart' as fit;
import 'package:test/test.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Worst case error of the semicircle round trip, in degrees.
///
/// Encoding rounds `degrees * 2^31 / 180` to the nearest integer, so the
/// stored value is at most half a semicircle away from the input; decoding
/// multiplies back by `180 / 2^31` exactly. Half a semicircle is
/// `0.5 * 180 / 2^31` = 4.1909e-8 degrees, roughly 4.7 mm of latitude. A tiny
/// slack is added for the double rounding of the two multiplications.
const double semicircleToleranceDeg = 0.5 * degreesPerSemicircle + 1e-12;

/// Worst case error of the FIT `altitude` field: it is stored as
/// `round((metres + 500) * 5)` in a uint16, so the step is 0.2 m and the
/// rounding error is at most half a step.
const double altitudeToleranceM = 0.5 / 5.0 + 1e-9;

/// Worst case error of the FIT `speed` field: `round(mps * 1000)` in a uint16,
/// so half a step is 0.0005 m/s.
const double speedToleranceMps = 0.5 / 1000.0 + 1e-9;

/// A ~20 point circle of about 100 m radius near Berlin, with elevation,
/// timestamps and speeds.
List<TrackPoint> syntheticTrack({int count = 20}) {
  final start = DateTime.utc(2024, 5, 17, 8, 30, 15);
  const centerLat = 52.520008;
  const centerLon = 13.404954;
  const radiusDeg = 0.001; // ~111 m north/south
  return List<TrackPoint>.generate(count, (i) {
    final angle = 2 * math.pi * i / count;
    return TrackPoint(
      LatLng(
        centerLat + radiusDeg * math.sin(angle),
        centerLon +
            radiusDeg * math.cos(angle) / math.cos(centerLat * math.pi / 180),
      ),
      ele: 34.0 + i * 1.5,
      time: start.add(Duration(seconds: i * 3)),
      speedMps: 5.25 + i * 0.125,
    );
  });
}

Uint8List gpxBytes() => Uint8List.fromList(
  utf8.encode(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<gpx version="1.1" creator="velorki">'
    '<trk><trkseg><trkpt lat="52.5" lon="13.4"><ele>34</ele></trkpt>'
    '</trkseg></trk></gpx>',
  ),
);

/// The first message of type [messageNumber] in [bytes], so a test can look at
/// the summary fields the public decoder does not return.
fit.Mesg _messageOf(Uint8List bytes, int messageNumber) {
  fit.Mesg? found;
  fit.Decode()
    ..onMesg = (fit.Mesg mesg) {
      if (found == null && mesg.num == messageNumber) found = mesg;
    }
    ..read(bytes);
  final mesg = found;
  if (mesg == null) throw StateError('no message $messageNumber in the file');
  return mesg;
}

void main() {
  group('encode/decode round trip', () {
    test('activity preserves positions, elevations, times and speeds', () {
      final points = syntheticTrack();
      final bytes = FitCodec.encodeActivity(points, name: 'Morning loop');

      expect(looksLikeFit(bytes), isTrue);

      final decoded = FitCodec.decodeActivity(bytes);
      expect(decoded, hasLength(points.length));

      for (var i = 0; i < points.length; i++) {
        final want = points[i];
        final got = decoded[i];
        expect(
          got.lat,
          closeTo(want.lat, semicircleToleranceDeg),
          reason: 'lat at $i',
        );
        expect(
          got.lon,
          closeTo(want.lon, semicircleToleranceDeg),
          reason: 'lon at $i',
        );
        expect(got.ele, isNotNull, reason: 'ele at $i');
        expect(
          got.ele!,
          closeTo(want.ele!, altitudeToleranceM),
          reason: 'ele at $i',
        );
        expect(got.time, want.time, reason: 'time at $i');
        expect(got.speedMps, isNotNull, reason: 'speed at $i');
        expect(
          got.speedMps!,
          closeTo(want.speedMps!, speedToleranceMps),
          reason: 'speed at $i',
        );
      }
    });

    test('a straight line without optional fields round trips', () {
      final points = List<TrackPoint>.generate(
        20,
        (i) => TrackPoint(LatLng(48.0 + i * 0.0005, 11.0 + i * 0.0005)),
      );
      final decoded = FitCodec.decodeActivity(FitCodec.encodeActivity(points));

      expect(decoded, hasLength(points.length));
      for (var i = 0; i < points.length; i++) {
        expect(decoded[i].lat, closeTo(points[i].lat, semicircleToleranceDeg));
        expect(decoded[i].lon, closeTo(points[i].lon, semicircleToleranceDeg));
        expect(decoded[i].ele, isNull);
        expect(decoded[i].speedMps, isNull);
        // No point carried a time, so the encoder stamped one per second.
        expect(decoded[i].time, isNotNull);
      }
      expect(
        decoded.last.time!.difference(decoded.first.time!),
        const Duration(seconds: 19),
      );
    });

    test('an explicit startTime is used when points carry no time', () {
      final start = DateTime.utc(2023, 1, 2, 3, 4, 5);
      final points = List<TrackPoint>.generate(
        5,
        (i) => TrackPoint(LatLng(48.0 + i * 0.0005, 11.0)),
      );
      final decoded = FitCodec.decodeActivity(
        FitCodec.encodeActivity(points, startTime: start),
      );
      expect(decoded.first.time, start);
      expect(decoded.last.time, start.add(const Duration(seconds: 4)));
    });

    test('every FitSport encodes and decodes without error', () {
      for (final sport in FitSport.values) {
        final bytes = FitCodec.encodeActivity(
          syntheticTrack(count: 3),
          sport: sport,
        );
        expect(
          FitCodec.decodeActivity(bytes),
          hasLength(3),
          reason: sport.name,
        );
        expect(FitSport.fromFitValue(sport.fitValue), sport);
      }
      expect(FitSport.fromFitValue(254), isNull);
    });
  });

  group('encodeCourse', () {
    test('produces a sniffable, decodable file with the same positions', () {
      final points = syntheticTrack();
      final bytes = FitCodec.encodeCourse(points, name: 'Velorki Test Loop');

      expect(looksLikeFit(bytes), isTrue);
      // A 14 byte header with its own CRC, and the file CRC at the end.
      expect(bytes[0], 14);
      expect(bytes.length, greaterThan(14 + 2));

      final decoded = FitCodec.decodeActivity(bytes);
      expect(decoded, hasLength(points.length));
      for (var i = 0; i < points.length; i++) {
        expect(decoded[i].lat, closeTo(points[i].lat, semicircleToleranceDeg));
        expect(decoded[i].lon, closeTo(points[i].lon, semicircleToleranceDeg));
      }
    });

    test('corrupting a byte breaks the CRC and is reported', () {
      final bytes = FitCodec.encodeCourse(syntheticTrack(), name: 'Loop');
      final corrupted = Uint8List.fromList(bytes);
      corrupted[corrupted.length - 10] ^= 0xFF;
      expect(
        () => FitCodec.decodeActivity(corrupted),
        throwsA(isA<FitFormatException>()),
      );
    });

    test('rejects a blank name', () {
      expect(
        () => FitCodec.encodeCourse(syntheticTrack(), name: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts a very long name by truncating it', () {
      final bytes = FitCodec.encodeCourse(
        syntheticTrack(count: 3),
        name: 'ä' * 200,
      );
      expect(looksLikeFit(bytes), isTrue);
      expect(FitCodec.decodeActivity(bytes), hasLength(3));
    });
  });

  group('looksLikeFit', () {
    test('accepts our own encoder output', () {
      expect(looksLikeFit(FitCodec.encodeActivity(syntheticTrack())), isTrue);
      expect(
        looksLikeFit(FitCodec.encodeCourse(syntheticTrack(), name: 'Loop')),
        isTrue,
      );
    });

    test('accepts the real Garmin sample file', () {
      expect(looksLikeFit(_sampleActivityBytes()), isTrue);
    });

    test('rejects non-FIT input', () {
      expect(looksLikeFit(gpxBytes()), isFalse);
      expect(
        looksLikeFit(
          Uint8List.fromList(
            utf8.encode('{"type":"FeatureCollection","features":[]}'),
          ),
        ),
        isFalse,
      );
      expect(looksLikeFit(Uint8List(0)), isFalse);
      expect(looksLikeFit(Uint8List.fromList([1, 2, 3, 4])), isFalse);
      expect(looksLikeFit(Uint8List(12)), isFalse);
      expect(looksLikeFit(Uint8List(14)), isFalse, reason: 'no signature');
    });

    test('rejects a good signature with a bad header size', () {
      final bytes = Uint8List.fromList(
        FitCodec.encodeActivity(syntheticTrack(count: 2)),
      );
      bytes[0] = 13;
      expect(looksLikeFit(bytes), isFalse);
    });
  });

  group('decodeActivity failure modes', () {
    test('throws FitFormatException on a GPX file', () {
      expect(
        () => FitCodec.decodeActivity(gpxBytes()),
        throwsA(isA<FitFormatException>()),
      );
    });

    test('throws FitFormatException on garbage', () {
      final garbage = Uint8List.fromList(
        List<int>.generate(512, (i) => (i * 37) & 0xFF),
      );
      expect(
        () => FitCodec.decodeActivity(garbage),
        throwsA(isA<FitFormatException>()),
      );
    });

    test('throws FitFormatException on empty and tiny buffers', () {
      for (final bytes in [Uint8List(0), Uint8List(4), Uint8List(12)]) {
        expect(
          () => FitCodec.decodeActivity(bytes),
          throwsA(isA<FitFormatException>()),
        );
      }
    });

    test('throws FitFormatException on a truncated FIT file', () {
      final bytes = FitCodec.encodeActivity(syntheticTrack());
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length ~/ 2);
      expect(
        () => FitCodec.decodeActivity(truncated),
        throwsA(isA<FitFormatException>()),
      );
    });

    test('carries a message and stringifies', () {
      const e = FitFormatException('boom', 'inner');
      expect(e.message, 'boom');
      expect(e.cause, 'inner');
      expect(e.toString(), contains('boom'));
      expect(
        const FitFormatException('boom').toString(),
        'FitFormatException: boom',
      );
    });
  });

  group('real sample file', () {
    // A Garmin Edge 820 ride from python-fitparse's test files (MIT), see
    // app/test/fixtures/formats/README.md.
    test('decodes to a plausible set of points', () {
      final points = FitCodec.decodeActivity(_sampleActivityBytes());

      expect(points.length, 15);

      for (final p in points) {
        expect(p.lat, inInclusiveRange(-90, 90));
        expect(p.lon, inInclusiveRange(-180, 180));
        expect(p.time, isNotNull);
        expect(p.time!.isUtc, isTrue);
        expect(p.time!.year, inInclusiveRange(2000, 2100));
        expect(p.ele, isNotNull);
        expect(p.ele!, inInclusiveRange(-500.0, 9000.0));
        expect(p.heartRateBpm, isNotNull);
        expect(p.cadenceRpm, isNotNull);
      }

      // The samples are in order, and the ride took about a minute.
      for (var i = 1; i < points.length; i++) {
        expect(points[i].time!.isBefore(points[i - 1].time!), isFalse);
      }
      expect(
        points.last.time!.difference(points.first.time!).inSeconds,
        inInclusiveRange(50, 70),
      );
    });
  });

  group('empty input', () {
    test('encodeActivity throws ArgumentError', () {
      expect(
        () => FitCodec.encodeActivity(const []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('encodeCourse throws ArgumentError', () {
      expect(
        () => FitCodec.encodeCourse(const [], name: 'Loop'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a single point still produces a valid file', () {
      final bytes = FitCodec.encodeActivity([
        TrackPoint(LatLng(52.5, 13.4), time: DateTime.utc(2024, 1, 1)),
      ]);
      expect(looksLikeFit(bytes), isTrue);
      expect(FitCodec.decodeActivity(bytes), hasLength(1));
    });
  });

  group('sensor fields', () {
    /// The synthetic track with a strap, a crank and a power meter on it.
    List<TrackPoint> withSensors({int count = 20}) => <TrackPoint>[
      for (final (i, point) in syntheticTrack(count: count).indexed)
        point.copyWith(
          heartRateBpm: 120 + i,
          cadenceRpm: i.isEven ? 0 : 85,
          powerW: 200 + i * 2,
        ),
    ];

    test('heart rate, cadence and power round trip through the records', () {
      final points = withSensors();

      final out = FitCodec.decodeActivity(FitCodec.encodeActivity(points));

      expect(out, hasLength(points.length));
      for (var i = 0; i < points.length; i++) {
        expect(out[i].heartRateBpm, points[i].heartRateBpm, reason: 'point $i');
        expect(out[i].cadenceRpm, points[i].cadenceRpm, reason: 'point $i');
        expect(out[i].powerW, points[i].powerW, reason: 'point $i');
      }
    });

    test('a cadence of zero comes back as zero, not as nothing', () {
      final points = <TrackPoint>[
        for (final point in syntheticTrack(count: 3))
          point.copyWith(cadenceRpm: 0, powerW: 0),
      ];

      final out = FitCodec.decodeActivity(FitCodec.encodeActivity(points));

      expect(out.map((p) => p.cadenceRpm), everyElement(0));
      expect(out.map((p) => p.powerW), everyElement(0));
    });

    test('a track without sensors decodes without them', () {
      final out = FitCodec.decodeActivity(
        FitCodec.encodeActivity(syntheticTrack(count: 3)),
      );

      expect(out.map((p) => p.heartRateBpm), everyElement(isNull));
      expect(out.map((p) => p.cadenceRpm), everyElement(isNull));
      expect(out.map((p) => p.powerW), everyElement(isNull));
    });

    test('the session and the lap carry the averages', () {
      final bytes = FitCodec.encodeActivity(withSensors(count: 4));

      final session = _messageOf(bytes, fit.MesgNum.session);
      final lap = _messageOf(bytes, fit.MesgNum.lap);

      // 120..123 beats: mean 122 (121.5 rounds up), maximum 123.
      expect(session.getFieldValue(16), 122, reason: 'avg_heart_rate');
      expect(session.getFieldValue(17), 123, reason: 'max_heart_rate');
      expect(session.getFieldValue(18), 43, reason: 'avg_cadence, 0/85/0/85');
      expect(session.getFieldValue(20), 203, reason: 'avg_power');
      expect(session.getFieldValue(21), 206, reason: 'max_power');

      expect(lap.getFieldValue(15), 122, reason: 'lap avg_heart_rate');
      expect(lap.getFieldValue(16), 123, reason: 'lap max_heart_rate');
      expect(lap.getFieldValue(17), 43, reason: 'lap avg_cadence');
      expect(lap.getFieldValue(19), 203, reason: 'lap avg_power');
      expect(lap.getFieldValue(20), 206, reason: 'lap max_power');
    });

    test('a track without sensors leaves the summary fields off', () {
      final bytes = FitCodec.encodeActivity(syntheticTrack(count: 4));

      final session = _messageOf(bytes, fit.MesgNum.session);

      expect(session.getFieldValue(16), isNull);
      expect(session.getFieldValue(20), isNull);
    });

    test('a reading beyond the field is clamped, not lost', () {
      final points = <TrackPoint>[
        for (final point in syntheticTrack(count: 2))
          point.copyWith(heartRateBpm: 400, powerW: 100000),
      ];

      final out = FitCodec.decodeActivity(FitCodec.encodeActivity(points));

      expect(out.first.heartRateBpm, 254);
      expect(out.first.powerW, 65534);
    });
  });

  group('constants', () {
    test('the FIT epoch offset is the documented one', () {
      expect(fitEpochOffsetSeconds, 631065600);
      expect(
        DateTime.fromMillisecondsSinceEpoch(
          fitEpochOffsetSeconds * 1000,
          isUtc: true,
        ),
        DateTime.utc(1989, 12, 31),
      );
    });

    test('semicircle constants are reciprocal', () {
      expect(degreesPerSemicircle * semicirclesPerDegree, closeTo(1.0, 1e-15));
      expect(degreesPerSemicircle, 180 / math.pow(2, 31));
    });
  });
}

Uint8List _sampleActivityBytes() =>
    File('test/fixtures/garmin_edge820_ride.fit').readAsBytesSync();
