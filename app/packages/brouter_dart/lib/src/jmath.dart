/// Java `Math.sin`, `Math.cos`, `Math.exp`, `Math.atan2` and `Math.atan` with
/// the bit-exact results of the HotSpot JVM.
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


  // ---- HotSpot Math.exp intrinsic (Intel LIBM) ----------------------------

  // StubRoutines::x86::_cv / _shifter of macroAssembler_x86_exp.cpp (jdk17u):
  // 64/ln2, ln2/64 in two parts, the polynomial coefficients and the
  // 1.5 * 2^52 rounding shifter.
  static final double _expL2e64 = longBitsToDouble(0x40571547652b82fe);
  static final double _expLn2hi64 = longBitsToDouble(0x3f862e42fefa0000);
  static final double _expLn2lo64 = longBitsToDouble(0x3d1cf79abc9e3b3a);
  static final double _expHalf = longBitsToDouble(0x3fdffffffffffffe);
  static final double _expC6 = longBitsToDouble(0x3f56c15ce3289860);
  static final double _expC4 = longBitsToDouble(0x3fa55555555b9e25);
  static final double _expC5 = longBitsToDouble(0x3f811115c090cf0f);
  static final double _expC3 = longBitsToDouble(0x3fc5555555548ba1);
  static final double _expShifter = longBitsToDouble(0x4338000000000000);

  /// `_Tbl_addr`: per j = 0..63 the low part `T_lo[j]` (a double) and the
  /// mantissa bits of `T_hi[j] = 2^(j/64)` (exponent field zero; the
  /// intrinsic ORs the exponent in), as the four 32-bit words of the stub.
  static const List<int> _expTblWords = <int>[
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x0e03754d, //
    0x3cad7bbf, 0x3e778060, 0x00002c9a, 0x3567f613, 0x3c8cd252, //
    0xd3158574, 0x000059b0, 0x61e6c861, 0x3c60f74e, 0x18759bc8, //
    0x00008745, 0x5d837b6c, 0x3c979aa6, 0x6cf9890f, 0x0000b558, //
    0x702f9cd1, 0x3c3ebe3d, 0x32d3d1a2, 0x0000e3ec, 0x1e63bcd8, //
    0x3ca3516e, 0xd0125b50, 0x00011301, 0x26f0387b, 0x3ca4c554, //
    0xaea92ddf, 0x0001429a, 0x62523fb6, 0x3ca95153, 0x3c7d517a, //
    0x000172b8, 0x3f1353bf, 0x3c8b898c, 0xeb6fcb75, 0x0001a35b, //
    0x3e3a2f5f, 0x3c9aecf7, 0x3168b9aa, 0x0001d487, 0x44a6c38d, //
    0x3c8a6f41, 0x88628cd6, 0x0002063b, 0xe3a8a894, 0x3c968efd, //
    0x6e756238, 0x0002387a, 0x981fe7f2, 0x3c80472b, 0x65e27cdd, //
    0x00026b45, 0x6d09ab31, 0x3c82f7e1, 0xf51fdee1, 0x00029e9d, //
    0x720c0ab3, 0x3c8b3782, 0xa6e4030b, 0x0002d285, 0x4db0abb6, //
    0x3c834d75, 0x0a31b715, 0x000306fe, 0x5dd3f84a, 0x3c8fdd39, //
    0xb26416ff, 0x00033c08, 0xcc187d29, 0x3ca12f8c, 0x373aa9ca, //
    0x000371a7, 0x738b5e8b, 0x3ca7d229, 0x34e59ff6, 0x0003a7db, //
    0xa72a4c6d, 0x3c859f48, 0x4c123422, 0x0003dea6, 0x259d9205, //
    0x3ca8b846, 0x21f72e29, 0x0004160a, 0x60c2ac12, 0x3c4363ed, //
    0x6061892d, 0x00044e08, 0xdaa10379, 0x3c6ecce1, 0xb5c13cd0, //
    0x000486a2, 0xbb7aafb0, 0x3c7690ce, 0xd5362a27, 0x0004bfda, //
    0x9b282a09, 0x3ca083cc, 0x769d2ca6, 0x0004f9b2, 0xc1aae707, //
    0x3ca509b0, 0x569d4f81, 0x0005342b, 0x18fdd78e, 0x3c933505, //
    0x36b527da, 0x00056f47, 0xe21c5409, 0x3c9063e1, 0xdd485429, //
    0x0005ab07, 0x2b64c035, 0x3c9432e6, 0x15ad2148, 0x0005e76f, //
    0x99f08c0a, 0x3ca01284, 0xb03a5584, 0x0006247e, 0x0073dc06, //
    0x3c99f087, 0x82552224, 0x00066238, 0x0da05571, 0x3c998d4d, //
    0x667f3bcc, 0x0006a09e, 0x86ce4786, 0x3ca52bb9, 0x3c651a2e, //
    0x0006dfb2, 0x206f0dab, 0x3ca32092, 0xe8ec5f73, 0x00071f75, //
    0x8e17a7a6, 0x3ca06122, 0x564267c8, 0x00075feb, 0x461e9f86, //
    0x3ca244ac, 0x73eb0186, 0x0007a114, 0xabd66c55, 0x3c65ebe1, //
    0x36cf4e62, 0x0007e2f3, 0xbbff67d0, 0x3c96fe9f, 0x994cce12, //
    0x00082589, 0x14c801df, 0x3c951f14, 0x9b4492ec, 0x000868d9, //
    0xc1f0eab4, 0x3c8db72f, 0x422aa0db, 0x0008ace5, 0x59f35f44, //
    0x3c7bf683, 0x99157736, 0x0008f1ae, 0x9c06283c, 0x3ca360ba, //
    0xb0cdc5e4, 0x00093737, 0x20f962aa, 0x3c95e8d1, 0x9fde4e4f, //
    0x00097d82, 0x2b91ce27, 0x3c71affc, 0x82a3f090, 0x0009c491, //
    0x589a2ebd, 0x3c9b6d34, 0x7b5de564, 0x000a0c66, 0x9ab89880, //
    0x3c95277c, 0xb23e255c, 0x000a5503, 0x6e735ab3, 0x3c846984, //
    0x5579fdbf, 0x000a9e6b, 0x92cb3387, 0x3c8c1a77, 0x995ad3ad, //
    0x000ae89f, 0xdc2d1d96, 0x3ca22466, 0xb84f15fa, 0x000b33a2, //
    0xb19505ae, 0x3ca1112e, 0xf2fb5e46, 0x000b7f76, 0x0a5fddcd, //
    0x3c74ffd7, 0x904bc1d2, 0x000bcc1e, 0x30af0cb3, 0x3c736eae, //
    0xdd85529c, 0x000c199b, 0xd10959ac, 0x3c84e08f, 0x2e57d14b, //
    0x000c67f1, 0x6c921968, 0x3c676b2c, 0xdcef9069, 0x000cb720, //
    0x36df99b3, 0x3c937009, 0x4a07897b, 0x000d072d, 0xa63d07a7, //
    0x3c74a385, 0xdcfba487, 0x000d5818, 0xd5c192ac, 0x3c8e5a50, //
    0x03db3285, 0x000da9e6, 0x1c4a9792, 0x3c98bb73, 0x337b9b5e, //
    0x000dfc97, 0x603a88d3, 0x3c74b604, 0xe78b3ff6, 0x000e502e, //
    0x92094926, 0x3c916f27, 0xa2a490d9, 0x000ea4af, 0x41aa2008, //
    0x3c8ec3bc, 0xee615a27, 0x000efa1b, 0x31d185ee, 0x3c8a64a9, //
    0x5b6e4540, 0x000f5076, 0x4d91cd9d, 0x3c77893b, 0x819e90d8, //
    0x000fa7c1,
  ];

  static final List<double> _expTlo = List<double>.generate(
    64,
    (j) => longBitsToDouble(
      (_expTblWords[4 * j + 1] << 32) | _expTblWords[4 * j],
    ),
    growable: false,
  );

  static final List<int> _expThiBits = List<int>.generate(
    64,
    (j) => (_expTblWords[4 * j + 3] << 32) | _expTblWords[4 * j + 2],
    growable: false,
  );

  static const int _mask64 = 0xffffffffffffffff;

  /// `Math.exp(x)`: a transcription of `MacroAssembler::fast_exp`
  /// (macroAssembler_x86_exp.cpp of jdk17u, the 64-bit stub), the LIBM
  /// table-driven algorithm `e^x = 2^n * T[j] * (1 + P(y))` with K = 64,
  /// including its overflow/underflow branch (`L_2TAG_PACKET_1_0_2`, which
  /// assembles subnormal results with integer arithmetic on the bit
  /// patterns) and the special cases. Unlike sin/cos every path is ported.
  static double exp(double x) {
    final bits = doubleToRawLongBits(x);
    final hiWord = (bits >> 32) & 0xffffffff; // Address(rsp, 12)
    final loWord = bits & 0xffffffff; // Address(rsp, 8)
    var eax = ((bits >> 48) & 0xffff) & 32767; // pextrw(eax, xmm0, 3)
    var edx = 16527 - eax;
    eax -= 15504;
    edx = (edx | eax) & 0xffffffff;
    if (edx >= 0x80000000) {
      // L_2TAG_PACKET_0_0_2: |x| < 2^-54 or |x| >= 1024
      final ax = hiWord & 0x7fffffff;
      if (ax >= 1083179008) {
        // L_2TAG_PACKET_8_0_2
        if (ax >= 2146435072) {
          // L_2TAG_PACKET_9_0_2: infinities and NaNs
          if (ax > 2146435072 || loWord != 0) return x + x; // NaN
          return hiWord == 2146435072 ? double.infinity : 0.0;
        }
        // XMAX * XMAX (overflow) or XMIN * XMIN (underflow)
        return hiWord < 0x80000000 ? double.infinity : 0.0;
      }
      return x + 1.0;
    }

    // range reduction: n = round(x * 64/ln2), j = n mod 64, N = n div 64
    final y = x * _expL2e64;
    final ys = y + _expShifter;
    final nd = ys - _expShifter;
    final n = (doubleToRawLongBits(ys) & 0xffffffff).toSigned(32);
    final j = n & 63;
    final nhi = n >> 6;
    final u = n & 0xffffffc0; // pand mmask (low dword, high dword zero)
    final expBits = ((u + 0xffc0) << 46) & _mask64; // paddq bias, psllq 46
    final r1 = x - nd * _expLn2hi64;
    final r = r1 - nd * _expLn2lo64;
    final c6r = _expC6 * r;
    final c4r = _expC4 * r;
    final r2 = r * r;
    final r3 = r * r2;
    final p5 = _expC5 + c6r;
    final p3 = _expC3 + c4r;
    final r5 = r3 * r2;
    final r2h = r2 * _expHalf;
    var t1 = r + _expTlo[j];
    final q5 = r5 * p5;
    final q3 = r3 * p3;
    t1 = t1 + q5;
    final tBits = _expThiBits[j] | expBits; // por(xmm2, xmm7)
    var t0 = q3 + t1;
    t0 = t0 + r2h;
    edx = (nhi + 894) & 0xffffffff;
    if (edx <= 1916) {
      final t = longBitsToDouble(tBits);
      return t0 * t + t;
    }

    // L_2TAG_PACKET_1_0_2: 2^N out of the normal range
    edx = (-1022 - nhi) & 0xffffffff;
    final mask4 = edx > 63 ? 0 : (_mask64 << edx) & _mask64; // psllq(xmm4, edx)
    final ecx = nhi;
    eax = nhi >> 1;
    var x3Bits = ((eax & 0xffff) << 52) & _mask64; // pinsrw word 3, psllq 4
    // psubd(xmm2, xmm3): 32-bit lanes
    final t2Bits =
        ((((tBits >> 32) & 0xffffffff) - ((x3Bits >> 32) & 0xffffffff)) &
                0xffffffff) <<
            32 |
        (tBits & 0xffffffff);
    final t2 = longBitsToDouble(t2Bits);
    var res = t0 * t2;
    if (edx.toSigned(32) > 52) {
      // L_2TAG_PACKET_2_0_2
      x3Bits = _paddd(x3Bits, 0x3ff0000000000000);
      res = res + t2;
      return res * longBitsToDouble(x3Bits);
    }
    final x4Bits = mask4 & t2Bits;
    final x4 = longBitsToDouble(x4Bits);
    x3Bits = _paddd(x3Bits, 0x3ff0000000000000);
    final x3 = longBitsToDouble(x3Bits);
    final tlow = t2 - x4;
    res = res + tlow;
    if (ecx >= 1023) {
      // L_2TAG_PACKET_3_0_2 (an overflow flag is raised, the value is returned)
      return (res + x4) * x3;
    }
    final sign = ((doubleToRawLongBits(res) >> 48) & 0xffff) & 32768;
    edx |= sign;
    if (edx == 0) {
      // L_2TAG_PACKET_4_0_2
      return (res + x4) * x3;
    }
    final saved = res;
    res = (res + x4) * x3;
    final ex = ((doubleToRawLongBits(res) >> 48) & 0xffff) & 32752;
    if (ex != 0) return res;
    // L_2TAG_PACKET_5_0_2: subnormal result, exact assembly on the bit patterns
    final aBits = doubleToRawLongBits(saved * x3);
    final bBits = doubleToRawLongBits(x4 * x3);
    final s = ((aBits ^ bBits) < 0) ? _mask64 : 0; // psrad 31, pshufd 85
    var out = aBits & 0x7fffffffffffffff; // psllq 1, psrlq 1
    out ^= s;
    out = (out + (s == 0 ? 0 : 1)) & _mask64; // paddq(xmm0, xmm6 >>> 63)
    out = (out + bBits) & _mask64;
    return longBitsToDouble(out);
  }

  /// `paddd`: 32-bit lane addition of two 64-bit lanes.
  static int _paddd(int a, int b) {
    final lo = ((a & 0xffffffff) + (b & 0xffffffff)) & 0xffffffff;
    final hi = (((a >> 32) & 0xffffffff) + ((b >> 32) & 0xffffffff)) &
        0xffffffff;
    return (hi << 32) | lo;
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
