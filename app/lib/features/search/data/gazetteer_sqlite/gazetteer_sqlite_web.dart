// The web side of a conditional import: what uses it is the same import
// on the phone side, which is the side dart_code_linter follows.
// ignore_for_file: unused-code

import 'package:sqlite3/wasm.dart';

import 'files_vfs.dart';

WasmSqlite3? _sqlite;
Future<void>? _loading;

/// Loads `sqlite3.wasm` (served beside `index.html`) once, and registers the
/// file system that reads the downloaded gazetteers where the tile
/// downloader put them.
Future<void> prepareGazetteerSqlite() => _loading ??= () async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  sqlite.registerVirtualFileSystem(FilesVfs(), makeDefault: true);
  _sqlite = sqlite;
}();

/// Opens the gazetteer at [path] read-only; [prepareGazetteerSqlite] must
/// have finished.
CommonDatabase openGazetteerFile(String path) {
  final sqlite = _sqlite;
  if (sqlite == null) {
    throw StateError('prepareGazetteerSqlite() has not finished');
  }
  return sqlite.open(path, vfs: filesVfsName, mode: OpenMode.readOnly);
}
