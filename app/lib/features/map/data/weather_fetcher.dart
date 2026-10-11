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

/// How far, in pixels, the softening of edges reaches: 1 is a 3 × 3 box.
const int radarBlurRadius = 1;

/// Turns the straight RGBA pixels of a DWD radar image ([width] ×
/// [height]) into the soft radar (see [softenRainPixels]).
Uint8List softenRadarPixels(int width, int height, Uint8List rgba) =>
    softenRainPixels(width, height, rgba, RainPalette.dwd);

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

/// The as-measured look of a rain image of [palette]: the service's
/// colours as they are, only the global model's no-rain veil taken away.
Uint8List measuredRainPixels(Uint8List rgba, RainPalette palette) {
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
/// 1 inside the ring where the pixel is not the [palette]'s "no data", 0
/// elsewhere (see [RainCoverage]). Read from the service's own pixels,
/// before the soft look takes the grey away.
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
  return inside;
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

/// Makes every pixel of [rgba] ([width] × [height], an image of [box] in
/// Web Mercator) transparent where one of [coverages] measures at its
/// middle (nearest pixel of the coverage, by Web Mercator position): the
/// places a source leaves to the frames of those before it.
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
      for (final coverage in coverages) {
        if (coverage.coversMercator(mx, my)) {
          rgba[o] = 0;
          break;
        }
      }
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
    this.forecast = false,
    this.extent,
  });

  final RainPalette palette;
  final bool soft;
  final BoundingBox box;
  final List<List<LatLng>> masks;
  final List<RainCoverage> coverages;

  /// Whether the image is a model's forecast, drawn lighter
  /// ([forecastAlphaScale]).
  final bool forecast;

  /// The source's [WeatherMapSource.extent]: where set, where the frame
  /// measures ([rainCoverageOf]) goes with the image ([readRainCoverage]).
  final List<LatLng>? extent;

  /// Whether the image is to be touched at all: as measured, unmasked, no
  /// forecast and in a palette drawn as it comes, it is drawn as the
  /// service sent it.
  bool get needed =>
      soft ||
      forecast ||
      masks.isNotEmpty ||
      coverages.isNotEmpty ||
      extent != null ||
      palette == RainPalette.dwdModel6h;
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
  cutRainPixels(width, height, out, job.box, job.coverages);
  if (job.forecast) {
    for (var o = 3; o < out.length; o += 4) {
      out[o] = (out[o] * forecastAlphaScale).round();
    }
  }
  return out;
}

/// The PNG chunk a rain image's coverage travels in (see
/// [readRainCoverage]): ancillary, private, safe to copy, so every decoder
/// skips it.
const String rainCoverageChunk = 'vlCv';

/// [rgba] (straight alpha, [width] × [height]) as a PNG: no filtering,
/// zlib-deflated, which is all a decoder needs. [coverage] (one byte a
/// pixel), where given, goes in a [rainCoverageChunk] of its own.
Uint8List encodePngRgba(
  int width,
  int height,
  Uint8List rgba, {
  Uint8List? coverage,
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
    chunk(rainCoverageChunk, ZLibCodec(level: 6).encode(coverage));
  }
  chunk('IDAT', ZLibCodec(level: 6).encode(raw.takeBytes()));
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
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  var at = 8;
  while (at + 12 <= png.length) {
    final length = data.getUint32(at);
    final type = String.fromCharCodes(png, at + 4, at + 8);
    final end = at + 12 + length;
    if (end > png.length) return null;
    if (type == rainCoverageChunk) {
      try {
        final covered = Uint8List.fromList(
          ZLibCodec().decode(Uint8List.sublistView(png, at + 8, end - 4)),
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
  return Isolate.run(() {
    final extent = job.extent;
    return encodePngRgba(
      width,
      height,
      prepareRainPixels(width, height, pixels, job),
      coverage: extent == null
          ? null
          : rainCoverageOf(width, height, pixels, job.palette, job.box, extent),
    );
  });
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

/// What tells the rain images prepared now from those an older app left in
/// the cache, which the age limit then clears: raised with each change to
/// how they are prepared.
const int rainImageVersion = 2;

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
    List<RainCoverage> coverages = const <RainCoverage>[],
    String maskKey = '',
  }) async {
    final url = source.softImageUrl(frame, box);
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
      forecast: source.role == RainRole.model,
      extent: soft ? source.extent : null,
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
