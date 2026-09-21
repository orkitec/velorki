import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/power_model.dart';
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
    expect(analysis.hasHeartRate, isFalse);
  });

  group('heart rate samples', () {
    test('the chart samples carry what the strap reported', () {
      final points = <TrackPoint>[
        for (final (i, point) in _ride(seconds: 60).indexed)
          point.copyWith(heartRateBpm: 120 + i),
      ];

      final analysis = analyseRide(points);

      expect(analysis.hasHeartRate, isTrue);
      expect(analysis.samples.first.heartRateBpm, 120);
      expect(analysis.samples.last.heartRateBpm, 180);
    });

    test('a ride without a strap has no heart rate chart', () {
      final analysis = analyseRide(_ride(seconds: 60));

      expect(analysis.hasHeartRate, isFalse);
      expect(analysis.samples.map((s) => s.heartRateBpm), everyElement(isNull));
    });

    test('one reading alone is not a chart', () {
      final points = _ride(seconds: 60);
      points[10] = points[10].copyWith(heartRateBpm: 140);

      final analysis = analyseRide(points);

      expect(analysis.hasHeartRate, isFalse);
    });

    test('thinning a long ride interpolates the readings', () {
      final points = <TrackPoint>[
        for (final (i, point) in _ride(seconds: 2000).indexed)
          point.copyWith(heartRateBpm: 100 + i ~/ 40),
      ];

      final analysis = analyseRide(points, maxSamples: 50);

      expect(analysis.samples, hasLength(50));
      expect(analysis.samples.first.heartRateBpm, 100);
      expect(analysis.samples.last.heartRateBpm, 150);
      expect(analysis.hasHeartRate, isTrue);
    });
  });

  group('effort', () {
    const zero = Duration.zero;

    test('a steady ride with a power meter is watts times seconds', () {
      final points = <TrackPoint>[
        for (final point in _ride(seconds: 60)) point.copyWith(powerW: 200),
      ];

      final effort = analyseRide(points).effort;

      expect(_seconds(effort.movingTime), closeTo(60, 1e-6));
      expect(_seconds(effort.powerTime), closeTo(60, 1e-6));
      expect(effort.energyKj, closeTo(200 * 60 / 1000, 1e-9));
      // 20 km/h is 8 MET, for a minute.
      expect(effort.metHours, closeTo(8 / 60, 1e-9));
    });

    test('the highest cadence and power are picked out', () {
      final points = <TrackPoint>[
        for (final (i, point) in _ride(seconds: 30).indexed)
          point.copyWith(cadenceRpm: 80 + (i == 12 ? 25 : 0), powerW: 150 + i),
      ];

      final effort = analyseRide(points).effort;

      expect(effort.maxCadenceRpm, 105);
      expect(effort.maxPowerW, 180);
    });

    test(
      'a ride without sensors has no maxima, no power and no heart rate',
      () {
        final effort = analyseRide(_ride(seconds: 60)).effort;

        expect(effort.maxCadenceRpm, isNull);
        expect(effort.maxPowerW, isNull);
        expect(effort.energyKj, 0);
        expect(effort.powerTime, zero);
        expect(effort.heartRateTime, zero);
        expect(effort.heartRateBeatSeconds, 0);
        expect(effort.heartRateZones, everyElement(zero));
      },
    );

    test(
      'the heart rate is summed as beat-seconds over the time it was known',
      () {
        final points = <TrackPoint>[
          for (final (i, point) in _ride(seconds: 60).indexed)
            // Only the first half of the ride had a strap.
            point.copyWith(heartRateBpm: i < 30 ? 140 : null),
        ];

        final effort = analyseRide(points).effort;

        expect(_seconds(effort.heartRateTime), closeTo(30, 1e-6));
        expect(effort.heartRateBeatSeconds, closeTo(140 * 30, 1e-6));
        expect(_seconds(effort.movingTime), closeTo(60, 1e-6));
      },
    );

    test('the zones are cut at 60, 70, 80 and 90 % of the maximum', () {
      // Ten seconds at each of five readings, the first four exactly on a
      // boundary: 119 is just under 60 % of 200, 120 exactly 60 %.
      const readings = <int>[119, 120, 140, 160, 180];
      final points = <TrackPoint>[
        for (final (i, point) in _ride(seconds: 50).indexed)
          point.copyWith(heartRateBpm: readings[(i ~/ 10).clamp(0, 4)]),
      ];

      final effort = analyseRide(points, maxHeartRateBpm: 200).effort;

      expect(effort.heartRateZones, hasLength(5));
      for (final zone in effort.heartRateZones) {
        expect(_seconds(zone), closeTo(10, 1e-6));
      }
    });

    test('everything under 60 % is zone 1', () {
      final points = <TrackPoint>[
        for (final point in _ride(seconds: 20))
          point.copyWith(heartRateBpm: 70),
      ];

      final effort = analyseRide(points, maxHeartRateBpm: 200).effort;

      expect(_seconds(effort.heartRateZones.first), closeTo(20, 1e-6));
      expect(effort.heartRateZones.skip(1), everyElement(zero));
    });

    test(
      'without a maximum the zones stay empty though the rate is summed',
      () {
        final points = <TrackPoint>[
          for (final point in _ride(seconds: 20))
            point.copyWith(heartRateBpm: 150),
        ];

        final effort = analyseRide(points).effort;

        expect(_seconds(effort.heartRateTime), closeTo(20, 1e-6));
        expect(effort.heartRateZones, everyElement(zero));
      },
    );

    test('a pause counts nowhere', () {
      // Thirty seconds of riding, a two minute stop, thirty more.
      final first = _ride(seconds: 30);
      final second = _ride(
        seconds: 30,
        from: first.last.pos,
        startedAt: first.last.time!.add(const Duration(minutes: 2)),
      );
      final points = <TrackPoint>[
        for (final point in <TrackPoint>[...first, ...second])
          point.copyWith(heartRateBpm: 150, powerW: 100),
      ];

      final effort = analyseRide(points, maxHeartRateBpm: 200).effort;

      expect(_seconds(effort.movingTime), closeTo(60, 1e-6));
      expect(_seconds(effort.powerTime), closeTo(60, 1e-6));
      expect(effort.energyKj, closeTo(100 * 60 / 1000, 1e-9));
      expect(_seconds(effort.heartRateTime), closeTo(60, 1e-6));
      // 150 of 200 is 75 %: zone 3, and only the ridden minute of it.
      expect(_seconds(effort.heartRateZones[2]), closeTo(60, 1e-6));
      expect(effort.metHours, closeTo(8 / 60, 1e-9));
    });

    test('an empty analysis has zero effort', () {
      expect(analyseRide(const <TrackPoint>[]).effort, RideEffort.zero);
      expect(RideAnalysis.empty.effort, RideEffort.zero);
    });
  });

  group('power zones', () {
    const zero = Duration.zero;

    test('the zones are cut at 55, 75, 90, 105, 120 and 150 % of the '
        'threshold', () {
      // Ten seconds at each of seven readings, each one exactly on its
      // boundary of a 200 W threshold, the first just under the lowest.
      const readings = <int>[109, 110, 150, 180, 210, 240, 300];
      final points = <TrackPoint>[
        for (final (i, point) in _ride(seconds: 70).indexed)
          point.copyWith(powerW: readings[(i ~/ 10).clamp(0, 6)]),
      ];

      final effort = analyseRide(points, thresholdPowerW: 200).effort;

      expect(effort.powerZones, hasLength(7));
      for (final zone in effort.powerZones) {
        expect(_seconds(zone), closeTo(10, 1e-6));
      }
    });

    test('without a threshold the seven zones stay empty though the power '
        'is summed', () {
      final points = <TrackPoint>[
        for (final point in _ride(seconds: 60)) point.copyWith(powerW: 200),
      ];

      final effort = analyseRide(points).effort;

      expect(effort.powerZones, hasLength(7));
      expect(effort.powerZones, everyElement(zero));
      expect(_seconds(effort.powerTime), closeTo(60, 1e-6));
    });

    test('a pause counts nowhere', () {
      final first = _ride(seconds: 30);
      final second = _ride(
        seconds: 30,
        from: first.last.pos,
        startedAt: first.last.time!.add(const Duration(minutes: 2)),
      );
      final points = <TrackPoint>[
        for (final point in <TrackPoint>[...first, ...second])
          point.copyWith(powerW: 160),
      ];

      final effort = analyseRide(points, thresholdPowerW: 200).effort;

      // 160 of 200 is 80 %: zone 3, and only the ridden minute of it.
      expect(_seconds(effort.powerZones[2]), closeTo(60, 1e-6));
      expect(effort.powerZones[0], zero);
      expect(effort.powerZones[1], zero);
      expect(effort.powerZones.skip(3), everyElement(zero));
    });

    test('a steady 200 W normalises to 200 W, a ride without a meter to '
        'nothing', () {
      final points = <TrackPoint>[
        for (final point in _ride(seconds: 60)) point.copyWith(powerW: 200),
      ];

      expect(analyseRide(points).effort.normalizedPowerW, 200);
      expect(analyseRide(_ride(seconds: 60)).effort.normalizedPowerW, isNull);
    });

    test('the normalised power is not carried across a pause', () {
      // Twenty seconds of power, a two minute stop, twenty more: no half
      // minute of it in one piece.
      final first = _ride(seconds: 20);
      final second = _ride(
        seconds: 20,
        from: first.last.pos,
        startedAt: first.last.time!.add(const Duration(minutes: 2)),
      );
      final points = <TrackPoint>[
        for (final point in <TrackPoint>[...first, ...second])
          point.copyWith(powerW: 200),
      ];

      expect(analyseRide(points).effort.normalizedPowerW, isNull);
    });

    test('the best twenty minutes are the meter\'s best twenty minutes, and '
        'nothing on a shorter ride', () {
      // Twenty-five minutes: 200 W with a twenty minute stretch at 260 W.
      final long = _ride(seconds: 1500);
      final points = <TrackPoint>[
        for (var i = 0; i < long.length; i++)
          long[i].copyWith(powerW: i >= 180 && i < 1380 ? 260 : 200),
      ];

      expect(analyseRide(points).effort.bestTwentyMinutePowerW, 260);
      final short = <TrackPoint>[
        for (final point in _ride(seconds: 1140)) point.copyWith(powerW: 260),
      ];
      expect(analyseRide(short).effort.bestTwentyMinutePowerW, isNull);
      expect(
        analyseRide(_ride(seconds: 1500)).effort.bestTwentyMinutePowerW,
        isNull,
      );
    });
  });

  group('estimated power', () {
    // A 75 kg rider on a 9 kg road bike.
    const model = PowerModel(massKg: 84, cdA: 0.32, crr: 0.005);
    const thirtyKmh = 30 / 3.6;

    test('a flat steady 30 km/h is about 151 W', () {
      final points = _ride(
        seconds: 120,
        speedMps: thirtyKmh,
        elevationAt: (_) => 0,
      );

      final effort = analyseRide(points, powerModel: model).effort;

      expect(_seconds(effort.estimatedPowerTime), closeTo(120, 1e-6));
      expect(effort.estimatedAvgPowerW, closeTo(151, 2));
      expect(effort.estimatedEnergyKj, closeTo(151 * 120 / 1000, 0.3));
    });

    test('without a model nothing is estimated', () {
      final effort = analyseRide(
        _ride(seconds: 120, speedMps: thirtyKmh, elevationAt: (_) => 0),
      ).effort;

      expect(effort.estimatedAvgPowerW, isNull);
      expect(effort.estimatedEnergyKj, 0);
      expect(effort.estimatedPowerTime, Duration.zero);
    });

    test('a track without heights is priced as flat at sea level', () {
      final effort = analyseRide(
        _ride(seconds: 120, speedMps: thirtyKmh),
        powerModel: model,
      ).effort;

      expect(effort.estimatedAvgPowerW, closeTo(151, 2));
    });

    test('a climb costs more than the flat, a descent nothing', () {
      // 8 % at 10 km/h: 2.778 m/s, 0.222 m a second. Ten minutes of it, so
      // the one-sided smoothing window at either end hardly shows.
      const tenKmh = 10 / 3.6;
      final climb = analyseRide(
        _ride(
          seconds: 600,
          speedMps: tenKmh,
          elevationAt: (second) => second * tenKmh * 0.08,
        ),
        powerModel: model,
      ).effort;
      final descent = analyseRide(
        _ride(
          seconds: 120,
          speedMps: thirtyKmh,
          elevationAt: (second) => 1000 - second * thirtyKmh * 0.08,
        ),
        powerModel: model,
      ).effort;

      expect(climb.estimatedAvgPowerW, closeTo(203, 4));
      expect(descent.estimatedAvgPowerW, 0);
    });

    test('a pause counts nowhere', () {
      // A minute of riding, a two minute stop, a minute more.
      final first = _ride(
        seconds: 60,
        speedMps: thirtyKmh,
        elevationAt: (_) => 0,
      );
      final second = _ride(
        seconds: 60,
        speedMps: thirtyKmh,
        elevationAt: (_) => 0,
        from: first.last.pos,
        startedAt: first.last.time!.add(const Duration(minutes: 2)),
      );

      final effort = analyseRide(<TrackPoint>[
        ...first,
        ...second,
      ], powerModel: model).effort;

      expect(_seconds(effort.estimatedPowerTime), closeTo(120, 1e-6));
      expect(effort.estimatedAvgPowerW, closeTo(151, 2));
    });
  });
}
