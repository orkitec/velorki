import 'dart:typed_data';

/// Byte offset of the 4 byte ASCII data type signature in a FIT file header.
const int _signatureOffset = 8;

/// The ASCII bytes `.FIT`.
const List<int> _signature = <int>[0x2E, 0x46, 0x49, 0x54];

/// The two header sizes the FIT protocol defines: 12 bytes (no header CRC)
/// and 14 bytes (with header CRC).
const List<int> _headerSizes = <int>[12, 14];

/// The shortest possible FIT file: a 12 byte header plus the 2 byte file CRC.
const int _minFitLength = 14;

/// Whether [bytes] looks like a FIT file.
///
/// This is the cheap sniffer used by the import pipeline to route a buffer to
/// the right decoder. It checks the header size byte at offset 0 (12 or 14),
/// the ASCII `.FIT` data type signature at offsets 8..11, and that the buffer
/// is long enough to hold a header and the trailing CRC.
///
/// It deliberately does not verify any CRC, so a `true` result means "worth
/// handing to [FitCodec.decodeActivity]", not "valid FIT file". It returns
/// `false` for GPX/XML, JSON, empty buffers and arbitrary short input.
bool looksLikeFit(Uint8List bytes) {
  if (bytes.length < _minFitLength) return false;
  final int headerSize = bytes[0];
  if (!_headerSizes.contains(headerSize)) return false;
  if (bytes.length < headerSize + 2) return false;
  for (var i = 0; i < _signature.length; i++) {
    if (bytes[_signatureOffset + i] != _signature[i]) return false;
  }
  return true;
}
