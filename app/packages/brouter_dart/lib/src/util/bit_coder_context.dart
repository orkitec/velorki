// Port of btools.util.BitCoderContext (BRouter v1.7.10).

import 'dart:typed_data';

import '../jvm.dart';

/// R5 note on the buffer word `_b`: upstream keeps it in a Java `int`. In
/// read mode it never holds more than 31 valid bits (`fillBuffer` stops at
/// 24..31 bits, `decodeBit` refills with 8), so it is never negative and every
/// `>>>` is a plain `>>`, every `int` wrap a no-op; the decoders below use
/// plain 64-bit arithmetic with the same results. In write mode `_b` can use
/// all 32 bits, so the encoders keep it as an unsigned 32-bit value
/// (`& 0xffffffff` where upstream wraps) and `_flushBuffer` shifts unsigned.
class BitCoderContext {
  BitCoderContext(Uint8List ab)
    : _ab = ab,
      _idxMax = ab.length - 1,
      _vlValues = _tables.vlValues,
      _vlLength = _tables.vlLength,
      _vcValues = _tables.vcValues,
      _vcLength = _tables.vcLength,
      _reverseByte = _tables.reverseByte;

  /// The context `_Tables._build` uses while the tables are being built
  /// (the table-free `encodeVarBits2`/`decodeVarBits2` only).
  BitCoderContext._forTables(Uint8List ab, _Tables t)
    : _ab = ab,
      _idxMax = ab.length - 1,
      _vlValues = t.vlValues,
      _vlLength = t.vlLength,
      _vcValues = t.vcValues,
      _vcLength = t.vcLength,
      _reverseByte = t.reverseByte;

  Uint8List _ab;
  int _idxMax;
  int _idx = -1;
  int _bits = 0; // bits left in buffer
  int _b = 0; // buffer word (a Java int, see above)

  // the lookup tables, held per instance so the hot decoders skip the lazy
  // static initialisation check
  final Int32List _vlValues;
  final Int32List _vlLength;
  final Int32List _vcValues;
  final Int32List _vcLength;
  final Int32List _reverseByte;

  /// The lookup tables of the Java static initializer. Built together on the
  /// first access of any of them (Java initialises the class eagerly; Dart
  /// statics are lazy, and `MixCoderDataInputStream` reads [vlValues] without
  /// ever constructing a `BitCoderContext`).
  static final _Tables _tables = _Tables._build();

  static Int32List get vlValues => _tables.vlValues;
  static Int32List get vlLength => _tables.vlLength;

  /// `reset()` and `reset(byte[] ab)`.
  void reset([Uint8List? ab]) {
    if (ab != null) {
      _ab = ab;
      _idxMax = ab.length - 1;
    }
    _idx = -1;
    _bits = 0;
    _b = 0;
  }

  /// encode a distance with a variable bit length
  /// (poor mans huffman tree)
  /// `1 -> 0`
  /// `01 -> 1` + following 1-bit word ( 1..2 )
  /// `001 -> 3` + following 2-bit word ( 3..6 )
  /// `0001 -> 7` + following 3-bit word ( 7..14 ) etc.
  void encodeVarBits2(int value) {
    var range = 0;
    while (value > range) {
      encodeBit(false);
      value = i32(value - (range + 1));
      range = i32(2 * range + 1);
    }
    encodeBit(true);
    encodeBounded(range, value);
  }

  void encodeVarBits(int value) {
    if ((value & 0xfff) == value) {
      _flushBuffer();
      _b = (_b | (_vcValues[value] << _bits)) & 0xffffffff;
      _bits += _vcLength[value];
    } else {
      encodeVarBits2(value); // slow fallback for large values
    }
  }

  int decodeVarBits2() {
    var range = 0;
    while (!decodeBit()) {
      range = i32(2 * range + 1);
    }
    return i32(range + decodeBounded(range));
  }

  int decodeVarBits() {
    _fillBuffer();
    final b12 = _b & 0xfff;
    final len = _vlLength[b12];
    if (len <= 12) {
      _b >>= len;
      _bits -= len;
      return _vlValues[b12]; // full value lookup
    }
    if (len <= 23) {
      // only length lookup
      final len2 = len >> 1;
      _b >>= len2 + 1;
      var mask = (1 << len2) - 1; // -1 >>> (32 - len2), len2 in 6..11
      mask = i32(mask + (_b & mask));
      _b >>= len2;
      _bits -= len;
      return mask;
    }
    if ((_b & 0xffffff) != 0) {
      // here we just know len in [25..47]
      // ( fillBuffer guarantees only 24 bits! )
      _b >>= 12;
      final len3 = 1 + (_vlLength[_b & 0xfff] >> 1);
      _b >>= len3;
      final len2 = 11 + len3;
      _bits -= len2 + 1;
      _fillBuffer();
      var mask = (1 << len2) - 1; // -1 >>> (32 - len2), len2 in 12..23
      mask = i32(mask + (_b & mask));
      _b >>= len2;
      _bits -= len2;
      return mask;
    }
    return decodeVarBits2(); // no chance, use the slow one
  }

  void encodeBit(bool value) {
    if (_bits > 31) {
      _ab[++_idx] = _b & 0xff;
      _b >>= 8;
      _bits -= 8;
    }
    if (value) {
      _b = (_b | (1 << _bits)) & 0xffffffff;
    }
    _bits++;
  }

  bool decodeBit() {
    if (_bits == 0) {
      _bits = 8;
      _b = _ab[++_idx];
    }
    final value = (_b & 1) != 0;
    _b >>= 1;
    _bits--;
    return value;
  }

  /// encode an integer in the range 0..max (inclusive).
  /// For max = 2^n-1, this just encodes n bits, but in general
  /// this is variable length encoding, with the shorter codes
  /// for the central value range
  void encodeBounded(int max, int value) {
    var im = 1; // integer mask
    while (im <= max) {
      if ((value & im) != 0) {
        encodeBit(true);
        max = i32(max - im);
      } else {
        encodeBit(false);
      }
      im = shl32(im, 1);
    }
  }

  /// decode an integer in the range 0..max (inclusive).
  int decodeBounded(int max) {
    var value = 0;
    var im = 1; // integer mask
    while ((value | im) <= max) {
      if (_bits == 0) {
        _bits = 8;
        _b = _ab[++_idx];
      }
      if ((_b & 1) != 0) value |= im;
      _b >>= 1;
      _bits--;
      im = shl32(im, 1);
    }
    return value;
  }

  int decodeBits(int count) {
    _fillBuffer();
    final mask = 0xffffffff >> ((32 - count) & 31); // -1 >>> (32 - count)
    final value = _b & mask;
    _b >>= count;
    _bits -= count;
    return value;
  }

  int decodeBitsReverse(int count) {
    _fillBuffer();
    var value = 0;
    while (count > 8) {
      value = i32(shl32(value, 8) | _reverseByte[_b & 0xff]);
      _b >>= 8;
      count -= 8;
      _bits -= 8;
      _fillBuffer();
    }
    value = i32(shl32(value, count) | (_reverseByte[_b & 0xff] >> (8 - count)));
    _bits -= count;
    _b >>= count;
    return value;
  }

  void _fillBuffer() {
    while (_bits < 24) {
      if (_idx++ < _idxMax) {
        _b |= _ab[_idx] << _bits;
      }
      _bits += 8;
    }
  }

  void _flushBuffer() {
    while (_bits > 7) {
      _ab[++_idx] = _b & 0xff;
      _b >>= 8;
      _bits -= 8;
    }
  }

  /// flushes and closes the (write-mode) context
  ///
  /// Returns the encoded length in bytes
  int closeAndGetEncodedLength() {
    _flushBuffer();
    if (_bits > 0) {
      _ab[++_idx] = _b & 0xff;
    }
    return _idx + 1;
  }

  /// Returns the encoded length in bits
  int getWritingBitPosition() {
    return (_idx << 3) + 8 + _bits;
  }

  int getReadingBitPosition() {
    return (_idx << 3) + 8 - _bits;
  }

  void setReadingBitPosition(int pos) {
    _idx = ushr32(pos, 3);
    _bits = (_idx << 3) + 8 - pos;
    _b = _ab[_idx];
    _b >>= 8 - _bits;
  }
}

class _Tables {
  _Tables._();

  final Int32List vlValues = Int32List(4096);
  final Int32List vlLength = Int32List(4096);
  final Int32List vcValues = Int32List(4096);
  final Int32List vcLength = Int32List(4096);
  final Int32List reverseByte = Int32List(256);
  final Int32List bm2bits = Int32List(256);

  /// The static initializer of the Java class: fill the varbits lookup tables.
  /// Only the table-free `encodeVarBits2`/`decodeVarBits2` are used here.
  static _Tables _build() {
    final t = _Tables._();
    final bc = BitCoderContext._forTables(Uint8List(4), t);
    for (var i = 0; i < 4096; i++) {
      bc.reset();
      bc._bits = 14;
      bc._b = 0x1000 + i;

      final b0 = bc.getReadingBitPosition();
      t.vlValues[i] = bc.decodeVarBits2();
      t.vlLength[i] = bc.getReadingBitPosition() - b0;
    }
    for (var i = 0; i < 4096; i++) {
      bc.reset();
      final b0 = bc.getWritingBitPosition();
      bc.encodeVarBits2(i);
      t.vcValues[i] = bc._b;
      t.vcLength[i] = bc.getWritingBitPosition() - b0;
    }
    for (var i = 0; i < 1024; i++) {
      bc.reset();
      bc._bits = 14;
      bc._b = 0x1000 + i;

      final b0 = bc.getReadingBitPosition();
      t.vlValues[i] = bc.decodeVarBits2();
      t.vlLength[i] = bc.getReadingBitPosition() - b0;
    }
    for (var b = 0; b < 256; b++) {
      var r = 0;
      for (var i = 0; i < 8; i++) {
        if ((b & (1 << i)) != 0) r |= 1 << (7 - i);
      }
      t.reverseByte[b] = r;
    }
    for (var b = 0; b < 8; b++) {
      t.bm2bits[1 << b] = b;
    }
    return t;
  }
}
