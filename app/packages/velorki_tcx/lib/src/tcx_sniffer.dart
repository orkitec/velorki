import 'dart:typed_data';

/// How many bytes are looked at: an XML declaration, a byte order mark and
/// the root element with its namespaces fit in a fraction of this.
const int _sniffWindow = 2048;

/// Whether [bytes] look like a TCX document: XML whose root element is
/// `TrainingCenterDatabase`, with or without a namespace prefix, in UTF-8
/// with or without a byte order mark, or in UTF-16 with one.
bool looksLikeTcx(Uint8List bytes) {
  if (bytes.length < 8) return false;
  final text = _decodeHead(bytes);
  final at = text.indexOf('<');
  if (at < 0) return false;
  // The root element is the first tag that is not the declaration, a
  // comment or a processing instruction.
  var from = 0;
  while (true) {
    final open = text.indexOf('<', from);
    if (open < 0) return false;
    if (text.startsWith('<?', open) || text.startsWith('<!', open)) {
      final close = text.indexOf('>', open);
      if (close < 0) return false;
      from = close + 1;
      continue;
    }
    final end = _nameEnd(text, open + 1);
    final name = text.substring(open + 1, end);
    final local = name.contains(':') ? name.split(':').last : name;
    return local == 'TrainingCenterDatabase';
  }
}

int _nameEnd(String text, int from) {
  var i = from;
  while (i < text.length) {
    final c = text[i];
    if (c == ' ' ||
        c == '\t' ||
        c == '\r' ||
        c == '\n' ||
        c == '>' ||
        c == '/') {
      break;
    }
    i++;
  }
  return i;
}

String _decodeHead(Uint8List bytes) {
  final end = bytes.length < _sniffWindow ? bytes.length : _sniffWindow;
  if (end >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return String.fromCharCodes(bytes, 3, end);
  }
  if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return String.fromCharCodes([for (var i = 2; i < end; i += 2) bytes[i]]);
  }
  if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return String.fromCharCodes([for (var i = 3; i < end; i += 2) bytes[i]]);
  }
  return String.fromCharCodes(bytes, 0, end);
}
