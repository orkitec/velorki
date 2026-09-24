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

  test('a glyph keeps its share of whatever disc it sits on', () {
    expect(
      markerGlyphSizeForDisc(markerDiscRadiusPx),
      markerDiscRadiusPx * 2 * markerGlyphDiscShare,
    );
    // Wider disc, bigger glyph, same share of it.
    expect(
      markerGlyphSizeForDisc(markerDiscSelectedRadiusPx),
      greaterThan(markerGlyphSizeForDisc(markerDiscRadiusPx)),
    );
    expect(
      markerGlyphSizeForDisc(markerDiscRadiusPx) /
          markerGlyphSizeForDisc(markerDiscSelectedRadiusPx),
      closeTo(markerGlyphUnselectedScale, 1e-9),
    );
    // The bitmap is drawn at the size the chosen point wants, so the style
    // only ever scales it down.
    expect(
      markerGlyphOnDiscSizePx,
      markerGlyphSizeForDisc(markerDiscSelectedRadiusPx),
    );
    expect(markerGlyphUnselectedScale, lessThan(1));
    // A disc the route line can still be seen under.
    expect(markerDiscRadiusPx, greaterThan(9));
    expect(markerDiscSelectedRadiusPx, greaterThan(markerDiscRadiusPx));
  });
}
