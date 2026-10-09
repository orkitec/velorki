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

List<(List<int>, int)> climbs(List<double> heights, {double step = 10}) {
  final (coords, elevations) = north(heights, stepMetres: step);
  final out = <(List<int>, int)>[];
  findClimbs(coords, elevations, (c, g) => out.add((c, g)));
  return out;
}

void main() {
  test('grade classes', () {
    expect(gradeClass(0.05), 0);
    expect(gradeClass(0.06), 1);
    expect(gradeClass(-0.12), 2);
    expect(gradeClass(0.2), 3);
  });

  test('a flat line has no climb', () {
    expect(climbs([0, 0, 0, 0, 0, 0, 0]), isEmpty);
  });

  test('a steady 8 % climb is one piece of class 1, drawn uphill', () {
    final c = climbs([0, 0.8, 1.6, 2.4, 3.2, 4.0, 4.8]);
    expect(c, hasLength(1));
    expect(c.single.$2, 1);
    final points = c.single.$1;
    // From the first point to the last: the way goes up.
    expect(points[1], lessThan(points[points.length - 1]));
  });

  test('a descent is drawn from its foot, against the way', () {
    final c = climbs([12, 10.8, 9.6, 8.4, 7.2, 6.0, 4.8]);
    expect(c.single.$2, 2);
    final points = c.single.$1;
    expect(points[1], greaterThan(points[points.length - 1]));
  });

  test('a one-point bump is smoothed away by the window', () {
    // 1 m up and down over 10 m would be 10 %, over 30 m it is not steep.
    expect(climbs([0, 0, 0, 1, 0, 0, 0]), isEmpty);
  });

  test('a climb then a flat: only the climb', () {
    final c = climbs([0, 1.2, 2.4, 3.6, 3.6, 3.6, 3.6, 3.6, 3.6, 3.6]);
    expect(c, hasLength(1));
    expect(c.single.$2, 2);
    // The climb's three stretches of 10 m make one window of 30 m.
    expect(c.single.$1, hasLength(8));
  });

  test('too short to tell', () {
    expect(climbs([0, 5], step: 15), isEmpty);
    expect(climbs([0, 5], step: 25), hasLength(1));
  });
}
