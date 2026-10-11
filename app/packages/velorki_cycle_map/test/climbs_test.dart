import 'package:test/test.dart';
import 'package:velorki_cycle_map/velorki_cycle_map.dart';

/// A line due north from the equator, a point every [stepMetres], with the
/// heights in metres [heights].
(List<int>, List<int>) north(List<double> heights, {double stepMetres = 10}) {
  final coords = <int>[];
  final elevations = <int>[];
  for (var i = 0; i < heights.length; i++) {
    coords
      ..add(180000000)
      ..add(90000000 + (i * stepMetres / 0.110574).round());
    elevations.add((heights[i] * 4).round());
  }
  return (coords, elevations);
}

/// No smoothing, no minimum: the stretches as they are.
const raw = ClimbRule(
  smoothMetres: 0,
  measureSmoothMetres: 0,
  windowMetres: 30,
  minLengthMetres: 20,
  minRiseMetres: 0,
  detectGrade: 0.06,
);

List<(List<int>, int)> climbs(
  List<double> heights, {
  double step = 10,
  ClimbRule rule = raw,
}) {
  final (coords, elevations) = north(heights, stepMetres: step);
  final out = <(List<int>, int)>[];
  findClimbs(coords, elevations, (c, g) => out.add((c, g)), rule: rule);
  return out;
}

/// [metres] of road at [grade], from [from] metres up.
List<double> slope(double metres, double grade, {double from = 0}) => [
  for (var d = 0.0; d <= metres; d += 10) from + d * grade,
];

void main() {
  test('grade classes', () {
    expect(gradeClass(0.05), 0);
    expect(gradeClass(0.06), 1);
    expect(gradeClass(-0.12), 2);
    expect(gradeClass(0.2), 3);
  });

  group('the stretches as they are', () {
    test('a flat line has no climb', () {
      expect(climbs([0, 0, 0, 0, 0, 0, 0]), isEmpty);
    });

    test('a steady 8 % climb is one piece of class 1, drawn uphill', () {
      final c = climbs(slope(60, 0.08));
      expect(c, hasLength(1));
      expect(c.single.$2, 1);
      final points = c.single.$1;
      expect(points[1], lessThan(points[points.length - 1]));
    });

    test('a descent is drawn from its foot, against the way', () {
      final c = climbs(slope(60, -0.12, from: 12));
      expect(c.single.$2, 2);
      final points = c.single.$1;
      expect(points[1], greaterThan(points[points.length - 1]));
    });

    test('a climb then a flat: only the climb', () {
      final c = climbs([...slope(30, 0.12), 3.6, 3.6, 3.6, 3.6, 3.6, 3.6]);
      expect(c, hasLength(1));
      expect(c.single.$2, 2);
    });

    test('too short to tell', () {
      expect(climbs([0, 5], step: 15), isEmpty);
      expect(climbs([0, 5], step: 25), hasLength(1));
    });
  });

  group('the rule of the map', () {
    List<(List<int>, int)> standard(List<double> heights) =>
        climbs(heights, rule: ClimbRule.standard);

    test('a long climb is found and measured at its own grade', () {
      final c = standard([
        ...slope(200, 0),
        ...slope(400, 0.12, from: 0),
        ...slope(200, 0, from: 48),
      ]);
      expect(c, isNotEmpty);
      expect(c.map((p) => p.$2), contains(2));
    });

    test('the bump of a block of tall buildings is no climb', () {
      // Up 8 m over 80 m, down again: a terrain model's tower block.
      final c = standard([
        ...slope(300, 0),
        ...slope(80, 0.1),
        ...slope(80, -0.1, from: 8),
        ...slope(300, 0),
      ]);
      expect(c, isEmpty);
    });

    test('a short steep ramp that gains little is no climb', () {
      expect(
        standard([
          ...slope(200, 0),
          ...slope(60, 0.15),
          ...slope(200, 0, from: 9),
        ]),
        isEmpty,
      );
    });

    test('a flat street with a metre of noise has no climb', () {
      final noisy = [for (var i = 0; i < 80; i++) (i % 3 == 0 ? 1.0 : 0.0)];
      expect(standard(noisy), isEmpty);
    });
  });
}
