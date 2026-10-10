import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../domain/weather_map.dart';

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

// The infrared images are bright where it is cold: high cloud tops are
// white, the warm ground dark grey. A pixel's luminance between these two
// is read as cloud, linearly, up to [cloudMaxAlpha]: darker is clear sky,
// brighter is as cloudy as it gets. Low fog and stratus are almost as warm
// as the ground under them, so they come out faint or not at all.
/// Luminance (0..255) at and below which a pixel is clear.
const double cloudLuminanceLow = 110;

/// Luminance at and above which a pixel is full cloud.
const double cloudLuminanceHigh = 220;

/// How opaque the thickest cloud is drawn, 0..1.
const double cloudMaxAlpha = 0.85;

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
  if (data == null) throw StateError('cloud image not decoded');
  final pixels = data.buffer.asUint8List();
  return Isolate.run(
    () => encodePngRgba(width, height, whitenCloudPixels(pixels)),
  );
}

/// What the weather layers ask of the network: whether a radar tile
/// answers, and the cloud image of a region.
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
}

/// [WeatherFetcher] over HTTP, cloud images cached in [cacheDir].
class HttpWeatherFetcher implements WeatherFetcher {
  /// A fetcher on [dio]; [process] turns the service's image into the one
  /// drawn (the engine's decoder by default).
  HttpWeatherFetcher({
    required this.dio,
    required this.cacheDir,
    this.process = processCloudImage,
    this.probeTimeout = weatherProbeTimeout,
    this.imageTimeout = cloudImageTimeout,
  });

  /// How long a probe may take.
  final Duration probeTimeout;

  /// How long a cloud image may take.
  final Duration imageTimeout;

  final Dio dio;

  /// Where processed cloud images are kept; created as needed.
  final Future<Directory> Function() cacheDir;

  final Future<Uint8List> Function(Uint8List png) process;

  /// The requests made, newest last; for tests and the log.
  final List<String> requests = <String>[];

  @override
  Future<bool> probe(String url) async =>
      await _getImage(url, probeTimeout) != null;

  @override
  Future<Uint8List?> cloudImage(
    WeatherMapSource source,
    int region,
    WeatherFrame frame,
    DateTime now,
  ) async {
    final stamp = cloudImageStamp(frame, now);
    final prefix = '${source.id}_${region}_';
    final Directory dir;
    try {
      dir = await cacheDir();
      final cached = File(p.join(dir.path, '$prefix$stamp.png'));
      if (cached.existsSync()) return await cached.readAsBytes();
    } on Object catch (error) {
      debugPrint('velorki: cloud cache unreadable: $error');
      return null;
    }
    final body = await _getImage(
      source.regionImageUrl(frame, region),
      imageTimeout,
    );
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
      await File(p.join(dir.path, '$prefix$stamp.png')).writeAsBytes(png);
      _prune(dir, prefix, '$prefix$stamp.png', now);
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

  /// Deletes the region's other images, and any image past
  /// [cloudCacheMaxAge].
  static void _prune(Directory dir, String prefix, String keep, DateTime now) {
    for (final entry in dir.listSync()) {
      if (entry is! File) continue;
      final name = p.basename(entry.path);
      if (name == keep || !name.endsWith('.png')) continue;
      try {
        if (name.startsWith(prefix) ||
            now.difference(entry.lastModifiedSync()) > cloudCacheMaxAge) {
          entry.deleteSync();
        }
      } on FileSystemException {
        // Gone already, or busy: the next prune tries again.
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
