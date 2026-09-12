import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  final vec = loadVector('trig.json');

  test(
    'JMath.sin / JMath.cos are bit-identical to HotSpot Math.sin / Math.cos (${(vec['sincos'] as List).length} args)',
    () {
      for (final line in (vec['sincos'] as List<dynamic>).cast<String>()) {
        final p = line.split(' ');
        final x = longBitsToDouble(hexToLong(p[0]));
        expect(
          doubleToRawLongBits(JMath.sin(x)),
          hexToLong(p[1]),
          reason: 'sin(${describeDouble(x)})',
        );
        expect(
          doubleToRawLongBits(JMath.cos(x)),
          hexToLong(p[2]),
          reason: 'cos(${describeDouble(x)})',
        );
      }
    },
  );

  test(
    'JMath.atan2 is bit-identical to Math.atan2 (${(vec['atan2'] as List).length} pairs)',
    () {
      for (final line in (vec['atan2'] as List<dynamic>).cast<String>()) {
        final p = line.split(' ');
        final y = longBitsToDouble(hexToLong(p[0]));
        final x = longBitsToDouble(hexToLong(p[1]));
        final expected = hexToLong(p[2]);
        final actual = doubleToRawLongBits(JMath.atan2(y, x));
        if (longBitsToDouble(expected).isNaN) {
          expect(
            JMath.atan2(y, x).isNaN,
            isTrue,
            reason: 'atan2(${describeDouble(y)}, ${describeDouble(x)})',
          );
        } else {
          expect(
            actual,
            expected,
            reason: 'atan2(${describeDouble(y)}, ${describeDouble(x)})',
          );
        }
      }
    },
  );

  test('javaRound and the (int)/(long) casts', () {
    expect(javaRound(0.49999999999999994), 0);
    expect(javaRound(0.5), 1);
    expect(javaRound(-0.5), 0);
    expect(javaRound(-1.5), -1);
    expect(javaRound(2.5), 3);
    expect(javaRound(double.nan), 0);
    expect(javaRound(1e300), longMaxValue);
    expect(javaRound(-1e300), longMinValue);
    expect(d2i(1e10), intMaxValue);
    expect(d2i(-1e10), intMinValue);
    expect(d2i(double.nan), 0);
    expect(d2i(-2.9), -2);
    expect(d2l(9.3e18), longMaxValue);
    expect(d2l(-2.9), -2);
  });
}
