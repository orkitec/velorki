import 'package:test/test.dart';
import 'package:velorki_cycle_map/velorki_cycle_map.dart';

CellWays cell(List<(List<int>, int)> lines) {
  final b = CellWaysBuilder();
  for (final (coords, attrs) in lines) {
    b.addLine(coords, attrs);
  }
  b.addBarrier(5, 5, BarrierClass.gate);
  return b.build();
}

List<List<int>> linesOf(CellWays c) => [
  for (var i = 0; i < c.lineCount; i++)
    c.coords.sublist(c.starts[i] * 2, c.starts[i + 1] * 2),
];

void main() {
  test('joins links that continue one another', () {
    final merged = mergeLines(
      cell([
        ([0, 0, 1, 0], 1),
        ([1, 0, 2, 0, 3, 1], 1),
        ([3, 1, 4, 1], 1),
      ]),
    );
    expect(linesOf(merged), [
      [0, 0, 1, 0, 2, 0, 3, 1, 4, 1],
    ]);
    expect(merged.attrs, [1]);
    expect(merged.barriers, [5, 5, BarrierClass.gate]);
  });

  test('joins in any order of the links', () {
    final merged = mergeLines(
      cell([
        ([3, 1, 4, 1], 1),
        ([0, 0, 1, 0], 1),
        ([1, 0, 3, 1], 1),
      ]),
    );
    expect(linesOf(merged), [
      [0, 0, 1, 0, 3, 1, 4, 1],
    ]);
  });

  test('keeps lines with other attributes apart', () {
    final merged = mergeLines(
      cell([
        ([0, 0, 1, 0], 1),
        ([1, 0, 2, 0], 2),
      ]),
    );
    expect(merged.lineCount, 2);
  });

  test('does not join at a fork', () {
    final merged = mergeLines(
      cell([
        ([0, 0, 1, 0], 1),
        ([1, 0, 2, 0], 1),
        ([1, 0, 1, 1], 1),
      ]),
    );
    expect(merged.lineCount, 3);
    expect(merged.pointCount, 6);
  });

  test('keeps the direction: head to head is not joined', () {
    final merged = mergeLines(
      cell([
        ([0, 0, 1, 0], 1),
        ([2, 0, 1, 0], 1),
      ]),
    );
    expect(merged.lineCount, 2);
  });

  test('a ring comes out as one line', () {
    final merged = mergeLines(
      cell([
        ([0, 0, 1, 0], 1),
        ([1, 0, 1, 1], 1),
        ([1, 1, 0, 0], 1),
      ]),
    );
    expect(merged.lineCount, 1);
    expect(merged.pointCount, 4);
  });
}
