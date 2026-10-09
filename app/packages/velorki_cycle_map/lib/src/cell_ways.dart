import 'dart:typed_data';

/// One cell of the cycle map: lines with their attributes and barrier
/// points, in BRouter's integer coordinates (micro-degrees, longitude plus
/// 180 and latitude plus 90), packed into typed lists so a cell is cheap to
/// keep and to send between isolates.
final class CellWays {
  /// Creates a cell from its packed lists.
  CellWays({
    required this.coords,
    required this.starts,
    required this.attrs,
    required this.barriers,
  }) : assert(starts.length == attrs.length + 1);

  /// A cell with nothing in it.
  CellWays.empty()
    : coords = Int32List(0),
      starts = Int32List(1),
      attrs = Int32List(0),
      barriers = Int32List(0);

  /// The lines' points, longitude and latitude in turn.
  final Int32List coords;

  /// Where each line starts in [coords], counted in points, and one more
  /// entry for the end of the last line.
  final Int32List starts;

  /// Each line's attribute bits (see `CycleAttrs`).
  final Int32List attrs;

  /// Barrier points: longitude, latitude and class in turn.
  final Int32List barriers;

  /// How many lines there are.
  int get lineCount => attrs.length;

  /// How many points the lines have together.
  int get pointCount => coords.length >> 1;

  /// How many barriers there are.
  int get barrierCount => barriers.length ~/ 3;

  /// The bytes the lists take, for the cache's budget.
  int get byteSize =>
      (coords.length + starts.length + attrs.length + barriers.length) * 4;
}

/// Collects lines and barriers into a [CellWays].
final class CellWaysBuilder {
  final _coords = _IntBuffer();
  final _starts = _IntBuffer()..add(0);
  final _attrs = _IntBuffer();
  final _barriers = _IntBuffer();

  /// Adds a line through the points in [coords] (longitude and latitude in
  /// turn, from [from] to [to], exclusive).
  void addLine(List<int> coords, int attrs, [int from = 0, int? to]) {
    final end = to ?? coords.length;
    for (var i = from; i < end; i++) {
      _coords.add(coords[i]);
    }
    _starts.add(_coords.length >> 1);
    _attrs.add(attrs);
  }

  /// Adds a barrier.
  void addBarrier(int lon, int lat, int barrierClass) {
    _barriers
      ..add(lon)
      ..add(lat)
      ..add(barrierClass);
  }

  /// The cell.
  CellWays build() => CellWays(
    coords: _coords.toList(),
    starts: _starts.toList(),
    attrs: _attrs.toList(),
    barriers: _barriers.toList(),
  );
}

final class _IntBuffer {
  var _data = Int32List(64);
  int length = 0;

  void add(int v) {
    if (length == _data.length) {
      final grown = Int32List(_data.length * 2)..setAll(0, _data);
      _data = grown;
    }
    _data[length++] = v;
  }

  Int32List toList() =>
      Int32List.fromList(Int32List.sublistView(_data, 0, length));
}
