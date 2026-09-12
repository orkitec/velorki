// Not upstream: the byte-level cache of track R5.

import 'dart:collection';
import 'dart:typed_data';

/// An LRU of still-encoded micro-cache cells (the bytes `OsmFile`
/// `getDataInputForSubIdx` reads from the rd5), bounded by [maxBytes].
///
/// Upstream re-reads and re-decodes every cell for every `NodesCache` reset
/// (each `findTrack` pass of a route starts with a fresh node graph) and
/// caches nothing at the byte level; with direct weaving the decoded
/// `MicroCache` stays empty, so this is the only cache in front of the file.
/// A hit copies the cell into the decoder's io buffer instead of `seek` +
/// `read`; the decoding itself is unchanged, so the result is byte-identical.
///
/// One instance per `BRouter` (per worker isolate); `BRouter.routeQuery`
/// clears it after every route unless told to retain it.
class RawCellCache {
  RawCellCache({this.maxBytes = defaultMaxBytes});

  /// The plan's ~16 MB.
  static const int defaultMaxBytes = 16 * 1024 * 1024;

  final int maxBytes;

  final LinkedHashMap<int, Uint8List> _cells = LinkedHashMap<int, Uint8List>();
  final Map<String, int> _fileIds = <String, int>{};

  int _bytes = 0;

  /// Bytes currently held.
  int get bytes => _bytes;

  /// Cells currently held.
  int get length => _cells.length;

  int hits = 0;
  int misses = 0;

  /// A small id per rd5 file name, so a cell key is `fileId << 40 | position`.
  int fileId(String fileName) =>
      _fileIds.putIfAbsent(fileName, () => _fileIds.length);

  static int key(int fileId, int position) => (fileId << 40) | position;

  /// Copies the cached cell into [target] and returns true, or returns false
  /// (and counts a miss) when it is not cached.
  bool copyInto(int key, Uint8List target, int size) {
    final cell = _cells.remove(key);
    if (cell == null) {
      misses++;
      return false;
    }
    _cells[key] = cell; // most recently used
    if (cell.length != size) {
      // cannot happen for an unchanged file; treat as a miss
      _bytes -= cell.length;
      _cells.remove(key);
      misses++;
      return false;
    }
    target.setRange(0, size, cell);
    hits++;
    return true;
  }

  /// Stores a copy of `source[0..size)` under [key], evicting the least
  /// recently used cells until it fits; cells larger than [maxBytes] are not
  /// cached.
  void put(int key, Uint8List source, int size) {
    if (size > maxBytes) return;
    final old = _cells.remove(key);
    if (old != null) _bytes -= old.length;
    while (_bytes + size > maxBytes && _cells.isNotEmpty) {
      final lru = _cells.keys.first;
      _bytes -= _cells.remove(lru)!.length;
    }
    final copy = Uint8List(size);
    copy.setRange(0, size, source);
    _cells[key] = copy;
    _bytes += size;
  }

  /// Drops every cell (the file ids are kept).
  void clear() {
    _cells.clear();
    _bytes = 0;
  }

  String formatStatus() =>
      'rawCache cells=${_cells.length} bytes=$_bytes hits=$hits misses=$misses';
}
