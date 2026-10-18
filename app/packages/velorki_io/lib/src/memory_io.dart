// The part of dart:io Velorki uses, over a map of paths to bytes. The names
// and signatures are dart:io's, so code written against dart:io compiles
// against this unchanged; what it does is what dart:io does on a POSIX file
// system, minus links, permissions and concurrency between processes.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZLibDecoderWeb, ZLibEncoderWeb;
import 'package:path/path.dart' as p;

final p.Context _posix = p.Context(style: p.Style.posix, current: '/');

/// The files and directories behind [File] and [Directory] in the browser.
///
/// Everything lives in memory for as long as the page does. A persistent
/// store keeps a copy by listening to [onChange] and puts it back with
/// [seed] before the app reads anything.
abstract final class MemoryFileSystem {
  static final Map<String, Uint8List> _files = <String, Uint8List>{};
  static final Map<String, DateTime> _modified = <String, DateTime>{};
  static final Map<String, DateTime> _accessed = <String, DateTime>{};
  static final Set<String> _dirs = <String>{'/'};

  /// Told about every file written ([bytes] its whole content) or deleted
  /// ([bytes] `null`), after the change.
  static void Function(String path, Uint8List? bytes)? onChange;

  /// Makes the buffer a file written in parts (an [IOSink], an append, a
  /// [RandomAccessFile]) is put together in. A browser sets it to bytes
  /// held by JavaScript, as a download's arrive: copying from those into
  /// the buffers JavaScript reads into (sqlite's) is one `TypedArray.set`,
  /// and into Dart's own buffers one bulk copy too, where copying Dart's
  /// bytes into JavaScript's goes element by element. A file written whole
  /// ([File.writeAsBytes]) keeps Dart's bytes.
  static Uint8List Function(int length) newBytes = Uint8List.new;

  /// Puts [bytes] at [path] without telling [onChange]: for a store that is
  /// loading what it kept.
  static void seed(String path, Uint8List bytes, {DateTime? modified}) {
    final key = _normalize(path);
    _mkdirs(_posix.dirname(key));
    _files[key] = bytes;
    _modified[key] = modified ?? DateTime.now();
  }

  /// Every file under [prefix], for a store deciding what to keep.
  static Iterable<String> filesUnder(String prefix) {
    final root = _normalize(prefix);
    return _files.keys.where((k) => k == root || _posix.isWithin(root, k));
  }

  /// Forgets everything, for tests.
  static void reset() {
    _files.clear();
    _modified.clear();
    _accessed.clear();
    _dirs
      ..clear()
      ..add('/');
  }

  static String _normalize(String path) =>
      _posix.normalize(_posix.isAbsolute(path) ? path : '/$path');

  static void _mkdirs(String dir) {
    var d = _normalize(dir);
    while (_dirs.add(d)) {
      final up = _posix.dirname(d);
      if (up == d) break;
      d = up;
    }
  }

  static bool _isDir(String key) =>
      _dirs.contains(key) ||
      _files.keys.any((k) => _posix.isWithin(key, k)) ||
      _dirs.any((d) => _posix.isWithin(key, d));

  static void _write(String key, Uint8List bytes) {
    final dir = _posix.dirname(key);
    if (!_isDir(dir)) {
      throw FileSystemException('Cannot open file', key, _noSuchFile);
    }
    _files[key] = bytes;
    _modified[key] = DateTime.now();
    onChange?.call(key, bytes);
  }

  static void _remove(String key) {
    if (_files.remove(key) == null) return;
    _modified.remove(key);
    _accessed.remove(key);
    onChange?.call(key, null);
  }
}

const OSError _noSuchFile = OSError('No such file or directory', 2);

/// The modes [File.open] and [File.openWrite] take.
class FileMode {
  const FileMode._(this._mode);

  final int _mode;

  static const FileMode read = FileMode._(0);
  static const FileMode write = FileMode._(1);
  static const FileMode append = FileMode._(2);
  static const FileMode writeOnly = FileMode._(3);
  static const FileMode writeOnlyAppend = FileMode._(4);

  bool get _truncates => this == write || this == writeOnly;
  bool get _appends => this == append || this == writeOnlyAppend;

  @override
  String toString() => 'FileMode($_mode)';
}

/// What a path names.
class FileSystemEntityType {
  const FileSystemEntityType._(this._name);

  final String _name;

  static const FileSystemEntityType file = FileSystemEntityType._('file');
  static const FileSystemEntityType directory = FileSystemEntityType._(
    'directory',
  );
  static const FileSystemEntityType link = FileSystemEntityType._('link');
  static const FileSystemEntityType notFound = FileSystemEntityType._(
    'notFound',
  );

  @override
  String toString() => _name;
}

/// An operating-system error, as dart:io reports one.
class OSError implements Exception {
  const OSError([this.message = '', this.errorCode = noErrorCode]);

  static const int noErrorCode = -1;

  final String message;
  final int errorCode;

  @override
  String toString() => 'OS Error: $message, errno = $errorCode';
}

/// A file operation that failed.
class FileSystemException implements Exception {
  const FileSystemException([this.message = '', this.path = '', this.osError]);

  final String message;
  final String? path;
  final OSError? osError;

  @override
  String toString() =>
      'FileSystemException: $message, path = \'$path\''
      '${osError == null ? '' : ' ($osError)'}';
}

/// What [FileSystemEntity.stat] reports.
class FileStat {
  const FileStat._(this.type, this.size, this.modified, [DateTime? accessed])
    : _accessed = accessed;

  static final FileStat _notFound = FileStat._(
    FileSystemEntityType.notFound,
    -1,
    DateTime.fromMillisecondsSinceEpoch(0),
  );

  final FileSystemEntityType type;
  final int size;
  final DateTime modified;
  final DateTime? _accessed;
  DateTime get changed => modified;
  DateTime get accessed => _accessed ?? modified;
  int get mode => 0;

  static FileStat statSync(String path) => _stat(path);

  static Future<FileStat> stat(String path) async => _stat(path);

  static FileStat _stat(String path) {
    final key = MemoryFileSystem._normalize(path);
    final bytes = MemoryFileSystem._files[key];
    if (bytes != null) {
      return FileStat._(
        FileSystemEntityType.file,
        bytes.length,
        MemoryFileSystem._modified[key] ?? DateTime.now(),
        MemoryFileSystem._accessed[key],
      );
    }
    if (MemoryFileSystem._isDir(key)) {
      return FileStat._(FileSystemEntityType.directory, 0, DateTime.now());
    }
    return _notFound;
  }
}

/// A file or a directory.
abstract class FileSystemEntity {
  FileSystemEntity._(this.path);

  final String path;

  String get _key => MemoryFileSystem._normalize(path);

  Uri get uri => Uri.file(path);

  bool get isAbsolute => _posix.isAbsolute(path);

  Directory get parent => Directory(_posix.dirname(path));

  FileSystemEntity get absolute;

  Future<bool> exists() async => existsSync();

  bool existsSync();

  Future<FileStat> stat() async => statSync();

  FileStat statSync() => FileStat._stat(path);

  Future<FileSystemEntity> delete({bool recursive = false}) async {
    deleteSync(recursive: recursive);
    return this;
  }

  void deleteSync({bool recursive = false});

  Future<FileSystemEntity> rename(String newPath);

  FileSystemEntity renameSync(String newPath);

  static Future<bool> isDirectory(String path) async => isDirectorySync(path);

  static bool isDirectorySync(String path) =>
      MemoryFileSystem._isDir(MemoryFileSystem._normalize(path));

  static Future<bool> isFile(String path) async => isFileSync(path);

  static bool isFileSync(String path) =>
      MemoryFileSystem._files.containsKey(MemoryFileSystem._normalize(path));

  static Future<FileSystemEntityType> type(
    String path, {
    bool followLinks = true,
  }) async => typeSync(path);

  static FileSystemEntityType typeSync(
    String path, {
    bool followLinks = true,
  }) => FileStat._stat(path).type;

  @override
  String toString() => '$runtimeType: \'$path\'';
}

/// A file in [MemoryFileSystem].
class File extends FileSystemEntity {
  File(super.path) : super._();

  File.fromUri(Uri uri) : this(uri.toFilePath());

  @override
  File get absolute => File(_key);

  @override
  bool existsSync() => MemoryFileSystem._files.containsKey(_key);

  Uint8List _bytes(String what) {
    final bytes = MemoryFileSystem._files[_key];
    if (bytes == null) {
      throw FileSystemException(what, path, _noSuchFile);
    }
    return bytes;
  }

  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    createSync(recursive: recursive, exclusive: exclusive);
    return this;
  }

  void createSync({bool recursive = false, bool exclusive = false}) {
    if (existsSync()) {
      if (exclusive) {
        throw FileSystemException('Cannot create file', path);
      }
      return;
    }
    if (recursive) MemoryFileSystem._mkdirs(_posix.dirname(_key));
    MemoryFileSystem._write(_key, Uint8List(0));
  }

  @override
  void deleteSync({bool recursive = false}) {
    if (!existsSync()) {
      throw FileSystemException('Cannot delete file', path, _noSuchFile);
    }
    MemoryFileSystem._remove(_key);
  }

  @override
  Future<File> rename(String newPath) async => renameSync(newPath);

  @override
  File renameSync(String newPath) {
    final bytes = _bytes('Cannot rename file');
    final target = File(newPath);
    MemoryFileSystem._write(target._key, bytes);
    MemoryFileSystem._remove(_key);
    return target;
  }

  Future<File> copy(String newPath) async => copySync(newPath);

  File copySync(String newPath) {
    final target = File(newPath);
    MemoryFileSystem._write(
      target._key,
      Uint8List.fromList(_bytes('Cannot copy file')),
    );
    return target;
  }

  Future<int> length() async => lengthSync();

  int lengthSync() => _bytes('Cannot retrieve length of file').length;

  Future<DateTime> lastModified() async => lastModifiedSync();

  DateTime lastModifiedSync() {
    _bytes('Cannot retrieve modification time');
    return MemoryFileSystem._modified[_key] ?? DateTime.now();
  }

  Future<void> setLastModified(DateTime time) async =>
      setLastModifiedSync(time);

  void setLastModifiedSync(DateTime time) {
    _bytes('Failed to set file modification time');
    MemoryFileSystem._modified[_key] = time;
  }

  Future<void> setLastAccessed(DateTime time) async =>
      setLastAccessedSync(time);

  void setLastAccessedSync(DateTime time) {
    _bytes('Failed to set file access time');
    MemoryFileSystem._accessed[_key] = time;
  }

  Future<Uint8List> readAsBytes() async => readAsBytesSync();

  Uint8List readAsBytesSync() => Uint8List.fromList(_bytes('Cannot open file'));

  Future<String> readAsString({Encoding encoding = utf8}) async =>
      readAsStringSync(encoding: encoding);

  String readAsStringSync({Encoding encoding = utf8}) =>
      encoding.decode(_bytes('Cannot open file'));

  Future<List<String>> readAsLines({Encoding encoding = utf8}) async =>
      readAsLinesSync(encoding: encoding);

  List<String> readAsLinesSync({Encoding encoding = utf8}) =>
      const LineSplitter().convert(readAsStringSync(encoding: encoding));

  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    writeAsBytesSync(bytes, mode: mode, flush: flush);
    return this;
  }

  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    final existing = MemoryFileSystem._files[_key];
    if (mode._appends && existing != null) {
      MemoryFileSystem._write(
        _key,
        MemoryFileSystem.newBytes(existing.length + bytes.length)
          ..setRange(0, existing.length, existing)
          ..setRange(existing.length, existing.length + bytes.length, bytes),
      );
    } else {
      MemoryFileSystem._write(_key, Uint8List.fromList(bytes));
    }
  }

  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => writeAsBytes(encoding.encode(contents), mode: mode, flush: flush);

  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => writeAsBytesSync(encoding.encode(contents), mode: mode, flush: flush);

  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      openSync(mode: mode);

  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    if (mode == FileMode.read) {
      _bytes('Cannot open file');
    } else if (!existsSync() || mode._truncates) {
      MemoryFileSystem._write(_key, Uint8List(0));
    }
    return RandomAccessFile._(this, mode);
  }

  Stream<List<int>> openRead([int? start, int? end]) async* {
    final bytes = _bytes('Cannot open file');
    final from = start ?? 0;
    final to = end == null || end > bytes.length ? bytes.length : end;
    const chunk = 64 * 1024;
    // A reader that takes it all at once (a checksum over a tile) gives the
    // page a frame every so often, as a disk's latency would.
    const chunksPerTurn = 16;
    for (var i = from, n = 0; i < to; i += chunk, n++) {
      if (n > 0 && n % chunksPerTurn == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      // A copy in Dart's own bytes: readers go through it a few bytes at a
      // time, which is slow on bytes held by JavaScript ([newBytes]).
      yield Uint8List.fromList(
        Uint8List.sublistView(bytes, i, i + chunk < to ? i + chunk : to),
      );
    }
  }

  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) {
    if (mode == FileMode.read) {
      throw ArgumentError.value(mode, 'mode', 'must be a write mode');
    }
    if (!MemoryFileSystem._isDir(_posix.dirname(_key))) {
      throw FileSystemException('Cannot open file', path, _noSuchFile);
    }
    return IOSink._(this, mode, encoding);
  }
}

/// A directory in [MemoryFileSystem].
class Directory extends FileSystemEntity {
  Directory(super.path) : super._();

  Directory.fromUri(Uri uri) : this(uri.toFilePath());

  static Directory get current => Directory('/');

  static Directory get systemTemp => Directory('/tmp');

  @override
  Directory get absolute => Directory(_key);

  @override
  bool existsSync() => MemoryFileSystem._isDir(_key);

  Future<Directory> create({bool recursive = false}) async {
    createSync(recursive: recursive);
    return this;
  }

  void createSync({bool recursive = false}) {
    if (!recursive && !MemoryFileSystem._isDir(_posix.dirname(_key))) {
      throw FileSystemException('Creation failed', path, _noSuchFile);
    }
    MemoryFileSystem._mkdirs(_key);
  }

  Future<Directory> createTemp([String? prefix]) async =>
      createTempSync(prefix);

  Directory createTempSync([String? prefix]) {
    var n = 0;
    Directory candidate;
    do {
      candidate = Directory(_posix.join(_key, '${prefix ?? ''}${n++}'));
    } while (candidate.existsSync());
    candidate.createSync(recursive: true);
    return candidate;
  }

  @override
  void deleteSync({bool recursive = false}) {
    if (!existsSync()) {
      throw FileSystemException('Deletion failed', path, _noSuchFile);
    }
    final inside = MemoryFileSystem._files.keys
        .where((k) => _posix.isWithin(_key, k))
        .toList();
    final dirs = MemoryFileSystem._dirs
        .where((d) => _posix.isWithin(_key, d))
        .toList();
    if (!recursive && (inside.isNotEmpty || dirs.isNotEmpty)) {
      throw FileSystemException(
        'Deletion failed',
        path,
        const OSError('Directory not empty', 66),
      );
    }
    inside.forEach(MemoryFileSystem._remove);
    MemoryFileSystem._dirs
      ..removeAll(dirs)
      ..remove(_key);
  }

  @override
  Future<Directory> rename(String newPath) async => renameSync(newPath);

  @override
  Directory renameSync(String newPath) {
    final target = Directory(newPath);
    for (final k
        in MemoryFileSystem._files.keys
            .where((k) => _posix.isWithin(_key, k))
            .toList()) {
      final moved = _posix.join(target._key, _posix.relative(k, from: _key));
      MemoryFileSystem._mkdirs(_posix.dirname(moved));
      MemoryFileSystem._write(moved, MemoryFileSystem._files[k]!);
      MemoryFileSystem._remove(k);
    }
    MemoryFileSystem._mkdirs(target._key);
    MemoryFileSystem._dirs.removeWhere(
      (d) => d == _key || _posix.isWithin(_key, d),
    );
    return target;
  }

  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => Stream<FileSystemEntity>.fromIterable(
    listSync(recursive: recursive, followLinks: followLinks),
  );

  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) {
    if (!existsSync()) {
      throw FileSystemException('Directory listing failed', path, _noSuchFile);
    }
    bool wanted(String k) =>
        _posix.isWithin(_key, k) && (recursive || _posix.dirname(k) == _key);
    // Under the path the caller used, as dart:io lists them.
    String under(String k) => _posix.join(path, _posix.relative(k, from: _key));
    final dirs = MemoryFileSystem._dirs.where(wanted).toList()..sort();
    final files = MemoryFileSystem._files.keys.where(wanted).toList()..sort();
    return <FileSystemEntity>[
      for (final d in dirs) Directory(under(d)),
      for (final f in files) File(under(f)),
    ];
  }
}

/// A file opened for reading or writing at a position.
class RandomAccessFile {
  RandomAccessFile._(this._file, this._mode)
    : _position = _mode._appends ? _file.lengthSync() : 0;

  final File _file;
  final FileMode _mode;
  int _position;
  bool _closed = false;

  String get path => _file.path;

  Uint8List get _bytes {
    if (_closed) throw FileSystemException('File closed', path);
    return _file._bytes('Cannot read file');
  }

  Future<void> close() async => closeSync();

  void closeSync() => _closed = true;

  Future<int> position() async => positionSync();

  int positionSync() => _position;

  Future<RandomAccessFile> setPosition(int position) async {
    setPositionSync(position);
    return this;
  }

  void setPositionSync(int position) {
    if (position < 0) throw FileSystemException('Invalid position', path);
    _position = position;
  }

  Future<int> length() async => lengthSync();

  int lengthSync() => _bytes.length;

  Future<Uint8List> read(int count) async => readSync(count);

  Uint8List readSync(int count) {
    final bytes = _bytes;
    final from = _position.clamp(0, bytes.length);
    final to = (from + count).clamp(0, bytes.length);
    _position = to;
    return Uint8List.fromList(Uint8List.sublistView(bytes, from, to));
  }

  Future<int> readByte() async => readByteSync();

  int readByteSync() {
    final bytes = _bytes;
    if (_position >= bytes.length) return -1;
    return bytes[_position++];
  }

  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) async =>
      readIntoSync(buffer, start, end);

  int readIntoSync(List<int> buffer, [int start = 0, int? end]) {
    final bytes = _bytes;
    final want = (end ?? buffer.length) - start;
    final available = bytes.length - _position;
    final n = want < available ? want : (available < 0 ? 0 : available);
    if (n <= 0) return 0;
    buffer.setRange(start, start + n, bytes, _position);
    _position += n;
    return n;
  }

  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    writeFromSync(buffer, start, end);
    return this;
  }

  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    if (_mode == FileMode.read) {
      throw FileSystemException('File not open for writing', path);
    }
    final data = buffer.sublist(start, end ?? buffer.length);
    final old = _bytes;
    final length = _position + data.length > old.length
        ? _position + data.length
        : old.length;
    final next = MemoryFileSystem.newBytes(length)
      ..setRange(0, old.length, old);
    next.setRange(_position, _position + data.length, data);
    _position += data.length;
    MemoryFileSystem._write(_file._key, next);
  }

  Future<RandomAccessFile> writeByte(int value) => writeFrom(<int>[value]);

  int writeByteSync(int value) {
    writeFromSync(<int>[value]);
    return 1;
  }

  Future<RandomAccessFile> writeString(
    String string, {
    Encoding encoding = utf8,
  }) => writeFrom(encoding.encode(string));

  void writeStringSync(String string, {Encoding encoding = utf8}) =>
      writeFromSync(encoding.encode(string));

  Future<RandomAccessFile> truncate(int length) async {
    truncateSync(length);
    return this;
  }

  void truncateSync(int length) {
    final old = _bytes;
    final next = MemoryFileSystem.newBytes(length)
      ..setRange(0, length < old.length ? length : old.length, old);
    MemoryFileSystem._write(_file._key, next);
  }

  Future<RandomAccessFile> flush() async => this;

  void flushSync() {}
}

/// Collects what is written and puts it into the file on [flush] and
/// [close].
class IOSink implements StreamSink<List<int>>, StringSink {
  IOSink._(this._file, FileMode mode, this.encoding) {
    final existing = MemoryFileSystem._files[_file._key];
    if (mode._appends && existing != null) add(existing);
    _commit();
  }

  final File _file;
  final List<List<int>> _chunks = <List<int>>[];
  int _length = 0;
  final Completer<void> _done = Completer<void>();

  Encoding encoding;

  /// Puts what was written into the file, unless it is there already.
  void _commit() {
    if (_chunks.length == 1 && _chunks.single is Uint8List) {
      final only = _chunks.single as Uint8List;
      if (identical(MemoryFileSystem._files[_file._key], only)) return;
    }
    final bytes = MemoryFileSystem.newBytes(_length);
    var at = 0;
    for (final chunk in _chunks) {
      bytes.setRange(at, at + chunk.length, chunk);
      at += chunk.length;
    }
    // One chunk from now on, so a flush and then a close copy once.
    _chunks
      ..clear()
      ..add(bytes);
    MemoryFileSystem._write(_file._key, bytes);
  }

  @override
  void add(List<int> data) {
    _chunks.add(data);
    _length += data.length;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_done.isCompleted) _done.completeError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  void write(Object? object) => add(encoding.encode('$object'));

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  Future<void> flush() async => _commit();

  @override
  Future<void> close() async {
    _commit();
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

/// The console, as far as the routing engine writes to it.
class Stdout implements StringSink {
  Stdout._(this._print);

  final void Function(String line) _print;
  final StringBuffer _line = StringBuffer();

  @override
  void write(Object? object) {
    final text = '$object';
    final cut = text.lastIndexOf('\n');
    if (cut < 0) {
      _line.write(text);
      return;
    }
    _line.write(text.substring(0, cut));
    for (final line in _line.toString().split('\n')) {
      _print(line);
    }
    _line
      ..clear()
      ..write(text.substring(cut + 1));
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');
}

/// zlib as dart:io offers it, in Dart (package:archive's encoder and
/// decoder) since a browser has no native one.
class ZLibCodec extends Codec<List<int>, List<int>> {
  const ZLibCodec({this.level = 6});

  /// 0 (stored) to 9 (smallest); 6 is zlib's default, as in dart:io.
  final int level;

  @override
  Converter<List<int>, List<int>> get encoder => _ZLibEncoder(level);

  @override
  Converter<List<int>, List<int>> get decoder => const _ZLibDecoder();
}

/// zlib at the default level, as dart:io's `zlib`.
const ZLibCodec zlib = ZLibCodec();

class _ZLibEncoder extends Converter<List<int>, List<int>> {
  const _ZLibEncoder(this.level);

  final int level;

  @override
  List<int> convert(List<int> input) =>
      const ZLibEncoderWeb().encodeBytes(input, level: level);
}

class _ZLibDecoder extends Converter<List<int>, List<int>> {
  const _ZLibDecoder();

  @override
  List<int> convert(List<int> input) =>
      const ZLibDecoderWeb().decodeBytes(input);
}

final Stdout stdout = Stdout._(print);
final Stdout stderr = Stdout._(print);

/// There is no process to end in a browser.
Never exit(int code) => throw UnsupportedError('exit($code) in a browser');

/// The header names dart:io offers, as far as Velorki sends them.
abstract final class HttpHeaders {
  static const String acceptHeader = 'accept';
  static const String authorizationHeader = 'authorization';
  static const String contentLengthHeader = 'content-length';
  static const String contentTypeHeader = 'content-type';
  static const String rangeHeader = 'range';
  static const String userAgentHeader = 'user-agent';
}
