import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/wind_arrow_image.dart';

void main() {
  test('the arrow is a distance field: over 0.75 inside, under it outside, '
      'nothing 6 pixels out', () {
    const side = 40;
    final rgba = windArrowField(side, windArrowOutline);
    int alphaAt(double x, double y) {
      final px = (x + side / 2 - 0.5).round();
      final py = (y + side / 2 - 0.5).round();
      return rgba[(py * side + px) * 4 + 3];
    }

    // The middle of the shaft and of the head.
    expect(alphaAt(0, 5), greaterThan(191));
    expect(alphaAt(0, -5), greaterThan(191));
    // Beyond the shaft's edge, at 1.5, under the edge's value.
    expect(alphaAt(2, 5), lessThan(191));
    // Far out: nothing.
    expect(alphaAt(12, 12), 0);
    expect(alphaAt(-15, -15), 0);
    // Black: only the alpha is read.
    for (var i = 0; i < rgba.length; i += 4) {
      expect(rgba[i] | rgba[i + 1] | rgba[i + 2], 0);
    }
  });

  test('the arrow points up: more of it above the middle is the head', () {
    const side = 40;
    final rgba = windArrowField(side, windArrowOutline);
    int widthOfRow(int y) {
      var n = 0;
      for (var x = 0; x < side; x++) {
        if (rgba[(y * side + x) * 4 + 3] >= 191) n++;
      }
      return n;
    }

    // Four pixels above the middle the head is wide, below it the shaft.
    expect(widthOfRow(side ~/ 2 - 5), greaterThan(widthOfRow(side ~/ 2 + 5)));
  });

  test('a square PNG at the screen density', () {
    final png = buildWindArrowImage(devicePixelRatio: 3);
    expect(png.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
    final header = ByteData.sublistView(png, 16, 24);
    expect(header.getUint32(0), header.getUint32(4));
    // 28 logical pixels tall at 3, and the field's room around it.
    expect(header.getUint32(0), greaterThanOrEqualTo(84 + 14));
  });

  test('a long thin shaft under a solid triangular head, not a chevron', () {
    const side = 48;
    final rgba = windArrowField(side, windArrowOutline);
    int widthOfRow(double y) {
      final py = (y + side / 2 - 0.5).round();
      var n = 0;
      for (var x = 0; x < side; x++) {
        if (rgba[(py * side + x) * 4 + 3] >= 191) n++;
      }
      return n;
    }

    // The shaft: thin and the same all along, more than half the length.
    for (final y in <double>[-2, 3, 8, 13]) {
      expect(widthOfRow(y), inInclusiveRange(2, 3), reason: 'row $y');
    }
    // The head: solid (its middle filled, unlike a chevron's), widening
    // from its tip to its base.
    expect(widthOfRow(-12), lessThan(widthOfRow(-8)));
    expect(widthOfRow(-8), lessThan(widthOfRow(-5)));
    expect(widthOfRow(-5), greaterThanOrEqualTo(11));
    int alphaAt(double x, double y) {
      final px = (x + side / 2 - 0.5).round();
      final py = (y + side / 2 - 0.5).round();
      return rgba[(py * side + px) * 4 + 3];
    }

    for (final y in <double>[-11, -8, -5]) {
      expect(alphaAt(0, y), greaterThan(191), reason: 'head middle at $y');
    }
  });

  test('crisp at every density: the edge lies where the outline does', () {
    for (final ratio in <double>[1, 1.5, 2, 2.625, 3, 3.5, 4]) {
      final pts = <(double, double)>[
        for (final (x, y) in windArrowOutline) (x * ratio, y * ratio),
      ];
      final side = (28 * ratio).ceil() + 16;
      final rgba = windArrowField(side, pts);
      int alphaAt(double x, double y) {
        final px = (x + side / 2 - 0.5).floor();
        final py = (y + side / 2 - 0.5).floor();
        return rgba[(py * side + px) * 4 + 3];
      }

      // A pixel inside the shaft's edge is over the edge's value, a pixel
      // outside it under: the edge is sharp to a pixel at any density.
      final edge = 1.2 * ratio;
      expect(alphaAt(edge - 1, 5 * ratio), greaterThan(191), reason: '$ratio');
      expect(alphaAt(edge + 1, 5 * ratio), lessThan(191), reason: '$ratio');
    }
  });
}
