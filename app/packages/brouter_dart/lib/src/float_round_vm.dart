/// `(double) (float) v` on the VM (JIT and AOT): through a SIMD lane, which
/// the compiler keeps in registers (`fcvt` down, `fcvt` up), where a
/// `Float32List` store and load goes through memory. Measured 20 % faster on
/// a chain of roundings and 3-4 % on a whole route (R5, step H); the same
/// rounding instruction either way, and `test/float_round_test.dart` holds
/// the two to the same bits.
library;

import 'dart:typed_data';

@pragma('vm:prefer-inline')
double roundToFloat(double v) => Float32x4.splat(v).x;

/// [buffer] is what the web implementation rounds through; unused here.
@pragma('vm:prefer-inline')
double roundToFloatVia(Float32List buffer, double v) => Float32x4.splat(v).x;
