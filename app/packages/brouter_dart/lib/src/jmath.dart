/// Java `Math.sin`, `Math.cos`, `Math.atan2` and `Math.atan` with the bit-exact
/// results of the HotSpot JVM.
///
/// `Math.sin`/`Math.cos` are JIT intrinsics on HotSpot (x86_64 and aarch64
/// share the algorithm), derived from Intel's LIBM: `x = N * pi/32 + r`, a
/// 64-entry table of `sin(N*pi/32)`/`cos(N*pi/32)` and short polynomials in
/// `r`, computed with plain IEEE binary64 operations and no fused multiply-add.
/// `_sincos` below transcribes the main path of
/// `MacroAssembler::fast_sin`/`fast_cos` (macroAssembler_x86_sin.cpp /
/// _cos.cpp of jdk17u) instruction by instruction, which covers
/// `2^-252 <= |x| < 90112` -- every argument the routing runtime produces. For
/// larger arguments the intrinsic does a Payne-Hanek reduction that is not
/// ported; `dart:math` is used there and the result may differ in the last ulp.
/// Neither the fdlibm `StrictMath` nor the C library agree with the intrinsic
/// bit for bit (60 of the 1800 CheapRuler scale-cache entries differ between
/// `Math.cos` and `StrictMath.cos`), hence the port.
///
/// `Math.atan2`/`Math.atan` delegate to `StrictMath` (fdlibm `e_atan2.c`,
/// `s_atan.c`) on every platform; those are transcribed here as well.
library;

import 'dart:math' as math;

import 'jvm.dart';

class JMath {
  JMath._();

  // 32/pi, pi/32 in three parts, and the polynomial coefficients of the
  // HotSpot stubs (StubRoutines::x86::_PI32INV, _P_1.._P_3, _SC_1.._SC_4).
  static final double _pi32inv = longBitsToDouble(0x40245f306dc9c883);
  static final double _p1 = longBitsToDouble(0x3fb921fb54400000);
  static final double _p2 = longBitsToDouble(0x3d90b4611a600000);
  static final double _p3 = longBitsToDouble(0x3b63198a2e037073);
  static final double _sc4lo = longBitsToDouble(0x3ec71de3a556c734);
  static final double _sc4hi = longBitsToDouble(0x3efa01a01a01a01a);
  static final double _sc2lo = longBitsToDouble(0x3f81111111111111);
  static final double _sc2hi = longBitsToDouble(0x3fa5555555555555);
  static final double _sc3lo = longBitsToDouble(
    0xbf2a01a01a01a01a.toSigned(64),
  );
  static final double _sc3hi = longBitsToDouble(
    0xbf56c16c16c16c17.toSigned(64),
  );
  static final double _sc1lo = longBitsToDouble(
    0xbfc5555555555555.toSigned(64),
  );
  static final double _sc1hi = longBitsToDouble(
    0xbfe0000000000000.toSigned(64),
  );
  static final double _allOnes = longBitsToDouble(0x3fefffffffffffff);
  static final double _twoPow55 = longBitsToDouble(0x4360000000000000);
  static final double _twoPowM55 = longBitsToDouble(0x3c80000000000000);

  /// StubRoutines::x86::_Ctable: per row `C_hl`, `S_hi`, `S_lo`, `sigma` for
  /// `B = M * pi/32`, M = 0..63.
  static final List<double> _ctable = _ctableBits
      .map((b) => longBitsToDouble(b.toSigned(64)))
      .toList(growable: false);

  static const List<int> _ctableBits = <int>[
    0x0000000000000000,
    0x0000000000000000,
    0x0000000000000000,
    0x3ff0000000000000, // 0
    0xbf73b92e176d6d31,
    0x3fb917a6bc29b42c,
    0xbc3e2718e0000000,
    0x3ff0000000000000, // 1
    0xbf93ad06011469fb,
    0x3fc8f8b83c69a60b,
    0xbc626d19c0000000,
    0x3ff0000000000000, // 2
    0xbfa60bea939d225a,
    0x3fd294062ed59f06,
    0xbc75d28da0000000,
    0x3ff0000000000000, // 3
    0xbfb37ca1866b95cf,
    0x3fd87de2a6aea963,
    0xbc672cede0000000,
    0x3ff0000000000000, // 4
    0xbfbe3a6873fa1279,
    0x3fde2b5d3806f63b,
    0x3c5e0d8920000000,
    0x3ff0000000000000, // 5
    0xbfc592675bc57974,
    0x3fe1c73b39ae68c8,
    0x3c8b25dd20000000,
    0x3ff0000000000000, // 6
    0xbfcd0dfe53aba2fd,
    0x3fe44cf325091dd6,
    0x3c68076a20000000,
    0x3ff0000000000000, // 7
    0x3fca827999fcef32,
    0x3fe6a09e667f3bcd,
    0xbc8bdd3420000000,
    0x3fe0000000000000, // 8
    0x3fc133cc94247758,
    0x3fe8bc806b151741,
    0xbc82c5e120000000,
    0x3fe0000000000000, // 9
    0x3fac73b39ae68c87,
    0x3fea9b66290ea1a3,
    0x3c39f630e0000000,
    0x3fe0000000000000, // 10
    0xbf9d4a2c7f909c4e,
    0x3fec38b2f180bdb1,
    0xbc76e0b180000000,
    0x3fe0000000000000, // 11
    0xbfbe087565455a75,
    0x3fed906bcf328d46,
    0x3c7457e620000000,
    0x3fe0000000000000, // 12
    0x3fa4a03176acf82d,
    0x3fee9f4156c62dda,
    0x3c8760b1e0000000,
    0x3fd0000000000000, // 13
    0xbfac1d1f0e5967d5,
    0x3fef6297cff75cb0,
    0x3c75621720000000,
    0x3fd0000000000000, // 14
    0xbf9ba1650f592f50,
    0x3fefd88da3d12526,
    0xbc887df640000000,
    0x3fc0000000000000, // 15
    0x0000000000000000,
    0x3ff0000000000000,
    0x0000000000000000,
    0x0000000000000000, // 16
    0x3f9ba1650f592f50,
    0x3fefd88da3d12526,
    0xbc887df640000000,
    0xbfc0000000000000, // 17
    0x3fac1d1f0e5967d5,
    0x3fef6297cff75cb0,
    0x3c75621720000000,
    0xbfd0000000000000, // 18
    0xbfa4a03176acf82d,
    0x3fee9f4156c62dda,
    0x3c8760b1e0000000,
    0xbfd0000000000000, // 19
    0x3fbe087565455a75,
    0x3fed906bcf328d46,
    0x3c7457e620000000,
    0xbfe0000000000000, // 20
    0x3f9d4a2c7f909c4e,
    0x3fec38b2f180bdb1,
    0xbc76e0b180000000,
    0xbfe0000000000000, // 21
    0xbfac73b39ae68c87,
    0x3fea9b66290ea1a3,
    0x3c39f630e0000000,
    0xbfe0000000000000, // 22
    0xbfc133cc94247758,
    0x3fe8bc806b151741,
    0xbc82c5e120000000,
    0xbfe0000000000000, // 23
    0xbfca827999fcef32,
    0x3fe6a09e667f3bcd,
    0xbc8bdd3420000000,
    0xbfe0000000000000, // 24
    0x3fcd0dfe53aba2fd,
    0x3fe44cf325091dd6,
    0x3c68076a20000000,
    0xbff0000000000000, // 25
    0x3fc592675bc57974,
    0x3fe1c73b39ae68c8,
    0x3c8b25dd20000000,
    0xbff0000000000000, // 26
    0x3fbe3a6873fa1279,
    0x3fde2b5d3806f63b,
    0x3c5e0d8920000000,
    0xbff0000000000000, // 27
    0x3fb37ca1866b95cf,
    0x3fd87de2a6aea963,
    0xbc672cede0000000,
    0xbff0000000000000, // 28
    0x3fa60bea939d225a,
    0x3fd294062ed59f06,
    0xbc75d28da0000000,
    0xbff0000000000000, // 29
    0x3f93ad06011469fb,
    0x3fc8f8b83c69a60b,
    0xbc626d19c0000000,
    0xbff0000000000000, // 30
    0x3f73b92e176d6d31,
    0x3fb917a6bc29b42c,
    0xbc3e2718e0000000,
    0xbff0000000000000, // 31
    0x0000000000000000,
    0x0000000000000000,
    0x0000000000000000,
    0xbff0000000000000, // 32
    0x3f73b92e176d6d31,
    0xbfb917a6bc29b42c,
    0x3c3e2718e0000000,
    0xbff0000000000000, // 33
    0x3f93ad06011469fb,
    0xbfc8f8b83c69a60b,
    0x3c626d19c0000000,
    0xbff0000000000000, // 34
    0x3fa60bea939d225a,
    0xbfd294062ed59f06,
    0x3c75d28da0000000,
    0xbff0000000000000, // 35
    0x3fb37ca1866b95cf,
    0xbfd87de2a6aea963,
    0x3c672cede0000000,
    0xbff0000000000000, // 36
    0x3fbe3a6873fa1279,
    0xbfde2b5d3806f63b,
    0xbc5e0d8920000000,
    0xbff0000000000000, // 37
    0x3fc592675bc57974,
    0xbfe1c73b39ae68c8,
    0xbc8b25dd20000000,
    0xbff0000000000000, // 38
    0x3fcd0dfe53aba2fd,
    0xbfe44cf325091dd6,
    0xbc68076a20000000,
    0xbff0000000000000, // 39
    0xbfca827999fcef32,
    0xbfe6a09e667f3bcd,
    0x3c8bdd3420000000,
    0xbfe0000000000000, // 40
    0xbfc133cc94247758,
    0xbfe8bc806b151741,
    0x3c82c5e120000000,
    0xbfe0000000000000, // 41
    0xbfac73b39ae68c87,
    0xbfea9b66290ea1a3,
    0xbc39f630e0000000,
    0xbfe0000000000000, // 42
    0x3f9d4a2c7f909c4e,
    0xbfec38b2f180bdb1,
    0x3c76e0b180000000,
    0xbfe0000000000000, // 43
    0x3fbe087565455a75,
    0xbfed906bcf328d46,
    0xbc7457e620000000,
    0xbfe0000000000000, // 44
    0xbfa4a03176acf82d,
    0xbfee9f4156c62dda,
    0xbc8760b1e0000000,
    0xbfd0000000000000, // 45
    0x3fac1d1f0e5967d5,
    0xbfef6297cff75cb0,
    0xbc75621720000000,
    0xbfd0000000000000, // 46
    0x3f9ba1650f592f50,
    0xbfefd88da3d12526,
    0x3c887df640000000,
    0xbfc0000000000000, // 47
    0x0000000000000000,
    0xbff0000000000000,
    0x0000000000000000,
    0x0000000000000000, // 48
    0xbf9ba1650f592f50,
    0xbfefd88da3d12526,
    0x3c887df640000000,
    0x3fc0000000000000, // 49
    0xbfac1d1f0e5967d5,
    0xbfef6297cff75cb0,
    0xbc75621720000000,
    0x3fd0000000000000, // 50
    0x3fa4a03176acf82d,
    0xbfee9f4156c62dda,
    0xbc8760b1e0000000,
    0x3fd0000000000000, // 51
    0xbfbe087565455a75,
    0xbfed906bcf328d46,
    0xbc7457e620000000,
    0x3fe0000000000000, // 52
    0xbf9d4a2c7f909c4e,
    0xbfec38b2f180bdb1,
    0x3c76e0b180000000,
    0x3fe0000000000000, // 53
    0x3fac73b39ae68c87,
    0xbfea9b66290ea1a3,
    0xbc39f630e0000000,
    0x3fe0000000000000, // 54
    0x3fc133cc94247758,
    0xbfe8bc806b151741,
    0x3c82c5e120000000,
    0x3fe0000000000000, // 55
    0x3fca827999fcef32,
    0xbfe6a09e667f3bcd,
    0x3c8bdd3420000000,
    0x3fe0000000000000, // 56
    0xbfcd0dfe53aba2fd,
    0xbfe44cf325091dd6,
    0xbc68076a20000000,
    0x3ff0000000000000, // 57
    0xbfc592675bc57974,
    0xbfe1c73b39ae68c8,
    0xbc8b25dd20000000,
    0x3ff0000000000000, // 58
    0xbfbe3a6873fa1279,
    0xbfde2b5d3806f63b,
    0xbc5e0d8920000000,
    0x3ff0000000000000, // 59
    0xbfb37ca1866b95cf,
    0xbfd87de2a6aea963,
    0x3c672cede0000000,
    0x3ff0000000000000, // 60
    0xbfa60bea939d225a,
    0xbfd294062ed59f06,
    0x3c75d28da0000000,
    0x3ff0000000000000, // 61
    0xbf93ad06011469fb,
    0xbfc8f8b83c69a60b,
    0x3c626d19c0000000,
    0x3ff0000000000000, // 62
    0xbf73b92e176d6d31,
    0xbfb917a6bc29b42c,
    0x3c3e2718e0000000,
    0x3ff0000000000000, // 63
  ];

  /// `Math.cos(x)`.
  static double cos(double x) {
    final bits = doubleToRawLongBits(x);
    final hx = (bits >> 32) & 0xffffffff;
    final eax = ((hx & 0x7fff0000) - 0x30300000) & 0xffffffff;
    if (eax > 0x10C50000) {
      if (eax.toSigned(32) > 0x10C50000) {
        if ((hx & 0x7ff00000) == 0x7ff00000) return x * -0.0; // NaN, +-Inf
        return math.cos(x); // |x| >= 90112: Payne-Hanek path not ported
      }
      return 1.0 - x.abs(); // |x| < 2^-252
    }
    return _sincos(x, bits, 1865232);
  }

  /// `Math.sin(x)`.
  static double sin(double x) {
    final bits = doubleToRawLongBits(x);
    final hx = (bits >> 32) & 0xffffffff;
    final eax = ((hx & 0x7fff0000) - 0x30300000) & 0xffffffff;
    if (eax > 0x10C50000) {
      if (eax.toSigned(32) > 0x10C50000) {
        if ((hx & 0x7ff00000) == 0x7ff00000) return x * -0.0; // NaN, +-Inf
        return math.sin(x); // |x| >= 90112: Payne-Hanek path not ported
      }
      if ((eax >> 20) == 3325) return x * _allOnes; // zero or subnormal
      return (_twoPow55 * x - x) * _twoPowM55; // 2^-1022 <= |x| < 2^-252
    }
    return _sincos(x, bits, 1865216);
  }

  /// The shared main path; [tableShift] is 1865216 (= 0 mod 64) for sin and
  /// 1865232 (= 16 mod 64, i.e. a quarter turn) for cos.
  static double _sincos(double x, int bits, int tableShift) {
    // range reduction: N = round-half-away(x * 32/pi), r = x - N * pi/32
    final y = _pi32inv * x;
    final n = (y + (bits < 0 ? -0.5 : 0.5)).truncate(); // cvttsd2si
    final nd = n.toDouble();
    final m1 = _p1 * nd;
    final m = (n + tableShift) & 63;
    final ct0 = _ctable[4 * m]; // C_hl
    final ct1 = _ctable[4 * m + 1]; // S_hi
    final ct2 = _ctable[4 * m + 2]; // S_lo
    final ct3 = _ctable[4 * m + 3]; // sigma
    final m2 = _p2 * nd;
    final r1 = x - m1;
    final m3 = nd * _p3;
    final r = r1 - m2;
    final psc4lo = _sc4lo * r1;
    final psc4hi = _sc4hi * r1;
    final ct1r = ct1 * r;
    final c1 = r1 - r;
    final msc4lo = psc4lo * r;
    final msc4hi = psc4hi * r;
    final r2 = r * r;
    final c2 = c1 - m2;
    final negc = m3 - c2;
    final csig = ct0 + ct3;
    final negd = ct1r - csig;
    final csigr = csig * r;
    final msc2lo = _sc2lo * r2;
    final msc2hi = _sc2hi * r2;
    final rs = ct3 * r;
    final x2lo = csigr * r2; // (C_hl + sigma) * r^3
    final x2hi = ct1 * r2; // S_hi * r^2
    final r4 = r2 * r2;
    final psc3lo = msc4lo + _sc3lo;
    final psc3hi = msc4hi + _sc3hi;
    final med = r * ct0;
    final psc1lo = msc2lo + _sc1lo;
    final psc1hi = msc2hi + _sc1hi;
    final msc3lo = psc3lo * r4;
    final msc3hi = psc3hi * r4;
    final resInt = rs + ct1;
    final corr0 = negc * negd;
    final resHi = med + resInt;
    final polslo0 = psc1lo + msc3lo;
    final polshi0 = psc1hi + msc3hi;
    final k0 = ct1 - resInt;
    final k1 = resInt - resHi;
    final corr = corr0 + ct2;
    final polslo = polslo0 * x2lo;
    final polshi = polshi0 * x2hi;
    final k2 = rs + k0;
    final k3 = k1 + med;
    var s = k2 + corr;
    s += k3;
    s += polslo;
    s += polshi;
    return s + resHi;
  }

  // ---- fdlibm atan / atan2 ------------------------------------------------

  static final List<double> _atanhi = <double>[
    4.63647609000806093515e-01, // atan(0.5)hi 0x3FDDAC67, 0x0561BB4F
    7.85398163397448278999e-01, // atan(1.0)hi 0x3FE921FB, 0x54442D18
    9.82793723247329054082e-01, // atan(1.5)hi 0x3FEF730B, 0xD281F69B
    1.57079632679489655800e+00, // atan(inf)hi 0x3FF921FB, 0x54442D18
  ];

  static final List<double> _atanlo = <double>[
    2.26987774529616870924e-17, // atan(0.5)lo 0x3C7A2B7F, 0x222F65E2
    3.06161699786838301793e-17, // atan(1.0)lo 0x3C81A626, 0x33145C07
    1.39033110312309984516e-17, // atan(1.5)lo 0x3C700788, 0x7AF0CBBD
    6.12323399573676603587e-17, // atan(inf)lo 0x3C91A626, 0x33145C07
  ];

  static final List<double> _aT = <double>[
    3.33333333333329318027e-01, // 0x3FD55555, 0x5555550D
    -1.99999999998764832476e-01, // 0xBFC99999, 0x9998EBC4
    1.42857142725034663711e-01, // 0x3FC24924, 0x920083FF
    -1.11111104054623557880e-01, // 0xBFBC71C6, 0xFE231671
    9.09088713343650656196e-02, // 0x3FB745CD, 0xC54C206E
    -7.69187620504482999495e-02, // 0xBFB3B0F2, 0xAF749A6D
    6.66107313738753120669e-02, // 0x3FB10D66, 0xA0D03D51
    -5.83357013379057348645e-02, // 0xBFADDE2D, 0x52DEFD9A
    4.97687799461593236017e-02, // 0x3FA97B4B, 0x24760DEB
    -3.65315727442169155270e-02, // 0xBFA2B444, 0x2C6A6C2F
    1.62858201153657823623e-02, // 0x3F90AD3A, 0xE322DA11
  ];

  static const double _piO4 =
      7.8539816339744827900E-01; // 0x3FE921FB, 0x54442D18
  static const double _piO2 =
      1.5707963267948965580E+00; // 0x3FF921FB, 0x54442D18
  static const double _pi = 3.1415926535897931160E+00; // 0x400921FB, 0x54442D18
  static const double _piLo =
      1.2246467991473531772E-16; // 0x3CA1A626, 0x33145C07
  static const double _tiny = 1.0e-300;

  static int _hi(double d) => (doubleToRawLongBits(d) >> 32).toSigned(32);
  static int _lo(double d) => doubleToRawLongBits(d) & 0xffffffff;

  /// `Math.atan(x)` (fdlibm s_atan.c).
  static double atan(double x) {
    final hx = _hi(x);
    final ix = hx & 0x7fffffff;
    int id;
    if (ix >= 0x44100000) {
      // |x| >= 2^66
      if (ix > 0x7ff00000 || (ix == 0x7ff00000 && _lo(x) != 0)) {
        return x + x; // NaN
      }
      if (hx > 0) {
        return _atanhi[3] + _atanlo[3];
      }
      return -_atanhi[3] - _atanlo[3];
    }
    if (ix < 0x3fdc0000) {
      // |x| < 0.4375
      if (ix < 0x3e200000) {
        // |x| < 2^-29
        return x; // (huge + x > one)
      }
      id = -1;
    } else {
      x = x.abs();
      if (ix < 0x3ff30000) {
        // |x| < 1.1875
        if (ix < 0x3fe60000) {
          // 7/16 <= |x| < 11/16
          id = 0;
          x = (2.0 * x - 1.0) / (2.0 + x);
        } else {
          // 11/16 <= |x| < 19/16
          id = 1;
          x = (x - 1.0) / (x + 1.0);
        }
      } else {
        if (ix < 0x40038000) {
          // |x| < 2.4375
          id = 2;
          x = (x - 1.5) / (1.0 + 1.5 * x);
        } else {
          // 2.4375 <= |x| < 2^66
          id = 3;
          x = -1.0 / x;
        }
      }
    }
    // end of argument reduction
    var z = x * x;
    final w = z * z;
    // break sum from i=0 to 10 aT[i]z**(i+1) into odd and even poly
    final aT = _aT;
    final s1 =
        z *
        (aT[0] +
            w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * aT[10])))));
    final s2 =
        w * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * aT[9]))));
    if (id < 0) return x - x * (s1 + s2);
    z = _atanhi[id] - ((x * (s1 + s2) - _atanlo[id]) - x);
    return hx < 0 ? -z : z;
  }

  /// `Math.atan2(y, x)` (fdlibm e_atan2.c).
  static double atan2(double y, double x) {
    final hx = _hi(x);
    final ix = hx & 0x7fffffff;
    final lx = _lo(x);
    final hy = _hi(y);
    final iy = hy & 0x7fffffff;
    final ly = _lo(y);
    if ((ix | ((lx | (-lx & 0xffffffff)) >> 31)) > 0x7ff00000 ||
        (iy | ((ly | (-ly & 0xffffffff)) >> 31)) > 0x7ff00000) {
      return x + y; // x or y is NaN
    }
    if (((hx - 0x3ff00000) | lx) == 0) return atan(y); // x=1.0
    final m = ((hy >> 31) & 1) | ((hx >> 30) & 2); // 2*sign(x)+sign(y)

    // when y = 0
    if ((iy | ly) == 0) {
      switch (m) {
        case 0:
        case 1:
          return y; // atan(+-0,+anything)=+-0
        case 2:
          return _pi + _tiny; // atan(+0,-anything) = pi
        default:
          return -_pi - _tiny; // atan(-0,-anything) =-pi
      }
    }
    // when x = 0
    if ((ix | lx) == 0) return hy < 0 ? -_piO2 - _tiny : _piO2 + _tiny;

    // when x is INF
    if (ix == 0x7ff00000) {
      if (iy == 0x7ff00000) {
        switch (m) {
          case 0:
            return _piO4 + _tiny; // atan(+INF,+INF)
          case 1:
            return -_piO4 - _tiny; // atan(-INF,+INF)
          case 2:
            return 3.0 * _piO4 + _tiny; // atan(+INF,-INF)
          default:
            return -3.0 * _piO4 - _tiny; // atan(-INF,-INF)
        }
      } else {
        switch (m) {
          case 0:
            return 0.0; // atan(+...,+INF)
          case 1:
            return -1.0 * 0.0; // atan(-...,+INF)
          case 2:
            return _pi + _tiny; // atan(+...,-INF)
          default:
            return -_pi - _tiny; // atan(-...,-INF)
        }
      }
    }
    // when y is INF
    if (iy == 0x7ff00000) return hy < 0 ? -_piO2 - _tiny : _piO2 + _tiny;

    // compute y/x
    final k = (iy - ix) >> 20;
    double z;
    if (k > 60) {
      z = _piO2 + 0.5 * _piLo; // |y/x| >  2**60
    } else if (hx < 0 && k < -60) {
      z = 0.0; // |y|/x < -2**60
    } else {
      z = atan((y / x).abs()); // safe to do y/x
    }
    switch (m) {
      case 0:
        return z; // atan(+,+)
      case 1:
        return -z; // atan(-,+)
      case 2:
        return _pi - (z - _piLo); // atan(+,-)
      default:
        return (z - _piLo) - _pi; // atan(-,-)
    }
  }
}
