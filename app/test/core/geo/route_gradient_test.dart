import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/route_gradient.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Points every [stepM] metres over [lengthM], at the height [ele] gives
/// for the distance.
(List<double>, List<double?>) _line(
  double lengthM,
  double? Function(double d) ele, {
  double stepM = 20,
}) {
  final distances = <double>[];
  final heights = <double?>[];
  for (var d = 0.0; d <= lengthM + 1e-6; d += stepM) {
    distances.add(d);
    heights.add(ele(d));
  }
  return (distances, heights);
}

List<GradientRun> _runsOf(
  double lengthM,
  double? Function(double d) ele, {
  double stepM = 20,
}) {
  final (d, e) = _line(lengthM, ele, stepM: stepM);
  return gradientRuns(d, e);
}

List<GradientClass> _classes(List<GradientRun> runs) => [
  for (final run in runs) run.gradient,
];

/// The runs cover [from] to [to] without a hole or an overlap.
void _expectContiguous(List<GradientRun> runs, double from, double to) {
  expect(runs.first.startM, closeTo(from, 1e-6));
  expect(runs.last.endM, closeTo(to, 1e-6));
  for (var i = 1; i < runs.length; i++) {
    expect(runs[i].startM, closeTo(runs[i - 1].endM, 1e-6));
  }
}

void main() {
  group('gradientClassOf', () {
    test('puts each bound into the steeper class', () {
      expect(gradientClassOf(-8), GradientClass.descent);
      expect(gradientClassOf(-3), GradientClass.descent);
      expect(gradientClassOf(-2.9), GradientClass.flat);
      expect(gradientClassOf(0), GradientClass.flat);
      expect(gradientClassOf(3), GradientClass.moderate);
      expect(gradientClassOf(5.9), GradientClass.moderate);
      expect(gradientClassOf(6), GradientClass.steep);
      expect(gradientClassOf(10), GradientClass.verySteep);
      expect(gradientClassOf(25), GradientClass.verySteep);
    });

    test('every class has its own colour', () {
      final colours = GradientClass.values.map(gradientClassColour).toSet();
      expect(colours, hasLength(GradientClass.values.length));
      expect(gradientClassColour(GradientClass.descent), 0x3B82F6);
      expect(gradientClassColour(GradientClass.verySteep), 0xD7352B);
    });
  });

  group('gradientRuns', () {
    test('a flat road is one flat run end to end', () {
      final runs = _runsOf(3000, (_) => 250);
      expect(_classes(runs), [GradientClass.flat]);
      _expectContiguous(runs, 0, 3000);
    });

    for (final (percent, gradient) in [
      (5.0, GradientClass.moderate),
      (8.0, GradientClass.steep),
      (12.0, GradientClass.verySteep),
      (-6.0, GradientClass.descent),
    ]) {
      test('a steady $percent % is one ${gradient.name} run', () {
        final runs = _runsOf(2000, (d) => 400 + d * percent / 100);
        expect(_classes(runs), [gradient]);
        _expectContiguous(runs, 0, 2000);
      });
    }

    test('a climb between two flats is cut where it starts and ends', () {
      // Flat to 1 km, 8 % to 2 km, flat to 3 km.
      final runs = _runsOf(
        3000,
        (d) => 100 + (d.clamp(1000, 2000) - 1000) * 0.08,
      );
      expect(_classes(runs), [
        GradientClass.flat,
        GradientClass.steep,
        GradientClass.flat,
      ]);
      _expectContiguous(runs, 0, 3000);
      expect(runs[1].startM, closeTo(1000, 50));
      expect(runs[1].endM, closeTo(2000, 50));
    });

    test('a zigzag of DEM noise on a flat road stays flat', () {
      // Two metres up and down from one point to the next, ten metres
      // apart: a 40 % "gradient" from point to point.
      final runs = _runsOf(
        2000,
        (d) => 300 + ((d / 10).round().isEven ? 2.0 : -2.0),
        stepM: 10,
      );
      expect(_classes(runs), [GradientClass.flat]);
    });

    test('noise on a steady climb keeps it one class', () {
      final random = math.Random(7);
      final runs = _runsOf(
        3000,
        (d) => 200 + d * 0.08 + (random.nextDouble() - 0.5) * 3,
        stepM: 15,
      );
      expect(_classes(runs), [GradientClass.steep]);
    });

    test('measures sparse and dense lines of the same road alike', () {
      double ele(double d) => 100 + (d > 1500 ? (d - 1500) * 0.05 : 0);
      final dense = _runsOf(3000, ele, stepM: 5);
      final sparse = _runsOf(3000, ele, stepM: 250);
      expect(_classes(dense), _classes(sparse));
      expect(_classes(dense), [GradientClass.flat, GradientClass.moderate]);
    });

    test('bridges a short stretch without heights', () {
      final runs = _runsOf(
        2000,
        (d) => d > 900 && d < 1100 ? null : 100 + d * 0.05,
      );
      expect(_classes(runs), [GradientClass.moderate]);
      _expectContiguous(runs, 0, 2000);
    });

    test('leaves a long stretch without heights uncoloured', () {
      final runs = _runsOf(
        4000,
        (d) => d > 1000 && d < 2500 ? null : 100 + d * 0.05,
      );
      expect(_classes(runs), [GradientClass.moderate, GradientClass.moderate]);
      expect(runs.first.startM, 0);
      expect(runs.first.endM, closeTo(1000, 1e-6));
      expect(runs.last.startM, closeTo(2500, 25));
      expect(runs.last.endM, closeTo(4000, 1e-6));
    });

    test('points far apart with heights are a straight road, not a gap', () {
      final runs = gradientRuns(
        <double>[0, 2000, 4000],
        <double?>[100, 100, 100],
      );
      expect(_classes(runs), [GradientClass.flat]);
      _expectContiguous(runs, 0, 4000);
    });

    test('colours nothing before the first height or after the last', () {
      final runs = _runsOf(
        2000,
        (d) => d < 300 || d > 1700 ? null : 100 + d * 0.12,
      );
      expect(_classes(runs), [GradientClass.verySteep]);
      expect(runs.first.startM, closeTo(300, 20));
      expect(runs.last.endM, closeTo(1700, 20));
    });

    test('a line without heights has no runs', () {
      expect(_runsOf(2000, (_) => null), isEmpty);
      expect(gradientRuns(const <double>[], const <double?>[]), isEmpty);
      expect(gradientRuns(const <double>[0], const <double?>[100]), isEmpty);
    });

    test('a very short route is measured whole', () {
      final runs = gradientRuns(<double>[0, 30], <double?>[100, 103]);
      expect(_classes(runs), [GradientClass.verySteep]);
      _expectContiguous(runs, 0, 30);
      final flat = gradientRuns(<double>[0, 30], <double?>[100, 100]);
      expect(_classes(flat), [GradientClass.flat]);
    });

    test('a kerb-sized kick does not colour the road', () {
      // A metre and a half up over 15 m in the middle of a flat road.
      final runs = _runsOf(
        2000,
        (d) => 100 + (d.clamp(1000, 1015) - 1000) * 0.1,
        stepM: 5,
      );
      expect(_classes(runs), [GradientClass.flat]);
      _expectContiguous(runs, 0, 2000);
    });

    test('a road right on a bound does not flicker', () {
      // 3 % with a few centimetres of noise: point by point it crosses
      // from flat to moderate and back again and again.
      final random = math.Random(11);
      final runs = _runsOf(
        3000,
        (d) => 100 + d * 0.03 + (random.nextDouble() - 0.5) * 0.4,
        stepM: 10,
      );
      for (final run in runs) {
        expect(run.endM - run.startM, greaterThanOrEqualTo(gradientMinRunM));
      }
      expect(
        _classes(runs).toSet(),
        everyElement(isIn([GradientClass.flat, GradientClass.moderate])),
      );
      _expectContiguous(runs, 0, 3000);
    });

    test('no run but a lone one is shorter than the merge length', () {
      final random = math.Random(3);
      // A rolling road: half-kilometre waves with noise on top.
      final runs = _runsOf(
        8000,
        (d) =>
            200 +
            30 * math.sin(d / 500 * math.pi) +
            (random.nextDouble() - 0.5) * 2,
        stepM: 10,
      );
      expect(runs.length, greaterThan(1));
      for (final run in runs) {
        expect(run.endM - run.startM, greaterThanOrEqualTo(gradientMinRunM));
      }
      for (var i = 1; i < runs.length; i++) {
        expect(runs[i].gradient, isNot(runs[i - 1].gradient));
      }
      _expectContiguous(runs, 0, 8000);
    });
  });

  test('gradientRunsOf measures a route by its own positions', () {
    final geometry = <TrackPoint>[
      for (var d = 0.0; d <= 2000; d += 100)
        TrackPoint(
          destinationPoint(const LatLng(47, 8), 90, d),
          ele: 500 - d * 0.07,
        ),
    ];
    final runs = gradientRunsOf(geometry);
    expect(_classes(runs), [GradientClass.descent]);
    expect(runs.single.endM, closeTo(2000, 1));
  });
}
