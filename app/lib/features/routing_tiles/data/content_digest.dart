import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:velorki_io/io.dart';

import '../../search/data/gazetteer_sqlite/gazetteer_sqlite.dart';
import '../domain/sha256.dart';

// The two digests the mirror publishes as `contentSha256`, worked out for the
// files already on the phone. They must match the mirror's definitions
// exactly: for a `.gaz` `tools/gazetteer/digest.py`, for an rd5 the sha256 of
// the file with its header's creation time zeroed.

/// Where the rd5 header keeps the offset of the creation time's slot
/// (`fileIndex[24]`: the 48 low bits of the big-endian int64 at byte 192).
const int _creationTimeIndexAt = 192;

/// The content digest of the rd5 at [path], computed off the UI thread.
Future<String> rd5ContentDigest(String path) =>
    compute<String, String>(_rd5Digest, path);

/// The content digest of the `.gaz` at [path], computed off the UI thread.
Future<String> gazetteerContentDigest(String path) async {
  await prepareGazetteerSqlite();
  return compute<String, String>(gazetteerDigestSync, path);
}

Future<String> _rd5Digest(String path) => rd5DigestOfFile(File(path));

/// sha256 of [file], streamed, with the 8 bytes of the creation time zeroed.
///
/// A file too short to hold the header or the slot is hashed as it is.
Future<String> rd5DigestOfFile(File file) async {
  final length = await file.length();
  var zeroAt = -1;
  if (length >= _creationTimeIndexAt + 8) {
    final head = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, _creationTimeIndexAt + 8)) {
      head.add(chunk);
    }
    final bytes = head.takeBytes();
    // The int64's low 48 bits: its last six bytes.
    var offset = 0;
    for (var i = 2; i < 8; i++) {
      offset = offset * 256 + bytes[_creationTimeIndexAt + i];
    }
    if (length >= offset + 8) zeroAt = offset;
  }
  final digest = Sha256();
  var position = 0;
  await for (final chunk in file.openRead()) {
    final end = position + chunk.length;
    if (zeroAt >= 0 && position < zeroAt + 8 && end > zeroAt) {
      final copy = Uint8List.fromList(chunk);
      for (var i = zeroAt; i < zeroAt + 8; i++) {
        if (i >= position && i < end) copy[i - position] = 0;
      }
      digest.add(copy);
    } else {
      digest.add(chunk);
    }
    position = end;
  }
  return digest.hexDigest();
}

/// The `.gaz` digest of `digest.py`, synchronously: sha256 over the tables'
/// rows, `meta.built_at` left out, SQLite's page layout not involved.
String gazetteerDigestSync(String path) {
  final db = openGazetteerFile(path);
  try {
    final names = <String>[
      for (final row in db.select(
        "SELECT name FROM sqlite_master WHERE type = 'table'"
        r" AND name NOT LIKE 'sqlite\_%' ESCAPE '\'"
        " AND sql NOT LIKE 'CREATE VIRTUAL TABLE%'",
      ))
        row['name'] as String,
    ]..sort(_compareCodePoints);
    final digest = Sha256();
    final out = _Feed(digest);
    for (final table in names) {
      out.byte(0x54);
      out.text(table);
      final quoted = '"${table.replaceAll('"', '""')}"';
      final columns = db.select('SELECT * FROM $quoted LIMIT 0').columnNames;
      final order = <String>[for (var i = 1; i <= columns.length; i++) '$i']
          .join(', ');
      final statement = db.prepare('SELECT * FROM $quoted ORDER BY $order');
      final rows = statement.selectCursor();
      while (rows.moveNext()) {
        final values = rows.current.values;
        if (table == 'meta' && values.first == 'built_at') continue;
        out.byte(0x52);
        values.forEach(out.value);
      }
      statement.close();
    }
    out.flush();
    return digest.hexDigest();
  } finally {
    db.close();
  }
}

int _compareCodePoints(String a, String b) {
  final x = a.runes.toList();
  final y = b.runes.toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return x.length.compareTo(y.length);
}

/// Feeds the digest in blocks rather than a call per value.
class _Feed {
  _Feed(this._digest);

  final Sha256 _digest;
  final BytesBuilder _buffer = BytesBuilder();
  final ByteData _scratch = ByteData(8);

  void byte(int b) {
    _buffer.addByte(b);
    if (_buffer.length >= 1 << 16) flush();
  }

  void flush() {
    if (_buffer.isEmpty) return;
    _digest.add(_buffer.takeBytes());
  }

  void _uint32(int v) {
    _scratch.setUint32(0, v);
    _buffer.add(Uint8List.sublistView(_scratch, 0, 4));
  }

  void text(String s) {
    final data = utf8.encode(s);
    byte(0x03);
    _uint32(data.length);
    _buffer.add(data);
  }

  void value(Object? v) {
    switch (v) {
      case null:
        byte(0x00);
      case int():
        byte(0x01);
        // Two halves: an int64 setter is not there in a browser.
        _uint32((v >> 32) & 0xffffffff);
        _uint32(v & 0xffffffff);
      case double():
        byte(0x02);
        _scratch.setFloat64(0, v);
        _buffer.add(Uint8List.sublistView(_scratch));
      case String():
        text(v);
      case Uint8List():
        byte(0x04);
        _uint32(v.length);
        _buffer.add(v);
      default:
        throw StateError('unexpected SQLite value ${v.runtimeType}');
    }
    if (_buffer.length >= 1 << 16) flush();
  }
}
