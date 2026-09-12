/// Java `float` <-> `String` conversions with the exact results of JDK 17.
///
/// The expressions module parses every number of a `.brf` profile with
/// `Float.parseFloat`, prints numeric lookup values with `Float.toString`
/// (`BExpressionContext.getKeyValueDescription`, which ends up in the routing
/// messages) and formats unit-converted tag values with
/// `String.format(Locale.US, "%3.1f", f)`. None of the three is what Dart's
/// `double.parse` / `toString` / `toStringAsFixed` produce:
///
/// * `Float.parseFloat` rounds the decimal string to the nearest `float`
///   directly. `double.parse` followed by a `float` round trip rounds twice and
///   is off by one ulp when the double lands exactly on a float midpoint.
///   [javaParseFloat] therefore rounds the exact decimal value with `BigInt`
///   arithmetic (the JDK's `ASCIIToBinaryBuffer.floatValue` is correctly
///   rounded too) and implements the JDK grammar (sign, `NaN`, `Infinity`,
///   hex floats, trailing `f`/`F`/`d`/`D`, `String.trim`).
/// * `Float.toString` in JDK 17 is the old `FloatingDecimal.dtoa` algorithm
///   (Steele & White with an "insignificant digits" shortcut), which is not
///   always the shortest representation and predates the JDK 19 rewrite.
///   [javaFloatToString] transcribes `dtoa` (the `int`, `long` and
///   `FDBigInteger` branches are the same exact integer arithmetic, done here
///   with `BigInt`) and `BinaryToASCIIBuffer.getChars`.
/// * `%3.1f` formats the `float` promoted to `double`: `dtoa` on the double
///   bits in non-compatible mode, `FormattedFloatingDecimal.applyPrecision`
///   (half-up on the decimal digits), `fillDecimal` and `Formatter.addZeros`.
///   That is [javaFormatFixed].
///
/// All three are checked bit for bit against `tools/brouter-oracle/dump/
/// run_dump.sh math-vectors` (`test/vectors/expressions/float.json`).
library;

import 'dart:typed_data';

import 'jvm.dart';

final Float32List _f32buf = Float32List(1);
final Int32List _f32bits = _f32buf.buffer.asInt32List();

/// `Float.floatToRawIntBits((float) v)`.
int floatToRawIntBits(double v) {
  _f32buf[0] = v;
  return _f32bits[0];
}

/// `Float.floatToIntBits((float) v)`: every NaN is 0x7fc00000.
int floatToIntBits(double v) => v.isNaN ? 0x7fc00000 : floatToRawIntBits(v);

/// `Float.intBitsToFloat(bits)` as a double holding the float value.
double intBitsToFloat(int bits) {
  _f32bits[0] = bits.toSigned(32);
  return _f32buf[0];
}

/// `Arrays.hashCode(float[])`.
int arraysHashCodeFloat(Float32List a) {
  var result = 1;
  for (var i = 0; i < a.length; i++) {
    result = i32(31 * result + floatToIntBits(a[i]));
  }
  return result;
}

/// Thrown where Java throws `java.lang.NumberFormatException`.
class NumberFormatException implements Exception {
  NumberFormatException(this.message);

  final String message;

  @override
  String toString() => 'NumberFormatException: $message';
}

// ---------------------------------------------------------------------------
// Float.parseFloat
// ---------------------------------------------------------------------------

/// `Float.parseFloat(s)`: the JDK grammar, correctly rounded to `float`.
///
/// Throws [NumberFormatException] like the JDK.
double javaParseFloat(String input) {
  final s = javaTrim(input);
  final len = s.length;
  if (len == 0) throw NumberFormatException('empty String');
  var i = 0;
  var isNegative = false;
  var signSeen = false;
  final c0 = s.codeUnitAt(0);
  if (c0 == 0x2d /* - */ || c0 == 0x2b /* + */ ) {
    isNegative = c0 == 0x2d;
    signSeen = true;
    i++;
  }
  if (i >= len) throw NumberFormatException('For input string: "$input"');
  final c = s.codeUnitAt(i);
  if (c == 0x4e /* N */ ) {
    if (s.substring(i) == 'NaN') return double.nan;
    throw NumberFormatException('For input string: "$input"');
  }
  if (c == 0x49 /* I */ ) {
    if (s.substring(i) == 'Infinity') {
      return isNegative ? double.negativeInfinity : double.infinity;
    }
    throw NumberFormatException('For input string: "$input"');
  }
  if (c == 0x30 /* 0 */ && len > i + 1) {
    final ch = s.codeUnitAt(i + 1);
    if (ch == 0x78 /* x */ || ch == 0x58 /* X */ ) {
      return _parseHexFloat(s, i + 2, isNegative, input);
    }
  }

  // decimal
  final digits = StringBuffer();
  var decSeen = false;
  var nDigits = 0;
  var decPt = 0;
  var nLeadZero = 0;
  var nTrailZero = 0;
  while (i < len) {
    final ch = s.codeUnitAt(i);
    if (ch == 0x30) {
      nLeadZero++;
    } else if (ch == 0x2e) {
      if (decSeen) throw NumberFormatException('multiple points');
      decPt = signSeen ? i - 1 : i;
      decSeen = true;
    } else {
      break;
    }
    i++;
  }
  while (i < len) {
    final ch = s.codeUnitAt(i);
    if (ch >= 0x31 && ch <= 0x39) {
      digits.writeCharCode(ch);
      nDigits++;
      nTrailZero = 0;
    } else if (ch == 0x30) {
      digits.writeCharCode(ch);
      nDigits++;
      nTrailZero++;
    } else if (ch == 0x2e) {
      if (decSeen) throw NumberFormatException('multiple points');
      decPt = signSeen ? i - 1 : i;
      decSeen = true;
    } else {
      break;
    }
    i++;
  }
  nDigits -= nTrailZero;
  final isZero = nDigits == 0;
  if (isZero && nLeadZero == 0) {
    throw NumberFormatException('For input string: "$input"');
  }
  int decExp;
  if (decSeen) {
    decExp = decPt - nLeadZero;
  } else {
    decExp = nDigits + nTrailZero;
  }
  if (i < len) {
    final ch = s.codeUnitAt(i);
    if (ch == 0x65 /* e */ || ch == 0x45 /* E */ ) {
      var expSign = 1;
      var expVal = 0;
      var expOverflow = false;
      i++;
      if (i >= len) throw NumberFormatException('For input string: "$input"');
      final sc = s.codeUnitAt(i);
      if (sc == 0x2d) {
        expSign = -1;
        i++;
      } else if (sc == 0x2b) {
        i++;
      }
      final expAt = i;
      while (i < len) {
        if (expVal >= 214748364) expOverflow = true;
        final ec = s.codeUnitAt(i++);
        if (ec >= 0x30 && ec <= 0x39) {
          expVal = expVal * 10 + (ec - 0x30);
          if (expVal > 1000000000) expVal = 1000000000; // keep it finite
        } else {
          i--;
          break;
        }
      }
      if (i == expAt) throw NumberFormatException('For input string: "$input"');
      final expLimit = 324 + nDigits + nTrailZero;
      if (expOverflow || expVal > expLimit) {
        if (!expOverflow &&
            expSign == 1 &&
            decExp < 0 &&
            expVal + decExp < expLimit) {
          decExp += expVal;
        } else {
          decExp = expSign * expLimit;
        }
      } else {
        decExp = decExp + expSign * expVal;
      }
    }
  }
  if (i < len) {
    final ch = s.codeUnitAt(i);
    if (i != len - 1 ||
        (ch != 0x66 && ch != 0x46 && ch != 0x64 && ch != 0x44)) {
      throw NumberFormatException('For input string: "$input"');
    }
  }
  if (isZero) return isNegative ? -0.0 : 0.0;
  // value = 0.d1d2...dn * 10^decExp = D * 10^(decExp - nDigits)
  final mant = BigInt.parse(digits.toString().substring(0, nDigits));
  final e10 = decExp - nDigits;
  // magnitude bounds: nDigits + e10 - 1 is floor(log10) of the value
  if (nDigits + e10 > 40) {
    return isNegative ? double.negativeInfinity : double.infinity;
  }
  if (nDigits + e10 < -46) return isNegative ? -0.0 : 0.0;
  double v;
  if (e10 >= 0) {
    v = _roundRationalToFloat(mant * BigInt.from(10).pow(e10), BigInt.one);
  } else {
    v = _roundRationalToFloat(mant, BigInt.from(10).pow(-e10));
  }
  return isNegative ? -v : v;
}

double _parseHexFloat(String s, int i, bool isNegative, String input) {
  // 0x HexDigits [. HexDigits] p [+-] Digits [fFdD]
  final len = s.length;
  var mant = BigInt.zero;
  var nHex = 0;
  var fracDigits = 0;
  var decSeen = false;
  while (i < len) {
    final ch = s.codeUnitAt(i);
    int d;
    if (ch >= 0x30 && ch <= 0x39) {
      d = ch - 0x30;
    } else if (ch >= 0x61 && ch <= 0x66) {
      d = ch - 0x61 + 10;
    } else if (ch >= 0x41 && ch <= 0x46) {
      d = ch - 0x41 + 10;
    } else if (ch == 0x2e && !decSeen) {
      decSeen = true;
      i++;
      continue;
    } else {
      break;
    }
    mant = mant * BigInt.from(16) + BigInt.from(d);
    nHex++;
    if (decSeen) fracDigits++;
    i++;
  }
  if (nHex == 0 || i >= len) {
    throw NumberFormatException('For input string: "$input"');
  }
  final pc = s.codeUnitAt(i);
  if (pc != 0x70 && pc != 0x50) {
    throw NumberFormatException('For input string: "$input"');
  }
  i++;
  var expSign = 1;
  if (i < len && (s.codeUnitAt(i) == 0x2d || s.codeUnitAt(i) == 0x2b)) {
    if (s.codeUnitAt(i) == 0x2d) expSign = -1;
    i++;
  }
  var expVal = 0;
  var nExp = 0;
  while (i < len) {
    final ch = s.codeUnitAt(i);
    if (ch < 0x30 || ch > 0x39) break;
    expVal = expVal * 10 + (ch - 0x30);
    if (expVal > 100000) expVal = 100000;
    nExp++;
    i++;
  }
  if (nExp == 0) throw NumberFormatException('For input string: "$input"');
  if (i < len) {
    final ch = s.codeUnitAt(i);
    if (i != len - 1 ||
        (ch != 0x66 && ch != 0x46 && ch != 0x64 && ch != 0x44)) {
      throw NumberFormatException('For input string: "$input"');
    }
  }
  if (mant == BigInt.zero) return isNegative ? -0.0 : 0.0;
  final e2 = expSign * expVal - 4 * fracDigits;
  final magnitude = mant.bitLength + e2;
  if (magnitude > 130) {
    return isNegative ? double.negativeInfinity : double.infinity;
  }
  if (magnitude < -152) return isNegative ? -0.0 : 0.0;
  final v = e2 >= 0
      ? _roundRationalToFloat(mant << e2, BigInt.one)
      : _roundRationalToFloat(mant, BigInt.one << -e2);
  return isNegative ? -v : v;
}

/// 2^e as a double for -1022 <= e <= 1023.
double _pow2(int e) => longBitsToDouble((e + 1023) << 52);

/// The float nearest to num/den (num > 0, den > 0), ties to even; infinity
/// on overflow, 0 on underflow, subnormals handled.
double _roundRationalToFloat(BigInt num, BigInt den) {
  var e = num.bitLength - den.bitLength - 24;
  if (e < -149) e = -149;
  BigInt q, r, d;
  for (;;) {
    if (e >= 0) {
      d = den << e;
      q = num ~/ d;
      r = num - q * d;
    } else {
      final n = num << -e;
      d = den;
      q = n ~/ d;
      r = n - q * d;
    }
    if (q.bitLength > 24) {
      e++;
      continue;
    }
    if (q.bitLength < 24 && e > -149) {
      e--;
      continue;
    }
    break;
  }
  final cmp = (r << 1).compareTo(d);
  if (cmp > 0 || (cmp == 0 && q.isOdd)) q += BigInt.one;
  if (q.bitLength > 24) {
    q >>= 1;
    e++;
  }
  if (e > 104) return double.infinity;
  return q.toDouble() * _pow2(e);
}

// ---------------------------------------------------------------------------
// FloatingDecimal.dtoa (JDK 17)
// ---------------------------------------------------------------------------

const int _expShift = 52;
const int _fractHob = 1 << _expShift;
const int _expOne = 1023 << _expShift;
const int _maxSmallBinExp = 62;
const int _minSmallBinExp = -(63 ~/ 3);
const int _signifBitMask = 0x000FFFFFFFFFFFFF;

const List<int> _n5Bits = <int>[
  0, 3, 5, 7, 10, 12, 14, 17, 19, 21, 24, 26, 28, 31, 33, 35, 38, 40, 42, //
  45, 47, 49, 52, 54, 56, 59, 61,
];

const List<int> _insignificantDigitsNumber = <int>[
  0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3, //
  4, 4, 4, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, //
  8, 8, 8, 9, 9, 9, 9, 10, 10, 10, 11, 11, 11, //
  12, 12, 12, 12, 13, 13, 13, 14, 14, 14, //
  15, 15, 15, 15, 16, 16, 16, 17, 17, 17, //
  18, 18, 18, 19,
];

const List<int> _small5Pow = <int>[
  1, 5, 25, 125, 625, 3125, 15625, 78125, 390625, 1953125, 9765625, //
  48828125, 244140625, 1220703125,
];

final List<int> _long5Pow = List<int>.generate(27, (i) {
  var v = 1;
  for (var k = 0; k < i; k++) {
    v *= 5;
  }
  return v;
});

final BigInt _big5 = BigInt.from(5);
final BigInt _big10 = BigInt.from(10);

/// The digit buffer of `BinaryToASCIIBuffer` after `dtoa`.
class _Dtoa {
  bool isNegative = false;
  int decExponent = 0;
  int firstDigitIndex = 0;
  int nDigits = 0;
  final List<int> digits = List<int>.filled(20, 0x30);
  bool decimalDigitsRoundedUp = false;
  bool exactDecimalConversion = false;

  void developLongDigits(int decExponent, int lvalue, int insignificantDigits) {
    if (insignificantDigits != 0) {
      final pow10 = _long5Pow[insignificantDigits] << insignificantDigits;
      final residue = lvalue % pow10;
      lvalue ~/= pow10;
      decExponent += insignificantDigits;
      if (residue >= (pow10 >> 1)) lvalue++;
    }
    var digitno = digits.length - 1;
    var c = lvalue % 10;
    lvalue ~/= 10;
    while (c == 0) {
      decExponent++;
      c = lvalue % 10;
      lvalue ~/= 10;
    }
    while (lvalue != 0) {
      digits[digitno--] = c + 0x30;
      decExponent++;
      c = lvalue % 10;
      lvalue ~/= 10;
    }
    digits[digitno] = c + 0x30;
    this.decExponent = decExponent + 1;
    firstDigitIndex = digitno;
    nDigits = digits.length - digitno;
  }

  void dtoa(
    int binExp,
    int fractBits,
    int nSignificantBits,
    bool isCompatibleFormat,
  ) {
    final tailZeros = _numberOfTrailingZeros64(fractBits);
    final nFractBits = _expShift + 1 - tailZeros;
    decimalDigitsRoundedUp = false;
    exactDecimalConversion = false;
    final nTinyBits = nFractBits - binExp - 1 > 0 ? nFractBits - binExp - 1 : 0;
    if (binExp <= _maxSmallBinExp && binExp >= _minSmallBinExp) {
      if (nTinyBits < _long5Pow.length &&
          (nFractBits + _n5Bits[nTinyBits]) < 64) {
        if (nTinyBits == 0) {
          int insignificant;
          if (binExp > nSignificantBits) {
            insignificant = _insignificantDigitsForPow2(
              binExp - nSignificantBits - 1,
            );
          } else {
            insignificant = 0;
          }
          if (binExp >= _expShift) {
            fractBits <<= binExp - _expShift;
          } else {
            fractBits >>>= _expShift - binExp;
          }
          developLongDigits(0, fractBits, insignificant);
          return;
        }
      }
    }
    var decExp = _estimateDecExp(fractBits, binExp);
    final b5 = -decExp > 0 ? -decExp : 0;
    var b2 = b5 + nTinyBits + binExp;
    final s5 = decExp > 0 ? decExp : 0;
    var s2 = s5 + nTinyBits;
    final m5 = b5;
    var m2 = b2 - nSignificantBits;

    fractBits >>>= tailZeros;
    b2 -= nFractBits - 1;
    final common2factor = b2 < s2 ? b2 : s2;
    b2 -= common2factor;
    s2 -= common2factor;
    m2 -= common2factor;
    if (nFractBits == 1) m2 -= 1;
    if (m2 < 0) {
      b2 -= m2;
      s2 -= m2;
      m2 = 0;
    }

    // The JDK picks int, long or FDBigInteger arithmetic by the estimated
    // sizes. The int and long branches overflow for a few values ("same
    // bugs, too" in the JDK source: `b + m > tens` and `tens = s * 10` wrap)
    // and then print a different last digit than exact arithmetic would, so
    // all three branches are kept, with wrapping 32-/64-bit arithmetic.
    var ndigit = 0;
    bool low, high;
    int lowDigitDifference;
    int q;
    final bbits =
        nFractBits + b2 + (b5 < _n5Bits.length ? _n5Bits[b5] : b5 * 3);
    final tenSbits =
        s2 + 1 + ((s5 + 1) < _n5Bits.length ? _n5Bits[s5 + 1] : (s5 + 1) * 3);
    if (bbits < 64 && tenSbits < 64) {
      if (bbits < 32 && tenSbits < 32) {
        // wa-hoo! They're all ints!
        var b = shl32(mul32(i32(fractBits), _small5Pow[b5]), b2);
        final s = shl32(_small5Pow[s5], s2);
        var m = shl32(_small5Pow[m5], m2);
        final tens = mul32(s, 10);
        q = b ~/ s;
        b = mul32(10, b.remainder(s));
        m = mul32(m, 10);
        low = b < m;
        high = i32(b + m) > tens;
        if (q == 0 && !high) {
          decExp--;
        } else {
          digits[ndigit++] = 0x30 + q;
        }
        if (!isCompatibleFormat || decExp < -3 || decExp >= 8) {
          high = low = false;
        }
        while (!low && !high) {
          q = b ~/ s;
          b = mul32(10, b.remainder(s));
          m = mul32(m, 10);
          if (m > 0) {
            low = b < m;
            high = i32(b + m) > tens;
          } else {
            // hack -- m might overflow!
            low = true;
            high = true;
          }
          digits[ndigit++] = 0x30 + q;
        }
        lowDigitDifference = i32(shl32(b, 1) - tens);
        exactDecimalConversion = b == 0;
      } else {
        // still good! they're all longs!
        var b = shl64(fractBits * _long5Pow[b5], b2);
        final s = shl64(_long5Pow[s5], s2);
        var m = shl64(_long5Pow[m5], m2);
        final tens = s * 10;
        q = b ~/ s;
        b = 10 * b.remainder(s);
        m *= 10;
        low = b < m;
        high = b + m > tens;
        if (q == 0 && !high) {
          decExp--;
        } else {
          digits[ndigit++] = 0x30 + q;
        }
        if (!isCompatibleFormat || decExp < -3 || decExp >= 8) {
          high = low = false;
        }
        while (!low && !high) {
          q = b ~/ s;
          b = 10 * b.remainder(s);
          m *= 10;
          if (m > 0) {
            low = b < m;
            high = b + m > tens;
          } else {
            // hack -- m might overflow!
            low = true;
            high = true;
          }
          digits[ndigit++] = 0x30 + q;
        }
        lowDigitDifference = shl64(b, 1) - tens;
        exactDecimalConversion = b == 0;
      }
    } else {
      // We really must do FDBigInteger arithmetic (exact; BigInt here).
      var bval = BigInt.from(fractBits) * _big5.pow(b5) << b2;
      final sval = _big5.pow(s5) << s2;
      var mval = _big5.pow(m5) << m2;
      final tens = sval * _big10;

      q = (bval ~/ sval).toInt();
      bval = (bval % sval) * _big10;
      mval = mval * _big10;
      low = bval < mval;
      high = bval + mval > tens;
      if (q == 0 && !high) {
        decExp--;
      } else {
        digits[ndigit++] = 0x30 + q;
      }
      if (!isCompatibleFormat || decExp < -3 || decExp >= 8) {
        high = low = false;
      }
      while (!low && !high) {
        q = (bval ~/ sval).toInt();
        bval = (bval % sval) * _big10;
        mval = mval * _big10;
        low = bval < mval;
        high = bval + mval > tens;
        digits[ndigit++] = 0x30 + q;
      }
      if (high && low) {
        lowDigitDifference = (bval << 1).compareTo(tens);
      } else {
        lowDigitDifference = 0; // this here only for flow analysis!
      }
      exactDecimalConversion = bval == BigInt.zero;
    }

    decExponent = decExp + 1;
    firstDigitIndex = 0;
    nDigits = ndigit;
    if (high) {
      if (low) {
        if (lowDigitDifference == 0) {
          if ((digits[firstDigitIndex + nDigits - 1] & 1) != 0) roundup();
        } else if (lowDigitDifference > 0) {
          roundup();
        }
      } else {
        roundup();
      }
    }
  }

  void roundup() {
    var i = firstDigitIndex + nDigits - 1;
    var q = digits[i];
    if (q == 0x39) {
      while (q == 0x39 && i > firstDigitIndex) {
        digits[i] = 0x30;
        q = digits[--i];
      }
      if (q == 0x39) {
        decExponent += 1;
        digits[firstDigitIndex] = 0x31;
        return;
      }
    }
    digits[i] = q + 1;
    decimalDigitsRoundedUp = true;
  }

  /// `BinaryToASCIIBuffer.getChars` (Float.toString / Double.toString).
  String getChars() {
    final sb = StringBuffer();
    if (isNegative) sb.write('-');
    if (decExponent > 0 && decExponent < 8) {
      var charLength = nDigits < decExponent ? nDigits : decExponent;
      for (var k = 0; k < charLength; k++) {
        sb.writeCharCode(digits[firstDigitIndex + k]);
      }
      if (charLength < decExponent) {
        for (var k = charLength; k < decExponent; k++) {
          sb.write('0');
        }
        sb.write('.0');
      } else {
        sb.write('.');
        if (charLength < nDigits) {
          for (var k = charLength; k < nDigits; k++) {
            sb.writeCharCode(digits[firstDigitIndex + k]);
          }
        } else {
          sb.write('0');
        }
      }
    } else if (decExponent <= 0 && decExponent > -3) {
      sb.write('0.');
      for (var k = 0; k < -decExponent; k++) {
        sb.write('0');
      }
      for (var k = 0; k < nDigits; k++) {
        sb.writeCharCode(digits[firstDigitIndex + k]);
      }
    } else {
      sb.writeCharCode(digits[firstDigitIndex]);
      sb.write('.');
      if (nDigits > 1) {
        for (var k = 1; k < nDigits; k++) {
          sb.writeCharCode(digits[firstDigitIndex + k]);
        }
      } else {
        sb.write('0');
      }
      sb.write('E');
      int e;
      if (decExponent <= 0) {
        sb.write('-');
        e = -decExponent + 1;
      } else {
        e = decExponent - 1;
      }
      sb.write(e);
    }
    return sb.toString();
  }
}

int _numberOfTrailingZeros64(int v) {
  if (v == 0) return 64;
  var n = 0;
  while ((v & 1) == 0) {
    v >>>= 1;
    n++;
  }
  return n;
}

int _insignificantDigitsForPow2(int p2) {
  if (p2 > 1 && p2 < _insignificantDigitsNumber.length) {
    return _insignificantDigitsNumber[p2];
  }
  return 0;
}

int _estimateDecExp(int fractBits, int binExp) {
  final d2 = longBitsToDouble(_expOne | (fractBits & _signifBitMask));
  final d = (d2 - 1.5) * 0.289529654 + 0.176091259 + binExp * 0.301029995663981;
  final dBits = doubleToRawLongBits(d);
  final exponent = ((dBits & 0x7FF0000000000000) >> _expShift) - 1023;
  final isNegative = dBits < 0;
  if (exponent >= 0 && exponent < 52) {
    final mask = _signifBitMask >> exponent;
    final r = ((dBits & _signifBitMask) | _fractHob) >> (_expShift - exponent);
    return isNegative ? ((mask & dBits) == 0 ? -r : -r - 1) : r;
  } else if (exponent < 0) {
    return (dBits & 0x7FFFFFFFFFFFFFFF) == 0 ? 0 : (isNegative ? -1 : 0);
  } else {
    return d2i(d);
  }
}

/// `FloatingDecimal.getBinaryToASCIIConverter(float)` for a finite, non-zero
/// float held in [v].
_Dtoa _floatConverter(double v) {
  final fBits = floatToRawIntBits(v);
  final buf = _Dtoa();
  buf.isNegative = fBits < 0;
  var fractBits = fBits & 0x007FFFFF;
  var binExp = (fBits & 0x7F800000) >> 23;
  int nSignificantBits;
  if (binExp == 0) {
    final leadingZeros = 32 - fractBits.bitLength;
    final shift = leadingZeros - (31 - 23);
    fractBits <<= shift;
    binExp = 1 - shift;
    nSignificantBits = 32 - leadingZeros;
  } else {
    fractBits |= 1 << 23;
    nSignificantBits = 24;
  }
  binExp -= 127;
  buf.dtoa(binExp, fractBits << (_expShift - 23), nSignificantBits, true);
  return buf;
}

/// `FloatingDecimal.getBinaryToASCIIConverter(double, isCompatibleFormat)`
/// for a finite, non-zero double.
_Dtoa _doubleConverter(double d, bool isCompatibleFormat) {
  final dBits = doubleToRawLongBits(d);
  final buf = _Dtoa();
  buf.isNegative = dBits < 0;
  var fractBits = dBits & _signifBitMask;
  var binExp = (dBits & 0x7FF0000000000000) >> _expShift;
  int nSignificantBits;
  if (binExp == 0) {
    final leadingZeros = 64 - fractBits.bitLength;
    final shift = leadingZeros - (63 - _expShift);
    fractBits <<= shift;
    binExp = 1 - shift;
    nSignificantBits = 64 - leadingZeros;
  } else {
    fractBits |= _fractHob;
    nSignificantBits = 53;
  }
  binExp -= 1023;
  buf.dtoa(binExp, fractBits, nSignificantBits, isCompatibleFormat);
  return buf;
}


/// `Double.parseDouble(s)`: the JDK grammar of [javaParseFloat] (`String.trim`,
/// sign, `NaN`/`Infinity`, trailing `f`/`d`, exponent) with a correctly
/// rounded double result (`double.parse` is correctly rounded for decimal
/// strings). Hexadecimal floating literals are not supported here; the
/// router only parses coordinates, radii and weights with it.
double javaParseDouble(String input) {
  final s = javaTrim(input);
  if (s.isEmpty) throw NumberFormatException('empty String');
  var i = 0;
  var negative = false;
  if (s[0] == '-' || s[0] == '+') {
    negative = s[0] == '-';
    i = 1;
  }
  final rest = s.substring(i);
  if (rest == 'NaN') return double.nan;
  if (rest == 'Infinity') {
    return negative ? double.negativeInfinity : double.infinity;
  }
  if (rest.startsWith('0x') || rest.startsWith('0X')) {
    throw UnsupportedError('hexadecimal floating literal: "$input"');
  }
  final m = RegExp(
    r'^(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?[fFdD]?$',
  ).firstMatch(rest);
  if (m == null) throw NumberFormatException('For input string: "$input"');
  var mant = m.group(1)!;
  if (mant.endsWith('.')) mant = mant.substring(0, mant.length - 1);
  if (mant.startsWith('.')) mant = '0$mant';
  final v = double.parse('$mant${m.group(2) ?? ''}');
  return negative ? -v : v;
}

/// `Float.toString((float) v)` of JDK 17.
String javaFloatToString(double v) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? 'Infinity' : '-Infinity';
  if (v == 0) return floatToRawIntBits(v) < 0 ? '-0.0' : '0.0';
  return _floatConverter(v).getChars();
}

/// `Double.toString(d)` of JDK 17 (the same algorithm on double bits; only
/// used to double-check the port, the runtime prints floats).
String javaDoubleToString(double d) {
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
  if (d == 0) return doubleToRawLongBits(d) < 0 ? '-0.0' : '0.0';
  return _doubleConverter(d, true).getChars();
}


/// `new DecimalFormat("0.###")` (`Locale.ENGLISH`) applied to a `double`:
/// `DigitList.set` takes the `FloatingDecimal` digits of the value (the
/// `Double.toString` digits, with the "rounded up" and "exact" flags) and
/// rounds them `HALF_EVEN` to [maxFraction] decimals, `subformat` prints at
/// least one integer digit, no grouping and no trailing zeros.
/// `FormatJson` prints the travel times with it (`float` promoted to double).
String javaDecimalFormat(double number, {int maxFraction = 3}) {
  if (number.isNaN) return '\u{FFFD}'; // DecimalFormatSymbols.getNaN(), never printed by the router
  var isNegative = number < 0.0 || (number == 0.0 && 1 / number < 0.0);
  if (isNegative) number = -number;
  if (number.isInfinite) return isNegative ? '-∞' : '∞';
  final sb = StringBuffer();
  // DigitList.set(isNegative, double, maximumDigits, fixedPoint = true)
  List<int> digits;
  var decimalAt = 0;
  var count = 0;
  if (number == 0) {
    digits = const <int>[];
  } else {
    final fd = _doubleConverter(number, true);
    digits = List<int>.generate(
      fd.nDigits,
      (i) => fd.digits[fd.firstDigitIndex + i] - 0x30,
      growable: true,
    );
    count = digits.length;
    decimalAt = fd.decExponent;
    final roundedUp = fd.decimalDigitsRoundedUp;
    final exact = fd.exactDecimalConversion;
    if (-decimalAt > maxFraction) {
      count = 0;
    } else if (-decimalAt == maxFraction) {
      if (_shouldRoundUpHalfEven(digits, count, 0, roundedUp, exact)) {
        count = 1;
        decimalAt++;
        digits = <int>[1];
      } else {
        count = 0;
      }
    } else {
      while (count > 1 && digits[count - 1] == 0) {
        count--;
      }
      var maximumDigits = maxFraction + decimalAt;
      if (maximumDigits >= 0 && maximumDigits < count) {
        if (_shouldRoundUpHalfEven(digits, count, maximumDigits, roundedUp, exact)) {
          for (;;) {
            maximumDigits--;
            if (maximumDigits < 0) {
              digits[0] = 1;
              decimalAt++;
              maximumDigits = 0;
              break;
            }
            digits[maximumDigits]++;
            if (digits[maximumDigits] <= 9) break;
          }
          maximumDigits++;
        }
        count = maximumDigits;
        while (count > 1 && digits[count - 1] == 0) {
          count--;
        }
      }
    }
  }
  if (count == 0) decimalAt = 0; // isZero: normalise
  if (isNegative) sb.write('-');
  // subformat: minimumIntegerDigits 1, maximumFractionDigits maxFraction
  var intCount = 1;
  if (decimalAt > 0 && intCount < decimalAt) intCount = decimalAt;
  var digitIndex = 0;
  for (var i = intCount - 1; i >= 0; i--) {
    if (i < decimalAt && digitIndex < count) {
      sb.writeCharCode(0x30 + digits[digitIndex++]);
    } else {
      sb.write('0');
    }
  }
  final fractionPresent = digitIndex < count;
  if (fractionPresent) sb.write('.');
  for (var i = 0; i < maxFraction; i++) {
    if (digitIndex >= count) break;
    if (-1 - i > decimalAt - 1) {
      sb.write('0');
      continue;
    }
    sb.writeCharCode(0x30 + digits[digitIndex++]);
  }
  return sb.toString();
}

/// `DigitList.shouldRoundUp` for `RoundingMode.HALF_EVEN`.
bool _shouldRoundUpHalfEven(
  List<int> digits,
  int count,
  int maximumDigits,
  bool alreadyRounded,
  bool valueExactAsDecimal,
) {
  if (digits[maximumDigits] > 5) return true;
  if (digits[maximumDigits] == 5) {
    if (maximumDigits == count - 1) {
      if (alreadyRounded) return false;
      if (!valueExactAsDecimal) return true;
      return maximumDigits > 0 && (digits[maximumDigits - 1] % 2 != 0);
    }
    for (var i = maximumDigits + 1; i < count; i++) {
      if (digits[i] != 0) return true;
    }
  }
  return false;
}

/// `String.format(Locale.US, "%.<prec>f", d)` (a `float` argument is promoted
/// to `double` first, which is what the callers of this port pass in).
String javaFormatFixed(double d, int prec) {
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
  final neg = javaDoubleCompare(d, 0.0) == -1;
  final v = d.abs();
  final sb = StringBuffer();
  if (neg) sb.write('-');
  String mant;
  if (v == 0) {
    mant = '0';
  } else {
    final fd = _doubleConverter(v, false);
    final digits = List<int>.generate(
      fd.nDigits,
      (k) => fd.digits[fd.firstDigitIndex + k],
    );
    final exp = _applyPrecision(fd.decExponent, digits, prec + fd.decExponent);
    mant = _fillDecimal(prec, digits, exp);
  }
  sb.write(mant);
  // Formatter.addZeros
  final dot = mant.indexOf('.');
  final outPrec = dot < 0 ? 0 : mant.length - dot - 1;
  if (outPrec < prec) {
    if (dot < 0) sb.write('.');
    for (var k = outPrec; k < prec; k++) {
      sb.write('0');
    }
  }
  return sb.toString();
}

/// `FormattedFloatingDecimal.applyPrecision` (half-up on the digit string).
int _applyPrecision(int decExp, List<int> digits, int prec) {
  final nDigits = digits.length;
  if (prec >= nDigits || prec < 0) return decExp;
  if (prec == 0) {
    if (digits[0] >= 0x35) {
      digits[0] = 0x31;
      for (var k = 1; k < nDigits; k++) {
        digits[k] = 0x30;
      }
      return decExp + 1;
    }
    for (var k = 0; k < nDigits; k++) {
      digits[k] = 0x30;
    }
    return decExp;
  }
  var q = digits[prec];
  if (q >= 0x35) {
    var i = prec;
    q = digits[--i];
    if (q == 0x39) {
      while (q == 0x39 && i > 0) {
        q = digits[--i];
      }
      if (q == 0x39) {
        digits[0] = 0x31;
        for (var k = 1; k < nDigits; k++) {
          digits[k] = 0x30;
        }
        return decExp + 1;
      }
    }
    digits[i] = q + 1;
    for (var k = i + 1; k < nDigits; k++) {
      digits[k] = 0x30;
    }
  } else {
    for (var k = prec; k < nDigits; k++) {
      digits[k] = 0x30;
    }
  }
  return decExp;
}

/// `FormattedFloatingDecimal.fillDecimal` (without the sign).
String _fillDecimal(int precision, List<int> digits, int exp) {
  final nDigits = digits.length;
  final sb = StringBuffer();
  if (exp > 0) {
    if (nDigits < exp) {
      for (var k = 0; k < nDigits; k++) {
        sb.writeCharCode(digits[k]);
      }
      for (var k = nDigits; k < exp; k++) {
        sb.write('0');
      }
    } else {
      final t = nDigits - exp < precision ? nDigits - exp : precision;
      for (var k = 0; k < exp; k++) {
        sb.writeCharCode(digits[k]);
      }
      if (t > 0) {
        sb.write('.');
        for (var k = 0; k < t; k++) {
          sb.writeCharCode(digits[exp + k]);
        }
      }
    }
  } else {
    var zeros = -exp < precision ? -exp : precision;
    if (zeros < 0) zeros = 0;
    var t = nDigits < precision + exp ? nDigits : precision + exp;
    if (t < 0) t = 0;
    if (zeros > 0) {
      sb.write('0.');
      for (var k = 0; k < zeros; k++) {
        sb.write('0');
      }
      for (var k = 0; k < t; k++) {
        sb.writeCharCode(digits[k]);
      }
    } else if (t > 0) {
      sb.write('0.');
      for (var k = 0; k < t; k++) {
        sb.writeCharCode(digits[k]);
      }
    } else {
      sb.write('0');
    }
  }
  return sb.toString();
}

// ---------------------------------------------------------------------------
// java.lang.String / Character / Integer helpers
// ---------------------------------------------------------------------------

/// `String.trim()`: strips leading and trailing chars `<= U+0020`.
String javaTrim(String s) {
  var st = 0;
  var len = s.length;
  while (st < len && s.codeUnitAt(st) <= 0x20) {
    st++;
  }
  while (st < len && s.codeUnitAt(len - 1) <= 0x20) {
    len--;
  }
  return st > 0 || len < s.length ? s.substring(st, len) : s;
}

/// `Character.isWhitespace(char)`.
bool javaIsWhitespace(int c) {
  if (c <= 0x20) {
    return c == 0x20 || (c >= 9 && c <= 13) || (c >= 0x1c && c <= 0x1f);
  }
  if (c < 0x1680) return false;
  return c == 0x1680 ||
      (c >= 0x2000 && c <= 0x2006) ||
      (c >= 0x2008 && c <= 0x200a) ||
      c == 0x2028 ||
      c == 0x2029 ||
      c == 0x205f ||
      c == 0x3000;
}

/// `String.split(literal)` for a non-empty literal separator without regex
/// metacharacters: leading empty strings are kept, trailing ones removed.
List<String> javaSplit(String s, String sep) {
  final list = <String>[];
  var index = 0;
  var m = s.indexOf(sep);
  if (m < 0) return <String>[s];
  while (m >= 0) {
    list.add(s.substring(index, m));
    index = m + sep.length;
    m = s.indexOf(sep, index);
  }
  list.add(s.substring(index));
  var n = list.length;
  while (n > 0 && list[n - 1].isEmpty) {
    n--;
  }
  return list.sublist(0, n);
}

/// `Integer.parseInt(s)` (radix 10, ASCII digits only -- the JDK also accepts
/// other Unicode decimal digits, which no tag value of the corpus has).
int javaParseInt(String s) {
  final len = s.length;
  if (len == 0) throw NumberFormatException('For input string: ""');
  var i = 0;
  var negative = false;
  final first = s.codeUnitAt(0);
  if (first == 0x2d || first == 0x2b) {
    negative = first == 0x2d;
    if (len == 1) throw NumberFormatException('For input string: "$s"');
    i++;
  }
  var result = 0;
  while (i < len) {
    final c = s.codeUnitAt(i++);
    if (c < 0x30 || c > 0x39) {
      throw NumberFormatException('For input string: "$s"');
    }
    result = result * 10 + (c - 0x30);
    if (result > 2147483648) {
      throw NumberFormatException('For input string: "$s"');
    }
  }
  if (negative) return -result;
  if (result > 2147483647) {
    throw NumberFormatException('For input string: "$s"');
  }
  return result;
}

/// `java.util.Random` (the 48-bit linear congruential generator), for
/// `BExpressionContext.generateRandomValues` and the profile comparator.
class JavaRandom {
  JavaRandom(int seed) : _seed = (seed ^ _multiplier) & _mask;

  static const int _multiplier = 0x5DEECE66D;
  static const int _addend = 0xB;
  static const int _mask = (1 << 48) - 1;

  int _seed;

  int next(int bits) {
    _seed = (_seed * _multiplier + _addend) & _mask;
    return (_seed >>> (48 - bits)).toSigned(32);
  }

  int nextInt([int? bound]) {
    if (bound == null) return next(32);
    if (bound <= 0) throw ArgumentError('bound must be positive');
    var r = next(31);
    final m = bound - 1;
    if ((bound & m) == 0) {
      return ((bound * r) >> 31).toSigned(32);
    }
    var u = r;
    r = u % bound;
    while (i32(u - r + m) < 0) {
      u = next(31);
      r = u % bound;
    }
    return r;
  }

  bool nextBoolean() => next(1) != 0;

  /// `nextFloat()` as a double holding the float value.
  double nextFloat() => next(24) / (1 << 24);
}
