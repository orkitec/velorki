import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/domain/street_numbers.dart';

import 'support/street_numbers_encoder.dart';

void main() {
  test('a blob decodes to both sides, in order', () {
    final data = encodeStreetNumbers(
      <(int, double, double)>[(1, 52.50001, 13.40001), (41, 52.50101, 13.4)],
      <(int, double, double)>[(2, 52.49998, 13.40002), (300, -33.9, -70.6)],
    );
    final sides = decodeStreetNumbers(data)!;
    expect(sides.odd.map((p) => p.number), <int>[1, 41]);
    expect(sides.even.map((p) => p.number), <int>[2, 300]);
    expect(sides.odd.first.position.lat, closeTo(52.50001, 1e-9));
    expect(sides.even.last.position.lat, closeTo(-33.9, 1e-9));
    expect(sides.even.last.position.lon, closeTo(-70.6, 1e-9));
  });

  test('an empty side, an unknown version and a broken blob', () {
    final oneSided = decodeStreetNumbers(
      encodeStreetNumbers(<(int, double, double)>[], <(int, double, double)>[
        (2, 1, 1),
      ]),
    )!;
    expect(oneSided.odd, isEmpty);
    expect(oneSided.even, hasLength(1));

    final data = encodeStreetNumbers(<(int, double, double)>[
      (1, 47, 9),
    ], <(int, double, double)>[]);
    expect(
      decodeStreetNumbers(Uint8List.fromList(<int>[2, ...data.skip(1)])),
      isNull,
    );
    expect(
      decodeStreetNumbers(Uint8List.sublistView(data, 0, data.length - 1)),
      isNull,
    );
    expect(decodeStreetNumbers(Uint8List.fromList(<int>[...data, 0])), isNull);
    expect(decodeStreetNumbers(Uint8List(0)), isNull);
  });

  group('locateOnStreet', () {
    final sides = decodeStreetNumbers(
      encodeStreetNumbers(
        <(int, double, double)>[(1, 47.0, 9.0), (21, 47.002, 9.0)],
        <(int, double, double)>[(2, 47.0, 9.0002), (40, 47.0038, 9.0002)],
      ),
    )!;

    test('between two points of its side: interpolated, good as exact', () {
      final at = locateOnStreet(sides, 11)!;
      expect(at.position.lat, closeTo(47.001, 1e-9));
      expect(at.position.lon, closeTo(9.0, 1e-9));
      expect(at.approximate, isFalse);
      final even = locateOnStreet(sides, 21 + 1)!;
      expect(even.position.lon, closeTo(9.0002, 1e-9), reason: 'its own side');
    });

    test('past either end: the end point, approximate', () {
      final high = locateOnStreet(sides, 99)!;
      expect(high.position.lat, closeTo(47.002, 1e-9));
      expect(high.approximate, isTrue);
      expect(locateOnStreet(sides, 40)!.approximate, isFalse);
    });

    test('a side with no points borrows the other one, approximate', () {
      final oneSided = decodeStreetNumbers(
        encodeStreetNumbers(<(int, double, double)>[
          (1, 47.0, 9.0),
          (9, 47.001, 9.0),
        ], <(int, double, double)>[]),
      )!;
      final at = locateOnStreet(oneSided, 4)!;
      expect(at.approximate, isTrue);
      expect(at.position.lat, closeTo(47.000375, 1e-9));
    });
  });
}
