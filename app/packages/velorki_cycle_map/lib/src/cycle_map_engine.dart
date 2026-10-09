import 'dart:io';
import 'dart:math' as math;

import 'cell_store.dart';
import 'cell_ways.dart';
import 'geojson_writer.dart';
import 'merge.dart';
import 'rd5_cell_reader.dart';

/// The area and the content to draw.
final class CycleMapRequest {
  /// A request for the box [south]..[north], [west]..[east] at [zoom].
  const CycleMapRequest({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.zoom,
    this.wanted = CycleContent.all,
    this.maxChars = 3000000,
  });

  /// The box, in degrees.
  final double south, west, north, east;

  /// The map's zoom; lines are simplified for it.
  final double zoom;

  /// [CycleContent] bits.
  final int wanted;

  /// The most characters of GeoJSON to make: cells nearest the middle of
  /// the box come first, and the ones that do not fit are left out.
  final int maxChars;
}

/// The cycle map for a [CycleMapRequest].
final class CycleMapResult {
  /// Creates a result.
  const CycleMapResult({
    required this.geojson,
    required this.cells,
    required this.cellsWithoutTile,
    required this.truncated,
    required this.decodedCells,
  });

  /// A GeoJSON feature collection.
  final String geojson;

  /// How many cells the box covers.
  final int cells;

  /// How many of them have no downloaded tile.
  final int cellsWithoutTile;

  /// Whether cells were left out to keep to the request's size.
  final bool truncated;

  /// How many cells had to be decoded from their tile for this result.
  final int decodedCells;
}

/// Makes the cycle map for an area out of the rd5 tiles in [segmentsDir],
/// with three caches in front of the tile:
///
/// * the features of a cell as GeoJSON, per zoom and content, in memory:
///   panning back and forth only joins strings;
/// * the decoded cells in memory, up to [memoryBudgetBytes];
/// * the decoded cells on disk ([CellStore]), when a [cacheDir] is given,
///   for the next start of the app.
///
/// Not thread-safe; it lives in one isolate (see `CycleMapWorker`).
final class CycleMapEngine {
  /// An engine over the tiles in [segmentsDir].
  CycleMapEngine({
    required this.reader,
    required this.segmentsDir,
    Directory? cacheDir,
    this.memoryBudgetBytes = 32 << 20,
    this.fragmentBudgetChars = 12 << 20,
  }) : _store = cacheDir == null ? null : CellStore(cacheDir);

  /// Reads cells out of tiles.
  final Rd5CellReader reader;

  /// The directory holding the `.rd5` tiles.
  final Directory segmentsDir;

  /// The most bytes of decoded cells kept in memory.
  final int memoryBudgetBytes;

  /// The most characters of GeoJSON pieces kept in memory.
  final int fragmentBudgetChars;

  final CellStore? _store;
  final _writer = GeoJsonWriter();
  final _tiles = <String, _OpenTile?>{};
  final _cells = <(String, int, int), CellWays>{};
  final _fragments = <(String, int, int, int, int), String>{};
  int _cellBytes = 0;
  int _fragmentChars = 0;

  /// Forgets what it knows about the tiles: call after one was downloaded,
  /// updated or deleted. Cells of tiles that did not change stay cached.
  void tilesChanged() {
    for (final entry in _tiles.entries.toList()) {
      final tile = entry.value;
      final file = File('${segmentsDir.path}/${entry.key}.rd5');
      final stat = file.statSync();
      final key = stat.type == FileSystemEntityType.notFound
          ? null
          : CellStore.versionKey(entry.key, stat);
      if (key != tile?.versionKey) {
        tile?.rd5.close();
        _tiles.remove(entry.key);
      }
    }
    final current = <String?>{
      for (final tile in _tiles.values) ...[
        tile?.versionKey,
        if (tile != null) '${tile.versionKey}_climbs',
      ],
    };
    _cells.removeWhere((k, v) {
      final gone = !current.contains(k.$1);
      if (gone) _cellBytes -= v.byteSize;
      return gone;
    });
    _fragments.removeWhere((k, v) {
      final gone = !current.contains(k.$1);
      if (gone) _fragmentChars -= v.length;
      return gone;
    });
  }

  /// Deletes the stored cells of tiles that are no longer on the phone or
  /// have changed.
  void pruneStore() {
    final store = _store;
    if (store == null || !segmentsDir.existsSync()) return;
    final current = <String>{};
    for (final entry in segmentsDir.listSync()) {
      final name = entry.uri.pathSegments.last;
      if (entry is File && name.endsWith('.rd5')) {
        final version = CellStore.versionKey(
          name.substring(0, name.length - 4),
          entry.statSync(),
        );
        current
          ..add(version)
          ..add('${version}_climbs');
      }
    }
    store.prune(current);
  }

  /// Closes the open tiles.
  void close() {
    for (final tile in _tiles.values) {
      tile?.rd5.close();
    }
    _tiles.clear();
  }

  /// The cycle map for [request].
  CycleMapResult render(CycleMapRequest request) {
    const cellsPerDegree = 32;
    int index(double deg, double offset) =>
        ((deg + offset) * cellsPerDegree).floor();
    final x0 = index(request.west, 180);
    final x1 = index(request.east, 180);
    final y0 = index(request.south, 90);
    final y1 = index(request.north, 90);
    final zoom = request.zoom.floor().clamp(0, 16);

    // Nearest the middle first, so a cut leaves the edges out.
    final cx = (x0 + x1) / 2;
    final cy = (y0 + y1) / 2;
    final order =
        <(int, int)>[
          for (var x = x0; x <= x1; x++)
            for (var y = y0; y <= y1; y++) (x, y),
        ]..sort((a, b) {
          final da = math.pow(a.$1 - cx, 2) + math.pow(a.$2 - cy, 2);
          final db = math.pow(b.$1 - cx, 2) + math.pow(b.$2 - cy, 2);
          return da.compareTo(db);
        });

    final pieces = <String>[];
    var chars = 0;
    var withoutTile = 0;
    var decoded = 0;
    var truncated = false;
    for (final (x, y) in order) {
      final tile = _tileFor(x ~/ cellsPerDegree, y ~/ cellsPerDegree);
      if (tile == null) {
        withoutTile++;
        continue;
      }
      if (truncated) continue;
      final fragmentKey = (tile.versionKey, x, y, zoom, request.wanted);
      var piece = _fragments.remove(fragmentKey);
      if (piece == null) {
        final (cell, fresh) = _cell(
          tile,
          x,
          y,
          climbs: request.wanted & CycleContent.climbs != 0,
        );
        if (fresh) decoded++;
        piece = _writer.cellFeatures(cell, request.wanted, zoom);
        _fragmentChars += piece.length;
      }
      _fragments[fragmentKey] = piece;
      // The middle cell is drawn whatever its size: a cut that leaves
      // nothing would look like a map without cycle ways.
      if (pieces.isNotEmpty && chars + piece.length > request.maxChars) {
        truncated = true;
        continue;
      }
      chars += piece.length + 1;
      pieces.add(piece);
    }
    _evict();
    return CycleMapResult(
      geojson: GeoJsonWriter.collection(pieces),
      cells: order.length,
      cellsWithoutTile: withoutTile,
      truncated: truncated,
      decodedCells: decoded,
    );
  }

  /// The cell at [x], [y], with its climbs when [climbs]: finding them
  /// takes as long again as the rest, so a cell is kept twice, without and
  /// with, and the second only made when the climbs are on.
  (CellWays, bool) _cell(_OpenTile tile, int x, int y, {required bool climbs}) {
    final version = climbs ? '${tile.versionKey}_climbs' : tile.versionKey;
    final key = (version, x, y);
    final cached = _cells.remove(key);
    if (cached != null) {
      _cells[key] = cached;
      return (cached, false);
    }
    var fresh = false;
    var cell = _store?.read(version, x, y);
    if (cell == null) {
      cell = mergeLines(reader.readCell(tile.rd5, x, y, climbs: climbs));
      _store?.write(version, x, y, cell);
      fresh = true;
    }
    _cells[key] = cell;
    _cellBytes += cell.byteSize;
    return (cell, fresh);
  }

  void _evict() {
    while (_cellBytes > memoryBudgetBytes && _cells.isNotEmpty) {
      final first = _cells.keys.first;
      _cellBytes -= _cells.remove(first)!.byteSize;
    }
    while (_fragmentChars > fragmentBudgetChars && _fragments.isNotEmpty) {
      final first = _fragments.keys.first;
      _fragmentChars -= _fragments.remove(first)!.length;
    }
  }

  /// The open tile holding the degree square at [lonDeg], [latDeg]
  /// (counted from 180° W and 90° S), or null when it is not downloaded.
  _OpenTile? _tileFor(int lonDeg, int latDeg) {
    final lon0 = ((lonDeg - 180) / 5).floor() * 5;
    final lat0 = ((latDeg - 90) / 5).floor() * 5;
    final name =
        '${lon0 < 0 ? 'W' : 'E'}${lon0.abs()}_${lat0 < 0 ? 'S' : 'N'}${lat0.abs()}';
    if (_tiles.containsKey(name)) return _tiles[name];
    final file = File('${segmentsDir.path}/$name.rd5');
    final stat = file.statSync();
    _OpenTile? tile;
    if (stat.type == FileSystemEntityType.file) {
      try {
        tile = _OpenTile(reader.open(file), CellStore.versionKey(name, stat));
      } on Object {
        // A tile that cannot be read is no tile; tilesChanged retries.
        tile = null;
      }
    }
    return _tiles[name] = tile;
  }
}

final class _OpenTile {
  _OpenTile(this.rd5, this.versionKey);

  final Rd5Tile rd5;
  final String versionKey;
}
