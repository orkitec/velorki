import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/domain/wind_field.dart';
import 'package:velorki/features/weather/data/dwd_route_forecast.dart';
import 'package:velorki/features/weather/domain/free_route_forecast.dart';
import 'package:velorki/features/weather/domain/route_sampling.dart';
import 'package:velorki/features/weather/domain/route_weather.dart';
import 'package:velorki_geo/velorki_geo.dart';

// Recorded off the DWD's WCS on 2026-10-12, run 12 UTC, over
// Lat(40.5,41) Long(23.5,24.5) (northern Greece, in rain):
// the wind at 2026-10-13T12, the global rain sums at 12 and 13 UTC, and
// ICON-EU's rain of the hour up to 13 UTC.
String _fixture(String name) =>
    File('test/fixtures/weather/$name').readAsStringSync();

final DateTime _run = DateTime.utc(2026, 10, 12, 12);
final DateTime _noon = DateTime.utc(2026, 10, 13, 12);

/// A sample at [position], heading [bearingDeg], [minutes] after leaving.
RouteWeatherSample _sample(
  LatLng position, {
  double distanceM = 0,
  double bearingDeg = 0,
  int minutes = 0,
}) => RouteWeatherSample(
  distanceM: distanceM,
  position: position,
  bearingDeg: bearingDeg,
  offset: Duration(minutes: minutes),
);

class _Adapter implements HttpClientAdapter {
  final List<Uri> requests = <Uri>[];
  String Function(Uri uri) body = (_) => '';
  String Function(Uri uri) contentType = (_) => 'text/plain';
  Completer<void>? gate;
  int inFlight = 0;
  int mostInFlight = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    inFlight++;
    if (inFlight > mostInFlight) mostInFlight = inFlight;
    try {
      if (gate != null) await gate!.future;
      return ResponseBody.fromString(
        body(options.uri),
        200,
        headers: {
          Headers.contentTypeHeader: [contentType(options.uri)],
        },
      );
    } finally {
      inFlight--;
    }
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('the grids the WCS answers with', () {
    test('ICON-EU rain of an hour: one band on its 0.0625° grid', () {
      final grid = parseWcsGrid(_fixture('dwd_route_totprec01h_13.txt'))!;
      expect(grid.columns, 16);
      expect(grid.rows, 8);
      expect(grid.lonStep, 0.0625);
      expect(grid.latStep, -0.0625);
      expect(grid.lon0, closeTo(23.5625, 1e-9));
      expect(grid.lat0, closeTo(40.9375, 1e-9));
      // A grid point is its own value.
      expect(grid.sampleBands(40.9375, 23.5625)!.single, closeTo(0.855, 1e-3));
      // Halfway between the first two points of the first row.
      expect(
        grid.sampleBands(40.9375, 23.59375)!.single,
        closeTo((0.85546875 + 0.798828125) / 2, 1e-6),
      );
      expect(grid.sampleBands(45, 23.6), isNull);
    });

    test('the wind: two bands, u and v', () {
      final grid = parseWcsWindGrid(_fixture('dwd_route_uv10m.txt'))!;
      expect(grid.columns, 4);
      expect(grid.rows, 2);
      final (u, v) = grid.sample(40.75, 24)!;
      expect(u, closeTo(1.2636, 1e-4));
      expect(v, closeTo(-1.4637, 1e-4));
      // A one-band text is no wind.
      expect(parseWcsWindGrid(_fixture('dwd_route_totprec_12.txt')), isNull);
    });

    test('the global rain is a sum from the run: an hour is the difference '
        'of its ends', () {
      final at12 = parseWcsGrid(_fixture('dwd_route_totprec_12.txt'))!;
      final at13 = parseWcsGrid(_fixture('dwd_route_totprec_13.txt'))!;
      final start = at12.sampleBands(40.75, 24)!.single;
      final end = at13.sampleBands(40.75, 24)!.single;
      expect(start, closeTo(4.40625, 1e-6));
      expect(end, closeTo(5.0625, 1e-6));
      expect(hourlyRain(start, end), closeTo(0.65625, 1e-6));
      // A sum that steps back a hair is no rain, never less.
      expect(hourlyRain(5, 4.99), 0);
    });

    test('the newest run off DescribeCoverage', () {
      expect(
        parseNewestRun(_fixture('dwd_route_totprec_describe.xml')),
        DateTime.utc(2026, 10, 12, 12),
      );
      expect(parseNewestRun('<xml/>'), isNull);
    });

    test('every request names the run', () {
      final url = dwdCoverageUrl(
        dwdRainEuCoverage,
        const BoundingBox(south: 40.5, west: 23.5, north: 41, east: 24.5),
        _noon,
        _run,
      );
      expect(url, contains('coverageId=$dwdRainEuCoverage'));
      expect(url, contains('subset=Lat(40.500,41.000)'));
      expect(url, contains('subset=Long(23.500,24.500)'));
      expect(url, contains('subset=time(%222026-10-13T12:00:00.000Z%22)'));
      expect(
        url,
        contains('subset=REFERENCE_TIME(%222026-10-12T12:00:00.000Z%22)'),
      );
    });
  });

  group('planFreeForecast', () {
    test('in Europe: the hour each sample falls in, ICON-EU rain at the end '
        'of that hour, one box snapped out around the whole route', () {
      final departure = DateTime.utc(2026, 10, 13, 11, 40);
      final samples = [
        _sample(const LatLng(50.1, 8.1)),
        _sample(const LatLng(50.3, 8.2), distanceM: 6000, minutes: 15),
        _sample(const LatLng(50.6, 8.3), distanceM: 20000, minutes: 70),
      ];
      final plan = planFreeForecast(samples, departure, europe: dwdRainEuArea);
      expect(plan.rain, FreeRain.europe);
      expect(plan.hours, [
        DateTime.utc(2026, 10, 13, 11),
        DateTime.utc(2026, 10, 13, 11),
        DateTime.utc(2026, 10, 13, 12),
      ]);
      expect(plan.wind.keys, [
        DateTime.utc(2026, 10, 13, 11),
        DateTime.utc(2026, 10, 13, 12),
      ]);
      expect(plan.rainGrids.keys, [
        DateTime.utc(2026, 10, 13, 12),
        DateTime.utc(2026, 10, 13, 13),
      ]);
      // The same box every hour, so one grid serves every departure.
      const box = BoundingBox(south: 49.5, west: 7.5, north: 51.5, east: 9);
      expect(plan.wind.values, everyElement(box));
      expect(plan.rainGrids.values, everyElement(box));
    });

    test('outside Europe the global sums: both ends of every hour', () {
      final departure = DateTime.utc(2026, 10, 13, 11, 40);
      final plan = planFreeForecast(
        [
          _sample(const LatLng(40.7, -74)),
          _sample(const LatLng(40.8, -74), distanceM: 9000, minutes: 30),
        ],
        departure,
        europe: dwdRainEuArea,
      );
      expect(plan.rain, FreeRain.global);
      expect(plan.rainGrids.keys.toSet(), {
        DateTime.utc(2026, 10, 13, 11),
        DateTime.utc(2026, 10, 13, 12),
        DateTime.utc(2026, 10, 13, 13),
      });
    });

    test('samples past three days ahead have no hour', () {
      final plan = planFreeForecast(
        [
          _sample(const LatLng(50, 8)),
          _sample(const LatLng(50, 8), minutes: 73 * 60),
        ],
        _noon,
        europe: dwdRainEuArea,
      );
      expect(plan.hours.last, isNull);
      expect(plan.wind.length, 1);
    });
  });

  group('freeSampleWeather', () {
    final wind = parseWcsWindGrid(_fixture('dwd_route_uv10m.txt'))!;
    final at12 = parseWcsGrid(_fixture('dwd_route_totprec_12.txt'))!;
    final at13 = parseWcsGrid(_fixture('dwd_route_totprec_13.txt'))!;
    final eu13 = parseWcsGrid(_fixture('dwd_route_totprec01h_13.txt'))!;
    final samples = [_sample(const LatLng(40.75, 24))];

    test('the wind met as the relay forecast is, and the rain of the hour', () {
      final plan = planFreeForecast(samples, _noon, europe: dwdRainEuArea);
      expect(plan.rain, FreeRain.europe);
      final weather = freeSampleWeather(
        samples,
        plan,
        _noon,
        wind: (h) => h == _noon ? wind : null,
        rain: (h) => h == _noon.add(const Duration(hours: 1)) ? eu13 : null,
      ).single!;
      final (u, v) = wind.sample(40.75, 24)!;
      final ms = windDirectionSpeed(u, v).ms;
      final expected = windOnRoute(ms, weather.windFromDeg, 0);
      expect(weather.windMs, closeTo(ms, 1e-9));
      // u east and v south: it blows to the south-east, from the north-west.
      expect(weather.windFromDeg, closeTo(319.2, 0.1));
      expect(weather.headwindMs, closeTo(expected.headwind, 1e-9));
      expect(weather.windClass, WindClass.headwind);
      expect(weather.precipMm, closeTo(eu13.sampleBands(40.75, 24)!.single, 0));
      expect(weather.temp, isNull);
      expect(weather.gust, isNull);
      expect(weather.precipProb, isNull);
      expect(weather.at, _noon);
    });

    test('the global rain from the sums at both ends of the hour', () {
      final plan = FreeForecastPlan(
        hours: [_noon],
        rain: FreeRain.global,
        wind: const {},
        rainGrids: const {},
      );
      final weather = freeSampleWeather(
        samples,
        plan,
        _noon,
        wind: (_) => wind,
        rain: (h) => h == _noon ? at12 : at13,
      ).single!;
      expect(weather.precipMm, closeTo(0.65625, 1e-6));
      expect(weather.wet, isTrue);
    });

    test('a sample whose wind or rain is missing is a gap', () {
      final plan = planFreeForecast(samples, _noon, europe: dwdRainEuArea);
      expect(
        freeSampleWeather(
          samples,
          plan,
          _noon,
          wind: (_) => null,
          rain: (_) => eu13,
        ).single,
        isNull,
      );
      expect(
        freeSampleWeather(
          samples,
          plan,
          _noon,
          wind: (_) => wind,
          rain: (_) => null,
        ).single,
        isNull,
      );
    });
  });

  group('HttpDwdForecastClient', () {
    late _Adapter adapter;
    late HttpDwdForecastClient client;
    late DateTime now;
    const box = BoundingBox(south: 40.5, west: 23.5, north: 41, east: 24.5);

    setUp(() {
      now = DateTime.utc(2026, 10, 12, 17);
      bool describe(Uri uri) => uri.query.contains('DescribeCoverage');
      adapter = _Adapter();
      adapter.body = (uri) => describe(uri)
          ? _fixture('dwd_route_totprec_describe.xml')
          : _fixture('dwd_route_totprec01h_13.txt');
      adapter.contentType = (uri) =>
          describe(uri) ? 'application/xml' : 'text/plain';
      client = HttpDwdForecastClient(
        dio: Dio()..httpClientAdapter = adapter,
        now: () => now,
        parse: (text, bands) async => parseWcsGrid(text, bands: bands),
      );
    });

    test('the newest run is read once and kept a while', () async {
      expect(await client.newestRun(dwdRainEuCoverage), _run);
      expect(await client.newestRun(dwdRainEuCoverage), _run);
      expect(adapter.requests, hasLength(1));
      now = now.add(dwdRunCacheAge);
      expect(await client.newestRun(dwdRainEuCoverage), _run);
      expect(adapter.requests, hasLength(2));
    });

    test(
      'a grid asked for again is not fetched again; a failed one is',
      () async {
        final grid = await client.grid(dwdRainEuCoverage, box, _noon, _run);
        expect(grid!.columns, 16);
        await client.grid(dwdRainEuCoverage, box, _noon, _run);
        expect(adapter.requests, hasLength(1));

        // An XML error under status 200 is no grid, and is asked again.
        adapter.contentType = (_) => 'application/xml';
        final later = _noon.add(const Duration(hours: 1));
        expect(await client.grid(dwdRainEuCoverage, box, later, _run), isNull);
        expect(await client.grid(dwdRainEuCoverage, box, later, _run), isNull);
        expect(adapter.requests, hasLength(3));
      },
    );

    test('what has come is there at once, without asking', () async {
      expect(client.knownRun(dwdRainEuCoverage), isNull);
      expect(client.loadedGrid(dwdRainEuCoverage, box, _noon, _run), isNull);
      await client.newestRun(dwdRainEuCoverage);
      expect(client.knownRun(dwdRainEuCoverage), _run);
      final grid = await client.grid(dwdRainEuCoverage, box, _noon, _run);
      expect(client.loadedGrid(dwdRainEuCoverage, box, _noon, _run), grid);
      // A failed one is not.
      adapter.contentType = (_) => 'application/xml';
      final later = _noon.add(const Duration(hours: 1));
      await client.grid(dwdRainEuCoverage, box, later, _run);
      expect(client.loadedGrid(dwdRainEuCoverage, box, later, _run), isNull);
      now = now.add(dwdRunCacheAge);
      expect(client.knownRun(dwdRainEuCoverage), isNull);
    });

    test('at most a few requests at once', () async {
      adapter.gate = Completer<void>();
      final all = Future.wait([
        for (var h = 0; h < 10; h++)
          client.grid(
            dwdRainEuCoverage,
            box,
            _noon.add(Duration(hours: h)),
            _run,
          ),
      ]);
      await pumpEventQueue();
      expect(adapter.mostInFlight, dwdMaxConcurrent);
      adapter.gate!.complete();
      expect((await all).every((g) => g != null), isTrue);
      expect(adapter.requests, hasLength(10));
    });
  });
}
