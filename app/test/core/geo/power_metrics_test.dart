import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/power_metrics.dart';

/// One reading a second, [watts] at second `i`.
List<PowerSample> _everySecond(int seconds, int Function(int i) watts) =>
    <PowerSample>[
      for (var i = 0; i < seconds; i++) (atSeconds: i, watts: watts(i)),
    ];

/// The definition, spelt out the long way: every thirty second window of a
/// one-a-second series, its mean to the fourth, the fourth root of the
/// average of those.
double _byDefinition(List<int> perSecond) {
  var sum = 0.0;
  var windows = 0;
  for (var start = 0; start + 30 <= perSecond.length; start++) {
    var total = 0;
    for (var k = start; k < start + 30; k++) {
      total += perSecond[k];
    }
    final mean = total / 30;
    sum += math.pow(mean, 4);
    windows++;
  }
  return math.pow(sum / windows, 0.25).toDouble();
}

void main() {
  group('normalizedPower', () {
    test('a steady 200 W is 200 W', () {
      expect(normalizedPower(_everySecond(120, (_) => 200)), 200);
    });

    test('surges weigh more than their mean', () {
      // Thirty seconds at 100 W, thirty at 300 W, four times over: a plain
      // mean of 200, a normalised power above it.
      final perSecond = <int>[
        for (var i = 0; i < 240; i++) (i ~/ 30).isEven ? 100 : 300,
      ];

      final result = normalizedPower(
        _everySecond(perSecond.length, (i) => perSecond[i]),
      );

      expect(result, _byDefinition(perSecond).round());
      expect(result, greaterThan(200));
    });

    test('a reading is held across a short silence of the meter', () {
      // Readings every 5 s hold to the next: the same as one a second.
      final sparse = <PowerSample>[
        for (var t = 0; t < 60; t += 5) (atSeconds: t, watts: 250),
      ];

      expect(normalizedPower(sparse), 250);
    });

    test('under thirty seconds of power is nothing', () {
      expect(normalizedPower(_everySecond(29, (_) => 200)), isNull);
      expect(normalizedPower(const <PowerSample>[]), isNull);
    });

    test('a gap longer than five seconds is not bridged', () {
      // Two runs of twenty seconds, a minute apart: neither fills a window
      // on its own, and the gap does not join them.
      final samples = <PowerSample>[
        ..._everySecond(20, (_) => 200),
        for (var i = 0; i < 20; i++) (atSeconds: 80 + i, watts: 200),
      ];

      expect(normalizedPower(samples), isNull);
    });

    test('the windows after a gap start afresh, so a gap of rest does not '
        'drag the figure down', () {
      // Thirty seconds at 200 W, a minute of nothing, thirty more at 200 W:
      // no window ever straddles the gap, so no window ever reads zero.
      final samples = <PowerSample>[
        ..._everySecond(30, (_) => 200),
        for (var i = 0; i < 30; i++) (atSeconds: 90 + i, watts: 200),
      ];

      expect(normalizedPower(samples), 200);
    });
  });

  group('bestAveragePower', () {
    test('a steady 250 W is 250 W', () {
      expect(bestAveragePower(_everySecond(1200, (_) => 250)), 250);
      expect(bestAveragePower(_everySecond(1500, (_) => 250)), 250);
    });

    test('a twenty minute burst inside a longer ride is picked out whole', () {
      // Ten minutes at 250 W, twenty at 300 W, ten more at 250 W.
      final samples = _everySecond(
        2400,
        (i) => i >= 600 && i < 1800 ? 300 : 250,
      );

      expect(bestAveragePower(samples), 300);
    });

    test('nineteen minutes of power is nothing', () {
      expect(bestAveragePower(_everySecond(1140, (_) => 250)), isNull);
      expect(bestAveragePower(const <PowerSample>[]), isNull);
    });

    test('a gap longer than five seconds breaks the window', () {
      // Two runs of fifteen minutes with a minute of nothing between them:
      // half an hour of power, none of it twenty minutes in one piece.
      final samples = <PowerSample>[
        ..._everySecond(900, (_) => 250),
        for (var i = 0; i < 900; i++) (atSeconds: 960 + i, watts: 250),
      ];

      expect(bestAveragePower(samples), isNull);
    });

    test('a reading is held across a short silence of the meter', () {
      // Readings every 5 s hold to the next; the last covers its own second,
      // so twenty minutes needs one at 1200 s.
      final sparse = <PowerSample>[
        for (var t = 0; t <= 1200; t += 5) (atSeconds: t, watts: 250),
      ];

      expect(bestAveragePower(sparse), 250);
      expect(bestAveragePower(sparse.sublist(0, sparse.length - 1)), isNull);
    });

    test('the window can be any length', () {
      // A minute at 300 W in ten minutes of 200 W.
      final samples = _everySecond(600, (i) => i >= 300 && i < 360 ? 300 : 200);

      expect(bestAveragePower(samples, windowSeconds: 60), 300);
      expect(bestAveragePower(samples, windowSeconds: 120), 250);
    });
  });

  group('powerZoneOf', () {
    test('the seven zones are cut at 55, 75, 90, 105, 120 and 150 %', () {
      const threshold = 200;
      // Each boundary and the watt below it, of a 200 W threshold.
      expect(powerZoneOf(109, threshold), 0);
      expect(powerZoneOf(110, threshold), 1);
      expect(powerZoneOf(149, threshold), 1);
      expect(powerZoneOf(150, threshold), 2);
      expect(powerZoneOf(179, threshold), 2);
      expect(powerZoneOf(180, threshold), 3);
      expect(powerZoneOf(209, threshold), 3);
      expect(powerZoneOf(210, threshold), 4);
      expect(powerZoneOf(239, threshold), 4);
      expect(powerZoneOf(240, threshold), 5);
      expect(powerZoneOf(299, threshold), 5);
      expect(powerZoneOf(300, threshold), 6);
      expect(powerZoneOf(1000, threshold), 6);
      expect(powerZoneOf(0, threshold), 0);
    });

    test('the bounds list one lower bound per zone', () {
      expect(powerZoneBoundsPercent, hasLength(powerZoneCount));
      expect(powerZoneBoundsPercent.first, 0);
    });
  });
}
