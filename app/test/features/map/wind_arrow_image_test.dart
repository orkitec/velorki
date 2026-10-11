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
    // 22 logical pixels tall at 3, and the field's room around it.
    expect(header.getUint32(0), greaterThanOrEqualTo(66 + 14));
  });
}
