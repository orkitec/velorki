import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  final vec = loadVector('cheapruler.json');

  void expectBits(double actual, Object? expected, String reason) {
    final e = doubleOf(expected);
    expect(
      doubleToRawLongBits(actual),
      bitsOf(expected),
      reason:
          '$reason: got ${describeDouble(actual)}, expected ${describeDouble(e)}',
    );
  }

  test('CheapRuler scale cache: all 1800 entries bit-identical', () {
    final cache = (vec['scaleCache'] as List<dynamic>).cast<List<dynamic>>();
    expect(cache.length, 1800);
    for (var i = 0; i < 1800; i++) {
      final k = CheapRuler.getLonLatToMeterScales(i * 100000 + 50000);
      final kx = hexToLong(cache[i][0] as String);
      final ky = hexToLong(cache[i][1] as String);
      expect(
        doubleToRawLongBits(k[0]),
        kx,
        reason: 'kx at cache index $i: ${describeDouble(k[0])}',
      );
      expect(
        doubleToRawLongBits(k[1]),
        ky,
        reason: 'ky at cache index $i: ${describeDouble(k[1])}',
      );
    }
  });

  test('CheapRuler.getLonLatToMeterScales', () {
    for (final c
        in (vec['scales'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final k = CheapRuler.getLonLatToMeterScales(c['ilat'] as int);
      expectBits(k[0], c['kx'], 'kx ilat=${c['ilat']}');
      expectBits(k[1], c['ky'], 'ky ilat=${c['ilat']}');
    }
  });

  test('CheapRuler.distance', () {
    for (final c
        in (vec['distances'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final p = (c['p'] as List<dynamic>).cast<int>();
      expectBits(
        CheapRuler.distance(p[0], p[1], p[2], p[3]),
        c['d'],
        'distance $p',
      );
    }
  });

  test('CheapRuler.destination', () {
    for (final c
        in (vec['destinations'] as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      final res = CheapRuler.destination(
        c['lon'] as int,
        c['lat'] as int,
        doubleOf(c['dist']),
        doubleOf(c['angle']),
      );
      expect(
        res.toList(),
        (c['res'] as List<dynamic>).cast<int>(),
        reason:
            'destination lon=${c['lon']} lat=${c['lat']} dist=${(c['dist'] as Map)['str']} angle=${(c['angle'] as Map)['str']}',
      );
    }
  });

  test('CheapAngleMeter.calcAngle / getCosAngle / getAngle / getDirection', () {
    final am = CheapAngleMeter();
    for (final c
        in (vec['angles'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final p = (c['p'] as List<dynamic>).cast<int>();
      final a = am.calcAngle(p[0], p[1], p[2], p[3], p[4], p[5]);
      expectBits(a, c['angle'], 'calcAngle $p');
      expectBits(am.getCosAngle(), c['cos'], 'getCosAngle $p');
      expectBits(
        CheapAngleMeter.getAngle(p[0], p[1], p[2], p[3]),
        c['getAngle'],
        'getAngle $p',
      );
      expectBits(
        CheapAngleMeter.getDirection(p[0], p[1], p[2], p[3]),
        c['getDirection'],
        'getDirection $p',
      );
    }
  });

  test('CheapAngleMeter.normalize', () {
    for (final c
        in (vec['normalize'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      expectBits(
        CheapAngleMeter.normalize(doubleOf(c['a'])),
        c['n'],
        'normalize ${(c['a'] as Map)['str']}',
      );
    }
  });

  test('CheapAngleMeter.getDifferenceFromDirection', () {
    for (final c
        in (vec['differences'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      expectBits(
        CheapAngleMeter.getDifferenceFromDirection(
          doubleOf(c['b1']),
          doubleOf(c['b2']),
        ),
        c['d'],
        'difference ${(c['b1'] as Map)['str']} ${(c['b2'] as Map)['str']}',
      );
    }
  });
}
