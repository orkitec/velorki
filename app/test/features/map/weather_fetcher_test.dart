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
      Uint8List.fromList(<int>[1, 2, 3]),
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
}
