// Port of btools.util.MixCoderDataInputStream (BRouter v1.7.10).
//
// DataInputStream for decoding fast-compact encoded number sequences

import 'dart:typed_data';

import '../jvm.dart';
import 'bit_coder_context.dart';

class MixCoderDataInputStream extends DataInputStream {
  MixCoderDataInputStream(super.ab);

  int _lastValue = 0;
  int _repCount = 0;
  int _diffshift = 0;

  int _bits = 0; // bits left in buffer
  int _b = 0; // buffer word

  static final Int32List _vlValues = BitCoderContext.vlValues;
  static final Int32List _vlLength = BitCoderContext.vlLength;

  int readMixed() {
    if (_repCount == 0) {
      final negative = decodeBit();
      final d = i32(decodeVarBits() + _diffshift);
      _repCount = i32(decodeVarBits() + 1);
      _lastValue = i32(_lastValue + (negative ? -d : d));
      _diffshift = 1;
    }
    _repCount--;
    return _lastValue;
  }

  bool decodeBit() {
    _fillBuffer();
    final value = (_b & 1) != 0;
    _b = ushr32(_b, 1);
    _bits--;
    return value;
  }

  int decodeVarBits2() {
    var range = 0;
    while (!decodeBit()) {
      range = i32(2 * range + 1);
    }
    return i32(range + decodeBounded(range));
  }

  /// decode an integer in the range 0..max (inclusive).
  int decodeBounded(int max) {
    var value = 0;
    var im = 1; // integer mask
    while ((value | im) <= max) {
      if (decodeBit()) {
        value |= im;
      }
      im = shl32(im, 1);
    }
    return value;
  }

  int decodeVarBits() {
    _fillBuffer();
    final b12 = _b & 0xfff;
    final len = _vlLength[b12];
    if (len <= 12) {
      _b = ushr32(_b, len);
      _bits -= len;
      return _vlValues[b12]; // full value lookup
    }
    if (len <= 23) {
      // only length lookup
      final len2 = len >> 1;
      _b = ushr32(_b, len2 + 1);
      var mask = ushr32(-1, 32 - len2);
      mask = i32(mask + (_b & mask));
      _b = ushr32(_b, len2);
      _bits -= len;
      return mask;
    }
    if ((_b & 0xffffff) != 0) {
      // here we just know len in [25..47]
      // ( fillBuffer guarantees only 24 bits! )
      _b = ushr32(_b, 12);
      final len3 = 1 + (_vlLength[_b & 0xfff] >> 1);
      _b = ushr32(_b, len3);
      final len2 = 11 + len3;
      _bits -= len2 + 1;
      _fillBuffer();
      var mask = ushr32(-1, 32 - len2);
      mask = i32(mask + (_b & mask));
      _b = ushr32(_b, len2);
      _bits -= len2;
      return mask;
    }
    return decodeVarBits2(); // no chance, use the slow one
  }

  void _fillBuffer() {
    while (_bits < 24) {
      final nextByte = read();

      if (nextByte != -1) {
        _b = i32(_b | shl32(nextByte & 0xff, _bits));
      }
      _bits += 8;
    }
  }
}
