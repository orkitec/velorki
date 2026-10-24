import 'dart:math' as math;
import 'dart:typed_data';

import 'weather_fetcher.dart' show encodePngRgba;

/// The icon OpenFreeMap's dark styles (`fiord`, `dark`) draw places with at
/// low zoom. Its SVG is in their repository but not in the sprite they
/// publish (https://github.com/hyperknot/openfreemap-styles/issues/29), so
/// without this the dot is missing and maplibre warns about it.
const String townDotImage = 'circle-11';

/// That icon as PNG bytes for [devicePixelRatio]: on a 17 pt square, a
/// #444444 dot of radius 4.5 inside a white ring at a quarter opacity
/// reaching 5.5, as `styles/dark/icons/circle-11.svg` draws it.
Uint8List buildTownDotImage({required double devicePixelRatio}) {
  final ratio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  final side = (17 * ratio).round();
  final c = side / 2;
  final dot = 4.5 * ratio;
  final ring = 5.5 * ratio;
  final out = Uint8List(side * side * 4);
  for (var py = 0; py < side; py++) {
    for (var px = 0; px < side; px++) {
      final dx = px + 0.5 - c;
      final dy = py + 0.5 - c;
      final r = math.sqrt(dx * dx + dy * dy);
      // Coverage of the dot and of the ring, antialiased over a pixel.
      final inDot = (dot - r + 0.5).clamp(0.0, 1.0);
      final inRing = (ring - r + 0.5).clamp(0.0, 1.0);
      // The dot over the ring, straight alpha.
      final ringAlpha = 0.25 * inRing;
      final alpha = inDot + ringAlpha * (1 - inDot);
      if (alpha == 0) continue;
      final grey = (0x44 * inDot + 0xFF * ringAlpha * (1 - inDot)) / alpha;
      final i = (py * side + px) * 4;
      out[i] = out[i + 1] = out[i + 2] = grey.round();
      out[i + 3] = (alpha * 255).round();
    }
  }
  return encodePngRgba(side, side, out);
}
