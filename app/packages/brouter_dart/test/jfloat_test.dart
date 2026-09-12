// JVM float semantics against `run_dump.sh math-vectors`
// (test/vectors/expressions/float.json): Float.parseFloat, Float.toString,
// float arithmetic, int/float conversions, String.format("%3.1f"),
// Integer.parseInt, Arrays.hashCode(float[]), Character.isWhitespace and
// String.split as the expressions module uses them.

import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

String hex8(int bits) => bits.toUnsigned(32).toRadixString(16).padLeft(8, '0');

void main() {
  final v = loadExpressionsVector('float.json');

  test(
    'Float.parseFloat: grammar and correct rounding (incl. float midpoints)',
    () {
      final cases = (v['parseFloat'] as List).cast<List>();
      expect(cases.length, greaterThan(4000));
      var midpoints = 0;
      for (final c in cases) {
        final s = c[0] as String;
        final bits = c[1] as int?;
        if (bits == null) {
          expect(
            () => javaParseFloat(s),
            throwsA(isA<NumberFormatException>()),
            reason: 'Java rejects "$s"',
          );
          continue;
        }
        final f = javaParseFloat(s);
        expect(
          hex8(floatToIntBits(f)),
          hex8(floatToIntBits(intBitsToFloat(bits))),
          reason:
              'parseFloat("$s") should be ${c[2]}, got ${javaFloatToString(f)}',
        );
        expect(javaFloatToString(f), c[2], reason: 'Float.toString of "$s"');
        if (s.length > 20) midpoints++;
        // the naive double.parse + float round trip is what the vector guards against
      }
      expect(midpoints, greaterThan(1000));
    },
  );

  test('a decimal on a float midpoint is not double-rounded', () {
    // 1.000000059604644775390626 lies just above the midpoint between 1.0f and
    // the next float (1.0000001192092896f); double.parse lands exactly on the
    // midpoint and a Float32List round trip then rounds to even (down).
    const s = '1.000000059604644775390626';
    expect(floatToRawIntBits(f32(double.parse(s))), 0x3f800000);
    expect(floatToRawIntBits(javaParseFloat(s)), 0x3f800001);
  });

  test('Float.toString (JDK 17 FloatingDecimal.dtoa) for ~17 000 floats', () {
    final cases = (v['toString'] as List).cast<List>();
    expect(cases.length, greaterThan(17000));
    final failures = <String>[];
    for (final c in cases) {
      final f = intBitsToFloat(c[0] as int);
      final actual = javaFloatToString(f);
      if (actual != c[1]) {
        failures.add(
          'bits ${hex8(c[0] as int)}: got $actual, expected ${c[1]}',
        );
      }
    }
    expect(
      failures,
      isEmpty,
      reason:
          '${failures.length} mismatches, first: ${failures.take(5).join('; ')}',
    );
  });

  test('float + - * / round like the JVM', () {
    final cases = (v['arith'] as List).cast<List>();
    for (final c in cases) {
      final a = intBitsToFloat(c[0] as int);
      final b = intBitsToFloat(c[1] as int);
      final results = [f32(a + b), f32(a - b), f32(a * b), f32(a / b)];
      for (var k = 0; k < 4; k++) {
        expect(
          hex8(floatToIntBits(results[k])),
          hex8(floatToIntBits(intBitsToFloat(c[2 + k] as int))),
          reason:
              'op $k on ${javaFloatToString(a)} and ${javaFloatToString(b)}',
        );
      }
    }
  });

  test('int -> float conversions: i / 100f and (float) i', () {
    for (final c in (v['intToFloat'] as List).cast<List>()) {
      final i = c[0] as int;
      expect(
        floatToRawIntBits(f32(f32(i.toDouble()) / 100.0)),
        c[1],
        reason: '$i / 100f',
      );
      expect(floatToRawIntBits(f32(i.toDouble())), c[2], reason: '(float) $i');
    }
  });

  test('float -> int casts: (int) (Math.abs(f) * 100f) and (int) f', () {
    for (final c in (v['floatToInt'] as List).cast<List>()) {
      final f = intBitsToFloat(c[0] as int);
      expect(
        d2i(f32(f.abs() * 100.0)),
        c[1],
        reason: '(int)(|${javaFloatToString(f)}| * 100f)',
      );
      expect(d2i(f), c[2], reason: '(int) ${javaFloatToString(f)}');
    }
  });

  test('String.format(Locale.US, "%3.1f", f)', () {
    final cases = (v['format1'] as List).cast<List>();
    expect(cases.length, greaterThan(5000));
    final failures = <String>[];
    for (final c in cases) {
      final f = intBitsToFloat(c[0] as int);
      final actual = javaFormatFixed(f, 1);
      if (actual != c[1]) {
        failures.add('${javaFloatToString(f)}: got $actual, expected ${c[1]}');
      }
    }
    expect(
      failures,
      isEmpty,
      reason:
          '${failures.length} mismatches, first: ${failures.take(5).join('; ')}',
    );
  });

  test('Integer.parseInt', () {
    for (final c in (v['parseInt'] as List).cast<List>()) {
      final s = c[0] as String;
      if (s.codeUnits.any((u) => u > 0x7f)) {
        // the JDK accepts every Unicode decimal digit ("٣" is 3); the port
        // takes ASCII digits only -- see README
        continue;
      }
      final expected = c[1] as int?;
      if (expected == null) {
        expect(
          () => javaParseInt(s),
          throwsA(isA<NumberFormatException>()),
          reason: '"$s"',
        );
      } else {
        expect(javaParseInt(s), expected, reason: '"$s"');
      }
    }
  });

  test('Arrays.hashCode(float[])', () {
    for (final c in (v['arraysHashCode'] as List).cast<List>()) {
      final bits = (c[0] as List).cast<int>();
      final a = Float32List(bits.length);
      for (var i = 0; i < bits.length; i++) {
        a[i] = intBitsToFloat(bits[i]);
      }
      expect(arraysHashCodeFloat(a), c[1]);
    }
  });

  test('Character.isWhitespace', () {
    final ws = (v['isWhitespace'] as List).cast<int>().toSet();
    for (var c = 0; c < 0x3100; c++) {
      expect(
        javaIsWhitespace(c),
        ws.contains(c),
        reason: 'U+${c.toRadixString(16)}',
      );
    }
  });

  test('String.trim and String.split with the unit separators', () {
    const seps = ['ft', "'", 'cm', 't', 'st', 'kg'];
    for (final c in (v['split'] as List).cast<List>()) {
      final s = c[0] as String;
      expect(javaTrim(s), c[1]);
      for (var k = 0; k < seps.length; k++) {
        expect(
          javaSplit(s, seps[k]),
          (c[2 + k] as List).cast<String>(),
          reason: '"$s".split("${seps[k]}")',
        );
      }
    }
  });

  test('JavaRandom reproduces java.util.Random', () {
    // new Random(42): nextInt() sequence and nextInt(10) values of the JDK
    final r = JavaRandom(42);
    expect(r.nextInt(), -1170105035);
    expect(r.nextInt(), 234785527);
    final r2 = JavaRandom(42);
    expect([for (var i = 0; i < 5; i++) r2.nextInt(10)], [0, 3, 8, 4, 0]);
  });
}
