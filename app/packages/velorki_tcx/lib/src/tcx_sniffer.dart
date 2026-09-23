import 'dart:typed_data';

/// Whether [bytes] look like a TCX document: XML whose root is
/// `TrainingCenterDatabase`, in any encoding the import pipeline accepts.
///
/// Throws [UnimplementedError] until phase 4.
bool looksLikeTcx(Uint8List bytes) {
  throw UnimplementedError('Phase 4: the TCX sniffer is not written yet');
}
