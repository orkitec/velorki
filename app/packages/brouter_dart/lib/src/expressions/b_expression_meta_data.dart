// Port of btools.expressions.BExpressionMetaData (BRouter v1.7.10).

import 'dart:convert';
import 'dart:io';

import '../jfloat.dart';
import 'b_expression_context.dart';

class BExpressionMetaData {
  static const String _contextTag = '---context:';
  static const String _versionTag = '---lookupversion:';
  static const String _minorVersionTag = '---minorversion:';
  static const String _varlengthTag = '---readvarlength';
  static const String _minAppVersionTag = '---minappversion:';

  int lookupVersion = -1;
  int lookupMinorVersion = -1;
  int minAppVersion = -1;

  final Map<String, BExpressionContext> _listeners =
      <String, BExpressionContext>{};

  void registerListener(String context, BExpressionContext ctx) {
    _listeners[context] = ctx;
  }

  /// `readMetaData(File)`: reads `lookups.dat`.
  void readMetaData(File lookupsFile) {
    readMetaDataLines(_readLines(lookupsFile));
  }

  /// The body of `readMetaData` over the lines of `lookups.dat` (for callers
  /// that hold the table in memory, e.g. as an app asset).
  void readMetaDataLines(Iterable<String> lines) {
    try {
      BExpressionContext? ctx;
      for (var line in lines) {
        line = javaTrim(line);
        if (line.isEmpty || line.startsWith('#')) continue;
        if (line.startsWith(_contextTag)) {
          ctx = _listeners[line.substring(_contextTag.length)];
          continue;
        }
        if (line.startsWith(_versionTag)) {
          lookupVersion = _parseShort(line.substring(_versionTag.length));
          continue;
        }
        if (line.startsWith(_minorVersionTag)) {
          lookupMinorVersion = _parseShort(
            line.substring(_minorVersionTag.length),
          );
          continue;
        }
        if (line.startsWith(_minAppVersionTag)) {
          minAppVersion = _parseShort(line.substring(_minAppVersionTag.length));
          continue;
        }
        if (line.startsWith(_varlengthTag)) {
          // tag removed...
          continue;
        }
        ctx?.parseMetaLine(line);
      }

      for (final c in _listeners.values) {
        c.finishMetaParsing();
      }
    } on Error {
      rethrow;
    } catch (e) {
      throw StateError('$e'); // RuntimeException(e)
    }
  }

  /// `Short.parseShort`.
  static int _parseShort(String s) {
    final v = javaParseInt(s);
    if (v < -32768 || v > 32767) {
      throw NumberFormatException('Value out of range. Value:"$s" Radix:10');
    }
    return v;
  }

  /// `BufferedReader.readLine()` over the file: lines split at `\n`, `\r` or
  /// `\r\n`, without a trailing empty line.
  static List<String> _readLines(File f) => readJavaLines(f.readAsBytesSync());
}

/// `BufferedReader.readLine()` semantics over UTF-8 bytes.
List<String> readJavaLines(List<int> bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  final lines = <String>[];
  var start = 0;
  final n = text.length;
  var i = 0;
  while (i < n) {
    final c = text.codeUnitAt(i);
    if (c == 0x0a || c == 0x0d) {
      lines.add(text.substring(start, i));
      if (c == 0x0d && i + 1 < n && text.codeUnitAt(i + 1) == 0x0a) i++;
      start = i + 1;
    }
    i++;
  }
  if (start < n) lines.add(text.substring(start));
  return lines;
}
