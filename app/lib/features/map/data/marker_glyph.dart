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

/// What the smaller glyph of an ordinary point is called: its name with
/// [markerGlyphUnselectedSuffix] after it.
///
/// Each size a glyph is shown at has a bitmap of its own, drawn at that
/// size: the style picks one by name instead of scaling a bitmap, which
/// smeared the thin strokes of a glyph scaled down.
String markerGlyphUnselectedName(IconData icon) =>
    '${markerGlyphName(icon)}$markerGlyphUnselectedSuffix';

/// What [markerGlyphUnselectedName] puts after a glyph's name.
const String markerGlyphUnselectedSuffix = '-small';

/// Height of the glyph on the chosen point's disc, in logical pixels.
///
/// The glyph is the measure here, and the disc is sized to it: picking a
/// radius and giving the glyph a share of it left an empty ring inside every
/// marker, which is what a rider sees as a disc that is too big.
const double markerGlyphOnDiscSizePx = 18;

/// How much smaller the glyph on an ordinary disc is than the chosen
/// point's.
///
/// Drawn at that size, outline and all, into a bitmap of its own
/// ([markerGlyphUnselectedName]), never scaled down by the style.
const double markerGlyphUnselectedScale = 0.8;

/// Height of the glyph on an ordinary point's disc, in logical pixels.
const double markerGlyphUnselectedSizePx =
    markerGlyphOnDiscSizePx * markerGlyphUnselectedScale;

/// The outline of the glyph on an ordinary point's disc, which shrinks with
/// the glyph so it keeps its share of it.
const double markerGlyphUnselectedHaloPx =
    markerGlyphHaloPx * markerGlyphUnselectedScale;

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
/// The outline shrinks with the glyph, as [markerGlyphUnselectedHaloPx]
/// does.
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

/// How much a glyph on a disc is thickened on each side, in logical pixels:
/// about one device pixel more stroke in all on a phone.
const double markerDiscGlyphBoldPx = 0.2;

/// The glyph of [icon], stroked in [haloColor] and filled with [color], laid
/// out at [sizePx] with an outline of [haloPx]: the halo first, then the
/// fill.
({TextPainter halo, TextPainter fill}) _glyphPainters({
  required IconData icon,
  required Color color,
  required Color haloColor,
  required double sizePx,
  required double haloPx,
}) {
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

  return (
    halo: painter(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = haloPx * 2
        ..color = haloColor
        ..isAntiAlias = true,
    ),
    fill: painter(
      Paint()
        ..style = PaintingStyle.fill
        ..color = color
        ..isAntiAlias = true,
    ),
  );
}

/// How many whole device pixels a marker bitmap [logicalPx] wide takes at
/// [devicePixelRatio]: rounded up, so nothing is cut off, and never none.
///
/// MapLibre shows a bitmap registered at the screen's pixel ratio one
/// bitmap pixel to one screen pixel, as long as the style does not scale
/// it (`icon-size` left alone): the picture then is exactly what was drawn
/// here, with nothing for the map's texture filter to smear.
int markerBitmapPixels(double logicalPx, double devicePixelRatio) {
  final ratio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  // A hair below a whole number is that number, not the next one up.
  return math.max(1, (logicalPx * ratio - 1e-6).ceil());
}

/// Records what [paint] draws on a canvas of [logical] size and encodes it
/// as a PNG at [devicePixelRatio].
///
/// The bitmap is a whole number of device pixels each way
/// ([markerBitmapPixels]) and the canvas is scaled by exactly the ratio, so
/// a logical pixel is the same number of device pixels in every bitmap;
/// what the rounding up adds is shared out round the picture, to the
/// nearest whole pixel, which keeps it centred on its point. [paint] is told the ratio, to put what it
/// draws on whole device pixels.
Future<Uint8List> _encodePng(
  Size logical,
  double devicePixelRatio,
  void Function(Canvas canvas, double ratio) paint,
) async {
  final ratio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  final width = markerBitmapPixels(logical.width, ratio);
  final height = markerBitmapPixels(logical.height, ratio);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  canvas
    ..translate(
      ((width - logical.width * ratio) / 2).roundToDouble(),
      ((height - logical.height * ratio) / 2).roundToDouble(),
    )
    ..scale(ratio);
  paint(canvas, ratio);

  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Paints [icon] and encodes it as PNG bytes.
///
/// The glyph is stroked in [haloColor] and filled with [color], so it is
/// legible on any ground the map paints under it, and rendered at
/// [devicePixelRatio] so it stays crisp on a phone. Drawn at the size it is
/// shown at, [sizePx] with an outline of [haloPx]: the style shows it as it
/// is, never scaled.
Future<Uint8List> buildMarkerGlyphImage({
  required IconData icon,
  required Color color,
  required Color haloColor,
  required double devicePixelRatio,
  double? sizePx,
  double haloPx = markerGlyphHaloPx,
}) async {
  final glyph = _glyphPainters(
    icon: icon,
    color: color,
    haloColor: haloColor,
    sizePx: sizePx ?? markerGlyphSizePx,
    haloPx: haloPx,
  );
  try {
    final logical = Size(
      glyph.halo.width + haloPx * 2,
      glyph.halo.height + haloPx * 2,
    );
    return await _encodePng(logical, devicePixelRatio, (canvas, ratio) {
      final origin = _onDevicePixels(Offset(haloPx, haloPx), ratio);
      glyph.halo.paint(canvas, origin);
      glyph.fill.paint(canvas, origin);
    });
  } finally {
    glyph.halo.dispose();
    glyph.fill.dispose();
  }
}

/// [offset], logical, moved to the nearest whole device pixel at [ratio], so
/// a glyph starts on a pixel rather than astride one.
Offset _onDevicePixels(Offset offset, double ratio) => Offset(
  (offset.dx * ratio).roundToDouble() / ratio,
  (offset.dy * ratio).roundToDouble() / ratio,
);

/// Air left round a disc's rim in its bitmap, in logical pixels, so the
/// anti-aliased edge is not cut off.
const double markerDiscBitmapPadPx = 1;

/// Paints a whole marker as one picture — a disc of [radiusPx] in [fill]
/// with a rim of [strokePx] in [stroke] outside it, as a style's circle
/// draws one, and [icon], if any, centred on it — and encodes it as PNG
/// bytes.
///
/// One picture rather than a circle layer under a glyph: a symbol fades in
/// and out with the map's placement, a circle only pops.
///
/// The glyph is [glyphPx] high in [glyphColor], its strokes thickened by
/// [glyphBoldPx] on each side with an edge of its own colour: no
/// translucent outline as on a bare glyph, where the disc sets it off and
/// that would only blur its edges, but the icon font's thin lines made a
/// little more solid.
Future<Uint8List> buildDiscMarkerImage({
  required Color fill,
  required Color stroke,
  required double radiusPx,
  required double strokePx,
  required double devicePixelRatio,
  IconData? icon,
  double glyphPx = markerGlyphOnDiscSizePx,
  double glyphBoldPx = markerDiscGlyphBoldPx,
  Color glyphColor = const Color(0xFFFFFFFF),
}) async {
  final glyph = icon == null
      ? null
      : _glyphPainters(
          icon: icon,
          color: glyphColor,
          haloColor: glyphColor,
          sizePx: glyphPx,
          haloPx: glyphBoldPx,
        );
  try {
    final side = (radiusPx + strokePx + markerDiscBitmapPadPx) * 2;
    final center = Offset(side / 2, side / 2);
    return await _encodePng(Size(side, side), devicePixelRatio, (
      canvas,
      ratio,
    ) {
      // The rim as a whole disc under the fill, not a ring beside it: two
      // soft edges that only meet leave a seam of the map showing through.
      if (strokePx > 0) {
        canvas.drawCircle(
          center,
          radiusPx + strokePx,
          Paint()
            ..style = PaintingStyle.fill
            ..color = stroke
            ..isAntiAlias = true,
        );
      }
      canvas.drawCircle(
        center,
        radiusPx,
        Paint()
          ..style = PaintingStyle.fill
          ..color = fill
          ..isAntiAlias = true,
      );
      if (glyph != null) {
        // Centred as the glyph's own bitmap is centred on its point.
        final origin = _onDevicePixels(
          center - Offset(glyph.halo.width / 2, glyph.halo.height / 2),
          ratio,
        );
        glyph.halo.paint(canvas, origin);
        glyph.fill.paint(canvas, origin);
      }
    });
  } finally {
    glyph?.halo.dispose();
    glyph?.fill.dispose();
  }
}
