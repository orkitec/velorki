import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  final vec = loadVector('noisydiff.json');
  final cases = (vec['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

  var i = 0;
  for (final m in cases) {
    final idx = i++;
    test('NoisyDiffCoder 3-pass encode + decode, case $idx', () {
      final values = (m['values'] as List<dynamic>).cast<int>();
      final buf = Uint8List(1 << 20);
      final coder = NoisyDiffCoder();
      late StatCoderContext bc;
      for (var pass = 1; pass <= 3; pass++) {
        bc = StatCoderContext(buf);
        coder.encodeDictionary(bc);
        for (final v in values) {
          coder.encodeSignedValue(v);
        }
      }
      final len = bc.closeAndGetEncodedLength();
      expect(hex(buf, len), m['bytes'], reason: 'encoded bytes');

      final rd = StatCoderContext(padded(unhex(m['bytes'] as String), 8));
      final dec = NoisyDiffCoder.decoder(rd);
      final out = [
        for (var k = 0; k < values.length; k++) dec.decodeSignedValue(),
      ];
      expect(out, (m['decoded'] as List<dynamic>).cast<int>());
    });
  }
}
