import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// The icons markers wear, drawn at runtime.
///
/// MapLibre can only put a picture on a symbol, and the app's marker icons
/// are glyphs of an icon font, not files: each one is painted here with
/// `dart:ui` and handed to `addImage`, exactly as the heading cone is.
/// Drawing them rather than shipping a PNG per kind keeps one icon table —
/// the app's — for the sheet, the lists and the map alike.

/// Name the glyph of [icon] is registered under in the style.
///
/// The code point alone: every icon the app draws on the map comes from the
/// one icon font, and every one of them is drawn the same way, light on the
/// disc of the marker it belongs to.
String markerGlyphName(IconData icon) => 'velorki-glyph-${icon.codePoint}';

/// Height of the glyph on the chosen point's disc, in logical pixels.
///
/// The glyph is the measure here, and the disc is sized to it: picking a
/// radius and giving the glyph a share of it left an empty ring inside every
/// marker, which is what a rider sees as a disc that is too big.
const double markerGlyphOnDiscSizePx = 18;

/// How much smaller the glyph on an ordinary disc is than the chosen
/// point's.
///
/// The bitmap is drawn once, at the size the chosen point needs, and scaled
/// down for the rest: scaling a bitmap down keeps its edges, scaling one up
/// softens them.
const double markerGlyphUnselectedScale = 0.8;

/// How much of a glyph's square its ink actually covers, taking the widest
/// and tallest of the sixteen.
///
/// Measured rather than assumed, on a device with the real icon font: at a
/// size of 18 the widest ink is 15.75 px across — the bike repair wrench,
/// the shelter, the summit, the campsite, the bed — which is seven eighths.
/// A unit test cannot measure this: `flutter test` runs with asset fonts off
/// and every glyph comes back as a full-square fallback box, which would
/// size every disc a good deal too wide.
const double markerGlyphInkShare = 0.875;

/// The ring of empty space left between a glyph and the inside of its disc,
/// in logical pixels.
///
/// The same at both sizes, so the chosen point's disc grows by exactly what
/// its glyph grows by and the ring never thickens.
const double markerGlyphMarginPx = 2.5;

/// Half of what a glyph of [glyphPx] paints, its outline included.
///
/// The outline is part of the one bitmap, so the style scales it along with
/// the glyph.
double markerGlyphDrawnHalfPx(double glyphPx) =>
    glyphPx * markerGlyphInkShare / 2 +
    markerGlyphHaloPx * glyphPx / markerGlyphOnDiscSizePx;

/// The disc that holds a glyph of [glyphPx] with [markerGlyphMarginPx] of
/// air all round it.
double markerDiscRadiusFor(double glyphPx) =>
    markerGlyphDrawnHalfPx(glyphPx) + markerGlyphMarginPx;

/// Radius of the disc of the point the rider has chosen.
final double markerDiscSelectedRadiusPx = markerDiscRadiusFor(
  markerGlyphOnDiscSizePx,
);

/// Radius of an ordinary marker's disc, in logical pixels.
final double markerDiscRadiusPx = markerDiscRadiusFor(
  markerGlyphOnDiscSizePx * markerGlyphUnselectedScale,
);

/// Height of a marker glyph, in logical pixels.
const double markerGlyphSizePx = 13;

/// How wide the light outline around a glyph is, in logical pixels. Enough
/// to read a dark glyph against a dark wood or a motorway.
const double markerGlyphHaloPx = 1.6;

/// Paints [icon] and encodes it as PNG bytes.
///
/// The glyph is stroked in [haloColor] and filled with [color], so it is
/// legible on any ground the map paints under it, and rendered at
/// [devicePixelRatio] so it stays crisp on a phone.
Future<Uint8List> buildMarkerGlyphImage({
  required IconData icon,
  required Color color,
  required Color haloColor,
  required double devicePixelRatio,
  double? sizePx,
  double haloPx = markerGlyphHaloPx,
}) async {
  sizePx ??= markerGlyphSizePx;
  final ratio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  final text = String.fromCharCode(icon.codePoint);

  TextPainter painter(Paint paint) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: sizePx,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        foreground: paint,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final halo = painter(
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = haloPx * 2
      ..color = haloColor
      ..isAntiAlias = true,
  );
  final fill = painter(
    Paint()
      ..style = PaintingStyle.fill
      ..color = color
      ..isAntiAlias = true,
  );

  final logical = Size(halo.width + haloPx * 2, halo.height + haloPx * 2);
  final pixels = Size(
    math.max(1, (logical.width * ratio).round()).toDouble(),
    math.max(1, (logical.height * ratio).round()).toDouble(),
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, pixels.width, pixels.height),
  );
  canvas.scale(pixels.width / logical.width, pixels.height / logical.height);
  const origin = Offset(markerGlyphHaloPx, markerGlyphHaloPx);
  halo.paint(canvas, origin);
  fill.paint(canvas, origin);

  final image = await recorder.endRecording().toImage(
    pixels.width.round(),
    pixels.height.round(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    halo.dispose();
    fill.dispose();
  }
}
