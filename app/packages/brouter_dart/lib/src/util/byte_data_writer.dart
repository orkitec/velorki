// Port of btools.util.ByteDataWriter (BRouter v1.7.10).
//
// fast data-writing to a byte-array

import 'dart:typed_data';

import '../jvm.dart';
import 'byte_data_reader.dart';

class ByteDataWriter extends ByteDataReader {
  ByteDataWriter(super.byteArray);

  void writeInt(int v) {
    ab[aboffset++] = (v >> 24) & 0xff;
    ab[aboffset++] = (v >> 16) & 0xff;
    ab[aboffset++] = (v >> 8) & 0xff;
    ab[aboffset++] = v & 0xff;
  }

  void writeLong(int v) {
    ab[aboffset++] = (v >> 56) & 0xff;
    ab[aboffset++] = (v >> 48) & 0xff;
    ab[aboffset++] = (v >> 40) & 0xff;
    ab[aboffset++] = (v >> 32) & 0xff;
    ab[aboffset++] = (v >> 24) & 0xff;
    ab[aboffset++] = (v >> 16) & 0xff;
    ab[aboffset++] = (v >> 8) & 0xff;
    ab[aboffset++] = v & 0xff;
  }

  void writeBoolean(bool v) {
    ab[aboffset++] = v ? 1 : 0;
  }

  void writeByte(int v) {
    ab[aboffset++] = v & 0xff;
  }

  void writeShort(int v) {
    ab[aboffset++] = (v >> 8) & 0xff;
    ab[aboffset++] = v & 0xff;
  }

  /// `write(byte[] sa)` / `write(byte[] sa, int offset, int len)`.
  void write(Uint8List sa, [int offset = 0, int? len]) {
    final n = len ?? sa.length;
    ab.setRange(aboffset, aboffset + n, sa, offset);
    aboffset += n;
  }

  void writeVarBytes(Uint8List? sa) {
    if (sa == null) {
      writeVarLengthUnsigned(0);
    } else {
      final len = sa.length;
      writeVarLengthUnsigned(len);
      write(sa, 0, len);
    }
  }

  void writeModeAndDesc(bool isReverse, Uint8List? sa) {
    final len = sa == null ? 0 : sa.length;
    final sizecode = len << 1 | (isReverse ? 1 : 0);
    writeVarLengthUnsigned(sizecode);
    if (len > 0) {
      write(sa!, 0, len);
    }
  }

  Uint8List toByteArray() {
    final c = Uint8List(aboffset);
    c.setRange(0, aboffset, ab);
    return c;
  }

  /// Just reserves a single byte and return it' offset.
  /// Used in conjunction with injectVarLengthUnsigned
  /// to efficiently write a size prefix
  ///
  /// Returns the offset of the placeholder
  int writeSizePlaceHolder() {
    return aboffset++;
  }

  void injectSize(int sizeoffset) {
    var size = 0;
    final datasize = aboffset - sizeoffset - 1;
    var v = datasize;
    do {
      v = shr32(v, 7);
      size++;
    } while (v != 0);
    if (size > 1) {
      // doesn't fit -> shift the data after the placeholder
      ab.setRange(
        sizeoffset + size,
        sizeoffset + size + datasize,
        ab,
        sizeoffset + 1,
      );
    }
    aboffset = sizeoffset;
    writeVarLengthUnsigned(datasize);
    aboffset = sizeoffset + size + datasize;
  }

  void writeVarLengthSigned(int v) {
    writeVarLengthUnsigned(v < 0 ? shl32(-v, 1) | 1 : shl32(v, 1));
  }

  void writeVarLengthUnsigned(int v) {
    var i7 = v & 0x7f;
    if ((v = ushr32(v, 7)) == 0) {
      ab[aboffset++] = i7;
      return;
    }
    ab[aboffset++] = i7 | 0x80;

    i7 = v & 0x7f;
    if ((v = ushr32(v, 7)) == 0) {
      ab[aboffset++] = i7;
      return;
    }
    ab[aboffset++] = i7 | 0x80;

    i7 = v & 0x7f;
    if ((v = ushr32(v, 7)) == 0) {
      ab[aboffset++] = i7;
      return;
    }
    ab[aboffset++] = i7 | 0x80;

    i7 = v & 0x7f;
    if ((v = ushr32(v, 7)) == 0) {
      ab[aboffset++] = i7;
      return;
    }
    ab[aboffset++] = i7 | 0x80;

    ab[aboffset++] = v & 0xff;
  }

  /// `size()` upstream; renamed because `MicroCache` (a subclass) has a `size`
  /// field and Dart has one namespace for fields and methods.
  int writtenSize() {
    return aboffset;
  }
}
