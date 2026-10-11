import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:velorki_geo/velorki_geo.dart';

import '../domain/weather_map.dart';
import '../domain/wind_field.dart';

/// How long a probe of one radar tile may take before the radar counts as
/// unavailable.
const Duration weatherProbeTimeout = Duration(seconds: 8);

/// How long the one image of a cloud region may take: it is a large image
/// the service renders on request.
const Duration cloudImageTimeout = Duration(seconds: 30);

/// How long a cloud image without a moment of its own (the latest GOES
/// image) is reused: as long as the refresh that would fetch it again.
const Duration latestCloudSlot = Duration(minutes: 10);

/// How long a cloud image stays in the cache at most.
const Duration cloudCacheMaxAge = Duration(hours: 6);

/// How long the wind of a box and a moment is reused before it is asked
/// for again: each model run changes the forecast a little.
const Duration windCacheMaxAge = Duration(hours: 1);

/// How many wind grids of one source the cache keeps: the boxes and
/// moments of the last few views and steps of the time control.
const int windCacheKeep = 24;

/// How long the wind of a box may take.
const Duration windTimeout = Duration(seconds: 15);

/// How many detail images of one source the cache keeps: the boxes of the
/// last few views, for panning back.
const int cloudDetailCacheKeep = 12;

// The infrared images are bright where it is cold: high cloud tops are
// white, the warm ground dark grey. A pixel's luminance between these two
// is read as cloud, linearly, up to [cloudMaxAlpha]: darker is clear sky,
// brighter is as cloudy as it gets. Low fog and stratus are almost as warm
// as the ground under them, so they come out faint or not at all.
/// Luminance (0..255) at and below which a pixel is clear.
const double cloudLuminanceLow = 110;

/// Luminance at and above which a pixel is full cloud.
const double cloudLuminanceHigh = 220;

/// How opaque the thickest cloud is drawn, 0..1: a sky wholly overcast
/// stays a veil the map and the rain show through.
const double cloudMaxAlpha = 0.45;

/// How far apart a pixel's strongest and weakest channel have to be for it
/// to count as coloured. The GOES images paint the coldest cloud tops in an
/// enhancement colour scale (blue to red) instead of grey; those are the
/// thickest clouds there are.
const int cloudColourSpread = 48;

/// Turns the straight RGBA pixels of an infrared image into white cloud on
/// a clear ground: every pixel white, its alpha from how cold (bright) it
/// was; a pixel the service left transparent stays so.
Uint8List whitenCloudPixels(Uint8List rgba) {
  final out = Uint8List(rgba.length);
  const span = cloudLuminanceHigh - cloudLuminanceLow;
  const full = cloudMaxAlpha * 255;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final a = rgba[i + 3];
    out[i] = 255;
    out[i + 1] = 255;
    out[i + 2] = 255;
    if (a == 0) {
      out[i + 3] = 0;
      continue;
    }
    final r = rgba[i];
    final g = rgba[i + 1];
    final b = rgba[i + 2];
    final spread = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
    final double cloud;
    if (spread >= cloudColourSpread) {
      cloud = 1;
    } else {
      final v = 0.299 * r + 0.587 * g + 0.114 * b;
      cloud = ((v - cloudLuminanceLow) / span).clamp(0.0, 1.0);
    }
    out[i + 3] = (cloud * full * a / 255).round();
  }
  return out;
}

// The soft rain radar keeps each service's colours and sets every pixel's
// alpha by how heavy the rain is, read along the palette's hue: both the
// DWD and NOAA run from light blue and cyan through green, yellow, orange
// and red to magenta and purple as the rain gets heavier. So light rain is
// a lighter wash than a downpour, but always stronger than the clouds
// under it: on a dark map at a third, NOAA's slate blue all but vanished.

/// The alpha of light blue and cyan, the lightest rain.
const double radarAlphaCyan = 0.6;

/// The alpha of green.
const double radarAlphaGreen = 0.7;

/// The alpha of yellow.
const double radarAlphaYellow = 0.8;

/// The alpha of orange.
const double radarAlphaOrange = 0.85;

/// The alpha of red, heavy rain: a pixel this heavy or heavier is never
/// made fainter by the softening of edges, so a small storm cell keeps its
/// strength.
const double radarAlphaRed = 0.9;

/// The alpha of magenta and purple, the heaviest rain and hail.
const double radarAlphaMagenta = 0.95;

/// The alpha of opaque grey, which no radar palette uses for rain: faint.
/// The DWD's see-through grey beyond its radars' reach goes altogether
/// (see [rainPixel]).
const double radarAlphaGrey = 0.25;

/// How far apart a pixel's strongest and weakest channel have to be for its
/// hue to count; below it the pixel is grey.
const int radarGreySpread = 24;

/// How far, in pixels, the softening of edges reaches: 1 is a 3 × 3 box.
const int radarBlurRadius = 1;

// Each colour's hue, in degrees, and its alpha. Hues above 255 (purple,
// magenta, the reds just under 360) are read as below 0, so the path runs
// on downwards from red: cyan 180 → green 120 → yellow 60 → orange 30 →
// red 0 → magenta −60 → purple −90. Blue, up to 255, is light rain as cyan.
const List<(double, double)> _radarHueAlpha = <(double, double)>[
  (180, radarAlphaCyan),
  (120, radarAlphaGreen),
  (60, radarAlphaYellow),
  (30, radarAlphaOrange),
  (0, radarAlphaRed),
  (-60, radarAlphaMagenta),
];

/// The hue above which a colour is read as purple or magenta rather than
/// blue.
const double _radarBlueTop = 255;

/// The alpha one radar colour gets: by its hue along the palette, grey at
/// [radarAlphaGrey]. Without the service's own alpha.
double radarIntensityAlpha(int r, int g, int b) {
  final hi = math.max(r, math.max(g, b));
  final lo = math.min(r, math.min(g, b));
  final spread = hi - lo;
  if (spread < radarGreySpread) return radarAlphaGrey;
  double hue;
  if (hi == r) {
    hue = 60 * ((g - b) / spread % 6);
  } else if (hi == g) {
    hue = 60 * ((b - r) / spread + 2);
  } else {
    hue = 60 * ((r - g) / spread + 4);
  }
  if (hue > _radarBlueTop) hue -= 360;
  final first = _radarHueAlpha.first;
  if (hue >= first.$1) return first.$2;
  for (var i = 1; i < _radarHueAlpha.length; i++) {
    final (h1, a1) = _radarHueAlpha[i];
    if (hue >= h1) {
      final (h0, a0) = _radarHueAlpha[i - 1];
      return a1 + (a0 - a1) * (hue - h1) / (h0 - h1);
    }
  }
  return _radarHueAlpha.last.$2;
}

/// Turns the straight RGBA pixels of a radar image ([width] × [height])
/// into the soft radar: each pixel keeps its colour, its alpha becomes
/// [radarIntensityAlpha] times its own, and then the alpha alone is
/// averaged over a box of [radarBlurRadius], so the edges of the rain fade
/// out instead of stepping. A pixel the service left transparent stays so,
/// and one as heavy as [radarAlphaRed] or more is never made fainter.
Uint8List softenRadarPixels(int width, int height, Uint8List rgba) =>
    softenRainPixels(width, height, rgba, RainPalette.radarHue);

/// The soft look of a rain image of [palette]: every pixel's colour and
/// its alpha by how heavy the rain is ([rainPixel]), then the alpha alone
/// averaged over a box of [radarBlurRadius], so the edges fade out instead
/// of stepping. A pixel that is no rain stays transparent, and one at
/// [radarAlphaRed] or more is never made fainter.
Uint8List softenRainPixels(
  int width,
  int height,
  Uint8List rgba,
  RainPalette palette,
) {
  final n = width * height;
  final alpha = Float64List(n);
  final heavy = Uint8List(n);
  final out = Uint8List.fromList(rgba);
  for (var i = 0; i < n; i++) {
    final o = i * 4;
    final a = rgba[o + 3];
    if (a == 0) continue;
    final pixel = rainPixel(palette, rgba[o], rgba[o + 1], rgba[o + 2], a);
    if (pixel == null) {
      out[o + 3] = 0;
      continue;
    }
    final (r, g, b, intensity) = pixel;
    out[o] = r;
    out[o + 1] = g;
    out[o + 2] = b;
    alpha[i] = intensity * a / 255;
    if (intensity >= radarAlphaRed) heavy[i] = 1;
  }
  const r = radarBlurRadius;
  const box = (2 * r + 1) * (2 * r + 1);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      final o = i * 4;
      if (out[o + 3] == 0) continue;
      // Beyond the image's edge counts as the edge's own pixel, so the
      // border of the box is not taken for the border of the rain.
      var sum = 0.0;
      for (var dy = -r; dy <= r; dy++) {
        final yy = (y + dy).clamp(0, height - 1);
        for (var dx = -r; dx <= r; dx++) {
          final xx = (x + dx).clamp(0, width - 1);
          sum += alpha[yy * width + xx];
        }
      }
      var value = sum / box;
      if (heavy[i] == 1 && value < alpha[i]) value = alpha[i];
      out[o + 3] = (value * 255).round().clamp(0, 255);
    }
  }
  return out;
}

/// One pixel of a rain image of [palette] as the soft look draws it: its
/// colour and how opaque its rain is (0..1, before the service's own alpha
/// [a]); `null` where it is no rain.
///
/// The radar's palette is read by hue; its grey is "no data" (the DWD's
/// area beyond the radars' reach, which the service itself draws
/// see-through) and goes, other grey stays faint. The satellite's and the
/// global model's are read class by class from their legends.
(int, int, int, double)? rainPixel(
  RainPalette palette,
  int r,
  int g,
  int b,
  int a,
) {
  switch (palette) {
    case RainPalette.radarHue:
      final spread = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
      if (spread < radarGreySpread && a < 128) return null;
      return (r, g, b, radarIntensityAlpha(r, g, b));
    case RainPalette.hsaf:
      final (_, _, _, alpha) = _nearest(hsafClasses, r, g, b);
      return (r, g, b, alpha);
    case RainPalette.dwdModel6h:
      if (_modelNoData(r, g, b)) return null;
      final (rr, gg, bb, _) = _nearest(dwdModel6hClasses, r, g, b);
      return (rr, gg, bb, radarIntensityAlpha(rr, gg, bb));
  }
}

/// The global model's ground with no rain: the service draws it a faint
/// black veil (alpha 20), and "under 0.1 mm" a light grey.
bool _modelNoData(int r, int g, int b) =>
    math.max(r, math.max(g, b)) < 40 || (r == g && g == b && r >= 200);

/// The class of [classes] (legend colour first, then what it is drawn as)
/// whose legend colour is nearest to (r, g, b).
(int, int, int, double) _nearest(
  List<((int, int, int), (int, int, int, double))> classes,
  int r,
  int g,
  int b,
) {
  var best = classes.first.$2;
  var bestDistance = 1 << 30;
  for (final ((cr, cg, cb), drawn) in classes) {
    final d = (cr - r) * (cr - r) + (cg - g) * (cg - g) + (cb - b) * (cb - b);
    if (d < bestDistance) {
      bestDistance = d;
      best = drawn;
    }
  }
  return best;
}

/// The H SAF rain's legend (`mtg_h40b_default`), lightest first, each class
/// drawn in its own colour at its alpha: light green under about 1.5 mm an
/// hour at [radarAlphaCyan], as faint as the radar's lightest, up to the
/// purples of 30 mm and more at [radarAlphaMagenta].
const List<((int, int, int), (int, int, int, double))> hsafClasses =
    <((int, int, int), (int, int, int, double))>[
      ((204, 255, 204), (204, 255, 204, radarAlphaCyan)), // < 1.5 mm/h
      ((153, 230, 153), (153, 230, 153, 0.68)), // < 4
      ((102, 204, 102), (102, 204, 102, 0.76)), // < 7
      ((51, 179, 51), (51, 179, 51, 0.82)), // < 10
      ((51, 153, 204), (51, 153, 204, 0.86)), // < 15
      ((51, 102, 255), (51, 102, 255, radarAlphaRed)), // < 20
      ((0, 0, 255), (0, 0, 255, 0.92)), // < 25
      ((102, 0, 204), (102, 0, 204, 0.94)), // < 30
      ((153, 51, 204), (153, 51, 204, radarAlphaMagenta)), // < 40
      ((204, 0, 153), (204, 0, 153, radarAlphaMagenta)), // < 50
      ((127, 0, 127), (127, 0, 127, radarAlphaMagenta)), // 50 and more
    ];

/// The global ICON's six-hour legend (`icon_reg025_fd_sl_totprec06h_wmc_
/// isoarea`), each class drawn in the DWD radar's colour for its mean rate
/// per hour (the class's middle over six hours): 0.1–0.5 mm in six hours is
/// the radar's lightest, 200–300 mm its 30–45 mm an hour. The alpha is then
/// the radar's, by hue.
const List<((int, int, int), (int, int, int, double))> dwdModel6hClasses =
    <((int, int, int), (int, int, int, double))>[
      ((220, 247, 195), (51, 255, 255, 0)), // 0.1–0.5 mm
      ((185, 247, 124), (51, 255, 255, 0)), // 0.5–1
      ((0, 230, 1), (26, 204, 154, 0)), // 1–2
      ((0, 191, 1), (1, 153, 52, 0)), // 2–5
      ((0, 128, 23), (77, 179, 27, 0)), // 5–10
      ((51, 185, 255), (153, 204, 1, 0)), // 10–15
      ((0, 125, 255), (153, 204, 1, 0)), // 15–20
      ((255, 192, 64), (204, 230, 1, 0)), // 20–25
      ((230, 153, 0), (204, 230, 1, 0)), // 25–30
      ((179, 119, 0), (255, 255, 1, 0)), // 30–35
      ((255, 0, 0), (255, 255, 1, 0)), // 35–40
      ((204, 0, 0), (255, 196, 1, 0)), // 40–50
      ((166, 0, 0), (255, 196, 1, 0)), // 50–60
      ((254, 0, 255), (255, 137, 1, 0)), // 60–70
      ((216, 0, 217), (255, 137, 1, 0)), // 70–80
      ((188, 0, 191), (255, 137, 1, 0)), // 80–90
      ((165, 0, 166), (255, 69, 1, 0)), // 90–100
      ((199, 179, 255), (255, 69, 1, 0)), // 100–150
      ((170, 140, 255), (255, 69, 1, 0)), // 150–200
      ((142, 102, 255), (254, 0, 0, 0)), // 200–300
    ];

/// The as-measured look of a rain image of [palette]: the service's
/// colours as they are, only the global model's no-rain veil taken away.
Uint8List measuredRainPixels(Uint8List rgba, RainPalette palette) {
  if (palette != RainPalette.dwdModel6h) return rgba;
  final out = Uint8List.fromList(rgba);
  for (var o = 0; o + 3 < out.length; o += 4) {
    if (out[o + 3] == 0) continue;
    if (_modelNoData(out[o], out[o + 1], out[o + 2])) out[o + 3] = 0;
  }
  return out;
}

/// Makes every pixel of [rgba] ([width] × [height], an image of [box] in
/// Web Mercator) transparent that lies inside one of [masks] (lon/lat
/// rings): the places a source leaves to those before it. Row by row, by
/// where each row's middle crosses the rings' edges.
void maskRainPixels(
  int width,
  int height,
  Uint8List rgba,
  BoundingBox box,
  List<List<LatLng>> masks,
) {
  if (masks.isEmpty || width <= 0 || height <= 0) return;
  final x0 = mercatorX(box.west);
  final xSpan = mercatorX(box.east) - x0;
  final y1 = mercatorY(box.north);
  final ySpan = y1 - mercatorY(box.south);
  if (xSpan <= 0 || ySpan <= 0) return;
  for (final ring in masks) {
    if (ring.length < 3) continue;
    final xs = <double>[
      for (final p in ring) (mercatorX(p.lon) - x0) / xSpan * width,
    ];
    final ys = <double>[
      for (final p in ring) (y1 - mercatorY(p.lat)) / ySpan * height,
    ];
    final top = ys.reduce(math.min).floor().clamp(0, height);
    final bottom = ys.reduce(math.max).ceil().clamp(0, height);
    for (var y = top; y < bottom; y++) {
      final cy = y + 0.5;
      final crossings = <double>[];
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        if ((ys[i] > cy) != (ys[j] > cy)) {
          crossings.add(
            xs[i] + (cy - ys[i]) / (ys[j] - ys[i]) * (xs[j] - xs[i]),
          );
        }
      }
      crossings.sort();
      for (var k = 0; k + 1 < crossings.length; k += 2) {
        final from = (crossings[k] - 0.5).ceil().clamp(0, width);
        final to = (crossings[k + 1] - 0.5).floor().clamp(-1, width - 1);
        for (var x = from; x <= to; x++) {
          rgba[(y * width + x) * 4 + 3] = 0;
        }
      }
    }
  }
}

/// What a rain image needs on the phone before the map draws it: the look
/// ([soft] or as measured), how its colours are read ([palette]), the box
/// it shows and the places it leaves to other sources ([masks]).
@immutable
class RainImageJob {
  /// Creates the job.
  const RainImageJob({
    required this.palette,
    required this.soft,
    required this.box,
    this.masks = const <List<LatLng>>[],
    this.forecast = false,
  });

  final RainPalette palette;
  final bool soft;
  final BoundingBox box;
  final List<List<LatLng>> masks;

  /// Whether the image is a model's forecast, drawn lighter
  /// ([forecastAlphaScale]).
  final bool forecast;

  /// Whether the image is to be touched at all: as measured, unmasked, no
  /// forecast and in a palette drawn as it comes, it is drawn as the
  /// service sent it.
  bool get needed =>
      soft || forecast || masks.isNotEmpty || palette == RainPalette.dwdModel6h;
}

/// [rgba] ([width] × [height]) as [job] wants it drawn.
Uint8List prepareRainPixels(
  int width,
  int height,
  Uint8List rgba,
  RainImageJob job,
) {
  final out = job.soft
      ? softenRainPixels(width, height, rgba, job.palette)
      : Uint8List.fromList(measuredRainPixels(rgba, job.palette));
  maskRainPixels(width, height, out, job.box, job.masks);
  if (job.forecast) {
    for (var o = 3; o < out.length; o += 4) {
      out[o] = (out[o] * forecastAlphaScale).round();
    }
  }
  return out;
}

/// [rgba] (straight alpha, [width] × [height]) as a PNG: no filtering,
/// zlib-deflated, which is all a decoder needs.
Uint8List encodePngRgba(int width, int height, Uint8List rgba) {
  final raw = BytesBuilder(copy: false);
  final stride = width * 4;
  for (var y = 0; y < height; y++) {
    raw
      ..addByte(0)
      ..add(Uint8List.sublistView(rgba, y * stride, (y + 1) * stride));
  }
  final out = BytesBuilder(copy: false)
    ..add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typed = Uint8List.fromList(<int>[...type.codeUnits, ...data]);
    out
      ..add(_uint32(data.length))
      ..add(typed)
      ..add(_uint32(_crc32(typed)));
  }

  chunk('IHDR', <int>[
    ..._uint32(width),
    ..._uint32(height),
    8, // bit depth
    6, // RGBA
    0,
    0,
    0,
  ]);
  chunk('IDAT', ZLibCodec(level: 6).encode(raw.takeBytes()));
  chunk('IEND', const <int>[]);
  return out.takeBytes();
}

Uint8List _uint32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v & 0xFFFFFFFF, Endian.big);

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c;
  }
  return table;
}();

int _crc32(Uint8List bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Decodes the service's [png] on the engine, then whitens and re-encodes
/// it on a background isolate.
Future<Uint8List> processCloudImage(Uint8List png) async {
  final (width, height, pixels) = await _decode(png);
  return Isolate.run(
    () => encodePngRgba(width, height, whitenCloudPixels(pixels)),
  );
}

/// Decodes the rain's [png] on the engine, then prepares it as [job] says
/// ([prepareRainPixels]) and re-encodes it on a background isolate; the
/// service's own image where the job wants nothing done.
Future<Uint8List> processRainImage(Uint8List png, RainImageJob job) async {
  if (!job.needed) return png;
  final (width, height, pixels) = await _decode(png);
  return Isolate.run(
    () => encodePngRgba(
      width,
      height,
      prepareRainPixels(width, height, pixels, job),
    ),
  );
}

Future<(int, int, Uint8List)> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final width = image.width;
  final height = image.height;
  image.dispose();
  codec.dispose();
  if (data == null) throw StateError('weather image not decoded');
  return (width, height, data.buffer.asUint8List());
}

/// How many soft radar images of one source the cache keeps: the boxes and
/// moments of the last few views and steps of the time control.
const int radarImageCacheKeep = 24;

/// Whether the map's own decoder takes [image]: a PNG must carry its
/// transparency as an alpha channel (colour type 6) or a palette (3). An
/// RGB PNG with a colour key (`tRNS`), as ArcGIS sends for `format=png`,
/// fails on Android, its tiles silently empty; other formats pass.
bool mapCanDecode(Uint8List image) {
  const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (image.length < 8) return true;
  for (var i = 0; i < 8; i++) {
    if (image[i] != signature[i]) return true;
  }
  // The IHDR chunk comes first: length, type, width, height, bit depth,
  // then the colour type at byte 25.
  if (image.length < 26) return false;
  final colourType = image[25];
  return colourType == 6 || colourType == 3;
}

/// What the weather layers ask of the network: whether a radar tile
/// answers, the cloud image of a region and the finer one of a view.
abstract class WeatherFetcher {
  /// Whether [url] answers with an image within [weatherProbeTimeout].
  Future<bool> probe(String url);

  /// The cloud image of [source]'s coverage box [region] at [frame], white
  /// cloud on a clear ground as a PNG; `null` when it cannot be had.
  Future<Uint8List?> cloudImage(
    WeatherMapSource source,
    int region,
    WeatherFrame frame,
    DateTime now,
  );

  /// The detail cloud image of [box] at [frame] (see `cloudDetailArea`),
  /// processed as [cloudImage]'s; `null` when it cannot be had.
  Future<Uint8List?> cloudDetailImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now,
  );

  /// A rain source's image of [box] at [frame] (see
  /// `WeatherMapSource.softImageUrl`): the soft radar, the satellite or a
  /// model, prepared for [style] with [masks] left out as
  /// [processRainImage] does; `null` when the service does not answer with
  /// an image within [weatherProbeTimeout], which is the source's check.
  /// [maskKey] names the masks in the cache.
  Future<Uint8List?> radarImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now, {
    RadarStyle style = RadarStyle.soft,
    List<List<LatLng>> masks = const <List<LatLng>>[],
    String maskKey = '',
  });

  /// The wind of [request]'s box at [frame] from [source] (see
  /// `WindRequest.url`); `null` when the service does not answer with a
  /// grid within [windTimeout], which is the source's check.
  Future<WindGrid?> windGrid(
    WeatherMapSource source,
    WindRequest request,
    WeatherFrame frame,
    DateTime now,
  );
}

/// Reads a wind grid off the main isolate.
Future<WindGrid?> parseWindGridInBackground(String text) =>
    Isolate.run(() => parseWcsWindGrid(text));

/// [WeatherFetcher] over HTTP, cloud images cached in [cacheDir].
class HttpWeatherFetcher implements WeatherFetcher {
  /// A fetcher on [dio]; [process] turns the service's image into the one
  /// drawn (the engine's decoder by default).
  HttpWeatherFetcher({
    required this.dio,
    required this.cacheDir,
    this.process = processCloudImage,
    this.processRadar = processRainImage,
    this.probeTimeout = weatherProbeTimeout,
    this.imageTimeout = cloudImageTimeout,
    this.windTimeLimit = windTimeout,
    this.parseWind = parseWindGridInBackground,
  });

  /// How long the wind of a box may take.
  final Duration windTimeLimit;

  /// Reads the service's text into a grid.
  final Future<WindGrid?> Function(String text) parseWind;

  /// How long a probe may take.
  final Duration probeTimeout;

  /// How long a cloud image may take.
  final Duration imageTimeout;

  final Dio dio;

  /// Where processed cloud images are kept; created as needed.
  final Future<Directory> Function() cacheDir;

  final Future<Uint8List> Function(Uint8List png) process;

  /// Turns a rain image into the one drawn.
  final Future<Uint8List> Function(Uint8List png, RainImageJob job)
  processRadar;

  /// The requests made, newest last; for tests and the log.
  final List<String> requests = <String>[];

  @override
  Future<bool> probe(String url) async {
    final body = await _getImage(url, probeTimeout);
    return body != null && mapCanDecode(body);
  }

  @override
  Future<Uint8List?> cloudImage(
    WeatherMapSource source,
    int region,
    WeatherFrame frame,
    DateTime now,
  ) {
    final prefix = '${source.id}_${region}_';
    final name = '$prefix${cloudImageStamp(frame, now)}.png';
    return _cloud(
      source.regionImageUrl(frame, region),
      name,
      (dir) => _prune(dir, (file) => file.startsWith(prefix), name, now),
    );
  }

  @override
  Future<Uint8List?> cloudDetailImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now,
  ) {
    final prefix = '${source.id}_detail_';
    final stamp = '_${cloudImageStamp(frame, now)}.png';
    final name = '$prefix${cloudDetailKey(box)}$stamp';
    return _cloud(
      source.detailImageUrl(frame, box),
      name,
      // Other moments go; of this one the last few boxes stay.
      (dir) => _prune(
        dir,
        (file) => file.startsWith(prefix) && !file.endsWith(stamp),
        name,
        now,
        prefix: prefix,
        keep: cloudDetailCacheKeep,
      ),
    );
  }

  @override
  Future<Uint8List?> radarImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now, {
    RadarStyle style = RadarStyle.soft,
    List<List<LatLng>> masks = const <List<LatLng>>[],
    String maskKey = '',
  }) async {
    final url = source.softImageUrl(frame, box);
    if (url == null) return null;
    final prefix = '${source.id}_${style.name}_';
    final name =
        '$prefix${cloudDetailKey(box)}_${radarImageStamp(source, frame, now)}'
        '$maskKey.png';
    final job = RainImageJob(
      palette: source.palette,
      soft: style == RadarStyle.soft,
      box: box,
      masks: masks,
      forecast: source.role == RainRole.model,
    );
    return _cloud(
      url,
      name,
      (dir) => _prune(
        dir,
        (_) => false,
        name,
        now,
        prefix: prefix,
        keep: radarImageCacheKeep,
      ),
      timeout: probeTimeout,
      process: (png) => processRadar(png, job),
    );
  }

  @override
  Future<WindGrid?> windGrid(
    WeatherMapSource source,
    WindRequest request,
    WeatherFrame frame,
    DateTime now,
  ) async {
    final time = frame.time;
    if (time == null) return null;
    final prefix = '${source.id}_';
    final name = '$prefix${request.key}_${time.millisecondsSinceEpoch}.txt';
    Directory? dir;
    try {
      dir = await cacheDir();
      final cached = File(p.join(dir.path, name));
      if (cached.existsSync() &&
          now.difference(cached.lastModifiedSync()) < windCacheMaxAge) {
        final grid = await parseWind(await cached.readAsString());
        if (grid != null) return grid;
      }
    } on Object catch (error) {
      debugPrint('velorki: wind cache unreadable: $error');
    }
    final text = await _getText(request.url(source, frame), windTimeLimit);
    if (text == null) return null;
    final WindGrid? grid;
    try {
      grid = await parseWind(text);
    } on Object catch (error) {
      debugPrint('velorki: wind not read: $error');
      return null;
    }
    if (grid == null) return null;
    if (dir != null) {
      try {
        if (!dir.existsSync()) dir.createSync(recursive: true);
        await File(p.join(dir.path, name)).writeAsString(text);
        _prune(
          dir,
          (_) => false,
          name,
          now,
          prefix: prefix,
          keep: windCacheKeep,
          extension: '.txt',
        );
      } on Object catch (error) {
        debugPrint('velorki: wind not cached: $error');
      }
    }
    return grid;
  }

  /// The body of [url] when it is plain text, else `null`: the service
  /// answers a request it cannot serve with an XML error, status 200.
  Future<String?> _getText(String url, Duration timeout) async {
    requests.add(url);
    try {
      final response = await dio
          .get<String>(
            url,
            options: Options(
              responseType: ResponseType.plain,
              sendTimeout: timeout,
              receiveTimeout: timeout,
            ),
          )
          .timeout(timeout);
      final status = response.statusCode ?? 0;
      final type = response.headers.value(Headers.contentTypeHeader) ?? '';
      final data = response.data;
      if (status < 200 || status >= 300) return null;
      if (!type.toLowerCase().startsWith('text/plain')) return null;
      if (data == null || data.isEmpty) return null;
      return data;
    } on Object {
      return null;
    }
  }

  /// The image cached as [name], else fetched from [url] within [timeout]
  /// (the cloud images' by default), turned by [process] (the clouds') and
  /// cached, [prune] then tidying the cache.
  Future<Uint8List?> _cloud(
    String url,
    String name,
    void Function(Directory dir) prune, {
    Duration? timeout,
    Future<Uint8List> Function(Uint8List png)? process,
  }) async {
    final Directory dir;
    try {
      dir = await cacheDir();
      final cached = File(p.join(dir.path, name));
      if (cached.existsSync()) return await cached.readAsBytes();
    } on Object catch (error) {
      debugPrint('velorki: cloud cache unreadable: $error');
      return null;
    }
    final body = await _getImage(url, timeout ?? imageTimeout);
    if (body == null) return null;
    final Uint8List png;
    try {
      png = await (process ?? this.process)(body);
    } on Object catch (error) {
      debugPrint('velorki: cloud image not processed: $error');
      return null;
    }
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File(p.join(dir.path, name)).writeAsBytes(png);
      prune(dir);
    } on Object catch (error) {
      debugPrint('velorki: cloud image not cached: $error');
    }
    return png;
  }

  /// The body of [url] when it is an image, else `null`.
  Future<Uint8List?> _getImage(String url, Duration timeout) async {
    requests.add(url);
    try {
      final response = await dio
          .get<List<int>>(
            url,
            options: Options(
              responseType: ResponseType.bytes,
              sendTimeout: timeout,
              receiveTimeout: timeout,
            ),
          )
          .timeout(timeout);
      final status = response.statusCode ?? 0;
      // A map service answers a bad request with an XML error, often under
      // 200: only an image counts.
      final type = response.headers.value(Headers.contentTypeHeader) ?? '';
      final data = response.data;
      if (status < 200 || status >= 300) return null;
      if (!type.toLowerCase().startsWith('image/')) return null;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } on Object {
      return null;
    }
  }

  /// Deletes the images [replaced] names, any image past
  /// [cloudCacheMaxAge] and, with [prefix], all but the newest [keep]
  /// under it; never [current].
  static void _prune(
    Directory dir,
    bool Function(String name) replaced,
    String current,
    DateTime now, {
    String? prefix,
    int keep = 0,
    String extension = '.png',
  }) {
    final kept = <(File, DateTime)>[];
    for (final entry in dir.listSync()) {
      if (entry is! File) continue;
      final name = p.basename(entry.path);
      if (name == current || !name.endsWith(extension)) continue;
      try {
        final modified = entry.lastModifiedSync();
        if (replaced(name) || now.difference(modified) > cloudCacheMaxAge) {
          entry.deleteSync();
        } else if (prefix != null && name.startsWith(prefix)) {
          kept.add((entry, modified));
        }
      } on FileSystemException {
        // Gone already, or busy: the next prune tries again.
      }
    }
    // The current one counts towards [keep].
    if (kept.length < keep) return;
    kept.sort((a, b) => b.$2.compareTo(a.$2));
    for (final (file, _) in kept.skip(math.max(0, keep - 1))) {
      try {
        file.deleteSync();
      } on FileSystemException {
        // As above.
      }
    }
  }
}

/// What tells one cloud image from the next in the cache: the moment it
/// shows, or for the latest image the [latestCloudSlot] it was fetched in.
int cloudImageStamp(WeatherFrame frame, DateTime now) {
  final time = frame.time;
  if (time != null) return time.millisecondsSinceEpoch;
  final slot = latestCloudSlot.inMilliseconds;
  final ms = now.millisecondsSinceEpoch;
  return ms - ms % slot;
}
