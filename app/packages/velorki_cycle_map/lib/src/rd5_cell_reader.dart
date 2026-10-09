import 'dart:io';
import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';

import 'cell_ways.dart';
import 'climbs.dart';
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
  ///
  /// With [climbs], the steep pieces of every way a bike may use are found
  /// as well, from the heights the tile keeps for every point. Off by
  /// default: in cities the tiles' heights include the buildings, and a
  /// block-long stretch shows climbs on flat streets.
  CellWays readCell(
    Rd5Tile tile,
    int lonIdx,
    int latIdx, {
    bool Function(int attrs)? keep,
    bool climbs = false,
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
    final heights = <int>[];
    final nodeHeights = <int, int>{};
    // Links to find the climbs of once every node's height is known (the
    // last point's is its target node's), and which way each is.
    final pending = <(List<int>, List<int>, int, int)>[];
    final size = mc.getSize();
    for (var i = 0; i < size; i++) {
      final id = mc.getIdForIndex(i);
      if (!mc.getAndClear(id)) continue;
      final ilon = id >> 32;
      final ilat = id & 0xffffffff;
      // Turn restrictions are not for drawing.
      while (mc.readBoolean()) {
        mc
          ..readShort()
          ..readBoolean()
          ..readInt()
          ..readInt()
          ..readInt()
          ..readInt();
      }
      final selev = mc.readShort();
      nodeHeights[id] = selev;
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
        final value = _wayValueOf(desc);
        final attrs = value & 0xffffffff;
        final drawn = attrs != 0 && (keep == null || keep(attrs));
        final climbable = climbs && value & _climbable != 0;
        if (!drawn && !climbable) {
          mc.aboffset = end;
          continue;
        }
        line
          ..clear()
          ..add(ilon)
          ..add(ilat);
        heights
          ..clear()
          ..add(selev);
        var olon = ilon;
        var olat = ilat;
        var oelev = selev;
        while (mc.aboffset < end) {
          olon += mc.readVarLengthSigned();
          olat += mc.readVarLengthSigned();
          oelev = _short(oelev + mc.readVarLengthSigned());
          line
            ..add(olon)
            ..add(olat);
          heights.add(oelev);
        }
        line
          ..add(tlon)
          ..add(tlat);
        if (drawn) out.addLine(line, attrs);
        if (climbable && selev != _noHeight) {
          pending.add((
            List<int>.of(line),
            List<int>.of(heights),
            tlon << 32 | tlat,
            value >> 33,
          ));
        }
      }
    }
    _findClimbs(pending, nodeHeights, out);
    return out.build();
  }

  /// The climbs of the links in [pending], joined into whole streets first:
  /// a link ends where the next of the same way starts, and a slope taken
  /// over a block has the buildings' noise in it, over a street much less.
  void _findClimbs(
    List<(List<int>, List<int>, int, int)> pending,
    Map<int, int> nodeHeights,
    CellWaysBuilder out,
  ) {
    final links = <(List<int>, List<int>)>[];
    final starts = <int>[];
    final ends = <int>[];
    final ways = <int>[];
    for (final (coords, elevations, target, way) in pending) {
      final last = nodeHeights[target];
      if (last != null && last != _noHeight) {
        elevations.add(last);
      } else {
        // The target is in another cell: the link ends at its last point
        // with a height.
        coords.length -= 2;
      }
      if (coords.length < 4 || elevations.contains(_noHeight)) continue;
      links.add((coords, elevations));
      starts.add(coords[0] << 32 | coords[1]);
      ends.add(coords[coords.length - 2] << 32 | coords[coords.length - 1]);
      ways.add(way);
    }
    // Join a link to the one starting where it ends, of the same way, when
    // that is the only one there either way.
    final byStart = <(int, int), int>{};
    final byEnd = <(int, int), int>{};
    for (var i = 0; i < links.length; i++) {
      final s = (starts[i], ways[i]);
      byStart[s] = byStart.containsKey(s) ? -1 : i;
      final e = (ends[i], ways[i]);
      byEnd[e] = byEnd.containsKey(e) ? -1 : i;
    }
    final next = List<int>.filled(links.length, -1);
    final hasPrevious = List<bool>.filled(links.length, false);
    for (var i = 0; i < links.length; i++) {
      final at = (ends[i], ways[i]);
      if (byEnd[at] != i) continue;
      final j = byStart[at];
      if (j == null || j < 0 || j == i) continue;
      next[i] = j;
      hasPrevious[j] = true;
    }
    final done = List<bool>.filled(links.length, false);
    void chain(int head) {
      final coords = <int>[];
      final elevations = <int>[];
      for (var i = head; i >= 0 && !done[i]; i = next[i]) {
        done[i] = true;
        final (c, e) = links[i];
        final skip = coords.isEmpty ? 0 : 1; // the joint is the same point
        coords.addAll(c.skip(skip * 2));
        elevations.addAll(e.skip(skip));
      }
      findClimbs(coords, elevations, out.addClimb, rule: climbRule);
    }

    for (var i = 0; i < links.length; i++) {
      if (!hasPrevious[i]) chain(i);
    }
    for (var i = 0; i < links.length; i++) {
      if (!done[i]) chain(i);
    }
  }

  /// A way's attribute bits in the low 32 bits, [_climbable], and from bit
  /// 33 on the number of its description, which tells links of one way.
  int _wayValueOf(Uint8List desc) {
    final known = _wayAttrs.lookup(desc);
    if (known != null) return known;
    final tags = _tags(_way.getKeyValueList(false, desc));
    return _wayAttrs.put(
      desc,
      classifyWay(tags) & 0xffffffff |
          (isClimbable(tags) ? _climbable : 0) |
          _wayAttrs.length << 33,
    );
  }

  static const int _climbable = 1 << 32;

  /// How the climbs are found.
  ClimbRule climbRule = ClimbRule.standard;

  /// BRouter's height for "none known".
  static const int _noHeight = -32768;

  /// [v] as Java's short: the heights are kept in 16 bits.
  static int _short(int v) => ((v + 32768) & 0xffff) - 32768;

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
