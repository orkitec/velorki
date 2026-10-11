import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:velorki/features/map/data/rain_legend.dart';
import 'package:velorki/features/map/data/weather_fetcher.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/map/domain/wind_field.dart';
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
    final jobs = <CloudImageJob>[];

    setUp(() {
      adapter = _Adapter();
      jobs.clear();
      dir = Directory.systemTemp.createTempSync('clouds');
      addTearDown(() => dir.deleteSync(recursive: true));
      processed = 0;
      fetcher = HttpWeatherFetcher(
        dio: Dio()..httpClientAdapter = adapter,
        cacheDir: () async => dir,
        process: (png, job) async {
          processed++;
          jobs.add(job);
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

    test('the next hour is cached beside the last; dragged back, that one '
        'comes from the disk', () async {
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
      expect(dir.listSync(), hasLength(2));
      await fetcher.cloudImage(
        eumetsatClouds,
        0,
        eumetsatClouds.frameAt(now)!,
        later,
      );
      expect(adapter.requests, hasLength(2));
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

    test('the cache keeps the detail boxes of each hour; dragged back to an '
        'earlier hour, its boxes come from the disk', () async {
      final now = DateTime.utc(2026, 10, 10, 14, 25);
      final frame = eumetsatClouds.frameAt(now)!;
      for (var i = 0; i < 15; i++) {
        final box = BoundingBox(
          south: 50,
          west: 1.0 + i,
          north: 51,
          east: 1.5 + i,
        );
        await fetcher.cloudDetailImage(eumetsatClouds, box, frame, now);
      }
      expect(dir.listSync(), hasLength(15));
      final later = now.add(const Duration(hours: 1));
      await fetcher.cloudDetailImage(
        eumetsatClouds,
        const BoundingBox(south: 50, west: 1, north: 51, east: 1.5),
        eumetsatClouds.frameAt(later)!,
        later,
      );
      expect(dir.listSync(), hasLength(16));
      expect(adapter.requests, hasLength(16));
      await fetcher.cloudDetailImage(
        eumetsatClouds,
        const BoundingBox(south: 50, west: 1, north: 51, east: 1.5),
        frame,
        later,
      );
      expect(adapter.requests, hasLength(16));
    });

    test('images an older app prepared go; this version\'s stay', () async {
      final young = DateTime.now().subtract(const Duration(minutes: 10));
      final names = <String>[
        'clouds_eumetsat_v${cloudImageVersion - 1}_0_1.png',
        'clouds_eumetsat_v${cloudImageVersion - 1}_detail_1_2_3_4_5.png',
        'radar_dwd_soft${rainImageVersion - 1}_1_2_3_4_5.png',
        'clouds_goes_east_v${cloudImageVersion}_0_1.png',
        'radar_dwd_measured${rainImageVersion}_1_2_3_4_5.png',
        'wind_icon_1_2_3_4_5.txt',
      ];
      for (final name in names) {
        File(p.join(dir.path, name))
          ..writeAsBytesSync(<int>[1])
          ..setLastModifiedSync(young);
      }
      final now = DateTime.now().toUtc();
      await fetcher.cloudImage(
        eumetsatClouds,
        0,
        eumetsatClouds.frameAt(now)!,
        now,
      );
      final left = {for (final f in dir.listSync()) p.basename(f.path)};
      expect(left, containsAll(names.skip(3)));
      expect(left.intersection(names.take(3).toSet()), isEmpty);
    });

    test('a region\'s image is prepared over its box, faded as asked, and '
        'its fades name it in the cache', () async {
      final now = DateTime.utc(2026, 10, 10, 14, 25);
      final frame = eumetsatClouds.frameAt(now)!;
      final fades = cloudFadesOf(eumetsatClouds, defaultWeatherMapSources);
      await fetcher.cloudImage(eumetsatClouds, 1, frame, now, fades: fades);
      expect(jobs.single.box, eumetsatClouds.coverage[1]);
      expect(jobs.single.fades, fades);
      // Without the fades (GOES switched off) it is another image.
      await fetcher.cloudImage(eumetsatClouds, 1, frame, now);
      expect(adapter.requests, hasLength(2));
      expect(jobs.last.fades, isEmpty);
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

  group('the clouds\' seams', () {
    test('every cloud source reaches 70° south to 70° north', () {
      for (final source in <WeatherMapSource>[
        eumetsatClouds,
        goesEastClouds,
        goesWestClouds,
      ]) {
        expect(
          source.coverage.map((b) => b.south).reduce(math.min),
          -cloudMaxLat,
          reason: source.id,
        );
        expect(
          source.coverage.map((b) => b.north).reduce(math.max),
          cloudMaxLat,
          reason: source.id,
        );
        for (final box in source.coverage) {
          expect(safeImageBox(box), isTrue, reason: '${source.id} $box');
        }
      }
      expect(cloudMaxLat, 70);
    });

    test('neighbours overlap by a band ten degrees wide, over which one '
        'fades into the other, the two adding up to one', () {
      final eumetsat = cloudFadesOf(eumetsatClouds, defaultWeatherMapSources);
      final east = cloudFadesOf(goesEastClouds, defaultWeatherMapSources);
      final west = cloudFadesOf(goesWestClouds, defaultWeatherMapSources);
      expect(eumetsat, [const CloudFade(west: -30, east: -20, rising: true)]);
      expect(
        east,
        unorderedEquals(<CloudFade>[
          const CloudFade(west: -30, east: -20, rising: false),
          const CloudFade(west: -120, east: -110, rising: true),
        ]),
      );
      expect(west, [const CloudFade(west: -120, east: -110, rising: false)]);
      for (final fade in [...eumetsat, ...east, ...west]) {
        expect(fade.east - fade.west, cloudSeamWidth);
      }
      double factor(List<CloudFade> fades, double lon) =>
          fades.fold(1, (f, fade) => f * fade.factorAt(lon));
      for (var lon = -29.75; lon < -20; lon += 0.5) {
        expect(
          factor(eumetsat, lon) + factor(east, lon),
          closeTo(1, 1e-9),
          reason: '$lon',
        );
      }
      for (var lon = -119.75; lon < -110; lon += 0.5) {
        expect(
          factor(east, lon) + factor(west, lon),
          closeTo(1, 1e-9),
          reason: '$lon',
        );
      }
      // Linear: half way across, half each.
      expect(factor(eumetsat, -25), closeTo(0.5, 1e-9));
      // Beyond the bands, each in full.
      expect(factor(eumetsat, 0), 1);
      expect(factor(east, -70), 1);
      expect(factor(west, -150), 1);
      expect(factor(west, 170), 1);
    });

    test('a neighbour switched off: no fade', () {
      final sources = <WeatherMapSource>[
        for (final s in defaultWeatherMapSources)
          s.id == goesEastClouds.id ? s.copyWith(enabled: false) : s,
      ];
      expect(cloudFadesOf(eumetsatClouds, sources), isEmpty);
      expect(cloudFadesOf(goesWestClouds, sources), isEmpty);
    });

    test('the pixel pass ramps each column\'s alpha by its longitude', () {
      const box = BoundingBox(south: 0, west: -40, north: 10, east: 0);
      const width = 40;
      const height = 2;
      final rgba = Uint8List(width * height * 4);
      for (var i = 3; i < rgba.length; i += 4) {
        rgba[i] = 200;
      }
      fadeCloudPixels(width, height, rgba, box, const <CloudFade>[
        CloudFade(west: -30, east: -20, rising: true),
      ]);
      int alphaAtLon(double lon, [int row = 0]) {
        final x = ((lon - box.west) / (box.east - box.west) * width).floor();
        return rgba[(row * width + x) * 4 + 3];
      }

      // The middle of each column is half a degree east of its west edge.
      expect(alphaAtLon(-29.9), closeTo(200 * 0.05, 1));
      expect(alphaAtLon(-25.9), closeTo(200 * 0.45, 1));
      expect(alphaAtLon(-25.9, 1), closeTo(200 * 0.45, 1));
      expect(alphaAtLon(-10), 200);
      // Monotone across the band.
      for (var lon = -30.0; lon < -20; lon += 1) {
        expect(alphaAtLon(lon + 1), greaterThanOrEqualTo(alphaAtLon(lon)));
      }
    });
  });

  group('the soft look scales up smoothly', () {
    // Three cells of the DWD's legend, each 4 × 4 pixels, on clear ground.
    const w = 20;
    const h = 8;
    const colours = <List<int>>[
      <int>[0x01, 0x99, 0x34],
      <int>[0xFF, 0xFF, 0x00],
      <int>[0xFF, 0x00, 0x00],
    ];
    Uint8List cells() {
      final out = Uint8List(w * h * 4);
      for (final (k, colour) in colours.indexed) {
        for (var y = 2; y < 6; y++) {
          for (var x = 2 + 6 * k; x < 6 + 6 * k; x++) {
            out.setAll((y * w + x) * 4, <int>[...colour, 255]);
          }
        }
      }
      return out;
    }

    test('twice the size, the cells\' colours at their middles, the clear '
        'ground clear', () {
      final (w2, h2, out) = upsampleRainPixels(w, h, cells());
      expect((w2, h2), (40, 16));
      List<int> at(int x, int y) =>
          out.sublist((y * w2 + x) * 4, (y * w2 + x) * 4 + 4);
      for (final (k, colour) in colours.indexed) {
        // The middle of cell k: source pixels 3..4 of 2 + 6k on.
        final cx = (4 + 6 * k) * 2;
        expect(at(cx, 8), <int>[...colour, 255], reason: 'cell $k');
        expect(at(cx - 1, 7), <int>[...colour, 255], reason: 'cell $k');
      }
      // Far from every cell: clear.
      for (final (x, y) in <(int, int)>[(0, 0), (39, 15), (0, 15), (39, 0)]) {
        expect(at(x, y)[3], 0, reason: '($x, $y)');
      }
      // Between two cells, a gap two pixels wide: no colour of its own,
      // only the two cells' fading into it (premultiplied: no dark fringe).
      final gap = at(12, 8);
      expect(gap[3], lessThan(255));
      if (gap[3] > 0) {
        expect(gap[0], greaterThan(0));
        expect(gap[2], lessThan(0x40));
      }
    });

    test('the edge of a cell is rounded: a ramp, not a step', () {
      final (w2, _, out) = upsampleRainPixels(w, h, cells());
      final alphas = <int>[
        for (var x = 0; x < 10; x++) out[(8 * w2 + x) * 4 + 3],
      ];
      // Clear, then rising over more than one pixel, then full.
      expect(alphas.first, 0);
      expect(alphas.last, 255);
      expect(alphas.where((a) => a > 0 && a < 255), isNotEmpty);
      for (var x = 1; x < alphas.length; x++) {
        expect(alphas[x], greaterThanOrEqualTo(alphas[x - 1]));
      }
    });

    test('never past the longest side a soft image has', () {
      final (w2, h2, _) = upsampleRainPixels(1000, 10, Uint8List(1000 * 40));
      expect(w2, radarSoftMaxSide);
      expect(h2, 15);
      final big = Uint8List(radarSoftMaxSide * 4 * 4);
      final (w3, h3, same) = upsampleRainPixels(radarSoftMaxSide, 4, big);
      expect((w3, h3), (radarSoftMaxSide, 4));
      expect(identical(same, big), isTrue);
    });

    test('only the soft look is scaled; the coverage keeps the service\'s '
        'size', () {
      const box = BoundingBox(south: 50, west: 8, north: 51, east: 10);
      final rgba = cells();
      final soft = prepareRainImage(
        w,
        h,
        rgba,
        RainImageJob(
          palette: RainPalette.dwd,
          soft: true,
          box: box,
          extent: const <LatLng>[
            LatLng(49, 7),
            LatLng(49, 11),
            LatLng(52, 11),
            LatLng(52, 7),
          ],
        ),
      );
      final header = ByteData.sublistView(soft, 16, 24);
      expect(header.getUint32(0), 2 * w);
      expect(header.getUint32(4), 2 * h);
      final coverage = readRainCoverage(soft, box)!;
      expect((coverage.width, coverage.height), (w, h));
      final measured = prepareRainImage(
        w,
        h,
        rgba,
        const RainImageJob(palette: RainPalette.hsaf, soft: false, box: box),
      );
      expect(ByteData.sublistView(measured, 16, 24).getUint32(0), w);
    });
  });

  // Pixels as the services draw them, read from their GetMap images of
  // 2026-10-11 (DWD `dwd:Niederschlagsradar`, EUMETSAT `mtg_fd:h40b`, NOAA
  // `exportImage` nearest-neighbour, the DWD's ICON layers).
  group('softenRadarPixels: the DWD legend', () {
    int alphaOf(int r, int g, int b, [int a = 255]) =>
        softenRadarPixels(1, 1, _pixel(r, g, b, a))[3];

    int level(double alpha) => (alpha * 255).round();

    test('each class at its rank, from the lightest to the heaviest, its '
        'colour kept', () {
      final legend = dwdRadarLegend;
      expect(legend.classCount, 15);
      var last = 0;
      for (var k = 0; k < legend.colours.length; k++) {
        final c = legend.colours[k];
        final out = softenRadarPixels(
          1,
          1,
          _pixel(c >> 16 & 0xFF, c >> 8 & 0xFF, c & 0xFF, 255),
        );
        expect(out.sublist(0, 3), <int>[
          c >> 16 & 0xFF,
          c >> 8 & 0xFF,
          c & 0xFF,
        ]);
        expect(out[3], greaterThan(last), reason: c.toRadixString(16));
        last = out[3];
      }
      // [0.1, 0.2) mm an hour, cyan: the lightest.
      expect(alphaOf(0x33, 0xFF, 0xFF), level(rainAlphaLightest));
    });

    test('pure blue, 150 mm an hour and more, is the heaviest', () {
      expect(alphaOf(0x00, 0x00, 0xFE), level(rainAlphaHeaviest));
      expect(dwdRadarLegend.classify(0x00, 0x00, 0xFE, 255), 14);
      // Purple, 100 to 150, just below it.
      expect(dwdRadarLegend.classify(0x66, 0x00, 0xCB, 255), 13);
    });

    test('the line around the radars\' reach is no rain', () {
      for (final (r, g, b, a) in <(int, int, int, int)>[
        (0xFB, 0x00, 0xFF, 255),
        (0xFB, 0x00, 0xFF, 191),
        (0xFC, 0x00, 0xFF, 223),
        (0xF7, 0x00, 0xFF, 240),
        (0xC0, 0x3D, 0xC2, 122),
        (0xBB, 0x3F, 0xBE, 117),
        (0x8A, 0x72, 0x8A, 83),
      ]) {
        expect(alphaOf(r, g, b, a), 0, reason: '$r $g $b $a');
        expect(dwdRadarLegend.classify(r, g, b, a), rainNone);
      }
    });

    test('the see-through grey beyond the radars is no data, and goes', () {
      expect(dwdRadarLegend.classify(0x7E, 0x7E, 0x7E, 77), rainNoData);
      expect(alphaOf(0x7E, 0x7E, 0x7E, 77), 0);
    });

    test('a transparent pixel stays transparent', () {
      expect(alphaOf(0xFF, 0xFF, 0xFF, 0), 0);
      expect(alphaOf(0x01, 0x99, 0x34, 0), 0);
    });

    test('a pixel near a legend colour reads as it; one less opaque than '
        'rain is drawn, not at all', () {
      expect(dwdRadarLegend.classify(0x05, 0x9F, 0x30, 255), 2);
      expect(dwdRadarLegend.classify(0x01, 0x99, 0x34, 150), rainNone);
      // The service's own alpha is kept in the product.
      expect(alphaOf(0x00, 0x00, 0xFE, 230), (rainAlphaHeaviest * 230).round());
    });

    // A 5 × 5 image, transparent but for [pixels] at (x, y).
    Uint8List image(Map<(int, int), int> pixels) {
      final out = Uint8List(5 * 5 * 4);
      for (final MapEntry(key: (x, y), value: c) in pixels.entries) {
        out.setAll((y * 5 + x) * 4, <int>[
          c >> 16 & 0xFF,
          c >> 8 & 0xFF,
          c & 0xFF,
          255,
        ]);
      }
      return out;
    }

    int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 5 + x) * 4 + 3];
    final legend = dwdRadarLegend;

    test('edges soften: the alpha alone, averaged over its 3 × 3 box', () {
      // Green, under a millimetre, beside yellow, 5 to 7.5; the rest dry.
      final out = softenRadarPixels(
        5,
        5,
        image({(2, 2): 0x019934, (3, 2): 0xFFFF01}),
      );
      expect(
        alphaAt(out, 2, 2),
        ((legend.alphaOf(2) + legend.alphaOf(6)) / 9 * 255).round(),
      );
      // The colour is untouched, and dry pixels stay dry.
      expect(out.sublist((2 * 5 + 2) * 4, (2 * 5 + 2) * 4 + 3), <int>[
        0x01,
        0x99,
        0x34,
      ]);
      expect(alphaAt(out, 1, 2), 0);
    });

    test('inside a field of rain the alpha stays', () {
      final out = softenRadarPixels(
        5,
        5,
        image({
          for (var y = 0; y < 5; y++)
            for (var x = 0; x < 5; x++) (x, y): 0x019934,
        }),
      );
      expect(alphaAt(out, 2, 2), level(legend.alphaOf(2)));
      // At the image's border too: beyond it counts as the border.
      expect(alphaAt(out, 0, 0), level(legend.alphaOf(2)));
    });

    test('a small heavy cell keeps its strength: the top quarter of the '
        'classes', () {
      expect(legend.alphaOf(11), greaterThanOrEqualTo(rainAlphaHeavy));
      expect(legend.alphaOf(10), lessThan(rainAlphaHeavy));
      expect(
        alphaAt(softenRadarPixels(5, 5, image({(2, 2): 0xE5004C})), 2, 2),
        level(legend.alphaOf(11)),
      );
      expect(
        alphaAt(
          softenRadarPixels(5, 5, image({(2, 2): 0x0000FE, (2, 3): 0x019934})),
          2,
          2,
        ),
        level(rainAlphaHeaviest),
      );
      // 30 to 45 mm an hour is not heavy: it fades at the edge.
      expect(
        alphaAt(softenRadarPixels(5, 5, image({(2, 2): 0xFE0000})), 2, 2),
        (legend.alphaOf(10) / 9 * 255).round(),
      );
    });

    test('light rain beside heavy is lifted, never the other way', () {
      final out = softenRadarPixels(
        5,
        5,
        image({
          (2, 2): 0x33FFFF,
          (1, 2): 0xCC0098,
          (3, 2): 0xCC0098,
          (2, 1): 0xCC0098,
        }),
      );
      expect(alphaAt(out, 1, 2), level(legend.alphaOf(12)));
      expect(
        alphaAt(out, 2, 2),
        ((legend.alphaOf(0) + 3 * legend.alphaOf(12)) / 9 * 255).round(),
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
        process: (png, _) async => throw StateError('not the clouds'),
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

    test('an XML error under 200 is a refusal of the source, taken once; '
        'other failures are not', () async {
      final now = DateTime.utc(2026, 10, 11, 15, 12);
      final frame = hsafRain.frameAt(now)!;
      adapter.contentType = 'text/xml';
      adapter.body = Uint8List.fromList(
        utf8.encode('<ServiceExceptionReport/>'),
      );
      expect(await fetcher.radarImage(hsafRain, box, frame, now), isNull);
      expect(dir.listSync(), isEmpty);
      expect(fetcher.takeRefusal('radar_dwd'), isFalse);
      expect(fetcher.takeRefusal('rain_hsaf'), isTrue);
      expect(fetcher.takeRefusal('rain_hsaf'), isFalse);
      adapter
        ..contentType = 'image/png'
        ..status = 503;
      expect(await fetcher.radarImage(hsafRain, box, frame, now), isNull);
      expect(fetcher.takeRefusal('rain_hsaf'), isFalse);
    });

    test('the newest frame off the source\'s capabilities', () async {
      adapter
        ..contentType = 'text/xml; charset=UTF-8'
        ..body = Uint8List.fromList(
          utf8.encode(
            '<WMS_Capabilities><Dimension name="time" '
            'default="2026-10-11T14:20:00Z" units="ISO8601">'
            '2026-07-23T00:00:00.000Z/2026-10-11T14:20:00.000Z/PT10M'
            '</Dimension></WMS_Capabilities>',
          ),
        );
      expect(
        await fetcher.newestFrame(hsafRain),
        DateTime.utc(2026, 10, 11, 14, 20),
      );
      expect(adapter.requests.single.toString(), hsafRain.timesUrl);
      // None without a timesUrl, without asking.
      expect(await fetcher.newestFrame(dwdRadar), isNull);
      expect(adapter.requests, hasLength(1));
      // An error, a failure or no answer: none.
      adapter.body = Uint8List.fromList(
        utf8.encode('<ServiceExceptionReport/>'),
      );
      expect(await fetcher.newestFrame(hsafRain), isNull);
      adapter.status = 500;
      expect(await fetcher.newestFrame(hsafRain), isNull);
      adapter
        ..status = 200
        ..hang = true;
      expect(await fetcher.newestFrame(hsafRain), isNull);
    });

    group('the cache\'s budget', () {
      // Each prepared image is four bytes: the budget holds three.
      HttpWeatherFetcher budgeted() => HttpWeatherFetcher(
        dio: Dio()..httpClientAdapter = adapter,
        cacheDir: () async => dir,
        probeTimeout: const Duration(milliseconds: 200),
        cacheBudget: 12,
        processRadar: (png, job) async => Uint8List.fromList(<int>[8, ...png]),
      );
      final now = DateTime.utc(2026, 10, 10, 14, 42);
      final frame = dwdRadar.frameAt(now)!;
      BoundingBox boxAt(int i) => BoundingBox(
        south: 50,
        west: 2.0 + i / 2,
        north: 51,
        east: 2.4 + i / 2,
      );
      Future<void> fetch(HttpWeatherFetcher f, int i) =>
          f.radarImage(dwdRadar, boxAt(i), frame, now);
      String nameOf(int i) =>
          '${dwdRadar.id}_soft${rainImageVersion}_${cloudDetailKey(boxAt(i))}_'
          '${radarImageStamp(dwdRadar, frame, now)}.png';
      Set<String> files() => {
        for (final f in dir.listSync()) p.basename(f.path),
      };

      test(
        'past it, the image used longest ago goes; a read keeps one',
        () async {
          final f = budgeted();
          for (var i = 0; i < 3; i++) {
            await fetch(f, i);
          }
          expect(dir.listSync(), hasLength(3));
          // Image 0 read again: now 1 was used longest ago.
          await fetch(f, 0);
          expect(adapter.requests, hasLength(3));
          await fetch(f, 3);
          expect(files(), {nameOf(0), nameOf(2), nameOf(3)});
          await fetch(f, 4);
          expect(files(), {nameOf(0), nameOf(3), nameOf(4)});
        },
      );

      test(
        'the order of use outlives the launch, in the access times',
        () async {
          final first = budgeted();
          for (var i = 0; i < 3; i++) {
            await fetch(first, i);
          }
          final base = DateTime.now().subtract(const Duration(minutes: 10));
          for (final (i, used) in <(int, int)>[(0, 9), (1, 2), (2, 5)]) {
            File(p.join(dir.path, nameOf(i)))
              ..setLastModifiedSync(base)
              ..setLastAccessedSync(base.add(Duration(minutes: used)));
          }
          // The next launch: image 1 was used longest ago.
          await fetch(budgeted(), 3);
          expect(files(), {nameOf(0), nameOf(2), nameOf(3)});
        },
      );

      test(
        'the age limit still holds; older versions go, other files stay',
        () async {
          final old = DateTime.now().subtract(
            cloudCacheMaxAge + const Duration(minutes: 1),
          );
          final young = DateTime.now().subtract(const Duration(hours: 1));
          void place(String name, DateTime modified) {
            File(p.join(dir.path, name))
              ..writeAsBytesSync(<int>[1])
              ..setLastModifiedSync(modified)
              ..setLastAccessedSync(modified);
          }

          place('radar_dwd_soft1_old.png', old);
          place('radar_dwd_soft1_young.png', young);
          place('wind_icon_old.txt', old);
          place('notes.json', old);
          final f = HttpWeatherFetcher(
            dio: Dio()..httpClientAdapter = adapter,
            cacheDir: () async => dir,
            probeTimeout: const Duration(milliseconds: 200),
            processRadar: (png, job) async => png,
          );
          await f.radarImage(dwdRadar, boxAt(0), frame, DateTime.now());
          // Images and grids past the age go, and an older version's young
          // image too; a file not the cache's own stays.
          expect(files(), isNot(contains('radar_dwd_soft1_young.png')));
          expect(files(), contains('notes.json'));
          expect(files(), isNot(contains('radar_dwd_soft1_old.png')));
          expect(files(), isNot(contains('wind_icon_old.txt')));
        },
      );
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

  group('rain legends', () {
    int level(double alpha) => (alpha * 255).round();

    test('H SAF: light green the faintest, the purples the strongest; the '
        'colours kept', () {
      List<int> soft(int r, int g, int b) =>
          softenRainPixels(1, 1, _pixel(r, g, b, 255), RainPalette.hsaf);
      expect(soft(0xCC, 0xFF, 0xCC), <int>[
        0xCC,
        0xFF,
        0xCC,
        level(rainAlphaLightest),
      ]);
      expect(soft(0x99, 0xE6, 0x99)[3], level(hsafLegend.alphaOf(1)));
      expect(hsafLegend.classify(0x33, 0x66, 0xFF, 255), 5);
      expect(hsafLegend.classify(0x00, 0x00, 0xFF, 255), 6);
      expect(soft(0x80, 0x00, 0x80)[3], level(rainAlphaHeaviest));
      // An edge pixel near a class reads as it; the transparent ground
      // stays so.
      expect(hsafLegend.classify(199, 246, 199, 255), 0);
      expect(
        softenRainPixels(1, 1, _pixel(0, 0, 0, 0), RainPalette.hsaf)[3],
        0,
      );
      // A colour no class has is nothing.
      expect(hsafLegend.classify(0xFF, 0x80, 0x00, 255), rainNone);
    });

    test('NOAA: its ramp from grey-blue to dark red, the colours it was not '
        'seen to draw the heaviest', () {
      final legend = noaaRadarLegend;
      expect(legend.classify(0xA5, 0xAB, 0xB4, 255), 0); // grey-blue
      expect(legend.classify(0x43, 0x5E, 0x9F, 255), 1);
      expect(legend.classify(0x5E, 0xAD, 0xCF, 255), 2);
      expect(legend.classify(0x0E, 0xD6, 0x14, 255), 4); // green
      expect(legend.classify(0x09, 0x5E, 0x09, 255), 6); // dark green
      expect(legend.classify(0xFF, 0xE2, 0x00, 255), 7); // yellow
      expect(legend.classify(0xFF, 0xB1, 0x00, 255), 8);
      expect(legend.classify(0xFF, 0x00, 0x00, 255), 9); // red
      expect(legend.classify(0xB1, 0x00, 0x00, 255), 10);
      // Mixed by the service's own resampling (a real pixel of a bilinear
      // image): the class of the nearest colour, not the heaviest.
      expect(legend.classify(0x48, 0xC8, 0x93, 255), inInclusiveRange(3, 4));
      // Not seen on the day the ramp was read: the heaviest.
      expect(legend.classify(0xFF, 0x00, 0xFF, 255), legend.classCount - 1);
      expect(legend.alphaOf(legend.classCount - 1), rainAlphaHeaviest);
      // Light rain faint, a storm's core heavy, the ground transparent.
      List<int> soft(int r, int g, int b, [int a = 255]) =>
          softenRainPixels(1, 1, _pixel(r, g, b, a), RainPalette.noaa);
      expect(soft(0x8F, 0x97, 0xB4), <int>[
        0x8F,
        0x97,
        0xB4,
        level(rainAlphaLightest),
      ]);
      expect(soft(0xD8, 0x00, 0x00)[3], greaterThan(level(rainAlphaHeavy)));
      expect(soft(0, 0, 0, 0)[3], 0);
      // Every class rises.
      for (var k = 1; k < legend.classCount; k++) {
        expect(legend.alphaOf(k), greaterThan(legend.alphaOf(k - 1)));
      }
    });

    test('the global model: recoloured into the radar\'s legend at the mean '
        'rate an hour, its no-rain veil gone', () {
      List<int> soft(int r, int g, int b, [int a = 255]) =>
          softenRainPixels(1, 1, _pixel(r, g, b, a), RainPalette.dwdModel6h);
      // The veil over dry ground, as the service draws it.
      expect(soft(0, 0, 0, 20)[3], 0);
      // 0.1–0.5 mm in six hours: the radar's lightest cyan.
      expect(soft(0xDC, 0xF7, 0xC3), <int>[
        0x33,
        0xFF,
        0xFF,
        level(rainAlphaLightest),
      ]);
      // 2–5 mm: under a millimetre an hour, the radar's dark green.
      expect(soft(0x00, 0xBF, 0x01).sublist(0, 3), <int>[0x01, 0x99, 0x34]);
      // 40–50 mm: 7.5–10 mm an hour, orange-yellow.
      expect(soft(0xCC, 0x00, 0x00).sublist(0, 3), <int>[0xFF, 0xC4, 0x01]);
      // 200–300 mm: red, at the radar's red.
      expect(soft(0x8E, 0x66, 0xFF), <int>[
        0xFE,
        0x00,
        0x00,
        level(dwdRadarLegend.alphaOf(10)),
      ]);
      // More than 300: the radar's 45 to 75, heavy.
      expect(soft(0xFF, 0xFF, 0xFF).sublist(0, 3), <int>[0xE5, 0x00, 0x4C]);
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
      expect(iconEuRain.palette, RainPalette.dwd);
      expect(dwdRadar.palette, RainPalette.dwd);
      expect(noaaRadar.palette, RainPalette.noaa);
      expect(rainLegendOf(RainPalette.dwd), same(dwdRadarLegend));
      // The DWD radar style's colours, from a real ICON-EU image.
      expect(
        softenRainPixels(1, 1, _pixel(0xCC, 0x00, 0x98, 255), RainPalette.dwd),
        softenRadarPixels(1, 1, _pixel(0xCC, 0x00, 0x98, 255)),
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
      (RainPalette.dwd, _pixel(0x01, 0x99, 0x34, 255)),
      (RainPalette.dwdModel6h, _pixel(0x00, 0xBF, 0x01, 255)),
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
          palette: RainPalette.dwd,
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

  group('the DWD frame\'s coverage', () {
    // A strip from the Paris basin to the Black Forest, 40 × 4 pixels, a
    // quarter degree each: west of 3° beyond the DWD's grid, then the
    // grey of "no data", the line around the reach, and inside it dry
    // ground and rain, as the DWD draws them (real pixels).
    const box = BoundingBox(south: 48, west: 0, north: 49, east: 10);
    const width = 40;
    const height = 4;
    double lonOf(int x) => (x + 0.5) / width * 10;

    // The frame whose radars reach east from [reachFrom]° on.
    Uint8List frame(double reachFrom) {
      final out = Uint8List(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final lon = lonOf(x);
          final List<int> pixel;
          if (lon < 3) {
            pixel = <int>[255, 255, 255, 0]; // beyond the grid
          } else if (lon < reachFrom) {
            pixel = <int>[0x7E, 0x7E, 0x7E, 77]; // no data
          } else if (lon < reachFrom + 0.25) {
            pixel = <int>[0xFB, 0x00, 0xFF, 191]; // the line
          } else if (x.isEven) {
            pixel = <int>[0x01, 0x99, 0x34, 255]; // rain
          } else {
            pixel = <int>[255, 255, 255, 0]; // dry
          }
          out.setAll((y * width + x) * 4, pixel);
        }
      }
      return out;
    }

    RainCoverage coverageOf(Uint8List rgba) => RainCoverage(
      box: box,
      width: width,
      height: height,
      covered: rainCoverageOf(
        width,
        height,
        rgba,
        RainPalette.dwd,
        box,
        dwdRadarExtent,
      ),
    );

    test('measured where it rains or is dry inside the reach and on its '
        'line; not in the grey, nor beyond the grid', () {
      final coverage = coverageOf(frame(5));
      for (var x = 0; x < width; x++) {
        final lon = lonOf(x);
        expect(coverage.covered[x] > 0, lon >= 5, reason: 'at $lon°');
      }
      expect(coverage.coversAll(box), isFalse);
      // A view east of the grey: all measured.
      expect(
        coverage.coversAll(
          const BoundingBox(south: 48.2, west: 6, north: 48.8, east: 9),
        ),
        isTrue,
      );
    });

    // The satellite's image of the same box, coarser, all rain.
    const lowerWidth = 20;
    const lowerHeight = 3;
    Uint8List lower() {
      final out = Uint8List(lowerWidth * lowerHeight * 4);
      for (var i = 0; i < lowerWidth * lowerHeight; i++) {
        out.setAll(i * 4, <int>[0xCC, 0xFF, 0xCC, 255]);
      }
      return out;
    }

    Set<int> shownColumns(Uint8List rgba) => <int>{
      for (var y = 0; y < lowerHeight; y++)
        for (var x = 0; x < lowerWidth; x++)
          if (rgba[(y * lowerWidth + x) * 4 + 3] > 0) x,
    };

    test('the source after it fills exactly where the frame does not '
        'measure; a nowcast reaching less leaves it more', () {
      Uint8List cut(RainCoverage coverage) => prepareRainPixels(
        lowerWidth,
        lowerHeight,
        lower(),
        RainImageJob(
          palette: RainPalette.hsaf,
          soft: false,
          box: box,
          coverages: <RainCoverage>[coverage],
        ),
      );
      final now = cut(coverageOf(frame(5)));
      final ahead = cut(coverageOf(frame(7)));
      double lowerLon(int x) => (x + 0.5) / lowerWidth * 10;
      expect(shownColumns(now), <int>{
        for (var x = 0; x < lowerWidth; x++)
          if (lowerLon(x) < 5) x,
      });
      expect(shownColumns(ahead), <int>{
        for (var x = 0; x < lowerWidth; x++)
          if (lowerLon(x) < 7) x,
      });
      // The difference: where the nowcast no longer reaches.
      expect(shownColumns(ahead).difference(shownColumns(now)), <int>{
        for (var x = 0; x < lowerWidth; x++)
          if (lowerLon(x) >= 5 && lowerLon(x) < 7) x,
      });
    });

    test('no pixel of the source after it where the frame has rain or dry '
        'ground inside the reach', () {
      final rgba = frame(5);
      final coverage = coverageOf(rgba);
      final out = prepareRainPixels(
        lowerWidth,
        lowerHeight,
        lower(),
        RainImageJob(
          palette: RainPalette.hsaf,
          soft: true,
          box: box,
          coverages: <RainCoverage>[coverage],
        ),
      );
      for (final x in shownColumns(out)) {
        final lon = (x + 0.5) / lowerWidth * 10;
        final dwdX = (lon / 10 * width).floor();
        final a = rgba[dwdX * 4 + 3];
        final grey = rgba[dwdX * 4] == 0x7E;
        // Shown only beyond the grid (transparent) or over the grey.
        expect(a == 0 && lon < 3 || grey, isTrue, reason: 'at $lon°');
      }
    });

    test('a seam 25 km wide inside the edge: the weight rises with the '
        'distance from where it does not measure', () {
      // At the equator, where Web Mercator metres are the ground's: 120
      // pixels of a kilometre, the west 40 not measured.
      const w = 120;
      const h = 9;
      final metres = 120000.0;
      final equator = BoundingBox(
        south: latOfMercatorY(-metres * h / w / 2),
        west: 0,
        north: latOfMercatorY(metres * h / w / 2),
        east: lonOfMercatorX(metres),
      );
      final inside = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 40; x < w; x++) {
          inside[y * w + x] = 1;
        }
      }
      final weights = rainSeamWeights(w, h, inside, equator);
      int at(int x) => weights[4 * w + x];
      // Not measured: 0. One pixel in: a kilometre of 25.
      expect(at(39), 0);
      expect(at(40), closeTo(255 / 25, 1));
      // Thirteen kilometres in, thirteen of 25.
      expect(at(52), closeTo(255 * 13 / 25, 2));
      // Past it, full: the source alone.
      expect(at(65), 255);
      expect(at(119), 255);
      for (var x = 41; x < w; x++) {
        expect(at(x), greaterThanOrEqualTo(at(x - 1)), reason: '$x');
      }
      // The image's own edges are no edge of the coverage: the top row is
      // as deep in as the middle one.
      expect(weights[100], 255);
      expect(weights[45], at(45));
    });

    test('across the seam the source after it fades in as the frame\'s '
        'own fades out, the two adding up to the whole', () {
      const w = 60;
      const h = 3;
      const equator = BoundingBox(south: -0.1, west: 0, north: 0.1, east: 0.6);
      final inside = Uint8List(w * h);
      for (var i = 0; i < w * h; i++) {
        if (i % w >= 20) inside[i] = 1;
      }
      final seam = rainSeamWeights(w, h, inside, equator);
      final coverage = RainCoverage(
        box: equator,
        width: w,
        height: h,
        covered: seam,
      );
      Uint8List solid(List<int> colour) =>
          Uint8List.fromList(<int>[for (var i = 0; i < w * h; i++) ...colour]);
      final own = prepareRainPixels(
        w,
        h,
        solid(<int>[0x01, 0x99, 0x34, 255]),
        const RainImageJob(palette: RainPalette.dwd, soft: false, box: equator),
        seam: seam,
      );
      final after = prepareRainPixels(
        w,
        h,
        solid(<int>[0xCC, 0xFF, 0xCC, 255]),
        RainImageJob(
          palette: RainPalette.hsaf,
          soft: false,
          box: equator,
          coverages: <RainCoverage>[coverage],
        ),
      );
      for (var x = 0; x < w; x++) {
        final o = (w + x) * 4 + 3;
        expect(own[o] + after[o], closeTo(255, 1), reason: 'at $x');
      }
      // Outside the frame's reach the source after it alone; deep inside
      // the frame alone; in the seam both.
      expect(after[(w + 5) * 4 + 3], 255);
      expect(own[(w + 5) * 4 + 3], 0);
      expect(after[(w + 59) * 4 + 3], 0);
      expect(own[(w + 59) * 4 + 3], 255);
      expect(after[(w + 22) * 4 + 3], inExclusiveRange(0, 255));
      // Where the frame alone draws, the view counts as covered.
      expect(
        coverage.coversAll(
          const BoundingBox(south: -0.05, west: 0.5, north: 0.05, east: 0.58),
        ),
        isTrue,
      );
      expect(
        coverage.coversAll(
          const BoundingBox(south: -0.05, west: 0.25, north: 0.05, east: 0.58),
        ),
        isFalse,
      );
    });

    test('travels with the image in a chunk every decoder skips', () async {
      final rgba = frame(5);
      final covered = coverageOf(rgba).covered;
      final png = encodePngRgba(width, height, rgba, coverage: covered);
      final read = readRainCoverage(png, box)!;
      expect(read.width, width);
      expect(read.height, height);
      expect(read.covered, covered);
      expect(read.box, box);
      expect(readRainCoverage(encodePngRgba(width, height, rgba), box), isNull);
      expect(readRainCoverage(Uint8List.fromList(<int>[7, 8, 9]), box), isNull);
      expect(mapCanDecode(png), isTrue);
      // The engine's decoder takes it, pixels unchanged.
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      final bytes = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      expect(image.width, width);
      final decoded = bytes!.buffer.asUint8List();
      for (var i = 3; i < rgba.length; i += 4) {
        expect(decoded[i], rgba[i]);
      }
    });

    test('the soft look of the DWD keeps its frame\'s coverage', () {
      // The fetcher asks for it, drawn soft only.
      const job = RainImageJob(
        palette: RainPalette.dwd,
        soft: true,
        box: box,
        extent: dwdRadarExtent,
      );
      expect(job.needed, isTrue);
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

  group('wind', () {
    late _Adapter adapter;
    late Directory dir;
    late HttpWeatherFetcher fetcher;
    var parsed = 0;
    final text = File('test/fixtures/weather/dwd_wind_uv10m.txt')
        .readAsStringSync();
    final request = windRequestFor(
      const BoundingBox(south: 49, west: 7, north: 51, east: 8),
      8,
    )!;
    final now = DateTime.now().toUtc();
    final frame = dwdWind.frameAt(now)!;

    setUp(() {
      adapter = _Adapter()
        ..contentType = 'text/plain'
        ..body = Uint8List.fromList(utf8.encode(text));
      dir = Directory.systemTemp.createTempSync('wind');
      addTearDown(() => dir.deleteSync(recursive: true));
      parsed = 0;
      fetcher = HttpWeatherFetcher(
        dio: Dio()..httpClientAdapter = adapter,
        cacheDir: () async => dir,
        windTimeLimit: const Duration(milliseconds: 200),
        parseWind: (text) async {
          parsed++;
          return parseWcsWindGrid(text);
        },
      );
    });

    test('asks for the box at the hour, reads the grid, then comes from the '
        'cache for an hour', () async {
      final grid = await fetcher.windGrid(dwdWind, request, frame, now);
      expect(grid!.columns, 20);
      expect(adapter.requests, hasLength(1));
      final url = adapter.requests.single.toString();
      expect(url, contains('coverageId=dwd__Icon_reg025_fd_sl_UV10M'));
      expect(
        url,
        contains('subset=Long(${request.box.west.toStringAsFixed(3)}'),
      );
      expect(url, contains(formatWeatherTime(frame.time!)));
      final again = await fetcher.windGrid(dwdWind, request, frame, now);
      expect(again!.columns, 20);
      expect(adapter.requests, hasLength(1));
      expect(parsed, 2);
      // An hour on, asked again.
      await fetcher.windGrid(
        dwdWind,
        request,
        frame,
        now.add(windCacheMaxAge + const Duration(minutes: 1)),
      );
      expect(adapter.requests, hasLength(2));
    });

    test(
      'the service error, an answer not text or a hang is no grid',
      () async {
        adapter
          ..contentType = 'application/xml'
          ..body = Uint8List.fromList(
            utf8.encode(
              '<ows:ExceptionReport>Cannot find</ows:ExceptionReport>',
            ),
          );
        expect(await fetcher.windGrid(dwdWind, request, frame, now), isNull);
        adapter
          ..contentType = 'text/plain'
          ..body = Uint8List.fromList(utf8.encode('Grid range: nothing'));
        expect(await fetcher.windGrid(dwdWind, request, frame, now), isNull);
        adapter
          ..status = 500
          ..body = Uint8List.fromList(utf8.encode(text));
        expect(await fetcher.windGrid(dwdWind, request, frame, now), isNull);
        adapter
          ..status = 200
          ..hang = true;
        expect(await fetcher.windGrid(dwdWind, request, frame, now), isNull);
        // Nothing that failed was kept.
        expect(dir.listSync(), isEmpty);
      },
    );

    test('the grids share the budget, the oldest going first', () async {
      final size = utf8.encode(text).length;
      final fetcher = HttpWeatherFetcher(
        dio: Dio()..httpClientAdapter = adapter,
        cacheDir: () async => dir,
        windTimeLimit: const Duration(milliseconds: 200),
        cacheBudget: 3 * size,
        parseWind: (text) async => parseWcsWindGrid(text),
      );
      for (var h = 0; h < 7; h++) {
        await fetcher.windGrid(
          dwdWind,
          request,
          WeatherFrame(
            DateTime.utc(2026, 10, 11, h % 24, 0).add(Duration(days: h ~/ 24)),
          ),
          now,
        );
      }
      final names = [for (final f in dir.listSync()) p.basename(f.path)];
      expect(names, hasLength(3));
      for (var h = 4; h < 7; h++) {
        final ms = DateTime.utc(2026, 10, 11, h).millisecondsSinceEpoch;
        expect(names.where((n) => n.endsWith('_$ms.txt')), hasLength(1));
      }
    });
  });
}
