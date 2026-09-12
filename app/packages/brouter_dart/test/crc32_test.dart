import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  final vec = loadVector('crc32.json');
  final cases = (vec['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

  test('Crc32.crc matches the JVM for ${cases.length} inputs', () {
    for (final c in cases) {
      final ab = unhex(c['bytes'] as String);
      expect(
        Crc32.crc(ab, c['offset'] as int, c['len'] as int),
        c['crc'],
        reason: 'bytes=${c['bytes']} offset=${c['offset']} len=${c['len']}',
      );
    }
  });
}
