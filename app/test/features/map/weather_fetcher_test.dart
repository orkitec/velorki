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

    test('the DWD\'s see-through grey beyond its radars goes', () {
      // As its composite draws it, from a real image.
      expect(softenRadarPixels(1, 1, _pixel(126, 126, 126, 77))[3], 0);
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
    final jobs = <RainImageJob>[];
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
      jobs.clear();
      fetcher = HttpWeatherFetcher(
        dio: Dio()..httpClientAdapter = adapter,
        cacheDir: () async => dir,
        probeTimeout: const Duration(milliseconds: 200),
        process: (png) async => throw StateError('not the clouds'),
        processRadar: (png, job) async {
          processed++;
          jobs.add(job);
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
        dwdRadar.frameAt(now, offsetMinutes: 15)!,
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

    test('the satellite: its own look and masks, each a cache entry of its '
        'own', () async {
      final now = DateTime.utc(2026, 10, 10, 14, 42);
      final frame = hsafRain.frameAt(now)!;
      final view = hsafRain.softBox(box)!;
      await fetcher.radarImage(
        hsafRain,
        view,
        frame,
        now,
        masks: dwdRadar.reachRings,
        maskKey: '-radar_dwd',
      );
      final uri = adapter.requests.single;
      expect(uri.host, 'view.eumetsat.int');
      expect(uri.queryParameters['layers'], 'mtg_fd:h40b');
      expect(uri.queryParameters['time'], '2026-10-10T14:10:00.000Z');
      final job = jobs.single;
      expect(job.palette, RainPalette.hsaf);
      expect(job.soft, isTrue);
      expect(job.box, view);
      expect(job.masks, dwdRadar.reachRings);
      // As measured, or unmasked: another image.
      await fetcher.radarImage(
        hsafRain,
        view,
        frame,
        now,
        style: RadarStyle.measured,
        masks: dwdRadar.reachRings,
        maskKey: '-radar_dwd',
      );
      await fetcher.radarImage(hsafRain, view, frame, now);
      expect(adapter.requests, hasLength(3));
      expect(jobs[1].soft, isFalse);
      expect(jobs[2].masks, isEmpty);
      // The satellite measures: not drawn lighter.
      expect(jobs.any((job) => job.forecast), isFalse);
    });

    test('a model\'s image is a forecast, a radar\'s is not', () async {
      final now = DateTime.utc(2026, 10, 10, 14, 42);
      for (final source in <WeatherMapSource>[iconEuRain, iconGlobalRain]) {
        await fetcher.radarImage(
          source,
          source.softBox(box)!,
          source.frameAt(now, offsetMinutes: 60)!,
          now,
        );
      }
      await fetcher.radarImage(dwdRadar, box, dwdRadar.frameAt(now)!, now);
      expect(jobs.map((job) => job.forecast), <bool>[true, true, false]);
    });
  });

  group('rain palettes', () {
    int level(double alpha) => (alpha * 255).round();

    test('H SAF: light green the faintest, as the radar\'s lightest; the '
        'purples the strongest; the colours kept', () {
      // Each class's colour as the service draws it.
      List<int> soft(int r, int g, int b) =>
          softenRainPixels(1, 1, _pixel(r, g, b, 255), RainPalette.hsaf);
      expect(soft(204, 255, 204), <int>[204, 255, 204, level(radarAlphaCyan)]);
      expect(soft(153, 230, 153)[3], level(0.68));
      expect(soft(51, 179, 51)[3], level(0.82));
      expect(soft(51, 102, 255)[3], level(radarAlphaRed));
      expect(soft(153, 51, 204)[3], level(radarAlphaMagenta));
      expect(soft(127, 0, 127)[3], level(radarAlphaMagenta));
      // An edge pixel between two classes reads as the nearer.
      expect(soft(199, 246, 199)[3], level(radarAlphaCyan));
      // Every class at least as faint as the radar's lightest, at most its
      // heaviest, and rising.
      var last = 0.0;
      for (final (_, (_, _, _, alpha)) in hsafClasses) {
        expect(alpha, inInclusiveRange(radarAlphaCyan, radarAlphaMagenta));
        expect(alpha, greaterThanOrEqualTo(last));
        last = alpha;
      }
    });

    test('the global model: recoloured into the radar\'s palette at the mean '
        'rate an hour, its no-rain veil gone', () {
      List<int> soft(int r, int g, int b, [int a = 255]) =>
          softenRainPixels(1, 1, _pixel(r, g, b, a), RainPalette.dwdModel6h);
      // The veil over dry ground, as the service draws it.
      expect(soft(0, 0, 0, 20)[3], 0);
      // 0.1–0.5 mm in six hours: the radar's lightest cyan.
      expect(soft(220, 247, 195), <int>[51, 255, 255, level(radarAlphaCyan)]);
      // 2–5 mm: under a millimetre an hour, the radar's dark green.
      expect(soft(0, 191, 1).sublist(0, 3), <int>[1, 153, 52]);
      // 40–50 mm: 7.5–10 mm an hour, orange-yellow.
      expect(soft(204, 0, 0).sublist(0, 3), <int>[255, 196, 1]);
      // 200–300 mm: red, at the radar's red.
      expect(soft(142, 102, 255), <int>[254, 0, 0, level(radarAlphaRed)]);
      // As measured: the colours as they are, only the veil away.
      expect(
        measuredRainPixels(_pixel(0, 0, 0, 20), RainPalette.dwdModel6h)[3],
        0,
      );
      expect(
        measuredRainPixels(_pixel(0, 191, 1, 255), RainPalette.dwdModel6h),
        <int>[0, 191, 1, 255],
      );
    });

    test('ICON-EU in the radar\'s style reads as the radar', () {
      // The DWD radar style's colours, from a real ICON-EU image.
      expect(
        softenRainPixels(1, 1, _pixel(51, 255, 255, 255), RainPalette.radarHue),
        softenRadarPixels(1, 1, _pixel(51, 255, 255, 255)),
      );
      expect(
        softenRainPixels(1, 1, _pixel(254, 0, 0, 255), RainPalette.radarHue)[3],
        level(radarAlphaRed),
      );
    });

    test('the job does nothing to an image that needs nothing', () {
      const box = BoundingBox(south: 0, west: 0, north: 1, east: 1);
      expect(
        const RainImageJob(
          palette: RainPalette.hsaf,
          soft: false,
          box: box,
        ).needed,
        isFalse,
      );
      expect(
        const RainImageJob(
          palette: RainPalette.dwdModel6h,
          soft: false,
          box: box,
        ).needed,
        isTrue,
      );
      expect(
        const RainImageJob(
          palette: RainPalette.hsaf,
          soft: false,
          box: box,
          masks: <List<LatLng>>[
            <LatLng>[LatLng(0, 0), LatLng(1, 0), LatLng(1, 1)],
          ],
        ).needed,
        isTrue,
      );
    });
  });

  group('forecast alpha', () {
    const box = BoundingBox(south: 0, west: 0, north: 1, east: 1);
    final cases = <(RainPalette, Uint8List)>[
      (RainPalette.radarHue, _pixel(0, 200, 0, 255)),
      (RainPalette.dwdModel6h, _pixel(0, 0, 255, 255)),
    ];

    for (final soft in <bool>[true, false]) {
      test('a model\'s pixels keep $forecastAlphaScale of their alpha '
          '(soft: $soft), a measurement\'s all', () {
        for (final (palette, pixel) in cases) {
          final measured = prepareRainPixels(
            1,
            1,
            pixel,
            RainImageJob(palette: palette, soft: soft, box: box),
          );
          final forecast = prepareRainPixels(
            1,
            1,
            pixel,
            RainImageJob(
              palette: palette,
              soft: soft,
              box: box,
              forecast: true,
            ),
          );
          expect(measured[3], greaterThan(0), reason: '$palette');
          expect(
            forecast[3],
            (measured[3] * forecastAlphaScale).round(),
            reason: '$palette',
          );
          expect(forecast.sublist(0, 3), measured.sublist(0, 3));
        }
      });
    }

    test('a forecast job is always needed', () {
      expect(
        const RainImageJob(
          palette: RainPalette.radarHue,
          soft: false,
          box: box,
          forecast: true,
        ).needed,
        isTrue,
      );
    });
  });

  group('masks', () {
    // A 10 × 10 image of a box 10° wide at the equator, all rain.
    const box = BoundingBox(south: -5, west: 0, north: 5, east: 10);
    Uint8List rain() {
      final out = Uint8List(10 * 10 * 4);
      for (var i = 0; i < 100; i++) {
        out.setAll(i * 4, <int>[0, 200, 0, 255]);
      }
      return out;
    }

    int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 10 + x) * 4 + 3];

    test('pixels inside a ring go, the rest stay', () {
      final rgba = rain();
      // The box's western half, a little more.
      maskRainPixels(10, 10, rgba, box, <List<LatLng>>[
        <LatLng>[
          LatLng(-6, -1),
          LatLng(-6, 5.2),
          LatLng(6, 5.2),
          LatLng(6, -1),
        ],
      ]);
      for (var y = 0; y < 10; y++) {
        for (var x = 0; x < 10; x++) {
          expect(alphaAt(rgba, x, y), x < 5 ? 0 : 255, reason: '($x, $y)');
        }
      }
    });

    test('a ring beside the image takes nothing, a triangle its part', () {
      final rgba = rain();
      maskRainPixels(10, 10, rgba, box, <List<LatLng>>[
        <LatLng>[LatLng(10, 20), LatLng(11, 20), LatLng(11, 21)],
      ]);
      for (var i = 3; i < rgba.length; i += 4) {
        expect(rgba[i], 255);
      }
      // A triangle on the box's southern edge: wide at the bottom, a point
      // at the top.
      maskRainPixels(10, 10, rgba, box, <List<LatLng>>[
        <LatLng>[LatLng(-6, 0), LatLng(-6, 10), LatLng(5, 5)],
      ]);
      expect(alphaAt(rgba, 5, 9), 0);
      expect(alphaAt(rgba, 0, 9), 255);
      expect(alphaAt(rgba, 5, 1), 0);
      expect(alphaAt(rgba, 2, 1), 255);
    });

    test('prepared as measured and masked, the colours stay', () {
      final out = prepareRainPixels(
        10,
        10,
        rain(),
        RainImageJob(
          palette: RainPalette.hsaf,
          soft: false,
          box: box,
          masks: <List<LatLng>>[
            <LatLng>[
              LatLng(-6, -1),
              LatLng(-6, 2.5),
              LatLng(6, 2.5),
              LatLng(6, -1),
            ],
          ],
        ),
      );
      expect(alphaAt(out, 0, 0), 0);
      expect(out.sublist((5 * 10 + 5) * 4, (5 * 10 + 5) * 4 + 4), <int>[
        0,
        200,
        0,
        255,
      ]);
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
