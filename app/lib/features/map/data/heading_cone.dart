import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The runtime-drawn heading cone of the position puck.
///
/// MapLibre can only rotate a *symbol*, and a symbol needs a registered
/// image, so the cone cannot be a style layer of its own: it is painted here
/// with `dart:ui` in the palette's position colour and handed to
/// `addImage('velorki-heading', …)`.

/// Name the cone bitmap is registered under in the style.
const String headingConeImageName = 'velorki-heading';

/// Opening angle of the cone, in degrees.
const double headingConeSweepDeg = 70;

/// Length of the cone from the puck outwards, in logical pixels.
const double headingConeRadiusPx = 56;

/// Alpha of the cone at the apex; it fades to nothing at the rim.
const double headingConeApexAlpha = 0.55;

/// Size in *logical* pixels of the bitmap [buildHeadingConeImage] draws.
///
/// The apex sits at the bottom centre — which is what `icon-anchor: bottom`
/// pins to the fix — so the image only has to be as wide as the sector and as
/// tall as its radius.
Size headingConeLogicalSize({
  double radiusPx = headingConeRadiusPx,
  double sweepDeg = headingConeSweepDeg,
}) {
  final halfSweep = sweepDeg / 2 * math.pi / 180;
  final halfWidth = radiusPx * math.sin(halfSweep);
  return Size(halfWidth.ceilToDouble() * 2, radiusPx.ceilToDouble());
}

/// Size in *device* pixels of the bitmap for [devicePixelRatio].
Size headingConeImageSize({
  required double devicePixelRatio,
  double radiusPx = headingConeRadiusPx,
  double sweepDeg = headingConeSweepDeg,
}) {
  final logical = headingConeLogicalSize(
    radiusPx: radiusPx,
    sweepDeg: sweepDeg,
  );
  final ratio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  return Size(
    math.max(1, (logical.width * ratio).round()).toDouble(),
    math.max(1, (logical.height * ratio).round()).toDouble(),
  );
}

/// Draws the cone and encodes it as PNG bytes.
///
/// A sector of [sweepDeg] degrees and [radiusPx] logical pixels, pointing
/// straight up from the apex at the bottom centre, filled with a vertical
/// gradient from [color] at [headingConeApexAlpha] down to fully transparent
/// at the rim. The bitmap is rendered at [devicePixelRatio] so it stays crisp;
/// MapLibre is told the ratio through the image's own scale on the native
/// side, and the symbol layer draws it at its logical size.
Future<Uint8List> buildHeadingConeImage({
  required Color color,
  required double devicePixelRatio,
  double radiusPx = headingConeRadiusPx,
  double sweepDeg = headingConeSweepDeg,
}) async {
  final logical = headingConeLogicalSize(
    radiusPx: radiusPx,
    sweepDeg: sweepDeg,
  );
  final pixels = headingConeImageSize(
    devicePixelRatio: devicePixelRatio,
    radiusPx: radiusPx,
    sweepDeg: sweepDeg,
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, pixels.width, pixels.height),
  );
  canvas.scale(pixels.width / logical.width, pixels.height / logical.height);

  // The apex, i.e. the rider's position, is the bottom centre of the image.
  final apex = Offset(logical.width / 2, logical.height);
  // `arcTo` measures from three o'clock clockwise; straight up is -90°.
  final halfSweep = sweepDeg / 2 * math.pi / 180;
  final start = -math.pi / 2 - halfSweep;
  final path = Path()
    ..moveTo(apex.dx, apex.dy)
    ..arcTo(
      Rect.fromCircle(center: apex, radius: radiusPx),
      start,
      halfSweep * 2,
      false,
    )
    ..close();

  final paint = Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.linear(
      Offset(apex.dx, apex.dy),
      Offset(apex.dx, apex.dy - radiusPx),
      <Color>[
        color.withValues(alpha: headingConeApexAlpha),
        color.withValues(alpha: 0),
      ],
    );
  canvas.drawPath(path, paint);

  final image = await recorder.endRecording().toImage(
    pixels.width.round(),
    pixels.height.round(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
