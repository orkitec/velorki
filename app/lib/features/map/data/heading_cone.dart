import 'dart:convert' show ascii;
import 'dart:io' show zlib;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// The runtime-drawn heading cone of the position puck.
///
/// MapLibre can only rotate a *symbol*, and a symbol needs a registered
/// image, so the cone cannot be a style layer of its own: it is drawn here in
/// the palette's position colour and handed to `addImage('velorki-heading',
/// …)`.

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
/// straight up from the apex at the bottom centre, filled with [color] at
/// [headingConeApexAlpha] by the apex and fading linearly to nothing at the
/// rim's height. The bitmap is rendered at [devicePixelRatio] so it stays
/// crisp; MapLibre is told the ratio through the image's own scale on the
/// native side, and the symbol layer draws it at its logical size.
///
/// Worked out pixel by pixel in Dart rather than painted on a canvas:
/// `Picture.toImage` needs the GPU, and iOS takes the GPU away from an app in
/// the background, where a raster waits for the app to come back or fails.
/// A style that loads then (the app woken or relaunched in the background, a
/// phone locked mid-ride) would get a cone layer naming an image that was
/// never registered: the dot draws, the cone does not, for the rest of the
/// ride. The same inputs always give the same bytes, so they are kept.
Uint8List buildHeadingConeImage({
  required Color color,
  required double devicePixelRatio,
  double radiusPx = headingConeRadiusPx,
  double sweepDeg = headingConeSweepDeg,
}) {
  final key = (color.toARGB32(), devicePixelRatio, radiusPx, sweepDeg);
  return _coneCache[key] ??= _paintHeadingCone(
    color: color,
    devicePixelRatio: devicePixelRatio,
    radiusPx: radiusPx,
    sweepDeg: sweepDeg,
  );
}

final Map<(int, double, double, double), Uint8List> _coneCache =
    <(int, double, double, double), Uint8List>{};

/// Samples per device pixel along each axis: enough to smooth the two
/// straight edges and the rim.
const int _supersampling = 4;

Uint8List _paintHeadingCone({
  required Color color,
  required double devicePixelRatio,
  required double radiusPx,
  required double sweepDeg,
}) {
  final logical = headingConeLogicalSize(
    radiusPx: radiusPx,
    sweepDeg: sweepDeg,
  );
  final pixels = headingConeImageSize(
    devicePixelRatio: devicePixelRatio,
    radiusPx: radiusPx,
    sweepDeg: sweepDeg,
  );
  final width = pixels.width.round();
  final height = pixels.height.round();
  final scaleX = logical.width / width;
  final scaleY = logical.height / height;
  // The apex, i.e. the rider's position, is the bottom centre of the image.
  final apexX = logical.width / 2;
  final apexY = logical.height;
  final halfSweep = sweepDeg / 2 * math.pi / 180;
  final argb = color.toARGB32();
  final red = (argb >> 16) & 0xFF;
  final green = (argb >> 8) & 0xFF;
  final blue = argb & 0xFF;
  const samples = _supersampling * _supersampling;

  // Every row of RGBA starts with its filter byte, 0 for none.
  final stride = width * 4 + 1;
  final rows = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var alpha = 0.0;
      for (var sy = 0; sy < _supersampling; sy++) {
        final up = apexY - (y + (sy + 0.5) / _supersampling) * scaleY;
        if (up <= 0) continue;
        for (var sx = 0; sx < _supersampling; sx++) {
          final dx = (x + (sx + 0.5) / _supersampling) * scaleX - apexX;
          if (dx * dx + up * up > radiusPx * radiusPx) continue;
          if (math.atan2(dx.abs(), up) > halfSweep) continue;
          alpha += headingConeApexAlpha * (1 - up / radiusPx);
        }
      }
      final a = (alpha / samples * 255).round().clamp(0, 255);
      if (a == 0) continue;
      final at = y * stride + 1 + x * 4;
      rows[at] = red;
      rows[at + 1] = green;
      rows[at + 2] = blue;
      rows[at + 3] = a;
    }
  }
  return _encodePng(width, height, rows);
}

/// A minimal PNG (RFC 2083): 8-bit RGBA, unfiltered rows, one IDAT.
Uint8List _encodePng(int width, int height, Uint8List rows) {
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // colour type: RGBA
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter method
    ..setUint8(12, 0); // no interlace
  final out = BytesBuilder(copy: false)
    ..add(const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  _addChunk(out, 'IHDR', header.buffer.asUint8List());
  _addChunk(out, 'IDAT', Uint8List.fromList(zlib.encode(rows)));
  _addChunk(out, 'IEND', Uint8List(0));
  return out.toBytes();
}

void _addChunk(BytesBuilder out, String type, Uint8List data) {
  final typeBytes = ascii.encode(type);
  var crc = 0xFFFFFFFF;
  for (final byte in typeBytes.followedBy(data)) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  out
    ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
    ..add(typeBytes)
    ..add(data)
    ..add((ByteData(4)..setUint32(0, crc ^ 0xFFFFFFFF)).buffer.asUint8List());
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});
