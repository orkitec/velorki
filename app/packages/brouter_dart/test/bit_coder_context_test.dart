import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  final vec = loadVector('bitcoder.json');
  final cases = vec['cases'] as List<dynamic>;

  for (final c in cases) {
    final m = c as Map<String, dynamic>;
    final name = m['name'] as String;
    if (m.containsKey('ops')) {
      test('BitCoderContext encode/decode: $name', () {
        final ops = (m['ops'] as List<dynamic>).cast<List<dynamic>>();
        final buf = Uint8List(1 << 20);
        final ctx = BitCoderContext(buf);
        for (final op in ops) {
          switch (op[0] as String) {
            case 'varbits':
              ctx.encodeVarBits(op[1] as int);
            case 'varbits2':
              ctx.encodeVarBits2(op[1] as int);
            case 'bit':
              ctx.encodeBit((op[1] as int) != 0);
            case 'bounded':
              ctx.encodeBounded(op[1] as int, op[2] as int);
            default:
              fail('unknown op ${op[0]}');
          }
        }
        final len = ctx.closeAndGetEncodedLength();
        expect(hex(buf, len), m['bytes'], reason: 'encoded bytes');

        final rd = BitCoderContext(
          padded(unhex(m['bytes'] as String), m['decodePadding'] as int),
        );
        final decoded = <int>[];
        for (final op in ops) {
          switch (op[0] as String) {
            case 'varbits':
              decoded.add(rd.decodeVarBits());
            case 'varbits2':
              decoded.add(rd.decodeVarBits2());
            case 'bit':
              decoded.add(rd.decodeBit() ? 1 : 0);
            case 'bounded':
              decoded.add(rd.decodeBounded(op[1] as int));
          }
        }
        expect(decoded, (m['decoded'] as List<dynamic>).cast<int>());
      });
    } else {
      test('BitCoderContext read-only: $name', () {
        final ops = (m['readops'] as List<dynamic>).cast<List<dynamic>>();
        final ctx = BitCoderContext(unhex(m['bytes'] as String));
        final results = <int>[];
        for (final op in ops) {
          switch (op[0] as String) {
            case 'bits':
              results.add(ctx.decodeBits(op[1] as int));
            case 'bitsrev':
              results.add(ctx.decodeBitsReverse(op[1] as int));
            case 'bit':
              results.add(ctx.decodeBit() ? 1 : 0);
            case 'bounded':
              results.add(ctx.decodeBounded(op[1] as int));
            case 'varbits':
              results.add(ctx.decodeVarBits());
            case 'varbits2':
              results.add(ctx.decodeVarBits2());
            case 'setpos':
              ctx.setReadingBitPosition(op[1] as int);
              results.add(ctx.getReadingBitPosition());
            case 'pos':
              results.add(ctx.getReadingBitPosition());
            default:
              fail('unknown op ${op[0]}');
          }
        }
        expect(results, (m['results'] as List<dynamic>).cast<int>());
      });
    }
  }

  test('BitCoderContext.main() self-check of upstream', () {
    final ab = Uint8List(581969);
    var ctx = BitCoderContext(ab);
    for (var i = 0; i < 31; i++) {
      ctx.encodeVarBits((1 << i) + 3);
    }
    for (var i = 0; i < 100000; i += 13) {
      ctx.encodeVarBits(i);
    }
    ctx.closeAndGetEncodedLength();
    ctx = BitCoderContext(ab);
    for (var i = 0; i < 31; i++) {
      expect(ctx.decodeVarBits(), (1 << i) + 3);
    }
    for (var i = 0; i < 100000; i += 13) {
      expect(ctx.decodeVarBits(), i);
    }
  });
}
