import 'dart:io';
import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';

import 'cell_ways.dart';
import 'cycle_attrs.dart';

/// Reads the cycle map's lines and barriers out of BRouter's rd5 tiles, one
/// cell (a 1/32 degree square) at a time.
///
/// Every link of the routing graph is stored once in the forward direction,
/// in the cell of the node it starts at, with its way's tags and the points
/// between its ends; the reverse copies carry neither and are skipped. So
/// the lines of a cell are exactly the links starting in it, and the cells
/// of an area together hold each link once.
///
/// Tags are decoded once per distinct way description: a cell has
/// thousands of links but a tile only a few thousand descriptions.
final class Rd5CellReader {
  /// Creates a reader for tiles built against the lookup table in
  /// [lookupsLines] (`lookups.dat`, line by line).
  Rd5CellReader(Iterable<String> lookupsLines) {
    final meta = BExpressionMetaData();
    _way = BExpressionContextWay(meta);
    _node = BExpressionContextNode(meta);
    meta.readMetaDataLines(lookupsLines);
    _way.finishMetaParsing();
    _node.finishMetaParsing();
  }

  late final BExpressionContextWay _way;
  late final BExpressionContextNode _node;
  final _wayAttrs = _DescriptionTable();
  final _nodeClasses = _DescriptionTable();
  final _buffers = DataBuffers();

  /// How many distinct way descriptions were classified so far.
  int get descriptionCount => _wayAttrs.length;

  /// Opens a tile for reading; close it with [Rd5Tile.close].
  Rd5Tile open(File file) => Rd5Tile._(PhysicalFile(file, _buffers, -1, -1));

  /// Cells per degree in [tile]: 32 for current tiles.
  int divisor(Rd5Tile tile) => tile._file.divisor;

  /// The lines and barriers of the cell at [lonIdx], [latIdx] (counted in
  /// cells from 180° W and 90° S) out of [tile], which must hold it.
  ///
  /// [keep] says which lines to keep by their attribute bits; by default
  /// everything with something to draw.
  CellWays readCell(
    Rd5Tile tile,
    int lonIdx,
    int latIdx, {
    bool Function(int attrs)? keep,
  }) {
    final div = tile._file.divisor;
    final lonDeg = lonIdx ~/ div;
    final latDeg = latIdx ~/ div;
    final osm = tile._degrees.putIfAbsent(
      lonDeg * 1000 + latDeg,
      () => OsmFile(tile._file, lonDeg, latDeg, _buffers),
    );
    if (!osm.hasData()) return CellWays.empty();
    final mc = osm.createMicroCacheForIdx(
      lonIdx,
      latIdx,
      _buffers,
      null,
      null,
      true,
      null,
    );
    if (mc is! MicroCache2) return CellWays.empty();

    final out = CellWaysBuilder();
    final line = <int>[];
    final size = mc.getSize();
    for (var i = 0; i < size; i++) {
      final id = mc.getIdForIndex(i);
      if (!mc.getAndClear(id)) continue;
      final ilon = id >> 32;
      final ilat = id & 0xffffffff;
      // Turn restrictions, then the elevation: not for drawing.
      while (mc.readBoolean()) {
        mc
          ..readShort()
          ..readBoolean()
          ..readInt()
          ..readInt()
          ..readInt()
          ..readInt();
      }
      mc.readShort();
      final nodeDescSize = mc.readVarLengthUnsigned();
      if (nodeDescSize > 0) {
        final desc = Uint8List.sublistView(
          mc.ab,
          mc.aboffset,
          mc.aboffset + nodeDescSize,
        );
        mc.aboffset += nodeDescSize;
        final barrier = _nodeClass(desc);
        if (barrier != 0) out.addBarrier(ilon, ilat, barrier);
      }
      while (mc.hasMoreData()) {
        final end = mc.getEndPointer();
        final tlon = ilon + mc.readVarLengthSigned();
        final tlat = ilat + mc.readVarLengthSigned();
        final sizecode = mc.readVarLengthUnsigned();
        final descSize = sizecode >> 1;
        if ((sizecode & 1) != 0 || descSize == 0) {
          mc.aboffset = end;
          continue;
        }
        final desc = Uint8List.sublistView(
          mc.ab,
          mc.aboffset,
          mc.aboffset + descSize,
        );
        mc.aboffset += descSize;
        final attrs = _wayAttrsOf(desc);
        if (attrs == 0 || keep != null && !keep(attrs)) {
          mc.aboffset = end;
          continue;
        }
        line
          ..clear()
          ..add(ilon)
          ..add(ilat);
        var olon = ilon;
        var olat = ilat;
        while (mc.aboffset < end) {
          olon += mc.readVarLengthSigned();
          olat += mc.readVarLengthSigned();
          mc.readVarLengthSigned(); // elevation
          line
            ..add(olon)
            ..add(olat);
        }
        line
          ..add(tlon)
          ..add(tlat);
        out.addLine(line, attrs);
      }
    }
    return out.build();
  }

  int _wayAttrsOf(Uint8List desc) =>
      _wayAttrs.lookup(desc) ??
      _wayAttrs.put(
        desc,
        classifyWay(_tags(_way.getKeyValueList(false, desc))),
      );

  int _nodeClass(Uint8List desc) =>
      _nodeClasses.lookup(desc) ??
      _nodeClasses.put(
        desc,
        classifyNode(_tags(_node.getKeyValueList(false, desc))),
      );

  static Map<String, String> _tags(List<String> keyValues) => {
    for (var i = 0; i + 1 < keyValues.length; i += 2)
      keyValues[i]: keyValues[i + 1],
  };
}

/// An open rd5 tile.
final class Rd5Tile {
  Rd5Tile._(this._file);

  final PhysicalFile _file;
  final _degrees = <int, OsmFile>{};

  /// Closes the file.
  void close() {
    _file.ra?.closeSync();
  }
}

/// Classified descriptions by their bytes, without making a key object per
/// lookup: a link's description is a view into the cell's buffer, and
/// most links repeat one seen before.
final class _DescriptionTable {
  final _buckets = <int, List<(Uint8List, int)>>{};

  int get length => _count;
  int _count = 0;

  static int _hash(Uint8List b) {
    var h = 0x811c9dc5;
    for (var i = 0; i < b.length; i++) {
      h = ((h ^ b[i]) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  int? lookup(Uint8List desc) {
    final bucket = _buckets[_hash(desc)];
    if (bucket == null) return null;
    outer:
    for (final (bytes, value) in bucket) {
      if (bytes.length != desc.length) continue;
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] != desc[i]) continue outer;
      }
      return value;
    }
    return null;
  }

  int put(Uint8List desc, int value) {
    (_buckets[_hash(desc)] ??= []).add((Uint8List.fromList(desc), value));
    _count++;
    return value;
  }
}
