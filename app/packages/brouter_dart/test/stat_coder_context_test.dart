import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  final vec = loadVector('statcoder.json');
  final cases = vec['cases'] as List<dynamic>;

  for (final c in cases) {
    final m = c as Map<String, dynamic>;
    final name = m['name'] as String;
    test('StatCoderContext encode/decode: $name', () {
      final ops = (m['ops'] as List<dynamic>).cast<List<dynamic>>();
      final buf = Uint8List(1 << 20);
      final ctx = StatCoderContext(buf);
      for (final op in ops) {
        switch (op[0] as String) {
          case 'noisynum':
            ctx.encodeNoisyNumber(op[1] as int, op[2] as int);
          case 'noisydiff':
            ctx.encodeNoisyDiff(op[1] as int, op[2] as int);
          case 'predicted':
            ctx.encodePredictedValue(op[1] as int, op[2] as int);
          case 'varbits':
            ctx.encodeVarBits(op[1] as int);
          case 'bit':
            ctx.encodeBit((op[1] as int) != 0);
          case 'sorted':
            final a = Int32List.fromList((op[1] as List<dynamic>).cast<int>());
            ctx.encodeSortedArray(a, 0, a.length, 0x20000000, 0);
          default:
            fail('unknown op ${op[0]}');
        }
      }
      final len = ctx.closeAndGetEncodedLength();
      expect(hex(buf, len), m['bytes'], reason: 'encoded bytes');

      final rd = StatCoderContext(
        padded(unhex(m['bytes'] as String), m['decodePadding'] as int),
      );
      final decoded = <Object>[];
      for (final op in ops) {
        switch (op[0] as String) {
          case 'noisynum':
            decoded.add(rd.decodeNoisyNumber(op[2] as int));
          case 'noisydiff':
            decoded.add(rd.decodeNoisyDiff(op[2] as int));
          case 'predicted':
            decoded.add(rd.decodePredictedValue(op[2] as int));
          case 'varbits':
            decoded.add(rd.decodeVarBits());
          case 'bit':
            decoded.add(rd.decodeBit() ? 1 : 0);
          case 'sorted':
            final n = (op[1] as List<dynamic>).length;
            final out = Int32List(n);
            rd.decodeSortedArray(out, 0, n, 29, 0);
            decoded.add(out.toList());
        }
      }
      expect(decoded, m['decoded']);
    });
  }
}
