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

/// Radius of a marker's disc, in logical pixels.
///
/// Wide enough that the glyph inside it is read at a glance on a moving map,
/// and still about twice the width of the route line under it, so it reads as
/// a marker rather than a blob.
const double markerDiscRadiusPx = 12;

/// Radius of the disc of the point the rider has chosen.
const double markerDiscSelectedRadiusPx = 15;

/// How much of a disc's width its glyph takes.
const double markerGlyphDiscShare = 0.6;

/// The glyph height for a disc of [radiusPx], so the icon keeps its share of
/// the disc at every size.
double markerGlyphSizeForDisc(double radiusPx) =>
    radiusPx * 2 * markerGlyphDiscShare;

/// How much the style has to shrink the on-disc bitmap for a point that is
/// not the chosen one.
///
/// The bitmap is drawn once, at the size the chosen point needs, and scaled
/// down for the rest: scaling a bitmap down keeps its edges, scaling one up
/// softens them.
const double markerGlyphUnselectedScale =
    markerDiscRadiusPx / markerDiscSelectedRadiusPx;

/// Height of a marker glyph, in logical pixels.
const double markerGlyphSizePx = 13;

/// Height of a glyph drawn inside a disc, which has a rim to spare.
final double markerGlyphOnDiscSizePx = markerGlyphSizeForDisc(
  markerDiscSelectedRadiusPx,
);

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
