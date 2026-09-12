// Port of btools.util.MixCoderDataOutputStream (BRouter v1.7.10).
//
// DataOutputStream for fast-compact encoding of number sequences

import 'dart:typed_data';

import '../jvm.dart';

class MixCoderDataOutputStream extends DataOutputStream {
  MixCoderDataOutputStream();

  int _lastValue = 0;
  int _lastLastValue = 0;
  int _repCount = 0;
  int _diffshift = 0;

  int _bm = 1; // byte mask (write mode)
  int _b = 0;

  static final Int32List diffs = Int32List(100);
  static final Int32List counts = Int32List(100);

  void writeMixed(int v) {
    if (v != _lastValue && _repCount > 0) {
      var d = i32(_lastValue - _lastLastValue);
      _lastLastValue = _lastValue;

      encodeBit(d < 0);
      if (d < 0) {
        d = i32(-d);
      }
      encodeVarBits(i32(d - _diffshift));
      encodeVarBits(_repCount - 1);

      if (d < 100) diffs[d]++;
      if (_repCount < 100) counts[_repCount]++;

      _diffshift = 1;
      _repCount = 0;
    }
    _lastValue = v;
    _repCount++;
  }

  void flush() {
    final v = _lastValue;
    writeMixed(i32(v + 1));
    _lastValue = v;
    _repCount = 0;
    if (_bm > 1) {
      writeByte(toByte(_b)); // flush bit-coding
    }
  }

  void encodeBit(bool value) {
    if (_bm == 0x100) {
      writeByte(toByte(_b));
      _bm = 1;
      _b = 0;
    }
    if (value) {
      _b |= _bm;
    }
    _bm <<= 1;
  }

  void encodeVarBits(int value) {
    var range = 0;
    while (value > range) {
      encodeBit(false);
      value = i32(value - (range + 1));
      range = i32(2 * range + 1);
    }
    encodeBit(true);
    encodeBounded(range, value);
  }

  void encodeBounded(int max, int value) {
    var im = 1; // integer mask
    while (im <= max) {
      if (_bm == 0x100) {
        writeByte(toByte(_b));
        _bm = 1;
        _b = 0;
      }
      if ((value & im) != 0) {
        _b |= _bm;
        max = i32(max - im);
      }
      _bm <<= 1;
      im = shl32(im, 1);
    }
  }

  /// The JVM version prints `diffs`/`counts`; here they are returned.
  static String stats() {
    final sb = StringBuffer();
    for (var i = 1; i < 100; i++) {
      sb.writeln('diff[$i] = ${diffs[i]}');
    }
    for (var i = 1; i < 100; i++) {
      sb.writeln('counts[$i] = ${counts[i]}');
    }
    return sb.toString();
  }
}
