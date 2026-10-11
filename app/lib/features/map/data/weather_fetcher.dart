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
import 'rain_legend.dart';

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

/// How long the wind of a box may take.
const Duration windTimeout = Duration(seconds: 15);

/// How many bytes the weather cache keeps on disk, all sources together:
/// past it, the images and grids used longest ago go first. Enough for the
/// views and steps of the time control a rider moves between, so panning
/// back or dragging the slider back comes from the disk.
const int weatherCacheBudget = 150 * 1024 * 1024;

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

/// What a cloud image needs on the phone before the map draws it, besides
/// being whitened: the [box] it shows (Web Mercator) and where it fades
/// into a neighbour's ([fades], see `cloudFadesOf`).
@immutable
class CloudImageJob {
  /// Creates the job.
  const CloudImageJob({required this.box, this.fades = const <CloudFade>[]});

  final BoundingBox box;
  final List<CloudFade> fades;
}

/// Multiplies the alpha of each column of [rgba] ([width] × [height], an
/// image of [box] in Web Mercator) by where the column's middle lies on
/// each of [fades]' ramps.
void fadeCloudPixels(
  int width,
  int height,
  Uint8List rgba,
  BoundingBox box,
  List<CloudFade> fades,
) {
  if (fades.isEmpty || width <= 0 || height <= 0) return;
  final x0 = mercatorX(box.west);
  final xStep = (mercatorX(box.east) - x0) / width;
  final factors = Float64List(width);
  var any = false;
  for (var x = 0; x < width; x++) {
    final lon = lonOfMercatorX(x0 + (x + 0.5) * xStep);
    var f = 1.0;
    for (final fade in fades) {
      f *= fade.factorAt(lon);
    }
    factors[x] = f;
    if (f < 1) any = true;
  }
  if (!any) return;
  for (var y = 0; y < height; y++) {
    final row = y * width;
    for (var x = 0; x < width; x++) {
      final f = factors[x];
      if (f >= 1) continue;
      final o = (row + x) * 4 + 3;
      rgba[o] = (rgba[o] * f).round();
    }
  }
}

/// How far, in pixels, the softening of edges reaches: 1 is a 3 × 3 box.
const int radarBlurRadius = 1;

/// The soft look of a rain image of [palette]: each pixel read against the
/// palette's legend ([RainLegend.classify]), rain drawn in its legend
/// colour at its class's alpha times the service's own, everything else
/// transparent (the "no data" grey, the line around a radar's reach); then
/// the alpha alone averaged over a box of [radarBlurRadius], so the edges
/// fade out instead of stepping. Heavy rain ([rainAlphaHeavy] and more) is
/// never made fainter.
Uint8List softenRainPixels(
  int width,
  int height,
  Uint8List rgba,
  RainPalette palette,
) {
  final legend = rainLegendOf(palette);
  final n = width * height;
  final alpha = Float64List(n);
  final heavy = Uint8List(n);
  final out = Uint8List.fromList(rgba);
  // An image has a few hundred colours at most: each read once.
  final read = <int, int>{};
  for (var i = 0; i < n; i++) {
    final o = i * 4;
    final a = rgba[o + 3];
    if (a == 0) continue;
    final r = rgba[o];
    final g = rgba[o + 1];
    final b = rgba[o + 2];
    final key = r << 24 | g << 16 | b << 8 | a;
    final k = read[key] ??= legend.classify(r, g, b, a);
    if (k < 0) {
      out[o + 3] = 0;
      continue;
    }
    final colour = legend.colourOf(k, r, g, b);
    out[o] = colour >> 16 & 0xFF;
    out[o + 1] = colour >> 8 & 0xFF;
    out[o + 2] = colour & 0xFF;
    final intensity = legend.alphaOf(k);
    alpha[i] = intensity * a / 255;
    if (intensity >= rainAlphaHeavy - 1e-9) heavy[i] = 1;
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

/// The global model's ground with no rain: the service draws "under
/// 0.1 mm" a faint black veil (alpha 20).
bool _modelNoData(int r, int g, int b, int a) =>
    a < rainLegendMinAlpha && math.max(r, math.max(g, b)) < 40;

/// [rgba] of ICON-EU's hourly rain with each pixel in the radar colour of
/// the rate it stands for ([dwdModel1hLegend]), its alpha kept; no rain
/// and no data transparent.
Uint8List _recolouredPixels(Uint8List rgba) {
  final legend = dwdModel1hLegend;
  final out = Uint8List.fromList(rgba);
  for (var o = 0; o + 3 < out.length; o += 4) {
    if (out[o + 3] == 0) continue;
    final k = legend.classify(out[o], out[o + 1], out[o + 2], out[o + 3]);
    if (k < 0) {
      out[o + 3] = 0;
      continue;
    }
    final c = legend.colourOf(k, out[o], out[o + 1], out[o + 2]);
    out[o] = c >> 16 & 0xFF;
    out[o + 1] = c >> 8 & 0xFF;
    out[o + 2] = c & 0xFF;
  }
  return out;
}

/// The as-measured look of a rain image of [palette]: the service's
/// colours as they are, only the global model's no-rain veil and the N0Q
/// ramp's echoes too weak to be rain taken away; ICON-EU's hourly rain,
/// whose colours stand for other rates than their own, in the colours of
/// the rates they stand for.
Uint8List measuredRainPixels(Uint8List rgba, RainPalette palette) {
  if (palette == RainPalette.dwdModel1h) return _recolouredPixels(rgba);
  if (palette == RainPalette.n0q) {
    final legend = rainLegendOf(palette);
    final out = Uint8List.fromList(rgba);
    for (var o = 0; o + 3 < out.length; o += 4) {
      if (out[o + 3] == 0) continue;
      if (legend.classify(out[o], out[o + 1], out[o + 2], out[o + 3]) < 0) {
        out[o + 3] = 0;
      }
    }
    return out;
  }
  if (palette != RainPalette.dwdModel6h) return rgba;
  final out = Uint8List.fromList(rgba);
  for (var o = 0; o + 3 < out.length; o += 4) {
    if (out[o + 3] == 0) continue;
    if (_modelNoData(out[o], out[o + 1], out[o + 2], out[o + 3])) {
      out[o + 3] = 0;
    }
  }
  return out;
}

/// Where a frame of a source with an [extent] (lon/lat ring) measures:
/// over its image [rgba] ([width] × [height], of [box] in Web Mercator),
/// inside the ring where the pixel is not the [palette]'s "no data", as
/// the weights of [RainCoverage] ([rainSeamWeights]): 0 where it does not
/// measure, rising to 255 [rainSeamMetres] inside the edge. Read from the
/// service's own pixels, before the soft look takes the grey away.
Uint8List rainCoverageOf(
  int width,
  int height,
  Uint8List rgba,
  RainPalette palette,
  BoundingBox box,
  List<LatLng> extent,
) {
  final legend = rainLegendOf(palette);
  final inside = Uint8List(width * height);
  _fillRing(width, height, box, extent, (y, from, to) {
    inside.fillRange(y * width + from, y * width + to + 1, 1);
  });
  for (var i = 0; i < inside.length; i++) {
    if (inside[i] == 0) continue;
    final o = i * 4;
    if (legend.isNoData(rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3])) {
      inside[i] = 0;
    }
  }
  return rainSeamWeights(width, height, inside, box);
}

/// The weights of a coverage ([RainCoverage]) from where a frame measures,
/// [inside] (over 0 where it does), over an image of [box] ([width] ×
/// [height], Web Mercator): each measured pixel's distance on the ground to
/// the nearest pixel not measured, over [rainSeamMetres], as 1..255; 0
/// where not measured. Beyond the image's edges counts as measured, so the
/// edge of the image is no edge of the coverage.
///
/// The distance by a two-pass chamfer over the pixel grid (steps across,
/// up and down, and diagonal, in Web Mercator metres), scaled to the
/// ground by each row's latitude.
Uint8List rainSeamWeights(
  int width,
  int height,
  Uint8List inside,
  BoundingBox box,
) {
  final n = width * height;
  final out = Uint8List(n);
  if (n == 0) return out;
  final xStep = (mercatorX(box.east) - mercatorX(box.west)) / width;
  final y1 = mercatorY(box.north);
  final yStep = (y1 - mercatorY(box.south)) / height;
  final diagonal = math.sqrt(xStep * xStep + yStep * yStep);
  const far = double.infinity;
  final d = Float64List(n);
  for (var i = 0; i < n; i++) {
    d[i] = inside[i] == 0 ? 0 : far;
  }
  // Forward: from the north-west.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      if (d[i] == 0) continue;
      var v = d[i];
      if (x > 0) v = math.min(v, d[i - 1] + xStep);
      if (y > 0) {
        final up = i - width;
        v = math.min(v, d[up] + yStep);
        if (x > 0) v = math.min(v, d[up - 1] + diagonal);
        if (x + 1 < width) v = math.min(v, d[up + 1] + diagonal);
      }
      d[i] = v;
    }
  }
  // Backward: from the south-east.
  for (var y = height - 1; y >= 0; y--) {
    for (var x = width - 1; x >= 0; x--) {
      final i = y * width + x;
      if (d[i] == 0) continue;
      var v = d[i];
      if (x + 1 < width) v = math.min(v, d[i + 1] + xStep);
      if (y + 1 < height) {
        final down = i + width;
        v = math.min(v, d[down] + yStep);
        if (x + 1 < width) v = math.min(v, d[down + 1] + diagonal);
        if (x > 0) v = math.min(v, d[down - 1] + diagonal);
      }
      d[i] = v;
    }
  }
  for (var y = 0; y < height; y++) {
    // Web Mercator stretches the ground by 1 / cos(latitude).
    final lat = latOfMercatorY(y1 - (y + 0.5) * yStep);
    final ground = math.cos(lat * math.pi / 180);
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      if (inside[i] == 0) continue;
      final metres = d[i] * ground;
      out[i] = metres.isInfinite
          ? 255
          : (metres / rainSeamMetres * 255).round().clamp(1, 255);
    }
  }
  return out;
}

/// Calls [span] with each row of an image of [box] ([width] × [height])
/// and the first and last pixel of each run whose middles lie inside
/// [ring]: by where each row's middle crosses the ring's edges.
void _fillRing(
  int width,
  int height,
  BoundingBox box,
  List<LatLng> ring,
  void Function(int y, int from, int to) span,
) {
  if (ring.length < 3 || width <= 0 || height <= 0) return;
  final x0 = mercatorX(box.west);
  final xSpan = mercatorX(box.east) - x0;
  final y1 = mercatorY(box.north);
  final ySpan = y1 - mercatorY(box.south);
  if (xSpan <= 0 || ySpan <= 0) return;
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
        crossings.add(xs[i] + (cy - ys[i]) / (ys[j] - ys[i]) * (xs[j] - xs[i]));
      }
    }
    crossings.sort();
    for (var k = 0; k + 1 < crossings.length; k += 2) {
      final from = (crossings[k] - 0.5).ceil().clamp(0, width);
      final to = (crossings[k + 1] - 0.5).floor().clamp(-1, width - 1);
      if (from <= to) span(y, from, to);
    }
  }
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
  for (final ring in masks) {
    _fillRing(width, height, box, ring, (y, from, to) {
      for (var x = from; x <= to; x++) {
        rgba[(y * width + x) * 4 + 3] = 0;
      }
    });
  }
}

/// Leaves of each pixel of [rgba] ([width] × [height], an image of [box]
/// in Web Mercator) 1 − the weight of [coverages] at its middle (the
/// greatest, of the nearest pixel of each, by Web Mercator position): none
/// where one of them alone draws, a ramp across its seam, all where none
/// measures. The places a source leaves to the frames of those before it.
void cutRainPixels(
  int width,
  int height,
  Uint8List rgba,
  BoundingBox box,
  List<RainCoverage> coverages,
) {
  if (coverages.isEmpty || width <= 0 || height <= 0) return;
  final x0 = mercatorX(box.west);
  final xStep = (mercatorX(box.east) - x0) / width;
  final y1 = mercatorY(box.north);
  final yStep = (y1 - mercatorY(box.south)) / height;
  for (var y = 0; y < height; y++) {
    final my = y1 - (y + 0.5) * yStep;
    for (var x = 0; x < width; x++) {
      final o = (y * width + x) * 4 + 3;
      if (rgba[o] == 0) continue;
      final mx = x0 + (x + 0.5) * xStep;
      var weight = 0.0;
      for (final coverage in coverages) {
        weight = math.max(weight, coverage.weightAtMercator(mx, my));
        if (weight >= 1) break;
      }
      if (weight > 0) rgba[o] = (rgba[o] * (1 - weight)).round();
    }
  }
}

/// What a rain image needs on the phone before the map draws it: the look
/// ([soft] or as measured), how its colours are read ([palette]), the box
/// it shows, the places it leaves to other sources ([masks], fixed rings,
/// and [coverages], the frames of those before it) and, for a source with
/// an [extent], that its frame's coverage is to be kept with it.
@immutable
class RainImageJob {
  /// Creates the job.
  const RainImageJob({
    required this.palette,
    required this.soft,
    required this.box,
    this.masks = const <List<LatLng>>[],
    this.coverages = const <RainCoverage>[],
    this.extent,
  });

  final RainPalette palette;
  final bool soft;
  final BoundingBox box;
  final List<List<LatLng>> masks;
  final List<RainCoverage> coverages;

  /// The source's [WeatherMapSource.extent]: where set, where the frame
  /// measures ([rainCoverageOf]) goes with the image ([readRainCoverage]).
  final List<LatLng>? extent;

  /// Whether the image is to be touched at all: as measured, unmasked and
  /// in a palette drawn as it comes, it is drawn as the service sent it.
  bool get needed =>
      soft ||
      masks.isNotEmpty ||
      coverages.isNotEmpty ||
      extent != null ||
      palette == RainPalette.dwdModel6h ||
      palette == RainPalette.dwdModel1h ||
      palette == RainPalette.n0q;
}

/// [rgba] ([width] × [height]) as [job] wants it drawn. A source cut by
/// its own frame's coverage ([seam], the weights of [rainCoverageOf] over
/// the same pixels) keeps only that weight of its alpha, so it fades out
/// across its seam as the sources after it fade in.
Uint8List prepareRainPixels(
  int width,
  int height,
  Uint8List rgba,
  RainImageJob job, {
  Uint8List? seam,
}) {
  final out = job.soft
      ? softenRainPixels(width, height, rgba, job.palette)
      : Uint8List.fromList(measuredRainPixels(rgba, job.palette));
  if (seam != null && seam.length == width * height) {
    for (var i = 0; i < seam.length; i++) {
      final w = seam[i];
      if (w == 255) continue;
      final o = i * 4 + 3;
      out[o] = (out[o] * w / 255).round();
    }
  }
  maskRainPixels(width, height, out, job.box, job.masks);
  cutRainPixels(width, height, out, job.box, job.coverages);
  return out;
}

/// The PNG chunk a rain image's coverage travels in (see
/// [readRainCoverage]): ancillary, private, safe to copy, so every decoder
/// skips it.
const String rainCoverageChunk = 'vlCv';

/// [rgba] (straight alpha, [width] × [height]) as a PNG: no filtering,
/// zlib-deflated, which is all a decoder needs. [coverage] (one byte a
/// pixel, [coverageWidth] × [coverageHeight], the image's own size unless
/// said), where given, goes in a [rainCoverageChunk] of its own: its width
/// and height, then the bytes deflated.
Uint8List encodePngRgba(
  int width,
  int height,
  Uint8List rgba, {
  Uint8List? coverage,
  int? coverageWidth,
  int? coverageHeight,
  int level = 6,
}) {
  final raw = BytesBuilder(copy: false);
  final stride = width * 4;
  for (var y = 0; y < height; y++) {
    raw
      ..addByte(0)
      ..add(Uint8List.sublistView(rgba, y * stride, (y + 1) * stride));
  }
  final out = BytesBuilder(copy: false)..add(_pngSignature);
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
  if (coverage != null) {
    chunk(rainCoverageChunk, <int>[
      ..._uint32(coverageWidth ?? width),
      ..._uint32(coverageHeight ?? height),
      ...ZLibCodec(level: 6).encode(coverage),
    ]);
  }
  chunk('IDAT', ZLibCodec(level: level).encode(raw.takeBytes()));
  chunk('IEND', const <int>[]);
  return out.takeBytes();
}

const List<int> _pngSignature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// The coverage a rain image of [box] carries ([encodePngRgba]'s
/// `coverage`): where its source measures in that frame; `null` where the
/// image has none or is not one of ours.
RainCoverage? readRainCoverage(Uint8List png, BoundingBox box) {
  if (png.length < 33) return null;
  for (var i = 0; i < 8; i++) {
    if (png[i] != _pngSignature[i]) return null;
  }
  final data = ByteData.sublistView(png);
  var at = 8;
  while (at + 12 <= png.length) {
    final length = data.getUint32(at);
    final type = String.fromCharCodes(png, at + 4, at + 8);
    final end = at + 12 + length;
    if (end > png.length) return null;
    if (type == rainCoverageChunk) {
      if (length < 8) return null;
      final width = data.getUint32(at + 8);
      final height = data.getUint32(at + 12);
      try {
        final covered = Uint8List.fromList(
          ZLibCodec().decode(Uint8List.sublistView(png, at + 16, end - 4)),
        );
        if (covered.length != width * height) return null;
        return RainCoverage(
          box: box,
          width: width,
          height: height,
          covered: covered,
        );
      } on FormatException {
        return null;
      }
    }
    if (type == 'IDAT' || type == 'IEND') return null;
    at = end;
  }
  return null;
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

/// Decodes the service's [png] on the engine, then whitens it, fades it
/// as [job] says ([fadeCloudPixels]) and re-encodes it on a background
/// isolate.
Future<Uint8List> processCloudImage(Uint8List png, CloudImageJob job) async {
  final (width, height, pixels) = await _decode(png);
  return Isolate.run(() {
    final out = whitenCloudPixels(pixels);
    fadeCloudPixels(width, height, out, job.box, job.fades);
    return encodePngRgba(width, height, out);
  });
}

/// Decodes the rain's [png] on the engine, then prepares it as [job] says
/// ([prepareRainPixels]) and re-encodes it on a background isolate; the
/// service's own image where the job wants nothing done.
Future<Uint8List> processRainImage(Uint8List png, RainImageJob job) async {
  if (!job.needed) return png;
  final (width, height, pixels) = await _decode(png);
  return Isolate.run(() => prepareRainImage(width, height, pixels, job));
}

/// The rain image [rgba] ([width] × [height], straight RGBA, as the service
/// drew it) prepared as [job] wants it ([prepareRainPixels]) and encoded:
/// for a source with an extent its frame's coverage worked out first and
/// carried along, and drawn soft, scaled up smoothly
/// ([upsampleRainPixels]).
Uint8List prepareRainImage(
  int width,
  int height,
  Uint8List rgba,
  RainImageJob job,
) {
  final extent = job.extent;
  final coverage = extent == null
      ? null
      : rainCoverageOf(width, height, rgba, job.palette, job.box, extent);
  final prepared = prepareRainPixels(
    width,
    height,
    rgba,
    job,
    seam: job.soft ? coverage : null,
  );
  if (!job.soft) {
    return encodePngRgba(width, height, prepared, coverage: coverage);
  }
  final (w, h, smooth) = upsampleRainPixels(width, height, prepared);
  return encodePngRgba(
    w,
    h,
    smooth,
    coverage: coverage,
    coverageWidth: width,
    coverageHeight: height,
  );
}

/// How much the soft look scales a rain image up before the map draws it:
/// twice, within [radarSoftMaxSide].
const double rainUpsample = 2;

/// [rgba] ([width] × [height], straight RGBA) scaled up [rainUpsample]
/// times, its long side at most [radarSoftMaxSide] (not at all where it
/// is that long already), with the Catmull-Rom cubic on premultiplied
/// alpha: the contours of the rain come out round instead of the cells'
/// squares the map's linear smoothing leaves, and a cell's colour does not
/// bleed into the clear ground around it. No detail is made up: a cell of
/// one colour stays that colour, and a clear area clear.
(int, int, Uint8List) upsampleRainPixels(
  int width,
  int height,
  Uint8List rgba, {
  double factor = rainUpsample,
  int maxSide = radarSoftMaxSide,
}) {
  final long = math.max(width, height);
  final scale = long <= 0 ? 1.0 : math.min(factor, maxSide / long);
  if (scale <= 1.0 + 1e-9) return (width, height, rgba);
  final w2 = math.max(1, (width * scale).round());
  final h2 = math.max(1, (height * scale).round());
  // Premultiplied, as floats.
  final src = Float32List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final o = i * 4;
    final a = rgba[o + 3] / 255;
    src[o] = rgba[o] * a;
    src[o + 1] = rgba[o + 1] * a;
    src[o + 2] = rgba[o + 2] * a;
    src[o + 3] = rgba[o + 3].toDouble();
  }
  final (xi, xw) = _cubicTaps(width, w2);
  final (yi, yw) = _cubicTaps(height, h2);
  // Across, then down.
  final mid = Float32List(w2 * height * 4);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    for (var x = 0; x < w2; x++) {
      final o = (y * w2 + x) * 4;
      for (var k = 0; k < 4; k++) {
        final s = (row + xi[x * 4 + k]) * 4;
        final wk = xw[x * 4 + k];
        if (wk == 0) continue;
        mid[o] += src[s] * wk;
        mid[o + 1] += src[s + 1] * wk;
        mid[o + 2] += src[s + 2] * wk;
        mid[o + 3] += src[s + 3] * wk;
      }
    }
  }
  final out = Uint8List(w2 * h2 * 4);
  for (var y = 0; y < h2; y++) {
    for (var x = 0; x < w2; x++) {
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      var a = 0.0;
      for (var k = 0; k < 4; k++) {
        final wk = yw[y * 4 + k];
        if (wk == 0) continue;
        final s = (yi[y * 4 + k] * w2 + x) * 4;
        r += mid[s] * wk;
        g += mid[s + 1] * wk;
        b += mid[s + 2] * wk;
        a += mid[s + 3] * wk;
      }
      final o = (y * w2 + x) * 4;
      // The cubic overshoots a little at a hard edge: clamped, and the
      // colour never more than the alpha holds.
      final alpha = a.clamp(0.0, 255.0);
      if (alpha < 0.5) continue;
      final f = 255 / alpha;
      out[o] = (r.clamp(0.0, alpha) * f).round().clamp(0, 255);
      out[o + 1] = (g.clamp(0.0, alpha) * f).round().clamp(0, 255);
      out[o + 2] = (b.clamp(0.0, alpha) * f).round().clamp(0, 255);
      out[o + 3] = alpha.round();
    }
  }
  return (w2, h2, out);
}

/// For each of the [to] pixels of a row scaled from [from]: the four
/// source pixels the Catmull-Rom cubic reads (clamped to the row) and
/// their weights, four a pixel.
(Int32List, Float32List) _cubicTaps(int from, int to) {
  final index = Int32List(to * 4);
  final weight = Float32List(to * 4);
  final scale = to / from;
  for (var x = 0; x < to; x++) {
    final at = (x + 0.5) / scale - 0.5;
    final i = at.floor();
    final t = at - i;
    final t2 = t * t;
    final t3 = t2 * t;
    final w = <double>[
      (-t3 + 2 * t2 - t) / 2,
      (3 * t3 - 5 * t2 + 2) / 2,
      (-3 * t3 + 4 * t2 + t) / 2,
      (t3 - t2) / 2,
    ];
    for (var k = 0; k < 4; k++) {
      index[x * 4 + k] = (i - 1 + k).clamp(0, from - 1);
      weight[x * 4 + k] = w[k];
    }
  }
  return (index, weight);
}

/// The image [mosaic] describes, straight RGBA, from its [tiles] decoded
/// (width, height, pixels), in the order of [TileMosaic.tiles]; a `null`
/// tile is transparent. Each pixel takes the tile pixel under its middle.
Uint8List composeTileMosaic(
  TileMosaic mosaic,
  List<(int, int, Uint8List)?> tiles,
) {
  final width = mosaic.width;
  final height = mosaic.height;
  final size = mosaic.tileSize;
  final out = Uint8List(width * height * 4);
  final xScale = (mosaic.right - mosaic.left) / width;
  final yScale = (mosaic.bottom - mosaic.top) / height;
  final maxX = mosaic.columns * size - 1;
  final maxY = mosaic.rows * size - 1;
  final columns = Int32List(width);
  for (var i = 0; i < width; i++) {
    columns[i] = (mosaic.left + (i + 0.5) * xScale).floor().clamp(0, maxX);
  }
  for (var j = 0; j < height; j++) {
    final sy = (mosaic.top + (j + 0.5) * yScale).floor().clamp(0, maxY);
    final row = sy ~/ size;
    final inY = sy - row * size;
    for (var i = 0; i < width; i++) {
      final sx = columns[i];
      final column = sx ~/ size;
      final tile = tiles[row * mosaic.columns + column];
      if (tile == null) continue;
      final (tw, th, pixels) = tile;
      // A tile of another size than said: scaled to it.
      final tx = (sx - column * size) * tw ~/ size;
      final ty = inY * th ~/ size;
      final s = (ty * tw + tx) * 4;
      if (s + 3 >= pixels.length) continue;
      final o = (j * width + i) * 4;
      out[o] = pixels[s];
      out[o + 1] = pixels[s + 1];
      out[o + 2] = pixels[s + 2];
      out[o + 3] = pixels[s + 3];
    }
  }
  return out;
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

/// What tells the cloud images prepared now from those an older app left
/// in the cache: raised with each change to the cloud sources' boxes or to
/// how the images are prepared.
const int cloudImageVersion = 2;

/// What tells the rain images prepared now from those an older app left in
/// the cache, which the age limit then clears: raised with each change to
/// how they are prepared.
const int rainImageVersion = 7;

/// The width and height of [png] from its header; `null` where it is not
/// a PNG.
(int, int)? pngSize(Uint8List png) {
  if (png.length < 24) return null;
  for (var i = 0; i < 8; i++) {
    if (png[i] != _pngSignature[i]) return null;
  }
  final data = ByteData.sublistView(png);
  return (data.getUint32(16), data.getUint32(20));
}

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
  /// cloud on a clear ground as a PNG, faded where [fades] say (into a
  /// neighbouring source's); `null` when it cannot be had.
  Future<Uint8List?> cloudImage(
    WeatherMapSource source,
    int region,
    WeatherFrame frame,
    DateTime now, {
    List<CloudFade> fades = const <CloudFade>[],
  });

  /// The detail cloud image of [box] at [frame] (see `cloudDetailArea`),
  /// processed as [cloudImage]'s; `null` when it cannot be had.
  Future<Uint8List?> cloudDetailImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now, {
    List<CloudFade> fades = const <CloudFade>[],
  });

  /// A rain source's image of [box] at [frame] (see
  /// `WeatherMapSource.softImageUrl`, or put together from its tiles,
  /// `tileMosaicOf`): the soft radar, the satellite or a
  /// model, prepared for [style] with [masks] and [coverages] left out as
  /// [processRainImage] does; `null` when the service does not answer with
  /// an image within [weatherProbeTimeout], which is the source's check.
  /// [maskKey] names the masks and coverages in the cache. Drawn soft, a
  /// source with an extent carries where its frame measures
  /// ([readRainCoverage]).
  Future<Uint8List?> radarImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now, {
    RadarStyle style = RadarStyle.soft,
    List<List<LatLng>> masks = const <List<LatLng>>[],
    List<RainCoverage> coverages = const <RainCoverage>[],
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

  /// The newest frame [source]'s service has, read off its
  /// [WeatherMapSource.timesUrl] ([parseWmsNewestTime]); `null` without
  /// one, or when it cannot be had within [weatherProbeTimeout].
  Future<DateTime?> newestFrame(WeatherMapSource source);

  /// Whether the service refused an image of the source [sourceId] since
  /// this was last asked: answered with an XML error under status 200, as a
  /// WMS does for a moment it has no frame of. Asking clears it.
  bool takeRefusal(String sourceId);
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
    this.cacheBudget = weatherCacheBudget,
    this.decodeTile = _decode,
  });

  /// Decodes a tile of an image put together from tiles into straight
  /// RGBA (the engine's decoder by default).
  final Future<(int, int, Uint8List)> Function(Uint8List png) decodeTile;

  /// How many bytes the cache keeps on disk ([weatherCacheBudget]).
  final int cacheBudget;

  /// What the cache holds, read off the disk once.
  _WeatherCacheIndex? _index;

  /// The index of [dir], scanning it the first time.
  _WeatherCacheIndex _indexOf(Directory dir) {
    final index = _index;
    if (index != null && index.dir.path == dir.path) return index;
    return _index = _WeatherCacheIndex.scan(dir, cacheBudget);
  }

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

  /// Turns a cloud image into the one drawn.
  final Future<Uint8List> Function(Uint8List png, CloudImageJob job) process;

  /// Turns a rain image into the one drawn.
  final Future<Uint8List> Function(Uint8List png, RainImageJob job)
  processRadar;

  /// The requests made, newest last; for tests and the log.
  final List<String> requests = <String>[];

  /// The sources an image of which was refused since [takeRefusal] last
  /// asked.
  final Set<String> _refused = <String>{};

  @override
  bool takeRefusal(String sourceId) => _refused.remove(sourceId);

  @override
  Future<DateTime?> newestFrame(WeatherMapSource source) async {
    final url = source.timesUrl;
    if (url == null) return null;
    requests.add(url);
    try {
      final response = await dio
          .get<String>(
            url,
            options: Options(
              responseType: ResponseType.plain,
              sendTimeout: probeTimeout,
              receiveTimeout: probeTimeout,
            ),
          )
          .timeout(probeTimeout);
      final status = response.statusCode ?? 0;
      final data = response.data;
      if (status < 200 || status >= 300 || data == null) return null;
      // A model named by its run says its newest run; a WMS its frames.
      return source.timeFormat == WeatherTimeFormat.modelRun
          ? parseModelRunTime(data)
          : parseWmsNewestTime(data);
    } on Object {
      return null;
    }
  }

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
    DateTime now, {
    List<CloudFade> fades = const <CloudFade>[],
  }) {
    final prefix = '${source.id}_v${cloudImageVersion}_${region}_';
    final name = '$prefix${cloudImageStamp(frame, now)}${_fadesKey(fades)}.png';
    final job = CloudImageJob(box: source.coverage[region], fades: fades);
    return _cloud(
      source.regionImageUrl(frame, region),
      name,
      source: source.id,
      now,
      process: (png) => process(png, job),
    );
  }

  @override
  Future<Uint8List?> cloudDetailImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now, {
    List<CloudFade> fades = const <CloudFade>[],
  }) {
    final prefix = '${source.id}_v${cloudImageVersion}_detail_';
    final stamp = '_${cloudImageStamp(frame, now)}${_fadesKey(fades)}.png';
    final name = '$prefix${cloudDetailKey(box)}$stamp';
    final job = CloudImageJob(box: box, fades: fades);
    return _cloud(
      source.detailImageUrl(frame, box),
      name,
      source: source.id,
      now,
      process: (png) => process(png, job),
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
    List<RainCoverage> coverages = const <RainCoverage>[],
    String maskKey = '',
  }) async {
    final mosaic = source.imageFromTiles ? tileMosaicOf(source, box) : null;
    final url = mosaic == null
        ? source.softImageUrl(frame, box)
        : source.imageTileUrl(frame, mosaic.zoom, mosaic.x0, mosaic.y0);
    if (url == null) return null;
    final prefix = '${source.id}_${style.name}${rainImageVersion}_';
    final name =
        '$prefix${cloudDetailKey(box)}_${radarImageStamp(source, frame, now)}'
        '$maskKey.png';
    final soft = style == RadarStyle.soft;
    final job = RainImageJob(
      palette: source.palette,
      soft: soft,
      box: box,
      masks: masks,
      coverages: coverages,
      extent: soft ? source.extent : null,
    );
    return _cloud(
      url,
      name,
      source: source.id,
      now,
      timeout: probeTimeout,
      fetch: mosaic == null ? null : () => _mosaicImage(source, frame, mosaic),
      process: (png) => processRadar(png, job),
    );
  }

  /// The image [mosaic] describes of [source] at [frame], put together
  /// from its tiles, all asked for at once, as a PNG; `null` where one of
  /// them cannot be had within [probeTimeout].
  Future<Uint8List?> _mosaicImage(
    WeatherMapSource source,
    WeatherFrame frame,
    TileMosaic mosaic,
  ) async {
    final bodies = await Future.wait(<Future<Uint8List?>>[
      for (final (x, y) in mosaic.tiles)
        _getImage(
          source.imageTileUrl(frame, mosaic.zoom, x, y),
          probeTimeout,
          source: source.id,
        ),
    ]);
    if (bodies.any((body) => body == null)) return null;
    final tiles = <(int, int, Uint8List)?>[];
    for (final body in bodies) {
      try {
        tiles.add(await decodeTile(body!));
      } on Object catch (error) {
        debugPrint('velorki: weather tile not decoded: $error');
        return null;
      }
    }
    return Isolate.run(
      () => encodePngRgba(
        mosaic.width,
        mosaic.height,
        composeTileMosaic(mosaic, tiles),
        // Decoded again at once: speed over size.
        level: 1,
      ),
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
        if (grid != null) {
          _indexOf(dir).used(name);
          return grid;
        }
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
        final file = File(p.join(dir.path, name));
        await file.writeAsString(text);
        _indexOf(dir)
          ..added(file)
          ..prune(name, now);
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

  /// What names [fades] in a cloud image's cache name.
  static String _fadesKey(List<CloudFade> fades) {
    if (fades.isEmpty) return '';
    final keys = [for (final fade in fades) fade.key]..sort();
    return '_${keys.join('-')}';
  }

  /// The image cached as [name], else fetched from [url] within [timeout]
  /// (the cloud images' by default), or by [fetch] where given, turned by
  /// [process] and cached, the cache then kept to its budget at [now]
  /// ([_WeatherCacheIndex.prune]). A refusal is put down to [source].
  Future<Uint8List?> _cloud(
    String url,
    String name,
    DateTime now, {
    required Future<Uint8List> Function(Uint8List png) process,
    required String source,
    Duration? timeout,
    Future<Uint8List?> Function()? fetch,
  }) async {
    final Directory dir;
    try {
      dir = await cacheDir();
      final cached = File(p.join(dir.path, name));
      if (cached.existsSync()) {
        final bytes = await cached.readAsBytes();
        _indexOf(dir).used(name);
        return bytes;
      }
    } on Object catch (error) {
      debugPrint('velorki: cloud cache unreadable: $error');
      return null;
    }
    final body = fetch != null
        ? await fetch()
        : await _getImage(url, timeout ?? imageTimeout, source: source);
    if (body == null) return null;
    final Uint8List png;
    try {
      png = await process(body);
    } on Object catch (error) {
      debugPrint('velorki: cloud image not processed: $error');
      return null;
    }
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(png);
      _indexOf(dir)
        ..added(file)
        ..prune(name, now);
    } on Object catch (error) {
      debugPrint('velorki: cloud image not cached: $error');
    }
    return png;
  }

  /// The body of [url] when it is an image, else `null`; an XML error is
  /// put down as a refusal of [source] ([takeRefusal]).
  Future<Uint8List?> _getImage(
    String url,
    Duration timeout, {
    String? source,
  }) async {
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
      if (status < 200 ||
          status >= 300 ||
          !type.toLowerCase().startsWith('image/')) {
        debugPrint('velorki: weather image not served ($status, $type): $url');
        if (source != null && type.toLowerCase().contains('xml')) {
          _refused.add(source);
        }
        return null;
      }
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } on Object catch (error) {
      debugPrint('velorki: weather image not fetched ($error): $url');
      return null;
    }
  }
}

/// What the weather cache holds, read off its directory once
/// ([_WeatherCacheIndex.scan]) and kept up to date as images and grids are
/// read and written, so that keeping the cache tidy needs no scan of the
/// directory: the files in the order they were last used, and their sizes
/// and ages. Only the cache's own files count (`.png` images, `.txt` wind
/// grids). The order outlives the app in each file's access time.
class _WeatherCacheIndex {
  _WeatherCacheIndex._(this.dir, this.budget);

  /// The index of the files in [dir], kept to [budget] bytes and pruned
  /// once; the order of use is each file's access time, or its
  /// modification time where that is later.
  factory _WeatherCacheIndex.scan(Directory dir, int budget) {
    final index = _WeatherCacheIndex._(dir, budget);
    final found = <(String, _CacheEntry, DateTime)>[];
    try {
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          if (!_counts(name)) continue;
          final stat = entity.statSync();
          if (stat.type != FileSystemEntityType.file) continue;
          final used = stat.accessed.isAfter(stat.modified)
              ? stat.accessed
              : stat.modified;
          found.add((name, _CacheEntry(stat.size, stat.modified), used));
        }
      }
    } on FileSystemException catch (error) {
      debugPrint('velorki: weather cache not read: $error');
    }
    found.sort((a, b) => a.$3.compareTo(b.$3));
    for (final (name, entry, _) in found) {
      index._entries[name] = entry;
      index._bytes += entry.size;
    }
    return index..prune('', DateTime.now());
  }

  /// The cache's directory.
  final Directory dir;

  /// How many bytes it keeps.
  final int budget;

  /// The files, used longest ago first.
  final Map<String, _CacheEntry> _entries = <String, _CacheEntry>{};

  int _bytes = 0;

  static final RegExp _cloudName = RegExp(r'^\w+?_v(\d+)_');
  static final RegExp _rainName = RegExp(r'^\w+?_(?:soft|measured)(\d+)_');

  /// Whether [name] is an image prepared otherwise than now: a cloud image
  /// of another [cloudImageVersion], a rain image of another
  /// [rainImageVersion].
  static bool _stale(String name) {
    if (!name.endsWith('.png')) return false;
    final cloud = _cloudName.firstMatch(name);
    if (cloud != null) return int.parse(cloud[1]!) != cloudImageVersion;
    final rain = _rainName.firstMatch(name);
    if (rain != null) return int.parse(rain[1]!) != rainImageVersion;
    return false;
  }

  static bool _counts(String name) =>
      name.endsWith('.png') || name.endsWith('.txt');

  /// The file [name] was just read: it is the last to go.
  void used(String name) {
    final entry = _entries.remove(name);
    if (entry == null) return;
    _entries[name] = entry;
    try {
      File(p.join(dir.path, name)).setLastAccessedSync(DateTime.now());
    } on FileSystemException {
      // The order holds for this launch anyway.
    }
  }

  /// [file] was just written.
  void added(File file) {
    final name = p.basename(file.path);
    if (!_counts(name)) return;
    final stat = file.statSync();
    final old = _entries.remove(name);
    if (old != null) _bytes -= old.size;
    _entries[name] = _CacheEntry(stat.size, stat.modified);
    _bytes += stat.size;
  }

  /// Deletes the images an older app prepared ([_stale]) and any file past
  /// [cloudCacheMaxAge] at [now], then, while the cache is over its budget,
  /// the file used longest ago; never [current]. Other moments of an image
  /// stay, for the time control's slider dragged back.
  void prune(String current, DateTime now) {
    for (final name in _entries.keys.toList()) {
      if (name == current) continue;
      final entry = _entries[name]!;
      if (_stale(name) || now.difference(entry.modified) > cloudCacheMaxAge) {
        _delete(name);
      }
    }
    while (_bytes > budget) {
      final oldest = _entries.keys.firstWhere(
        (name) => name != current,
        orElse: () => current,
      );
      if (oldest == current) return;
      _delete(oldest);
    }
  }

  void _delete(String name) {
    final entry = _entries.remove(name);
    if (entry != null) _bytes -= entry.size;
    try {
      File(p.join(dir.path, name)).deleteSync();
    } on FileSystemException {
      // Gone already, or busy: the next launch's scan finds it again.
    }
  }
}

/// A file of the weather cache: its size and when it was written.
@immutable
class _CacheEntry {
  const _CacheEntry(this.size, this.modified);

  final int size;
  final DateTime modified;
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
