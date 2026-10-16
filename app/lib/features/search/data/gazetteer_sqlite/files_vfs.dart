import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:velorki_io/io.dart';

/// The name [FilesVfs] registers under by default.
const String filesVfsName = 'velorki-files';

/// The files of `package:velorki_io` as SQLite sees them: read in place, no
/// copy of a tens-of-megabytes index. Whatever SQLite creates for itself
/// (a temporary file for a sort) stays in a map of its own.
final class FilesVfs extends BaseVirtualFileSystem {
  /// Creates the file system; SQLite knows it by [name].
  FilesVfs({super.name = filesVfsName});

  final Map<String, Uint8List> _scratch = <String, Uint8List>{};
  int _next = 0;

  @override
  int xAccess(String path, int flags) =>
      _scratch.containsKey(path) || File(path).existsSync() ? 1 : 0;

  @override
  void xDelete(String path, int syncDir) => _scratch.remove(path);

  @override
  String xFullPathName(String path) => File(path).absolute.path;

  @override
  XOpenResult xOpen(Sqlite3Filename path, int flags) {
    final name = path.path;
    if (name != null && File(name).existsSync()) {
      return (outFlags: 0, file: _ReadOnlyFile(File(name).openSync()));
    }
    if (flags & SqlFlag.SQLITE_OPEN_CREATE == 0) {
      throw VfsException(SqlError.SQLITE_CANTOPEN);
    }
    final key = name ?? '/.scratch-${_next++}';
    _scratch.putIfAbsent(key, () => Uint8List(0));
    return (outFlags: 0, file: _ScratchFile(this, key));
  }

  @override
  void xSleep(Duration duration) {}
}

class _ReadOnlyFile extends BaseVfsFile {
  _ReadOnlyFile(this._file) : _length = _file.lengthSync();

  final RandomAccessFile _file;
  final int _length;

  @override
  int readInto(Uint8List buffer, int offset) {
    if (offset >= _length) return 0;
    _file.setPositionSync(offset);
    return _file.readIntoSync(buffer, 0, min(buffer.length, _length - offset));
  }

  @override
  int xCheckReservedLock() => 0;

  @override
  void xClose() => _file.closeSync();

  @override
  int xFileSize() => _length;

  @override
  void xLock(int mode) {}

  @override
  void xSync(int flags) {}

  @override
  void xTruncate(int size) => throw VfsException(SqlError.SQLITE_READONLY);

  @override
  void xUnlock(int mode) {}

  @override
  void xWrite(Uint8List buffer, int fileOffset) =>
      throw VfsException(SqlError.SQLITE_READONLY);
}

class _ScratchFile extends BaseVfsFile {
  _ScratchFile(this._vfs, this._key);

  final FilesVfs _vfs;
  final String _key;

  Uint8List get _bytes => _vfs._scratch[_key] ?? Uint8List(0);

  @override
  int readInto(Uint8List buffer, int offset) {
    final bytes = _bytes;
    if (offset >= bytes.length) return 0;
    final n = min(buffer.length, bytes.length - offset);
    buffer.setRange(0, n, bytes, offset);
    return n;
  }

  @override
  int xCheckReservedLock() => 0;

  @override
  void xClose() => _vfs._scratch.remove(_key);

  @override
  int xFileSize() => _bytes.length;

  @override
  void xLock(int mode) {}

  @override
  void xSync(int flags) {}

  @override
  void xTruncate(int size) {
    final old = _bytes;
    _vfs._scratch[_key] = Uint8List(size)
      ..setRange(0, min(size, old.length), old);
  }

  @override
  void xUnlock(int mode) {}

  @override
  void xWrite(Uint8List buffer, int fileOffset) {
    var bytes = _bytes;
    final end = fileOffset + buffer.length;
    if (end > bytes.length) {
      bytes = Uint8List(end)..setRange(0, bytes.length, bytes);
      _vfs._scratch[_key] = bytes;
    }
    bytes.setRange(fileOffset, end, buffer);
  }
}
