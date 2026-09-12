import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  final vec = loadVector('bytedata.json');
  final cases = (vec['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

  for (final m in cases) {
    test('ByteDataWriter / ByteDataReader: ${m['name']}', () {
      final ops = (m['ops'] as List<dynamic>).cast<List<dynamic>>();
      final w = ByteDataWriter(Uint8List(1 << 20));
      final blockStack = <int>[];
      final blockRemaining = <int>[];
      for (final op in ops) {
        final n = op[0] as String;
        switch (n) {
          case 'int':
            w.writeInt(op[1] as int);
          case 'long':
            w.writeLong(op[1] as int);
          case 'short':
            w.writeShort(op[1] as int);
          case 'byte':
            w.writeByte(op[1] as int);
          case 'boolean':
            w.writeBoolean((op[1] as int) != 0);
          case 'varsigned':
            w.writeVarLengthSigned(op[1] as int);
          case 'varunsigned':
            w.writeVarLengthUnsigned(op[1] as int);
          case 'varbytes':
            w.writeVarBytes(unhexOrNull(op[1]));
          case 'modedesc':
            w.writeModeAndDesc((op[1] as int) != 0, unhexOrNull(op[2]));
          case 'sizeblock':
            blockStack.add(w.writeSizePlaceHolder());
            blockRemaining.add(op[1] as int);
            if (op[1] == 0) {
              w.injectSize(blockStack.removeLast());
              blockRemaining.removeLast();
            }
            continue;
          default:
            fail('unknown op $n');
        }
        while (blockRemaining.isNotEmpty) {
          final rem = blockRemaining.last - 1;
          if (rem > 0) {
            blockRemaining[blockRemaining.length - 1] = rem;
            break;
          }
          blockRemaining.removeLast();
          w.injectSize(blockStack.removeLast());
        }
      }
      final bytes = w.toByteArray();
      expect(hex(bytes), m['bytes'], reason: 'written bytes');
      expect(w.writtenSize(), m['size']);

      final r = ByteDataReader(bytes);
      final decoded = <Object?>[];
      for (final op in ops) {
        switch (op[0] as String) {
          case 'int':
            decoded.add(r.readInt());
          case 'long':
            decoded.add(r.readLong());
          case 'short':
            decoded.add(r.readShort());
          case 'byte':
            decoded.add(r.readByte());
          case 'boolean':
            decoded.add(r.readBoolean() ? 1 : 0);
          case 'varsigned':
            decoded.add(r.readVarLengthSigned());
          case 'varunsigned':
            decoded.add(r.readVarLengthUnsigned());
          case 'varbytes':
            final b = r.readVarBytes();
            decoded.add(b == null ? null : hex(b));
          case 'modedesc':
            final sizecode = r.readVarLengthUnsigned();
            final len = sizecode >> 1;
            Uint8List? d;
            if (len > 0) {
              d = Uint8List(len);
              r.readFully(d);
            }
            decoded.add([sizecode, d == null ? null : hex(d)]);
          case 'sizeblock':
            decoded.add(r.getEndPointer());
        }
      }
      expect(decoded, m['decoded']);
      expect(r.hasMoreData(), m['hasMoreData']);
    });
  }
}
