import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  final vec = loadVector('streams.json');
  final cases = (vec['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

  var i = 0;
  for (final m in cases) {
    final idx = i++;
    if (m['kind'] == 'mix') {
      test('MixCoderDataOutputStream / InputStream case $idx', () {
        final values = (m['values'] as List<dynamic>).cast<int>();
        final mos = MixCoderDataOutputStream();
        for (final v in values) {
          mos.writeMixed(v);
        }
        mos.flush();
        final bytes = mos.toByteArray();
        expect(hex(bytes), m['bytes'], reason: 'encoded bytes');
        final mis = MixCoderDataInputStream(unhex(m['bytes'] as String));
        final out = [for (var k = 0; k < values.length; k++) mis.readMixed()];
        expect(out, (m['decoded'] as List<dynamic>).cast<int>());
      });
    } else {
      test('DiffCoderDataOutputStream / InputStream case $idx', () {
        final values = (m['values'] as List<dynamic>).cast<int>();
        final idxs = (m['idx'] as List<dynamic>).cast<int>();
        final dos = DiffCoderDataOutputStream();
        for (var k = 0; k < values.length; k++) {
          dos.writeDiffed(values[k], idxs[k]);
        }
        final bytes = dos.toByteArray();
        expect(hex(bytes), m['bytes'], reason: 'encoded bytes');
        final dis = DiffCoderDataInputStream(unhex(m['bytes'] as String));
        final out = [
          for (var k = 0; k < values.length; k++) dis.readDiffed(idxs[k]),
        ];
        expect(out, (m['decoded'] as List<dynamic>).cast<int>());
      });
    }
  }
}
