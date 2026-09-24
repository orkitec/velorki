import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/marker_glyph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a marker glyph is a PNG', () async {
    final bytes = await buildMarkerGlyphImage(
      icon: Icons.water_drop_outlined,
      color: const Color(0xFF14171A),
      haloColor: const Color(0xFFFFFFFF),
      devicePixelRatio: 2,
    );

    // The eight byte PNG signature (RFC 2083 §3.1).
    expect(bytes.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  });

  test('a device that reports no pixel ratio still gets a bitmap', () async {
    final bytes = await buildMarkerGlyphImage(
      icon: Icons.terrain_outlined,
      color: const Color(0xFF14171A),
      haloColor: const Color(0xFFFFFFFF),
      devicePixelRatio: 0,
    );

    expect(bytes, isNotEmpty);
  });

  test('every icon is registered under a name of its own', () {
    const icons = <IconData>[
      Icons.water_drop_outlined,
      Icons.restaurant_outlined,
      Icons.medical_services_outlined,
      Icons.wc_outlined,
      Icons.festival_outlined,
      Icons.local_parking_outlined,
      Icons.directions_transit_outlined,
    ];

    expect(icons.map(markerGlyphName).toSet(), hasLength(icons.length));
    expect(
      markerGlyphName(Icons.water_drop_outlined),
      'velorki-glyph-${Icons.water_drop_outlined.codePoint}',
    );
  });

  test('the disc is the glyph plus the same ring at either size', () {
    final ordinary = markerGlyphOnDiscSizePx * markerGlyphUnselectedScale;

    // The one thing that decides a radius: what the widest glyph paints,
    // plus an even margin. Measured on the widest of the sixteen, so no
    // glyph comes nearer its ring than this.
    expect(
      markerDiscRadiusPx - markerGlyphDrawnHalfPx(ordinary),
      closeTo(markerGlyphMarginPx, 1e-9),
    );
    expect(
      markerDiscSelectedRadiusPx -
          markerGlyphDrawnHalfPx(markerGlyphOnDiscSizePx),
      closeTo(markerGlyphMarginPx, 1e-9),
      reason: 'the chosen disc keeps the same ring, it does not thicken it',
    );

    // The chosen disc is wider only by what its glyph is wider by.
    expect(
      markerDiscSelectedRadiusPx - markerDiscRadiusPx,
      closeTo(
        markerGlyphDrawnHalfPx(markerGlyphOnDiscSizePx) -
            markerGlyphDrawnHalfPx(ordinary),
        1e-9,
      ),
    );
    expect(markerDiscSelectedRadiusPx, greaterThan(markerDiscRadiusPx));
  });

  test('the glyphs are the size the rider already liked, and the discs '
      'follow them', () {
    // Unchanged: only the ring around them moved.
    expect(markerGlyphOnDiscSizePx, 18);
    expect(
      markerGlyphOnDiscSizePx * markerGlyphUnselectedScale,
      closeTo(14.4, 1e-9),
    );
    // The bitmap is drawn at the size the chosen point wants, so the style
    // only ever scales it down.
    expect(markerGlyphUnselectedScale, lessThan(1));
    // Ink, not the square it sits in: a fallback box would fill the square
    // and push every disc wider.
    expect(markerGlyphInkShare, lessThan(1));
    // A disc the route line under it can still be seen past, and one a
    // finger's target still covers.
    expect(markerDiscRadiusPx, inInclusiveRange(9, 11));
    expect(markerDiscSelectedRadiusPx, lessThan(13));
  });
}
