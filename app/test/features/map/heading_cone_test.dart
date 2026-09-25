import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/heading_cone.dart';

Future<ui.Image> _decode(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('headingConeLogicalSize', () {
    test('is as tall as the cone is long and as wide as its sector', () {
      final size = headingConeLogicalSize();

      expect(size.height, headingConeRadiusPx);
      // 70° sector: half of it is 35°, so the half width is r·sin(35°) ≈ 32,
      // rounded up to a whole pixel per side.
      expect(size.width, 66);
    });
  });

  group('buildHeadingConeImage', () {
    test('returns PNG bytes', () async {
      final bytes = buildHeadingConeImage(
        color: const Color(0xFF1E88E5),
        devicePixelRatio: 1,
      );

      expect(bytes, isNotEmpty);
      // The eight byte PNG signature (RFC 2083 §3.1).
      expect(bytes.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    });

    test('needs no raster thread, so it works with the app in the '
        'background', () async {
      // A spawned isolate has no access to the engine's raster thread:
      // `Picture.toImage` cannot run there, just as it cannot complete on
      // iOS while the app is in the background. The cone is drawn anyway.
      final bytes = await Isolate.run(
        () => buildHeadingConeImage(
          color: const Color(0xFF1E88E5),
          devicePixelRatio: 3,
        ),
      );
      final image = await _decode(bytes);
      addTearDown(image.dispose);
      final logical = headingConeLogicalSize();

      expect(image.width, (logical.width * 3).round());
      expect(image.height, (logical.height * 3).round());
    });

    test('hands out the same bytes for the same cone', () {
      Uint8List cone() => buildHeadingConeImage(
        color: const Color(0xFF1E88E5),
        devicePixelRatio: 2,
      );

      expect(identical(cone(), cone()), isTrue);
    });

    test('scales the bitmap with the device pixel ratio', () async {
      final logical = headingConeLogicalSize();
      for (final ratio in <double>[1, 2, 3]) {
        final image = await _decode(
          buildHeadingConeImage(
            color: const Color(0xFF1E88E5),
            devicePixelRatio: ratio,
          ),
        );
        addTearDown(image.dispose);

        expect(image.width, (logical.width * ratio).round());
        expect(image.height, (logical.height * ratio).round());
      }
    });

    test('paints the cone above the apex and nothing beside it', () async {
      final image = await _decode(
        buildHeadingConeImage(
          color: const Color(0xFF1E88E5),
          devicePixelRatio: 1,
        ),
      );
      addTearDown(image.dispose);
      final pixels = await image.toByteData();

      int alphaAt(int x, int y) =>
          pixels!.getUint8((y * image.width + x) * 4 + 3);

      // Just above the apex, inside the sector: opaque-ish.
      expect(alphaAt(image.width ~/ 2, image.height - 2), greaterThan(60));
      // The bottom corners are outside the sector.
      expect(alphaAt(0, image.height - 1), 0);
      expect(alphaAt(image.width - 1, image.height - 1), 0);
      // The gradient has run out by the rim.
      expect(alphaAt(image.width ~/ 2, 1), lessThan(20));
    });
  });
}
