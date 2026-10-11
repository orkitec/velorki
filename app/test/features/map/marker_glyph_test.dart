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

  test('a whole marker, disc, rim and glyph, is one PNG as wide as the '
      'disc and its rim', () async {
    for (final icon in <IconData?>[Icons.water_drop_outlined, null]) {
      final bytes = await buildDiscMarkerImage(
        icon: icon,
        fill: const Color(0xFF1E88E5),
        stroke: const Color(0xFFFFFFFF),
        radiusPx: 10,
        strokePx: 1.5,
        devicePixelRatio: 2,
      );

      expect(bytes.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
      // The width of the IHDR chunk, big-endian at bytes 16..19: the disc,
      // its rim and a pixel of air each side, at the pixel ratio.
      expect(_pngWidth(bytes), (10 + 1.5 + markerDiscBitmapPadPx) * 2 * 2);
    }
  });

  test('each glyph picture is drawn at the size it is shown at, a whole '
      'number of device pixels at the pixel ratio', () async {
    const icon = Icons.water_drop_outlined;
    for (final ratio in <double>[1, 2, 2.625, 3]) {
      for (final (sizePx, haloPx) in <(double, double)>[
        (markerGlyphOnDiscSizePx, markerGlyphHaloPx),
        (markerGlyphUnselectedSizePx, markerGlyphUnselectedHaloPx),
      ]) {
        final bytes = await buildMarkerGlyphImage(
          icon: icon,
          color: const Color(0xFF14171A),
          haloColor: const Color(0xFFFFFFFF),
          devicePixelRatio: ratio,
          sizePx: sizePx,
          haloPx: haloPx,
        );
        final glyph = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(fontSize: sizePx, fontFamily: icon.fontFamily),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(
          _pngWidth(bytes),
          markerBitmapPixels(glyph.width + haloPx * 2, ratio),
          reason: '$sizePx px at $ratio',
        );
        glyph.dispose();
      }
    }
  });

  test('the smaller glyph is the chosen one scaled as the style used to '
      'scale it, outline and all', () {
    expect(
      markerGlyphUnselectedSizePx,
      closeTo(markerGlyphOnDiscSizePx * markerGlyphUnselectedScale, 1e-9),
    );
    expect(
      markerGlyphUnselectedHaloPx,
      closeTo(markerGlyphHaloPx * markerGlyphUnselectedScale, 1e-9),
    );
    expect(
      markerGlyphUnselectedName(Icons.water_drop_outlined),
      isNot(markerGlyphName(Icons.water_drop_outlined)),
    );
  });

  test('a bitmap is whole device pixels, rounded up, never none', () {
    expect(markerBitmapPixels(21.2, 3), 64);
    expect(markerBitmapPixels(20, 3), 60);
    // 0.1 × 3 is a hair over 0.3 in floating point; still not a pixel more.
    expect(markerBitmapPixels(10.1, 3), 31);
    expect(markerBitmapPixels(0, 3), 1);
    expect(markerBitmapPixels(10, 0), 10);
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

/// The width of a PNG, from its IHDR chunk (big-endian at bytes 16..19).
int _pngWidth(List<int> png) =>
    png[16] << 24 | png[17] << 16 | png[18] << 8 | png[19];
