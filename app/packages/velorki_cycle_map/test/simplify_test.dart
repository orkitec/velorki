import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:velorki_cycle_map/velorki_cycle_map.dart';

List<int> simplify(List<int> coords, double tolerance, [double scale = 1]) {
  final c = Int32List.fromList(coords);
  final keep = Int32List(c.length);
  final n = simplifyLine(c, 0, c.length >> 1, tolerance, scale, keep, []);
  return keep.sublist(0, n);
}

void main() {
  test('drops points closer to the line than the tolerance', () {
    expect(simplify([0, 0, 10, 1, 20, 0], 2), [0, 2]);
  });

  test('keeps the corner beyond it', () {
    expect(simplify([0, 0, 10, 10, 20, 0], 2), [0, 1, 2]);
  });

  test('keeps every point without a tolerance, and short lines', () {
    expect(simplify([0, 0, 10, 1, 20, 0], 0), [0, 1, 2]);
    expect(simplify([0, 0, 20, 0], 50), [0, 1]);
  });

  test('scales the longitude', () {
    // 4 east of the line is 2 at a scale of a half.
    expect(simplify([0, 0, 4, 10, 0, 20], 3, 0.5), [0, 2]);
    expect(simplify([0, 0, 4, 10, 0, 20], 3), [0, 1, 2]);
  });

  test('tolerance: half a pixel, none from zoom 16', () {
    // About 4.8 m a half pixel at zoom 13 on the equator.
    expect(toleranceAtZoom(13, 0), closeTo(4.78 / 0.111195, 0.5));
    expect(toleranceAtZoom(14, 0), closeTo(toleranceAtZoom(13, 0) / 2, 1e-9));
    expect(toleranceAtZoom(16, 50), 0);
  });
}
