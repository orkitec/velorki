import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  final vec = loadVector('tagvaluecoder.json');
  final cases = (vec['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

  var i = 0;
  for (final m in cases) {
    final idx = i++;
    test(
      'TagValueCoder 3-pass encode + decode, case $idx (${(m['input'] as List).length} sets)',
      () {
        final datas = [
          for (final h in m['input'] as List<dynamic>) unhexOrNull(h),
        ];
        final buf = Uint8List(1 << 20);
        final coder = TagValueCoder();
        late BitCoderContext bc;
        for (var pass = 1; pass <= 3; pass++) {
          bc = BitCoderContext(buf);
          coder.encodeDictionary(bc);
          for (final d in datas) {
            coder.encodeTagValueSet(d);
          }
        }
        final len = bc.closeAndGetEncodedLength();
        expect(hex(buf, len), m['bytes'], reason: 'encoded bytes');

        final rd = BitCoderContext(padded(unhex(m['bytes'] as String), 8));
        final dec = TagValueCoder.decoder(rd, DataBuffers(), null);
        final decoded = <Object?>[];
        for (var k = 0; k < datas.length; k++) {
          final w = dec.decodeTagValueSet();
          decoded.add(w == null ? null : [hex(w.data!), w.accessType]);
        }
        expect(decoded, m['decoded']);
        expect(rd.getReadingBitPosition(), m['readBits']);
      },
    );
  }
}
