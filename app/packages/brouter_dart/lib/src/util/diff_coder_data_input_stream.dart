// Port of btools.util.DiffCoderDataInputStream (BRouter v1.7.10).
//
// DataInputStream extended by varlength diff coding

import 'dart:typed_data';

import '../jvm.dart';

class DiffCoderDataInputStream extends DataInputStream {
  DiffCoderDataInputStream(super.ab);

  final Int64List _lastValues = Int64List(10);

  int readDiffed(int idx) {
    final d = readSigned();
    final v = _lastValues[idx] + d;
    _lastValues[idx] = v;
    return v;
  }

  int readSigned() {
    final v = readUnsigned();
    return (v & 1) == 0 ? v >> 1 : -(v >> 1);
  }

  int readUnsigned() {
    var v = 0;
    var shift = 0;
    for (;;) {
      final i7 = readByte() & 0xff;
      v |= shl64(i7 & 0x7f, shift);
      if ((i7 & 0x80) == 0) break;
      shift += 7;
    }
    return v;
  }
}
