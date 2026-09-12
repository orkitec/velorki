// Port of btools.codec.DataBuffers (BRouter v1.7.10).

import 'dart:typed_data';

import '../util/bit_coder_context.dart';

/// Container for some re-usable databuffers for the decoder
class DataBuffers {
  /// construct a set of databuffers except
  /// for 'iobuffer', where the given array is used
  DataBuffers([Uint8List? iobuffer]) : iobuffer = iobuffer ?? Uint8List(65636) {
    bctx1 = BitCoderContext(tagbuf1);
  }

  Uint8List iobuffer;
  final Uint8List tagbuf1 = Uint8List(256);
  late final BitCoderContext bctx1;
  final Uint8List bbuf1 = Uint8List(65636); // sic: 65636 upstream
  final Int32List ibuf1 = Int32List(4096);
  final Int32List ibuf2 = Int32List(2048);
  final Int32List ibuf3 = Int32List(2048);
  final Int32List alon = Int32List(2048);
  final Int32List alat = Int32List(2048);
}
