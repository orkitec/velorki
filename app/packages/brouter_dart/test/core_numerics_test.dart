// JVM numerics of brouter-core against `run_dump.sh core-vectors`
// (test/vectors/core/core.json.gz): Math.exp (the HotSpot x86_64 LIBM
// intrinsic), DecimalFormat("0.###") of float travel times and
// Double.toString of the elevations FormatJson prints.

import 'dart:convert';
import 'dart:io';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

Map<String, dynamic> loadCoreVector(String name) {
  final f = File('test/vectors/core/$name.gz');
  return jsonDecode(utf8.decode(gzip.decode(f.readAsBytesSync())))
      as Map<String, dynamic>;
}

void main() {
  final v = loadCoreVector('core.json');

  test('JMath.exp is bit-identical to HotSpot Math.exp', () {
    final cases = (v['exp'] as List).cast<String>();
    expect(cases.length, greaterThan(17000));
    var n = 0;
    for (final line in cases) {
      final p = line.split(' ');
      final x = longBitsToDouble(hexToLong(p[0]));
      final expected = hexToLong(p[1]);
      final actual = doubleToRawLongBits(JMath.exp(x));
      if (longBitsToDouble(expected).isNaN) {
        expect(JMath.exp(x).isNaN, isTrue, reason: 'exp(${describeDouble(x)})');
      } else {
        expect(
          actual.toRadixString(16),
          expected.toRadixString(16),
          reason: 'exp(${describeDouble(x)}) #$n',
        );
      }
      n++;
    }
  });

  test('DecimalFormat("0.###") of floats promoted to double', () {
    final cases = (v['decimalFormat'] as List).cast<String>();
    expect(cases.length, greaterThan(39000));
    for (final line in cases) {
      final sp = line.indexOf(' ');
      final f = intBitsToFloat(int.parse(line.substring(0, sp), radix: 16));
      expect(
        javaDecimalFormat(f),
        line.substring(sp + 1),
        reason: 'format(${javaFloatToString(f)})',
      );
    }
  });

  test('Double.toString of elevations and random doubles', () {
    final cases = (v['doubleToString'] as List).cast<String>();
    for (final line in cases) {
      final sp = line.indexOf(' ');
      final d = longBitsToDouble(hexToLong(line.substring(0, sp)));
      expect(javaDoubleToString(d), line.substring(sp + 1));
    }
  });

  test('float speed hack of the formatters', () {
    final cases = (v['speedHack'] as List).cast<String>();
    for (final line in cases) {
      final p = line.split(' ');
      final dist = int.parse(p[0]);
      final dt = intBitsToFloat(int.parse(p[1], radix: 16));
      // double speed = ((3.6f * dist) / dt + 0.5); (((int) (speed * 10)) / 10.f)
      final speed = f32(f32(f32(3.6) * dist) / dt) + 0.5;
      final s = f32(d2i(speed * 10) / 10.0);
      expect(javaFloatToString(s), p[2], reason: line);
    }
  });
}
