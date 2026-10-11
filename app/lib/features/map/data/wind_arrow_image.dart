import 'dart:math' as math;
import 'dart:typed_data';

import 'weather_fetcher.dart' show encodePngRgba;

// The wind arrow, as a signed distance field: the style colours it
// (`icon-color`, by the wind's speed) and outlines it (`icon-halo-color`)
// itself, so one image serves every speed and both map looks.
//
// The alpha of each pixel is its distance from the arrow's edge, as
// MapLibre reads an SDF image: 191 (0.75) on the edge, 32 a pixel more
// inside, 32 a pixel less outside, so it fades out 6 pixels from the edge,
// as far as a halo can reach. The colour channels are not read.

/// The arrow's outline, pointing up (north, which `icon-rotate` turns),
/// around its middle, in logical pixels: a head 12 wide over a shaft 3
/// wide, 22 long in all.
const List<(double, double)> windArrowOutline = <(double, double)>[
  (0, -11),
  (6, -3),
  (1.5, -3),
  (1.5, 11),
  (-1.5, 11),
  (-1.5, -3),
  (-6, -3),
];

/// How far, in the image's pixels, the field reaches beyond the edge.
const double _sdfRadius = 8;

/// Where the edge lies in the field, as a share of the full alpha.
const double _sdfCutoff = 0.25;

/// The room around the arrow, in the image's pixels: the field's fall-off
/// and a pixel.
const int _sdfPad = 7;

/// The wind arrow as an SDF PNG at [devicePixelRatio], see above.
Uint8List buildWindArrowImage({required double devicePixelRatio}) {
  final ratio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  final pts = <(double, double)>[
    for (final (x, y) in windArrowOutline) (x * ratio, y * ratio),
  ];
  final minX = pts.map((p) => p.$1).reduce(math.min);
  final maxX = pts.map((p) => p.$1).reduce(math.max);
  final minY = pts.map((p) => p.$2).reduce(math.min);
  final maxY = pts.map((p) => p.$2).reduce(math.max);
  // Square, so the arrow turns about the image's middle.
  final half = math.max(math.max(-minX, maxX), math.max(-minY, maxY));
  final side = (2 * half).ceil() + 2 * _sdfPad;
  final rgba = windArrowField(side, pts);
  return encodePngRgba(side, side, rgba);
}

/// The SDF of [outline] (pixels about the middle of a [side] × [side]
/// image) as straight RGBA, black, the distance in the alpha.
Uint8List windArrowField(int side, List<(double, double)> outline) {
  final out = Uint8List(side * side * 4);
  final c = side / 2;
  for (var py = 0; py < side; py++) {
    for (var px = 0; px < side; px++) {
      final x = px + 0.5 - c;
      final y = py + 0.5 - c;
      var d = _distanceToOutline(x, y, outline);
      if (_inside(x, y, outline)) d = -d;
      final a = 255 - 255 * (d / _sdfRadius + _sdfCutoff);
      out[(py * side + px) * 4 + 3] = a.round().clamp(0, 255);
    }
  }
  return out;
}

double _distanceToOutline(double x, double y, List<(double, double)> ring) {
  var best = double.infinity;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final (ax, ay) = ring[j];
    final (bx, by) = ring[i];
    final dx = bx - ax;
    final dy = by - ay;
    final len = dx * dx + dy * dy;
    final t = len == 0
        ? 0.0
        : (((x - ax) * dx + (y - ay) * dy) / len).clamp(0.0, 1.0);
    final ex = ax + t * dx - x;
    final ey = ay + t * dy - y;
    best = math.min(best, ex * ex + ey * ey);
  }
  return math.sqrt(best);
}

bool _inside(double x, double y, List<(double, double)> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final (xi, yi) = ring[i];
    final (xj, yj) = ring[j];
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}
