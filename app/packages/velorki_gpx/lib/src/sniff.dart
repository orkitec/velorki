import 'dart:typed_data';

/// How many leading bytes are inspected by [looksLikeGpx].
const int _sniffWindow = 512;

/// The `.FIT` magic that sits at byte offset 8 of every FIT file.
const List<int> _fitMagic = [0x2E, 0x46, 0x49, 0x54];

/// Cheap content sniffer for the import pipeline: does [bytes] look like GPX?
///
/// This only inspects the first 512 bytes, so it is safe to call on a whole
/// file before deciding which parser to hand it to. It tolerates a UTF-8 or
/// UTF-16 byte order mark, leading whitespace and an `<?xml ... ?>`
/// declaration, and looks for an opening `<gpx` tag (case-insensitively).
///
/// It deliberately answers *maybe*, not *yes*: a `true` result still has to be
/// confirmed by `GpxCodec.decode`. It returns `false` for FIT files (detected
/// by their `.FIT` magic at offset 8), for JSON, and for arbitrary binary.
bool looksLikeGpx(Uint8List bytes) {
  if (bytes.length < 4) {
    return false;
  }
  if (_hasFitMagic(bytes)) {
    return false;
  }

  final text = _decodeHead(bytes);
  return _containsGpxTag(text);
}

/// Whether [bytes] carries the FIT file magic (`.FIT` at offset 8).
bool _hasFitMagic(Uint8List bytes) {
  if (bytes.length < 12) {
    return false;
  }
  for (var i = 0; i < _fitMagic.length; i++) {
    if (bytes[8 + i] != _fitMagic[i]) {
      return false;
    }
  }
  return true;
}

/// Turns the first [_sniffWindow] bytes into a string for tag matching.
///
/// The bytes are treated as Latin-1 rather than UTF-8: everything we match on
/// is ASCII, and Latin-1 can never throw on malformed input. A UTF-16 byte
/// order mark switches to reading every second byte, which turns UTF-16 ASCII
/// back into plain ASCII.
String _decodeHead(Uint8List bytes) {
  final end = bytes.length < _sniffWindow ? bytes.length : _sniffWindow;

  // UTF-8 BOM: skip it, the rest is byte-per-character for ASCII.
  if (end >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return String.fromCharCodes(bytes, 3, end);
  }
  // UTF-16 LE BOM: ASCII characters are (byte, 0x00) pairs.
  if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return String.fromCharCodes([for (var i = 2; i < end; i += 2) bytes[i]]);
  }
  // UTF-16 BE BOM: ASCII characters are (0x00, byte) pairs.
  if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return String.fromCharCodes([for (var i = 3; i < end; i += 2) bytes[i]]);
  }
  return String.fromCharCodes(bytes, 0, end);
}

/// Whether [text] contains an opening `<gpx` tag.
///
/// The character after `<gpx` must end the name, so that `<gpxdata>` from some
/// unrelated XML dialect does not count.
bool _containsGpxTag(String text) {
  final lower = text.toLowerCase();
  var from = 0;
  while (true) {
    final at = lower.indexOf('<gpx', from);
    if (at < 0) {
      return false;
    }
    final after = at + 4;
    if (after >= lower.length) {
      // Truncated by the sniff window right after the tag name; good enough.
      return true;
    }
    switch (lower[after]) {
      case ' ':
      case '\t':
      case '\r':
      case '\n':
      case '>':
      case '/':
        return true;
    }
    from = after;
  }
}
