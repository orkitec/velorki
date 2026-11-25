/// `(double) (float) v` compiled for the web: a `Float32List` round trip.
/// `Float32x4`, which the VM implementation uses, is an allocated object
/// there.
library;

import 'dart:typed_data';

final Float32List _f32 = Float32List(1);

@pragma('wasm:prefer-inline')
double roundToFloat(double v) {
  _f32[0] = v;
  return _f32[0];
}

/// The same through a buffer the caller holds in a local: a top-level
/// `final` is lazily initialised and every access re-checks that.
@pragma('wasm:prefer-inline')
double roundToFloatVia(Float32List buffer, double v) {
  buffer[0] = v;
  return buffer[0];
}
