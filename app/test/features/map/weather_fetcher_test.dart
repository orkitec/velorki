import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/weather_fetcher.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Answers every request with [body] under [contentType] and [status], or
/// never, when [hang] is set.
class _Adapter implements HttpClientAdapter {
  int status = 200;
  String contentType = 'image/png';
  bool hang = false;
  Uint8List body = Uint8List.fromList(<int>[1, 2, 3]);
  final List<Uri> requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    if (hang) await Completer<void>().future;
    return ResponseBody.fromBytes(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Uint8List _pixel(int r, int g, int b, int a) =>
    Uint8List.fromList(<int>[r, g, b, a]);

void main() {
  group('whitenCloudPixels', () {
    test('dark ground is clear, the coldest cloud at the most alpha', () {
      final dark = whitenCloudPixels(_pixel(60, 60, 60, 255));
      expect(dark, <int>[255, 255, 255, 0]);
      final bright = whitenCloudPixels(_pixel(240, 240, 240, 255));
      expect(bright, <int>[255, 255, 255, (cloudMaxAlpha * 255).round()]);
    });

    test('between the two, linear in luminance', () {
      const mid = (cloudLuminanceLow + cloudLuminanceHigh) / 2;
      final v = mid.round();
      final out = whitenCloudPixels(_pixel(v, v, v, 255));
      expect(out[3], closeTo(cloudMaxAlpha * 255 / 2, 1.5));
      final atLow = whitenCloudPixels(
        _pixel(
          cloudLuminanceLow.round(),
          cloudLuminanceLow.round(),
          cloudLuminanceLow.round(),
          255,
        ),
      );
      expect(atLow[3], 0);
    });

    test('a transparent pixel stays transparent', () {
      expect(whitenCloudPixels(_pixel(250, 250, 250, 0))[3], 0);
    });

    test('an enhancement colour is the coldest cloud', () {
      // GOES paints the coldest tops green to red.
      final green = whitenCloudPixels(_pixel(40, 200, 40, 255));
      expect(green[3], (cloudMaxAlpha * 255).round());
    });
  });

  test('the PNG has its signature and size', () {
    final png = encodePngRgba(3, 2, Uint8List(3 * 2 * 4));
    expect(png.sublist(0, 8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    final header = ByteData.sublistView(png, 16, 24);
    expect(header.getUint32(0), 3);
    expect(header.getUint32(4), 2);
    expect(
      String.fromCharCodes(png.sublist(png.length - 8, png.length - 4)),
      'IEND',
    );
  });

  group('mapCanDecode', () {
    test('a PNG with alpha or a palette, not RGB with a colour key', () {
      expect(mapCanDecode(encodePngRgba(1, 1, Uint8List(4))), isTrue);
      Uint8List withColourType(int type) =>
          Uint8List.fromList(encodePngRgba(1, 1, Uint8List(4)))..[25] = type;
      expect(mapCanDecode(withColourType(3)), isTrue);
      expect(mapCanDecode(withColourType(2)), isFalse);
      expect(mapCanDecode(withColourType(0)), isFalse);
      // Not a PNG: left to the map.
      expect(mapCanDecode(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF])), isTrue);
    });
  });

  group('probe', () {
    late _Adapter adapter;
    late HttpWeatherFetcher fetcher;

    setUp(() {
      adapter = _Adapter();
      fetcher = HttpWeatherFetcher(
        dio: Dio()..httpClientAdapter = adapter,
        cacheDir: () async => Directory.systemTemp,
        probeTimeout: const Duration(milliseconds: 200),
      );
    });

    test('an image answers', () async {
      expect(await fetcher.probe('https://radar.example/1'), isTrue);
    });

    test('an XML error under 200 is a failure', () async {
      adapter.contentType = 'text/xml; charset=UTF-8';
      expect(await fetcher.probe('https://radar.example/1'), isFalse);
    });

    test('a server error is a failure', () async {
      adapter.status = 503;
      expect(await fetcher.probe('https://radar.example/1'), isFalse);
    });

    test('a timeout is a failure', () async {
      adapter.hang = true;
      expect(await fetcher.probe('https://radar.example/1'), isFalse);
    });
  });

  group('cloud images', () {
    late _Adapter adapter;
    late Directory dir;
    late HttpWeatherFetcher fetcher;
    var processed = 0;

    setUp(() {
      adapter = _Adapter();
      dir = Directory.systemTemp.createTempSync('clouds');
      addTearDown(() => dir.deleteSync(recursive: true));
      processed = 0;
      fetcher = HttpWeatherFetcher(
        dio: Dio()..httpClientAdapter = adapter,
        cacheDir: () async => dir,
        process: (png) async {
          processed++;
          return Uint8List.fromList(<int>[9, ...png]);
        },
      );
    });

    test('the EUMETSAT image asks for a full hour, then comes from the '
        'cache', () async {
      final now = DateTime.utc(2026, 10, 10, 14, 25);
      final frame = eumetsatClouds.frameAt(now)!;
      final first = await fetcher.cloudImage(eumetsatClouds, 0, frame, now);
      expect(first, <int>[9, 1, 2, 3]);
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.single.queryParameters['time'],
        '2026-10-10T14:00:00.000Z',
      );
      final again = await fetcher.cloudImage(
        eumetsatClouds,
        0,
        frame,
        now.add(const Duration(minutes: 30)),
      );
      expect(again, first);
      expect(adapter.requests, hasLength(1));
      expect(processed, 1);
    });

    test('the next hour replaces the last one in the cache', () async {
      final now = DateTime.utc(2026, 10, 10, 14, 25);
      await fetcher.cloudImage(
        eumetsatClouds,
        0,
        eumetsatClouds.frameAt(now)!,
        now,
      );
      final later = now.add(const Duration(hours: 1));
      await fetcher.cloudImage(
        eumetsatClouds,
        0,
        eumetsatClouds.frameAt(later)!,
        later,
      );
      expect(adapter.requests, hasLength(2));
      expect(dir.listSync(), hasLength(1));
    });

    test('a failed image is null and not cached', () async {
      adapter.contentType = 'application/vnd.ogc.se_xml';
      final now = DateTime.utc(2026, 10, 10, 14, 25);
      expect(
        await fetcher.cloudImage(
          goesEastClouds,
          0,
          goesEastClouds.frameAt(now)!,
          now,
        ),
        isNull,
      );
      expect(dir.listSync(), isEmpty);
    });

    test('a detail image asks for the box at its native size, a full hour, '
        'then comes from the cache', () async {
      final now = DateTime.utc(2026, 10, 10, 14, 25);
      final frame = eumetsatClouds.frameAt(now)!;
      final box = eumetsatClouds.detailBox(
        cloudDetailArea(
          const BoundingBox(south: 52.3, west: 13.2, north: 52.7, east: 13.6),
          8,
        )!,
      )!;
      final first = await fetcher.cloudDetailImage(
        eumetsatClouds,
        box,
        frame,
        now,
      );
      expect(first, <int>[9, 1, 2, 3]);
      final query = adapter.requests.single.queryParameters;
      expect(query['time'], '2026-10-10T14:00:00.000Z');
      final (w, h) = cloudDetailImageSize(eumetsatClouds, box);
      expect(query['width'], '$w');
      expect(query['height'], '$h');
      expect(query['bbox'], mercatorBboxString(box));
      await fetcher.cloudDetailImage(eumetsatClouds, box, frame, now);
      expect(adapter.requests, hasLength(1));
      expect(processed, 1);
      // The region's own image is a cache entry of its own.
      await fetcher.cloudImage(eumetsatClouds, 0, frame, now);
      expect(adapter.requests, hasLength(2));
      expect(dir.listSync(), hasLength(2));
    });

    test('the cache keeps the last few detail boxes of the hour; the next '
        'hour replaces them', () async {
      final now = DateTime.utc(2026, 10, 10, 14, 25);
      final frame = eumetsatClouds.frameAt(now)!;
      for (var i = 0; i < cloudDetailCacheKeep + 3; i++) {
        final box = BoundingBox(
          south: 50,
          west: 1.0 + i,
          north: 51,
          east: 1.5 + i,
        );
        await fetcher.cloudDetailImage(eumetsatClouds, box, frame, now);
      }
      expect(dir.listSync(), hasLength(cloudDetailCacheKeep));
      final later = now.add(const Duration(hours: 1));
      await fetcher.cloudDetailImage(
        eumetsatClouds,
        const BoundingBox(south: 50, west: 1, north: 51, east: 1.5),
        eumetsatClouds.frameAt(later)!,
        later,
      );
      expect(dir.listSync(), hasLength(1));
    });

    test('the latest GOES image is kept for one refresh slot', () {
      const latest = WeatherFrame(null);
      final a = cloudImageStamp(latest, DateTime.utc(2026, 10, 10, 14, 21));
      final b = cloudImageStamp(latest, DateTime.utc(2026, 10, 10, 14, 29));
      final c = cloudImageStamp(latest, DateTime.utc(2026, 10, 10, 14, 31));
      expect(a, b);
      expect(c, isNot(a));
    });
  });

  group('softenRadarPixels', () {
    int alphaOf(int r, int g, int b) =>
        softenRadarPixels(1, 1, _pixel(r, g, b, 255))[3];

    int level(double alpha) => (alpha * 255).round();

    test('the alpha follows the palette from cyan to purple', () {
      expect(alphaOf(0, 230, 230), level(radarAlphaCyan)); // cyan
      expect(alphaOf(0, 0, 240), level(radarAlphaCyan)); // blue
      expect(alphaOf(0, 200, 0), level(radarAlphaGreen));
      expect(alphaOf(250, 250, 0), level(radarAlphaYellow));
      expect(alphaOf(255, 128, 0), level(radarAlphaOrange));
      expect(alphaOf(250, 0, 0), level(radarAlphaRed));
      expect(alphaOf(250, 0, 250), level(radarAlphaMagenta));
      expect(alphaOf(150, 80, 200), level(radarAlphaMagenta)); // purple
      // Between two colours, between their alphas.
      final lime = alphaOf(160, 255, 0); // hue 82
      expect(lime, greaterThan(level(radarAlphaGreen)));
      expect(lime, lessThan(level(radarAlphaYellow)));
    });

    test('grey is faint, its colour kept', () {
      expect(softenRadarPixels(1, 1, _pixel(180, 180, 185, 255)), <int>[
        180,
        180,
        185,
        level(radarAlphaGrey),
      ]);
    });

    test('a transparent pixel stays transparent', () {
      expect(softenRadarPixels(1, 1, _pixel(0, 200, 0, 0))[3], 0);
    });

    test('the service\'s own alpha is kept in the product', () {
      expect(
        softenRadarPixels(1, 1, _pixel(250, 0, 0, 128))[3],
        (radarAlphaRed * 128).round(),
      );
    });

    // A 5 × 5 image, transparent but for [pixels] at (x, y).
    Uint8List image(Map<(int, int), List<int>> pixels) {
      final out = Uint8List(5 * 5 * 4);
      for (final MapEntry(key: (x, y), value: rgba) in pixels.entries) {
        out.setAll((y * 5 + x) * 4, rgba);
      }
      return out;
    }

    int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 5 + x) * 4 + 3];

    test('edges soften: the alpha alone, averaged over its 3 × 3 box', () {
      // A green pixel beside a yellow one, the rest dry.
      final input = image({
        (2, 2): <int>[0, 200, 0, 255],
        (3, 2): <int>[250, 250, 0, 255],
      });
      final out = softenRadarPixels(5, 5, input);
      expect(
        alphaAt(out, 2, 2),
        ((radarAlphaGreen + radarAlphaYellow) / 9 * 255).round(),
      );
      // The colour is untouched, and dry pixels stay dry.
      expect(out.sublist((2 * 5 + 2) * 4, (2 * 5 + 2) * 4 + 3), <int>[
        0,
        200,
        0,
      ]);
      expect(alphaAt(out, 1, 2), 0);
    });

    test('inside a field of rain the alpha stays', () {
      final input = Uint8List(5 * 5 * 4);
      for (var i = 0; i < 25; i++) {
        input.setAll(i * 4, <int>[0, 200, 0, 255]);
      }
      final out = softenRadarPixels(5, 5, input);
      expect(alphaAt(out, 2, 2), level(radarAlphaGreen));
      // At the image's border too: beyond it counts as the border.
      expect(alphaAt(out, 0, 0), level(radarAlphaGreen));
    });

    test('a small heavy cell keeps its strength', () {
      final input = image({
        (2, 2): <int>[250, 0, 0, 255],
      });
      expect(
        alphaAt(softenRadarPixels(5, 5, input), 2, 2),
        level(radarAlphaRed),
      );
      final hail = image({
        (2, 2): <int>[250, 0, 250, 255],
        (2, 3): <int>[0, 200, 0, 255],
      });
      expect(
        alphaAt(softenRadarPixels(5, 5, hail), 2, 2),
        level(radarAlphaMagenta),
      );
    });

    test('light rain beside heavy is lifted, never the other way', () {
      final input = image({
        (2, 2): <int>[0, 230, 230, 255],
        (1, 2): <int>[250, 0, 0, 255],
        (3, 2): <int>[250, 0, 0, 255],
        (2, 1): <int>[250, 0, 0, 255],
      });
      final out = softenRadarPixels(5, 5, input);
      expect(alphaAt(out, 1, 2), level(radarAlphaRed));
      expect(
        alphaAt(out, 2, 2),
        ((radarAlphaCyan + 3 * radarAlphaRed) / 9 * 255).round(),
      );
    });
  });

  group('soft radar images', () {
    late _Adapter adapter;
    late Directory dir;
    late HttpWeatherFetcher fetcher;
    var processed = 0;
    final box = dwdRadar.softBox(
      cloudDetailArea(
        const BoundingBox(south: 52.3, west: 13.2, north: 52.7, east: 13.6),
        8,
      )!,
    )!;

    setUp(() {
      adapter = _Adapter();
      dir = Directory.systemTemp.createTempSync('radar');
      addTearDown(() => dir.deleteSync(recursive: true));
      processed = 0;
      fetcher = HttpWeatherFetcher(
        dio: Dio()..httpClientAdapter = adapter,
        cacheDir: () async => dir,
        probeTimeout: const Duration(milliseconds: 200),
        process: (png) async => throw StateError('not the clouds'),
        processRadar: (png) async {
          processed++;
          return Uint8List.fromList(<int>[8, ...png]);
        },
      );
    });

    test('asks for the box at its size and moment, softens it, then comes '
        'from the cache', () async {
      final now = DateTime.utc(2026, 10, 10, 14, 42);
      final frame = dwdRadar.frameAt(now)!;
      final first = await fetcher.radarImage(dwdRadar, box, frame, now);
      expect(first, <int>[8, 1, 2, 3]);
      final query = adapter.requests.single.queryParameters;
      final (w, h) = radarSoftImageSize(dwdRadar, box);
      expect(query['bbox'], mercatorBboxString(box));
      expect(query['width'], '$w');
      expect(query['height'], '$h');
      expect(query['time'], '2026-10-10T14:35:00.000Z');
      expect(await fetcher.radarImage(dwdRadar, box, frame, now), first);
      expect(adapter.requests, hasLength(1));
      expect(processed, 1);
      // Another moment is an image of its own.
      await fetcher.radarImage(
        dwdRadar,
        box,
        dwdRadar.frameAt(now, offsetMinutes: -15)!,
        now,
      );
      expect(adapter.requests, hasLength(2));
      expect(dir.listSync(), hasLength(2));
    });

    test('not an image, or too slow: null and not cached', () async {
      final now = DateTime.utc(2026, 10, 10, 14, 42);
      final frame = dwdRadar.frameAt(now)!;
      adapter.contentType = 'application/vnd.ogc.se_xml';
      expect(await fetcher.radarImage(dwdRadar, box, frame, now), isNull);
      adapter
        ..contentType = 'image/png'
        ..status = 503;
      expect(await fetcher.radarImage(dwdRadar, box, frame, now), isNull);
      adapter
        ..status = 200
        ..hang = true;
      expect(await fetcher.radarImage(dwdRadar, box, frame, now), isNull);
      expect(dir.listSync(), isEmpty);
      expect(processed, 0);
    });

    test('the cache keeps the last few images of a source', () async {
      final now = DateTime.utc(2026, 10, 10, 14, 42);
      final frame = dwdRadar.frameAt(now)!;
      for (var i = 0; i < radarImageCacheKeep + 3; i++) {
        await fetcher.radarImage(
          dwdRadar,
          BoundingBox(
            south: 50,
            west: 2.0 + i / 2,
            north: 51,
            east: 2.4 + i / 2,
          ),
          frame,
          now,
        );
      }
      expect(dir.listSync(), hasLength(radarImageCacheKeep));
    });
  });

  test('an RGB PNG with a colour key fails the probe', () async {
    final adapter = _Adapter()
      ..body = (Uint8List.fromList(encodePngRgba(1, 1, Uint8List(4)))
        ..[25] = 2);
    final fetcher = HttpWeatherFetcher(
      dio: Dio()..httpClientAdapter = adapter,
      cacheDir: () async => Directory.systemTemp,
    );
    expect(await fetcher.probe('https://radar.example/1'), isFalse);
    adapter.body = encodePngRgba(1, 1, Uint8List(4));
    expect(await fetcher.probe('https://radar.example/1'), isTrue);
  });
}
