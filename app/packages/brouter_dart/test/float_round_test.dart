// The two implementations of `(double) (float) v` (float_round_vm.dart and
// float_round_web.dart) give the same bits: every route depends on it, and
// only one of the two is compiled into any given build.

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:brouter_dart/src/float_round_vm.dart' as vm;
import 'package:brouter_dart/src/float_round_web.dart' as web;
import 'package:brouter_dart/src/jvm.dart';
import 'package:test/test.dart';

final _bits = ByteData(8);

int _rawBits(double v) {
  _bits.setFloat64(0, v);
  return _bits.getInt64(0);
}

double _fromBits(int bits) {
  _bits.setInt64(0, bits);
  return _bits.getFloat64(0);
}

void _expectSame(double v) {
  final buffer = Float32List(1);
  final expected = web.roundToFloat(v);
  for (final actual in [
    vm.roundToFloat(v),
    vm.roundToFloatVia(buffer, v),
    web.roundToFloatVia(buffer, v),
    f32(v),
    buffer.f32(v),
  ]) {
    if (expected.isNaN) {
      expect(actual.isNaN, isTrue, reason: 'for $v');
    } else {
      expect(
        _rawBits(actual),
        _rawBits(expected),
        reason: 'for $v (0x${_rawBits(v).toRadixString(16)})',
      );
    }
  }
}

void main() {
  test('special values round the same', () {
    const floatMax = 3.4028234663852886e38;
    const floatMinNormal = 1.1754943508222875e-38;
    const floatMinSubnormal = 1.401298464324817e-45;
    for (final v in [
      0.0,
      -0.0,
      1.0,
      -1.0,
      0.1,
      1 / 3,
      double.nan,
      double.infinity,
      double.negativeInfinity,
      double.maxFinite,
      -double.maxFinite,
      double.minPositive,
      floatMax,
      -floatMax,
      // The largest double that still rounds down to Float.MAX_VALUE, and
      // the first that overflows to infinity.
      3.4028235677973362e38,
      3.4028235677973366e38,
      floatMinNormal,
      floatMinNormal / 2,
      floatMinSubnormal,
      // Half of the smallest subnormal ties to even (0), just above it
      // rounds up.
      floatMinSubnormal / 2,
      7.006492321624087e-46,
      16777216.0,
      // Ties between two floats: to even, both ways.
      16777217.0,
      16777219.0,
      2000000000.0,
      1e-7,
    ]) {
      _expectSame(v);
      _expectSame(-v);
    }
  });

  test('ties and near-ties around floats round the same', () {
    // Every double one ulp either side of the midpoint between two
    // neighbouring floats, over the exponents the cost arithmetic sees.
    for (var e = -30; e <= 40; e++) {
      for (var m = 0; m < 64; m++) {
        final lower = (1 + m / 8388608) * _pow2(e);
        final step = _pow2(e - 23);
        final mid = lower + step / 2;
        final midBits = _rawBits(mid);
        for (var d = -2; d <= 2; d++) {
          _expectSame(_fromBits(midBits + d));
        }
      }
    }
  });

  test('two million random bit patterns round the same', () {
    var seed = 0x2545F4914F6CDD1D;
    for (var i = 0; i < 2000000; i++) {
      seed ^= seed << 13;
      seed ^= seed >>> 7;
      seed ^= seed << 17;
      _expectSame(_fromBits(seed));
    }
  });

  test('values in the range of costs and distances round the same', () {
    var seed = 0x9E3779B97F4A7C15;
    for (var i = 0; i < 1000000; i++) {
      seed ^= seed << 13;
      seed ^= seed >>> 7;
      seed ^= seed << 17;
      final unit = (seed >>> 11) / 9007199254740992.0;
      _expectSame((unit - 0.5) * 4e9);
      _expectSame(unit * 1e-3);
    }
  });
}

double _pow2(int e) {
  var v = 1.0;
  for (var i = 0; i < e.abs(); i++) {
    v = e > 0 ? v * 2 : v / 2;
  }
  return v;
}
