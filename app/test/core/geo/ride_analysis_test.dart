import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/ride_analysis.dart';
import 'package:velorki/core/geo/ride_stats.dart';
import 'package:velorki/core/units/units.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// 20 km/h, the speed the split arithmetic is written against: a kilometre in
/// exactly three minutes.
const double _twentyKmh = 1000 / 180;

const LatLng _start = LatLng(48.0, 11.0);
final DateTime _t0 = DateTime.utc(2026, 9, 12, 10);

/// A ride due north at [speedMps], one fix a second, [seconds] of them.
///
/// [elevationAt] is asked for the height of every fix; returning `null` gives
/// a track without heights at all.
List<TrackPoint> _ride({
  required int seconds,
  double speedMps = _twentyKmh,
  double? Function(int second)? elevationAt,
  LatLng from = _start,
  DateTime? startedAt,
}) {
  final points = <TrackPoint>[];
  var position = from;
  final begin = startedAt ?? _t0;
  for (var i = 0; i <= seconds; i++) {
    if (i > 0) position = destinationPoint(position, 0, speedMps);
    points.add(
      TrackPoint(
        position,
        ele: elevationAt?.call(i),
        time: begin.add(Duration(seconds: i)),
      ),
    );
  }
  return points;
}

double _seconds(Duration d) =>
    d.inMicroseconds / Duration.microsecondsPerSecond;

void main() {
  group('splits', () {
    test('steady 20 km/h for 3 km gives three kilometres of 3:00', () {
      final analysis = analyseRide(_ride(seconds: 540));

      expect(analysis.splits, hasLength(3));
      for (final split in analysis.splits) {
        expect(split.distanceM, closeTo(1000, 0.001));
        expect(_seconds(split.movingTime), closeTo(180, 0.001));
        expect(split.avgSpeedMps, closeTo(_twentyKmh, 0.001));
        expect(split.partial, isFalse);
      }
    });

    test('the remainder is a split of its own and says so', () {
      final analysis = analyseRide(_ride(seconds: 252)); // 1.4 km

      expect(analysis.splits, hasLength(2));
      expect(analysis.splits.first.distanceM, closeTo(1000, 0.001));
      expect(analysis.splits.first.partial, isFalse);
      expect(analysis.splits.last.distanceM, closeTo(400, 0.001));
      expect(analysis.splits.last.partial, isTrue);
      expect(_seconds(analysis.splits.last.movingTime), closeTo(72, 0.001));
    });

    test('miles are splits too when that is what is asked for', () {
      final analysis = analyseRide(
        _ride(seconds: 540),
        splitLengthM: metersPerMile,
      );

      expect(analysis.splits, hasLength(2));
      expect(analysis.splits.first.distanceM, closeTo(metersPerMile, 0.001));
      expect(analysis.splits.last.partial, isTrue);
      expect(
        _seconds(analysis.splits.first.movingTime),
        closeTo(metersPerMile / _twentyKmh, 0.001),
      );
    });

    test('a climb lands in the kilometre it was ridden in', () {
      // Flat, then 85 m up between 1.0 and 1.95 km, then flat again.
      double elevation(int second) {
        if (second < 180) return 100;
        if (second > 350) return 185;
        return 100 + (second - 180) * 0.5;
      }

      final track = _ride(seconds: 540, elevationAt: elevation);
      final analysis = analyseRide(track);

      expect(analysis.splits, hasLength(3));
      expect(analysis.splits[0].ascentM, 0);
      // 85 m in 3 m steps: 84 counted, the last metre still under hysteresis.
      expect(analysis.splits[1].ascentM, closeTo(84, 0.001));
      expect(analysis.splits[2].ascentM, 0);
      // And the splits add up to the figure the ride tiles show.
      final stats = computeRideStats(track);
      final total = analysis.splits.fold<double>(0, (a, s) => a + s.ascentM);
      expect(total, closeTo(stats.ascentM, 0.001));
    });

    test('a descent is booked as one', () {
      final analysis = analyseRide(
        _ride(seconds: 360, elevationAt: (s) => 500 - s * 0.5),
      );

      expect(analysis.splits[0].descentM, greaterThan(80));
      expect(analysis.splits[0].ascentM, 0);
    });

    test('a pause counts towards neither distance nor moving time', () {
      final first = _ride(seconds: 180);
      // Ten minutes standing still, then another kilometre from there.
      final resumeAt = _t0.add(const Duration(seconds: 780));
      final second = _ride(
        seconds: 180,
        from: first.last.pos,
        startedAt: resumeAt,
      );
      final analysis = analyseRide(<TrackPoint>[...first, ...second]);

      expect(analysis.splits, hasLength(2));
      expect(_seconds(analysis.splits[0].movingTime), closeTo(180, 0.001));
      expect(_seconds(analysis.splits[1].movingTime), closeTo(180, 0.001));
      final moving = analysis.splits.fold<double>(
        0,
        (a, s) => a + _seconds(s.movingTime),
      );
      expect(moving, closeTo(360, 0.001), reason: 'not the 16 minutes elapsed');
    });

    test(
      'a ride the recorder was switched off in the middle of breaks too',
      () {
        final first = _ride(seconds: 180);
        // A seam: only ten seconds wide, so the timestamps alone would not show
        // it — the break has to be handed in.
        final resumeAt = _t0.add(const Duration(seconds: 190));
        final second = _ride(
          seconds: 180,
          from: destinationPoint(first.last.pos, 0, 50),
          startedAt: resumeAt,
        );
        final analysis = analyseRide(
          <TrackPoint>[...first, ...second],
          breaks: <StatsBreak>[
            StatsBreak(startedAt: first.last.time!, endedAt: resumeAt),
          ],
        );

        // The 50 m across the seam is in no split at all.
        final total = analysis.splits.fold<double>(
          0,
          (a, s) => a + s.distanceM,
        );
        expect(total, closeTo(2000, 0.001));
      },
    );

    test('a track without times has nothing to split', () {
      final analysis = analyseRide(<TrackPoint>[
        const TrackPoint(LatLng(48, 11)),
        const TrackPoint(LatLng(48.01, 11)),
      ]);

      expect(analysis.splits, isEmpty);
      expect(analysis.hasSpeed, isFalse);
    });
  });

  group('chart samples', () {
    test('a thousand fixes are thinned to at most four hundred', () {
      final analysis = analyseRide(
        _ride(seconds: 999, elevationAt: (s) => 500 + s * 0.1),
      );

      expect(analysis.samples.length, lessThanOrEqualTo(rideChartMaxSamples));
      expect(analysis.samples.length, greaterThan(300));
      expect(analysis.samples.first.distanceM, 0);
      expect(analysis.samples.last.distanceM, closeTo(999 * _twentyKmh, 0.001));
      // Still in order along the distance.
      for (var i = 1; i < analysis.samples.length; i++) {
        expect(
          analysis.samples[i].distanceM,
          greaterThanOrEqualTo(analysis.samples[i - 1].distanceM),
        );
      }
    });

    test('a short ride keeps every fix', () {
      final analysis = analyseRide(_ride(seconds: 60));

      expect(analysis.samples, hasLength(61));
    });

    test('the speed comes out at the speed that was ridden', () {
      final analysis = analyseRide(_ride(seconds: 300));

      expect(analysis.hasSpeed, isTrue);
      // The ends of the smoothing window are a hair slower; the middle is the
      // speed itself.
      final middle = analysis.samples[analysis.samples.length ~/ 2];
      expect(middle.speedMps, closeTo(_twentyKmh, 0.001));
    });

    test('a reported speed is preferred to the one derived from the fixes', () {
      final track = <TrackPoint>[
        for (final point in _ride(seconds: 60)) point.copyWith(speedMps: 10),
      ];
      final analysis = analyseRide(track);

      final middle = analysis.samples[analysis.samples.length ~/ 2];
      expect(middle.speedMps, closeTo(10, 0.001));
    });

    test('a single spike is smoothed away', () {
      final track = _ride(seconds: 60, elevationAt: (s) => s == 30 ? 900 : 500);
      final analysis = analyseRide(track);

      final peak = analysis.samples
          .map((s) => s.elevationM!)
          .reduce((a, b) => a > b ? a : b);
      expect(peak, closeTo(500, 0.001), reason: 'the median took the spike');
    });

    test('a ride without heights offers no elevation chart', () {
      final analysis = analyseRide(_ride(seconds: 300));

      expect(analysis.hasElevation, isFalse);
      expect(analysis.samples.every((s) => s.elevationM == null), isTrue);
    });

    test('a ride with heights offers one', () {
      final analysis = analyseRide(
        _ride(seconds: 300, elevationAt: (s) => 500 + s.toDouble()),
      );

      expect(analysis.hasElevation, isTrue);
      expect(analysis.samples.first.elevationM, closeTo(500, 5));
    });
  });

  group('speed bands', () {
    test('five speeds fall into the five classes', () {
      // One second per step, so the step length is the speed.
      var position = _start;
      final points = <TrackPoint>[TrackPoint(position, time: _t0)];
      for (var i = 0; i < 5; i++) {
        position = destinationPoint(position, 0, (i + 1).toDouble());
        points.add(
          TrackPoint(position, time: _t0.add(Duration(seconds: i + 1))),
        );
      }

      final bands = analyseRide(points).speedBands;

      expect(bands.segments.map((s) => s.speedClass), <int>[0, 1, 2, 3, 4]);
      expect(bands.segments.map((s) => s.t), <double>[0, 0.25, 0.5, 0.75, 1]);
      expect(bands.thresholdsMps, hasLength(4));
      expect(bands.thresholdsMps[0], closeTo(1.8, 0.001));
      expect(bands.thresholdsMps[1], closeTo(2.6, 0.001));
      expect(bands.thresholdsMps[2], closeTo(3.4, 0.001));
      expect(bands.thresholdsMps[3], closeTo(4.2, 0.001));
    });

    test('neighbouring segments touch, so the line has no holes', () {
      var position = _start;
      final points = <TrackPoint>[TrackPoint(position, time: _t0)];
      for (var i = 0; i < 5; i++) {
        position = destinationPoint(position, 0, (i + 1).toDouble());
        points.add(
          TrackPoint(position, time: _t0.add(Duration(seconds: i + 1))),
        );
      }

      final segments = analyseRide(points).speedBands.segments;
      for (var i = 1; i < segments.length; i++) {
        expect(segments[i].points.first, segments[i - 1].points.last);
      }
    });

    test('one speed throughout is drawn in the middle colour', () {
      final bands = analyseRide(_ride(seconds: 120)).speedBands;

      expect(bands.segments, hasLength(1));
      expect(bands.segments.single.speedClass, 2);
      expect(bands.segments.single.points, hasLength(121));
    });

    test('a pause cuts the line instead of being drawn across', () {
      final first = _ride(seconds: 60);
      final second = _ride(
        seconds: 60,
        from: destinationPoint(first.last.pos, 0, 50),
        startedAt: _t0.add(const Duration(seconds: 660)),
      );
      final bands = analyseRide(<TrackPoint>[...first, ...second]).speedBands;

      expect(bands.segments, hasLength(2));
      expect(bands.segments.first.points.last, first.last.pos);
      expect(bands.segments.last.points.first, second.first.pos);
    });

    test('a track without times has nothing to colour', () {
      final bands = analyseRide(<TrackPoint>[
        const TrackPoint(LatLng(48, 11)),
        const TrackPoint(LatLng(48.01, 11)),
      ]).speedBands;

      expect(bands.isEmpty, isTrue);
    });
  });

  test('an empty track analyses to nothing', () {
    final analysis = analyseRide(const <TrackPoint>[]);

    expect(analysis.splits, isEmpty);
    expect(analysis.samples, isEmpty);
    expect(analysis.speedBands.isEmpty, isTrue);
    expect(analysis.hasElevation, isFalse);
    expect(analysis.hasSpeed, isFalse);
  });
}
