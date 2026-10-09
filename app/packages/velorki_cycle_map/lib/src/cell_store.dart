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
  static const int formatVersion = 3;

  static const int _lists = 7;

  static const int _magic = 0x56434d32; // VCM2

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
    if (bytes.length < 32 || bytes.length % 4 != 0) return null;
    final ints = bytes.buffer.asInt32List(
      bytes.offsetInBytes,
      bytes.length >> 2,
    );
    if (ints[0] != _magic) return null;
    final n = List<int>.generate(_lists, (i) => ints[1 + i]);
    if (n.any((v) => v < 0) ||
        n[1] != n[2] + 1 ||
        n[5] != n[6] + 1 ||
        1 + _lists + n.fold<int>(0, (a, b) => a + b) != ints.length) {
      return null;
    }
    var at = 1 + _lists;
    Int32List take(int n) =>
        Int32List.fromList(Int32List.sublistView(ints, at, at += n));
    return CellWays(
      coords: take(n[0]),
      starts: take(n[1]),
      attrs: take(n[2]),
      barriers: take(n[3]),
      climbCoords: take(n[4]),
      climbStarts: take(n[5]),
      climbGrades: take(n[6]),
    );
  }

  /// Stores [cell]; a failure to write only means it is decoded again.
  void write(String versionKey, int lonIdx, int latIdx, CellWays cell) {
    final lists = [
      cell.coords,
      cell.starts,
      cell.attrs,
      cell.barriers,
      cell.climbCoords,
      cell.climbStarts,
      cell.climbGrades,
    ];
    final ints = Int32List(
      1 + _lists + lists.fold<int>(0, (a, l) => a + l.length),
    )..[0] = _magic;
    for (var i = 0; i < _lists; i++) {
      ints[1 + i] = lists[i].length;
    }
    var at = 1 + _lists;
    for (final list in lists) {
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
