// Port of btools.util.ByteDataReader (BRouter v1.7.10).
//
// fast data-reading from a byte-array

import 'dart:typed_data';

import '../jvm.dart';

/// Stands in for a Java `null` byte array (see the README on nullability).
final Uint8List emptyBytes = Uint8List(0);

class ByteDataReader {
  ByteDataReader(Uint8List? byteArray, [int offset = 0])
    : ab = byteArray ?? emptyBytes,
      aboffset = offset,
      aboffsetEnd = byteArray == null ? 0 : byteArray.length;

  /// `protected byte[] ab`; a Java `null` is represented by [emptyBytes].
  Uint8List ab;
  int aboffset;
  int aboffsetEnd;

  void reset(Uint8List? byteArray) {
    ab = byteArray ?? emptyBytes;
    aboffset = 0;
    aboffsetEnd = byteArray == null ? 0 : byteArray.length;
  }

  int readInt() {
    final i3 = ab[aboffset++] & 0xff;
    final i2 = ab[aboffset++] & 0xff;
    final i1 = ab[aboffset++] & 0xff;
    final i0 = ab[aboffset++] & 0xff;
    return i32((i3 << 24) + (i2 << 16) + (i1 << 8) + i0);
  }

  int readLong() {
    final i7 = ab[aboffset++] & 0xff;
    final i6 = ab[aboffset++] & 0xff;
    final i5 = ab[aboffset++] & 0xff;
    final i4 = ab[aboffset++] & 0xff;
    final i3 = ab[aboffset++] & 0xff;
    final i2 = ab[aboffset++] & 0xff;
    final i1 = ab[aboffset++] & 0xff;
    final i0 = ab[aboffset++] & 0xff;
    return (i7 << 56) +
        (i6 << 48) +
        (i5 << 40) +
        (i4 << 32) +
        (i3 << 24) +
        (i2 << 16) +
        (i1 << 8) +
        i0;
  }

  bool readBoolean() {
    final i0 = ab[aboffset++] & 0xff;
    return i0 != 0;
  }

  /// Returns a signed Java `byte`.
  int readByte() {
    final i0 = ab[aboffset++] & 0xff;
    return toByte(i0);
  }

  /// Returns a signed Java `short`.
  int readShort() {
    final i1 = ab[aboffset++] & 0xff;
    final i0 = ab[aboffset++] & 0xff;
    return toShort((i1 << 8) | i0);
  }

  /// Read a size value and return a pointer to the end of a data section of
  /// that size
  ///
  /// Returns the pointer to the first byte after that section
  int getEndPointer() {
    final size = readVarLengthUnsigned();
    return aboffset + size;
  }

  Uint8List? readDataUntil(int endPointer) {
    final size = endPointer - aboffset;
    if (size == 0) {
      return null;
    }
    final data = Uint8List(size);
    readFully(data);
    return data;
  }

  Uint8List? readVarBytes() {
    final len = readVarLengthUnsigned();
    if (len == 0) {
      return null;
    }
    final bytes = Uint8List(len);
    readFully(bytes);
    return bytes;
  }

  int readVarLengthSigned() {
    final v = readVarLengthUnsigned();
    return (v & 1) == 0 ? shr32(v, 1) : i32(-shr32(v, 1));
  }

  int readVarLengthUnsigned() {
    int b;
    var v = (b = ab[aboffset++]) & 0x7f;
    if (b < 0x80) return v;
    v |= ((b = ab[aboffset++]) & 0x7f) << 7;
    if (b < 0x80) return v;
    v |= ((b = ab[aboffset++]) & 0x7f) << 14;
    if (b < 0x80) return v;
    v |= ((b = ab[aboffset++]) & 0x7f) << 21;
    if (b < 0x80) return v;
    v |= ((b = ab[aboffset++]) & 0xf) << 28;
    return i32(v);
  }

  void readFully(Uint8List ta) {
    ta.setRange(0, ta.length, ab, aboffset);
    aboffset += ta.length;
  }

  bool hasMoreData() {
    return aboffset < aboffsetEnd;
  }

  @override
  String toString() {
    final sb = StringBuffer('[');
    for (var i = 0; i < ab.length; i++) {
      sb
        ..write(i == 0 ? ' ' : ', ')
        ..write(toByte(ab[i]));
    }
    sb.write(' ]');
    return sb.toString();
  }
}
