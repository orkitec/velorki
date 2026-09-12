/// Helpers that emulate JVM primitive semantics on the Dart VM.
///
/// Dart `int` is a 64-bit two's-complement integer on the VM, which is exactly
/// Java `long`. Java `int` (32 bit) has to be emulated wherever a value can
/// overflow or is shifted: the helpers below wrap with `toSigned(32)` and mask
/// shift distances the way the JVM does (`& 31` for `int`, `& 63` for `long`).
///
/// Java `float` is emulated with a `Float32List` round trip ([f32]). No class of
/// the `brouter-util` / `brouter-codec` modules uses `float`; the helper exists
/// for the later modules.
library;

import 'dart:typed_data';

/// `(int) v` for an integral value: wrap to a Java `int`.
int i32(int v) => v.toSigned(32);

/// `(short) v`.
int toShort(int v) => v.toSigned(16);

/// `(byte) v`.
int toByte(int v) => v.toSigned(8);

/// Java `int` `v >>> n` (the JVM masks the distance with `& 31`).
int ushr32(int v, int n) => ((v & 0xffffffff) >> (n & 31)).toSigned(32);

/// Java `int` `v >> n`.
int shr32(int v, int n) => v.toSigned(32) >> (n & 31);

/// Java `int` `v << n`.
int shl32(int v, int n) => (v << (n & 31)).toSigned(32);

/// Java `long` `v >>> n`.
int ushr64(int v, int n) => v >>> (n & 63);

/// Java `long` `v >> n`.
int shr64(int v, int n) => v >> (n & 63);

/// Java `long` `v << n`.
int shl64(int v, int n) => v << (n & 63);

/// Java `int` multiplication.
int mul32(int a, int b) => (a * b).toSigned(32);

/// Java `%` on integers: the remainder takes the sign of the dividend.
int rem(int a, int b) => a.remainder(b);

/// Java `%` on doubles (C `fmod` semantics).
double frem(double a, double b) => a.remainder(b);

/// `Integer.MAX_VALUE` / `Integer.MIN_VALUE`.
const int intMaxValue = 0x7fffffff;
const int intMinValue = -0x80000000;

/// `Long.MAX_VALUE` / `Long.MIN_VALUE`.
const int longMaxValue = 0x7fffffffffffffff;
const int longMinValue = -0x8000000000000000;

final Float32List _f32 = Float32List(1);

/// Java `float` round trip: `(double) (float) v`.
double f32(double v) {
  _f32[0] = v;
  return _f32[0];
}

/// Java `(int) d` for a double: NaN gives 0, out-of-range saturates.
int d2i(double d) {
  if (d.isNaN) return 0;
  if (d >= 2147483647.0) return intMaxValue;
  if (d <= -2147483648.0) return intMinValue;
  return d.truncate();
}

/// Java `(long) d` for a double: NaN gives 0, out-of-range saturates.
int d2l(double d) {
  if (d.isNaN) return 0;
  if (d >= 9223372036854775807.0) return longMaxValue;
  if (d <= -9223372036854775808.0) return longMinValue;
  return d.truncate();
}

final ByteData _bits = ByteData(8);

/// `Double.doubleToRawLongBits`.
int doubleToRawLongBits(double d) {
  _bits.setFloat64(0, d, Endian.big);
  return _bits.getInt64(0, Endian.big);
}

/// `Double.longBitsToDouble`.
double longBitsToDouble(int bits) {
  _bits.setInt64(0, bits, Endian.big);
  return _bits.getFloat64(0, Endian.big);
}

/// `Math.round(double)` as implemented by OpenJDK (the bit-twiddling version
/// that returns 0 for 0.49999999999999994, not `floor(x + 0.5)`).
int javaRound(double a) {
  const significandWidth = 53;
  const expBias = 1023;
  const expBitMask = 0x7FF0000000000000;
  const signifBitMask = 0x000FFFFFFFFFFFFF;
  final longBits = doubleToRawLongBits(a);
  final biasedExp = (longBits & expBitMask) >> (significandWidth - 1);
  final shift = (significandWidth - 2 + expBias) - biasedExp;
  if ((shift & -64) == 0) {
    var r = (longBits & signifBitMask) | (signifBitMask + 1);
    if (longBits < 0) r = -r;
    return ((r >> shift) + 1) >> 1;
  }
  return d2l(a);
}

/// `Math.toDegrees` (OpenJDK 9+ multiplies by this constant).
double toDegrees(double angrad) => angrad * 57.29577951308232;

/// `Math.toRadians`.
double toRadians(double angdeg) => angdeg * 0.017453292519943295;

/// Thrown where Java would throw `java.io.EOFException`.
class EofException implements Exception {
  @override
  String toString() => 'EOFException';
}

/// The subset of `java.io.DataInputStream` the runtime uses, over an in-memory
/// byte array (the JVM version wraps an arbitrary `InputStream`).
class DataInputStream {
  DataInputStream(this._ab, [this._pos = 0]);

  final Uint8List _ab;
  int _pos;

  /// `InputStream.read()`: the next unsigned byte, or -1 at end of stream.
  int read() => _pos < _ab.length ? _ab[_pos++] : -1;

  int readUnsignedByte() {
    if (_pos >= _ab.length) throw EofException();
    return _ab[_pos++];
  }

  /// Signed, like Java's `byte`.
  int readByte() => readUnsignedByte().toSigned(8);

  bool readBoolean() => readUnsignedByte() != 0;

  int readShort() =>
      ((readUnsignedByte() << 8) | readUnsignedByte()).toSigned(16);

  int readInt() {
    final i3 = readUnsignedByte();
    final i2 = readUnsignedByte();
    final i1 = readUnsignedByte();
    final i0 = readUnsignedByte();
    return ((i3 << 24) | (i2 << 16) | (i1 << 8) | i0).toSigned(32);
  }

  int readLong() {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | readUnsignedByte();
    }
    return v;
  }

  void readFully(Uint8List ta) {
    if (_pos + ta.length > _ab.length) throw EofException();
    ta.setRange(0, ta.length, _ab, _pos);
    _pos += ta.length;
  }

  int available() => _ab.length - _pos;
}

/// The subset of `java.io.DataOutputStream` the runtime uses, writing into an
/// in-memory buffer. Big-endian, like Java.
class DataOutputStream {
  final BytesBuilder _out = BytesBuilder(copy: false);

  /// `DataOutputStream.size()`: bytes written so far.
  int size() => _out.length;

  void write(int b) => _out.addByte(b & 0xff);

  void writeByte(int v) => _out.addByte(v & 0xff);

  void writeBoolean(bool v) => _out.addByte(v ? 1 : 0);

  void writeShort(int v) {
    _out.addByte((v >> 8) & 0xff);
    _out.addByte(v & 0xff);
  }

  void writeInt(int v) {
    _out.addByte((v >> 24) & 0xff);
    _out.addByte((v >> 16) & 0xff);
    _out.addByte((v >> 8) & 0xff);
    _out.addByte(v & 0xff);
  }

  void writeLong(int v) {
    for (var s = 56; s >= 0; s -= 8) {
      _out.addByte((v >> s) & 0xff);
    }
  }

  void writeBytes(Uint8List sa, [int offset = 0, int? len]) {
    _out.add(Uint8List.sublistView(sa, offset, offset + (len ?? sa.length)));
  }

  /// The bytes written so far (a copy).
  Uint8List toByteArray() => _out.toBytes();
}

/// A binary heap with `java.util.PriorityQueue` semantics for a total order:
/// [poll] always returns the least element under [compare].
class PriorityQueue<T> {
  PriorityQueue(this.compare);

  final int Function(T a, T b) compare;
  final List<T> _heap = <T>[];

  int get length => _heap.length;

  bool get isEmpty => _heap.isEmpty;

  void add(T e) {
    _heap.add(e);
    var k = _heap.length - 1;
    while (k > 0) {
      final parent = (k - 1) >> 1;
      if (compare(_heap[parent], _heap[k]) <= 0) break;
      final t = _heap[parent];
      _heap[parent] = _heap[k];
      _heap[k] = t;
      k = parent;
    }
  }

  void addAll(Iterable<T> es) => es.forEach(add);

  T? poll() {
    if (_heap.isEmpty) return null;
    final res = _heap[0];
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      var k = 0;
      final n = _heap.length;
      for (;;) {
        final l = 2 * k + 1;
        if (l >= n) break;
        final r = l + 1;
        var c = l;
        if (r < n && compare(_heap[r], _heap[l]) < 0) c = r;
        if (compare(_heap[k], _heap[c]) <= 0) break;
        final t = _heap[k];
        _heap[k] = _heap[c];
        _heap[c] = t;
        k = c;
      }
    }
    return res;
  }
}
