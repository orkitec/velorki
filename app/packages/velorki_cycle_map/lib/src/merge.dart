import 'cell_ways.dart';

/// [cell] with the lines that continue one another joined: a link ends
/// where the next of its way starts, so a street is a dozen links, and as
/// one line it is drawn (and dashed) in one piece and costs one feature.
///
/// Two lines join where one ends and the other starts with the same
/// attributes, and no other line with those attributes ends or starts
/// there. Lines keep their direction, which their sides depend on.
CellWays mergeLines(CellWays cell) {
  final n = cell.lineCount;
  if (n < 2) return cell;
  final coords = cell.coords;
  final starts = cell.starts;
  final attrs = cell.attrs;

  int pointKey(int point) =>
      coords[point * 2] * 0x40000000 + coords[point * 2 + 1];

  // The single line starting or ending at a point with given attributes,
  // or -1 where there are several.
  final byStart = <(int, int), int>{};
  final byEnd = <(int, int), int>{};
  for (var i = 0; i < n; i++) {
    final s = (pointKey(starts[i]), attrs[i]);
    byStart[s] = byStart.containsKey(s) ? -1 : i;
    final e = (pointKey(starts[i + 1] - 1), attrs[i]);
    byEnd[e] = byEnd.containsKey(e) ? -1 : i;
  }
  final next = List<int>.filled(n, -1);
  final hasPrevious = List<bool>.filled(n, false);
  for (var i = 0; i < n; i++) {
    final at = (pointKey(starts[i + 1] - 1), attrs[i]);
    if (byEnd[at] != i) continue;
    final j = byStart[at];
    if (j == null || j < 0 || j == i) continue;
    next[i] = j;
    hasPrevious[j] = true;
  }

  final out = CellWaysBuilder();
  final done = List<bool>.filled(n, false);
  final line = <int>[];
  void chain(int head) {
    line.clear();
    for (var i = head; i >= 0 && !done[i]; i = next[i]) {
      done[i] = true;
      // A joined line's first point is the previous one's last.
      final from = line.isEmpty ? starts[i] : starts[i] + 1;
      for (var p = from; p < starts[i + 1]; p++) {
        line
          ..add(coords[p * 2])
          ..add(coords[p * 2 + 1]);
      }
    }
    out.addLine(line, attrs[head]);
  }

  for (var i = 0; i < n; i++) {
    if (!hasPrevious[i]) chain(i);
  }
  // What is left is rings, every line of them with a previous one.
  for (var i = 0; i < n; i++) {
    if (!done[i]) chain(i);
  }
  final b = cell.barriers;
  for (var i = 0; i + 2 < b.length; i += 3) {
    out.addBarrier(b[i], b[i + 1], b[i + 2]);
  }
  out.addClimbsOf(cell);
  return out.build();
}
