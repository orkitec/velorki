// Port of btools.util.DiffCoderDataOutputStream (BRouter v1.7.10).
//
// DataOutputStream extended by varlength diff coding

import 'dart:typed_data';

import '../jvm.dart';

class DiffCoderDataOutputStream extends DataOutputStream {
  DiffCoderDataOutputStream();

  final Int64List _lastValues = Int64List(10);

  void writeDiffed(int v, int idx) {
    final d = v - _lastValues[idx];
    _lastValues[idx] = v;
    writeSigned(d);
  }

  void writeSigned(int v) {
    writeUnsigned(v < 0 ? ((-v) << 1) | 1 : v << 1);
  }

  void writeUnsigned(int v) {
    do {
      var i7 = v & 0x7f;
      v >>= 7;
      if (v != 0) i7 |= 0x80;
      writeByte(i7 & 0xff);
    } while (v != 0);
  }
}
