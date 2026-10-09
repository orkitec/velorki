import 'dart:io';
import 'dart:typed_data';

import 'cell_ways.dart';

/// Decoded cells on disk, so an area seen once draws at once the next time
/// the app starts, without decoding its tile again.
///
/// One file per cell, under a directory per tile *version* (its name, size
/// and modification time) and per [formatVersion]: a tile that is updated
/// or a classification that changes simply lands in a new directory, and
/// [prune] deletes the ones no longer current.
final class CellStore {
  /// A store under [root].
  CellStore(this.root);

  /// Bump when the classification or the file layout changes.
  static const int formatVersion = 1;

  static const int _magic = 0x56434d31; // VCM1

  /// The directory holding the stores' directories.
  final Directory root;

  /// The directory name for a tile version.
  static String versionKey(String tileName, FileStat stat) =>
      'v${formatVersion}_${tileName}_${stat.size}_'
      '${stat.modified.millisecondsSinceEpoch}';

  File _file(String versionKey, int lonIdx, int latIdx) =>
      File('${root.path}/$versionKey/${lonIdx}_$latIdx.bin');

  /// The stored cell, or null when there is none or it cannot be read.
  CellWays? read(String versionKey, int lonIdx, int latIdx) {
    final file = _file(versionKey, lonIdx, latIdx);
    final Uint8List bytes;
    try {
      bytes = file.readAsBytesSync();
    } on FileSystemException {
      return null;
    }
    if (bytes.length < 20 || bytes.length % 4 != 0) return null;
    final ints = bytes.buffer.asInt32List(
      bytes.offsetInBytes,
      bytes.length >> 2,
    );
    if (ints[0] != _magic) return null;
    final nCoords = ints[1];
    final nStarts = ints[2];
    final nAttrs = ints[3];
    final nBarriers = ints[4];
    if (nCoords < 0 ||
        nStarts != nAttrs + 1 ||
        nBarriers < 0 ||
        5 + nCoords + nStarts + nAttrs + nBarriers != ints.length) {
      return null;
    }
    var at = 5;
    Int32List take(int n) =>
        Int32List.fromList(Int32List.sublistView(ints, at, at += n));
    return CellWays(
      coords: take(nCoords),
      starts: take(nStarts),
      attrs: take(nAttrs),
      barriers: take(nBarriers),
    );
  }

  /// Stores [cell]; a failure to write only means it is decoded again.
  void write(String versionKey, int lonIdx, int latIdx, CellWays cell) {
    final ints = Int32List(
      5 +
          cell.coords.length +
          cell.starts.length +
          cell.attrs.length +
          cell.barriers.length,
    );
    ints
      ..[0] = _magic
      ..[1] = cell.coords.length
      ..[2] = cell.starts.length
      ..[3] = cell.attrs.length
      ..[4] = cell.barriers.length;
    var at = 5;
    for (final list in [cell.coords, cell.starts, cell.attrs, cell.barriers]) {
      ints.setAll(at, list);
      at += list.length;
    }
    final file = _file(versionKey, lonIdx, latIdx);
    // Written aside and renamed, so a reader never sees half a cell.
    final part = File('${file.path}.part');
    try {
      file.parent.createSync(recursive: true);
      part.writeAsBytesSync(ints.buffer.asUint8List(), flush: false);
      part.renameSync(file.path);
    } on FileSystemException {
      try {
        part.deleteSync();
      } on FileSystemException {
        // Nothing to clean up.
      }
    }
  }

  /// Deletes every tile directory not in [current].
  void prune(Set<String> current) {
    if (!root.existsSync()) return;
    for (final entry in root.listSync()) {
      if (entry is Directory &&
          !current.contains(
            entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
          )) {
        try {
          entry.deleteSync(recursive: true);
        } on FileSystemException {
          // Tried again on the next prune.
        }
      }
    }
  }
}
