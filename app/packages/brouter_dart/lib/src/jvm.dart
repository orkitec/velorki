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

/// `Short.MIN_VALUE` (BRouter's "no elevation" marker).
const int shortMinValue = -32768;

/// `Float.MAX_VALUE`.
const double floatMaxValue = 3.4028234663852886e38;

/// `Long.MAX_VALUE` / `Long.MIN_VALUE`.
const int longMaxValue = 0x7fffffffffffffff;
const int longMinValue = -0x8000000000000000;

final Float32List _f32 = Float32List(1);

/// Java `float` round trip: `(double) (float) v`.
double f32(double v) {
  _f32[0] = v;
  return _f32[0];
}

/// The same round trip through a buffer held in a local: a top-level
/// `final` is lazily initialised and every access re-checks that (about
/// 1.2 ns per call in AOT, measured in R5); the hot float paths fetch
/// `RoutingContext.f32buf` once per section instead.
extension FloatRounding on Float32List {
  double f32(double v) {
    this[0] = v;
    return this[0];
  }
}

/// Java `(int) d` for a double: NaN gives 0, out-of-range saturates.
/// (The saturation checks come first: a NaN fails both, and `isNaN` on the
/// common path was measurably slower in AOT -- R5.)
int d2i(double d) {
  if (d >= 2147483647.0) return intMaxValue;
  if (d <= -2147483648.0) return intMinValue;
  if (d.isNaN) return 0;
  return d.truncate();
}

/// Java `(long) d` for a double: NaN gives 0, out-of-range saturates.
int d2l(double d) {
  if (d.isNaN) return 0;
  if (d >= 9223372036854775807.0) return longMaxValue;
  if (d <= -9223372036854775808.0) return longMinValue;
  return d.truncate();
}

// Two views of one 8-byte buffer (host endianness on both sides, so the bit
// pattern is exact; the explicit big-endian `ByteData` round trip of R1 did
// the same with two byte swaps per call -- `javaRound` is on the hot path).
final Float64List _bitsAsDouble = Float64List(1);
final Int64List _bitsAsInt = Int64List.view(_bitsAsDouble.buffer);

/// `Double.doubleToRawLongBits`.
int doubleToRawLongBits(double d) {
  _bitsAsDouble[0] = d;
  return _bitsAsInt[0];
}

/// `Double.longBitsToDouble`.
double longBitsToDouble(int bits) {
  _bitsAsInt[0] = bits;
  return _bitsAsDouble[0];
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

/// `Double.doubleToLongBits` (a NaN is canonicalised to 0x7ff8000000000000).
int doubleToLongBits(double d) =>
    d.isNaN ? 0x7ff8000000000000 : doubleToRawLongBits(d);

/// `Double.compare`: -0.0 sorts before 0.0 and NaN after everything.
int javaDoubleCompare(double d1, double d2) {
  if (d1 < d2) return -1;
  if (d1 > d2) return 1;
  final thisBits = doubleToLongBits(d1);
  final anotherBits = doubleToLongBits(d2);
  return thisBits == anotherBits ? 0 : (thisBits < anotherBits ? -1 : 1);
}

/// Thrown where Java would throw `java.io.IOException`.
class IOException implements Exception {
  IOException(this.message);

  final String message;

  @override
  String toString() => 'IOException: $message';
}

/// Thrown where Java would throw `java.io.EOFException`.
class EofException extends IOException {
  EofException() : super('EOFException');

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

  /// `DataInput.readDouble`.
  double readDouble() => longBitsToDouble(readLong());

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

  /// `DataOutput.writeDouble`.
  void writeDouble(double v) => writeLong(doubleToLongBits(v));

  /// `DataOutput.writeBytes(String)`: the low byte of every char.
  void writeStringBytes(String s) {
    for (final c in s.codeUnits) {
      _out.addByte(c & 0xff);
    }
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

class _JEntry<K, V> {
  _JEntry(this.hash, this.key, this.value);

  final int hash;
  final K key;
  V value;
  _JEntry<K, V>? next;
}

/// A hash map with the iteration order of `java.util.HashMap` (bucket order,
/// insertion order inside a bucket, buckets split in place on resize).
///
/// Only [values] depends on it, but `OsmNodesMap.collectOutreachers` walks the
/// hollow-node map in that order and its `nodesCreated` count depends on the
/// order (which links are already gone when a node is reached). Bins with
/// eight or more entries, which the JDK converts into red-black trees whose
/// `next` order then depends on identity hash codes, are not emulated: their
/// order is not reproducible between two JVM runs either.
///
/// The two functions stand in for the key's `hashCode()` (must return a Java
/// `int`) and `equals()`.
class JavaHashMap<K, V> {
  JavaHashMap(int initialCapacity, this._hashCode, this._equals)
    : _threshold = _tableSizeFor(initialCapacity);

  final int Function(K key) _hashCode;
  final bool Function(K a, K b) _equals;
  List<_JEntry<K, V>?>? _table;
  int _size = 0;
  int _threshold;

  int get length => _size;

  static int _tableSizeFor(int cap) {
    var n = 1;
    while (n < cap) {
      n <<= 1;
    }
    return n;
  }

  int _hash(K key) {
    final h = i32(_hashCode(key));
    return h ^ ushr32(h, 16);
  }

  V? get(K key) {
    final tab = _table;
    if (tab == null) return null;
    final hash = _hash(key);
    var e = tab[(tab.length - 1) & hash];
    while (e != null) {
      if (e.hash == hash && _equals(e.key, key)) return e.value;
      e = e.next;
    }
    return null;
  }

  /// Returns the previous value for an equal key (the stored key is kept).
  V? put(K key, V value) {
    final tab = _table ?? _resize();
    final hash = _hash(key);
    final i = (tab.length - 1) & hash;
    var e = tab[i];
    if (e == null) {
      tab[i] = _JEntry(hash, key, value);
    } else {
      for (;;) {
        if (e!.hash == hash && _equals(e.key, key)) {
          final old = e.value;
          e.value = value;
          return old;
        }
        if (e.next == null) {
          e.next = _JEntry(hash, key, value);
          break;
        }
        e = e.next;
      }
    }
    if (++_size > _threshold) _resize();
    return null;
  }

  V? remove(K key) {
    final tab = _table;
    if (tab == null) return null;
    final hash = _hash(key);
    final i = (tab.length - 1) & hash;
    _JEntry<K, V>? prev;
    var e = tab[i];
    while (e != null) {
      if (e.hash == hash && _equals(e.key, key)) {
        if (prev == null) {
          tab[i] = e.next;
        } else {
          prev.next = e.next;
        }
        _size--;
        return e.value;
      }
      prev = e;
      e = e.next;
    }
    return null;
  }

  List<_JEntry<K, V>?> _resize() {
    final oldTab = _table;
    final oldCap = oldTab == null ? 0 : oldTab.length;
    final oldThr = _threshold;
    int newCap;
    var newThr = 0;
    if (oldCap > 0) {
      newCap = oldCap << 1;
      if (oldCap >= 16) newThr = oldThr << 1;
    } else if (oldThr > 0) {
      newCap = oldThr;
    } else {
      newCap = 16;
      newThr = 12;
    }
    if (newThr == 0) newThr = (newCap * 0.75).toInt();
    _threshold = newThr;
    final newTab = List<_JEntry<K, V>?>.filled(newCap, null);
    _table = newTab;
    if (oldTab != null) {
      for (var j = 0; j < oldCap; j++) {
        var e = oldTab[j];
        if (e == null) continue;
        oldTab[j] = null;
        if (e.next == null) {
          newTab[e.hash & (newCap - 1)] = e;
          continue;
        }
        _JEntry<K, V>? loHead, loTail, hiHead, hiTail;
        do {
          final next = e!.next;
          if ((e.hash & oldCap) == 0) {
            if (loTail == null) {
              loHead = e;
            } else {
              loTail.next = e;
            }
            loTail = e;
          } else {
            if (hiTail == null) {
              hiHead = e;
            } else {
              hiTail.next = e;
            }
            hiTail = e;
          }
          e = next;
        } while (e != null);
        if (loTail != null) {
          loTail.next = null;
          newTab[j] = loHead;
        }
        if (hiTail != null) {
          hiTail.next = null;
          newTab[j + oldCap] = hiHead;
        }
      }
    }
    return newTab;
  }

  /// `values()` in `HashMap` iteration order.
  Iterable<V> get values sync* {
    final tab = _table;
    if (tab == null) return;
    for (var i = 0; i < tab.length; i++) {
      var e = tab[i];
      while (e != null) {
        yield e.value;
        e = e.next;
      }
    }
  }

  /// `entrySet()` in `HashMap` iteration order.
  Iterable<MapEntry<K, V>> get entries sync* {
    final tab = _table;
    if (tab == null) return;
    for (var i = 0; i < tab.length; i++) {
      var e = tab[i];
      while (e != null) {
        yield MapEntry<K, V>(e.key, e.value);
        e = e.next;
      }
    }
  }

  /// `keySet()` in `HashMap` iteration order.
  Iterable<K> get keys => entries.map((e) => e.key);

  bool containsKey(K key) {
    final tab = _table;
    if (tab == null) return false;
    final hash = _hash(key);
    var e = tab[(tab.length - 1) & hash];
    while (e != null) {
      if (e.hash == hash && _equals(e.key, key)) return true;
      e = e.next;
    }
    return false;
  }

  /// A `HashMap<String, V>` with `String.hashCode`/`equals`.
  static JavaHashMap<String, V> ofStrings<V>([int initialCapacity = 16]) =>
      JavaHashMap<String, V>(
        initialCapacity,
        javaStringHashCode,
        (a, b) => a == b,
      );
}

/// `String.hashCode()`: `s[0]*31^(n-1) + ... + s[n-1]` over the UTF-16 code
/// units, wrapping to a Java `int`.
int javaStringHashCode(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (31 * h + c).toSigned(32);
  }
  return h;
}
