import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/application/weather_map_driver.dart';
import 'package:velorki/features/map/data/weather_fetcher.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/map/domain/wind_field.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Answers probes and cloud images as told, recording what was asked.
class _Fetcher implements WeatherFetcher {
  bool radarUp = true;
  bool cloudsUp = true;
  final List<String> probes = <String>[];
  final List<String> images = <String>[];

  /// The detail images asked for, and the answers held back for them while
  /// [holdDetails] is set.
  final List<BoundingBox> details = <BoundingBox>[];
  final List<Completer<Uint8List?>> held = <Completer<Uint8List?>>[];
  bool holdDetails = false;

  /// The soft radar images asked for (source, box, moment), and the
  /// answers held back for them while [holdRadar] is set.
  bool radarImagesUp = true;
  bool holdRadar = false;
  final List<(String, BoundingBox, DateTime?)> radarImages =
      <(String, BoundingBox, DateTime?)>[];
  final List<Completer<Uint8List?>> heldRadar = <Completer<Uint8List?>>[];

  /// Of each rain image asked for: the look and what it is masked by, and
  /// the frames' coverages it is cut by.
  final List<(RadarStyle, String)> radarJobs = <(RadarStyle, String)>[];
  final List<List<RainCoverage>> radarCoverages = <List<RainCoverage>>[];

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
  }) {
    radarImages.add((source.id, box, frame.time));
    radarJobs.add((style, maskKey));
    radarCoverages.add(coverages);
    if (holdRadar) {
      final answer = Completer<Uint8List?>();
      heldRadar.add(answer);
      return answer.future;
    }
    final answer = radarAnswer;
    if (answer != null) return Future<Uint8List?>.value(answer(source, box));
    return Future<Uint8List?>.value(
      radarImagesUp ? Uint8List.fromList(<int>[7, 8, 9]) : null,
    );
  }

  /// What a rain image is answered with, where set, instead.
  Uint8List? Function(WeatherMapSource source, BoundingBox box)? radarAnswer;

  /// The wind grids asked for (request, moment), whether the service
  /// answers, and the answers held back while [holdWind] is set.
  bool windUp = true;
  bool holdWind = false;
  final List<(WindRequest, DateTime?)> winds = <(WindRequest, DateTime?)>[];
  final List<Completer<WindGrid?>> heldWind = <Completer<WindGrid?>>[];

  @override
  Future<WindGrid?> windGrid(
    WeatherMapSource source,
    WindRequest request,
    WeatherFrame frame,
    DateTime now,
  ) {
    winds.add((request, frame.time));
    if (holdWind) {
      final answer = Completer<WindGrid?>();
      heldWind.add(answer);
      return answer.future;
    }
    return Future<WindGrid?>.value(windUp ? windGridOver(request.box) : null);
  }

  @override
  Future<bool> probe(String url) async {
    probes.add(url);
    return radarUp;
  }

  @override
  Future<Uint8List?> cloudImage(
    WeatherMapSource source,
    int region,
    WeatherFrame frame,
    DateTime now,
  ) async {
    images.add('${source.id}.$region@${frame.time}');
    return cloudsUp ? Uint8List.fromList(<int>[1, 2, 3]) : null;
  }

  @override
  Future<Uint8List?> cloudDetailImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now,
  ) {
    details.add(box);
    if (holdDetails) {
      final answer = Completer<Uint8List?>();
      held.add(answer);
      return answer.future;
    }
    return Future<Uint8List?>.value(
      cloudsUp ? Uint8List.fromList(<int>[4, 5, 6]) : null,
    );
  }
}

/// A steady west wind of 5 m/s (blowing east) over [box], on the model's
/// grid.
WindGrid windGridOver(BoundingBox box) {
  final columns = ((box.east - box.west) / windGridStep).round() + 1;
  final rows = ((box.north - box.south) / windGridStep).round() + 1;
  return WindGrid(
    lon0: box.west,
    lat0: box.north,
    lonStep: windGridStep,
    latStep: -windGridStep,
    columns: columns,
    rows: rows,
    u: Float32List(columns * rows)..fillRange(0, columns * rows, 5),
    v: Float32List(columns * rows),
  );
}

BoundingBox _view(double lon, double lat) => BoundingBox(
  south: lat - 0.2,
  west: lon - 0.2,
  north: lat + 0.2,
  east: lon + 0.2,
);

/// A DWD frame of [box] drawn soft, as the fetcher hands it over: a PNG
/// whose coverage says the radars measure where [measures] holds for a
/// column's middle longitude.
Uint8List _dwdFrame(BoundingBox box, bool Function(double lon) measures) {
  const width = 32;
  const height = 8;
  final covered = Uint8List(width * height);
  for (var x = 0; x < width; x++) {
    final lon = box.west + (x + 0.5) / width * (box.east - box.west);
    if (!measures(lon)) continue;
    for (var y = 0; y < height; y++) {
      covered[y * width + x] = 1;
    }
  }
  return encodePngRgba(
    width,
    height,
    Uint8List(width * height * 4),
    coverage: covered,
  );
}

final BoundingBox berlin = _view(13.4, 52.5);
final BoundingBox newYork = _view(-74, 40.7);

void main() {
  late FakeMapController map;
  late _Fetcher fetcher;
  late DateTime now;
  late WeatherMapDriver driver;

  setUp(() {
    map = FakeMapController()..visibleBounds = berlin;
    fetcher = _Fetcher();
    now = DateTime.utc(2026, 10, 10, 14, 42);
    driver = WeatherMapDriver(fetcher: fetcher, clock: () => now);
  });

  void configure({
    bool radar = false,
    bool clouds = false,
    bool wind = false,
    int offset = 0,
    List<WeatherMapSource>? sources,
    RadarStyle radarStyle = RadarStyle.measured,
  }) => driver.configure(
    settings: WeatherMapSettings(radar: radar, clouds: clouds, wind: wind),
    sources: sources ?? defaultWeatherMapSources,
    offsetMinutes: offset,
    radarStyle: radarStyle,
  );

  List<String> drawn() => <String>[
    for (final layer in map.weatherLayers) layer.id,
  ];

  test('off, nothing is drawn or asked', () {
    fakeAsync((async) {
      configure();
      driver.attach(map);
      async.flushMicrotasks();
      expect(map.weatherLayers, isEmpty);
      expect(fetcher.probes, isEmpty);
      driver.dispose();
    });
  });

  test('radar over Germany: the DWD frame of now, probed once', () {
    fakeAsync((async) {
      configure(radar: true);
      driver.attach(map);
      async.flushMicrotasks();
      expect(drawn(), <String>['radar_dwd']);
      expect(
        map.weatherLayers.single.tiles,
        contains('time=2026-10-10T14:35:00.000Z'),
      );
      expect(
        map.weatherLayers.single.attribution,
        'Radar: Deutscher Wetterdienst (CC BY 4.0)',
      );
      expect(fetcher.probes, hasLength(1));
      // Inside the radar's reach: no satellite asked for under it.
      expect(fetcher.radarImages, isEmpty);
      expect(driver.status.value.centre, berlin.center);
      expect(driver.status.value.at, now);
      expect(driver.status.value.failed, isEmpty);
      // A move within the coverage asks nothing new.
      map.emitCameraIdle();
      async.flushMicrotasks();
      expect(fetcher.probes, hasLength(1));
      expect(map.weatherLayerCalls, hasLength(1));
      driver.dispose();
    });
  });

  test('out of the coverage the layer goes; back in, it is probed again', () {
    fakeAsync((async) {
      configure(radar: true);
      driver.attach(map);
      async.flushMicrotasks();
      map.visibleBounds = _view(100, 10);
      map.emitCameraIdle();
      async.flushMicrotasks();
      expect(map.weatherLayers, isEmpty);
      map.visibleBounds = berlin;
      map.emitCameraIdle();
      async.flushMicrotasks();
      expect(drawn(), <String>['radar_dwd']);
      expect(fetcher.probes, hasLength(2));
      driver.dispose();
    });
  });

  test('a moment ahead: over New York the global model, over Germany the '
      'nowcast', () {
    fakeAsync((async) {
      map.visibleBounds = newYork;
      configure(radar: true);
      driver.attach(map);
      async.flushMicrotasks();
      expect(drawn(), <String>['radar_noaa']);
      configure(radar: true, offset: 30);
      async.flushMicrotasks();
      // NOAA has no moment ahead; the global ICON, as an image, for the six
      // hours up to 18 UTC that 15:12 falls in.
      expect(fetcher.radarImages.single.$1, 'rain_icon');
      expect(fetcher.radarImages.single.$3, DateTime.utc(2026, 10, 10, 18));
      expect(drawn(), <String>['rain_icon']);
      expect(
        map.weatherLayers.single.attribution,
        'Forecast: Deutscher Wetterdienst (CC BY 4.0)',
      );
      // Over Germany the nowcast, inside its reach alone.
      map.visibleBounds = berlin;
      map.emitCameraIdle();
      async.flushMicrotasks();
      expect(drawn(), <String>['radar_dwd']);
      expect(
        map.weatherLayers.single.tiles,
        contains('time=2026-10-10T15:05:00.000Z'),
      );
      // Three hours on, the nowcast is over: ICON-EU, for the hour 17 UTC.
      configure(radar: true, offset: 180);
      async.flushMicrotasks();
      expect(drawn(), <String>['rain_icon_eu']);
      expect(fetcher.radarImages.last.$3, DateTime.utc(2026, 10, 10, 18));
      expect(fetcher.radarJobs.last.$2, isEmpty);
      driver.dispose();
    });
  });

  test('at the edge of the DWD\'s reach, the satellite fills in around the '
      'radar, masked by it; ahead the model does', () {
    fakeAsync((async) {
      // Strasbourg to Nancy: half in reach, half beyond.
      map.visibleBounds = BoundingBox(
        south: 48.2,
        west: 6.0,
        north: 48.9,
        east: 7.8,
      );
      configure(radar: true);
      driver.attach(map);
      async.flushMicrotasks();
      expect(fetcher.radarImages.single.$1, 'rain_hsaf');
      // The newest ten-minute frame at least 25 minutes old.
      expect(fetcher.radarImages.single.$3, DateTime.utc(2026, 10, 10, 14, 10));
      expect(fetcher.radarJobs.single.$2, '-radar_dwd');
      expect(drawn(), <String>['radar_dwd', 'rain_hsaf']);
      configure(radar: true, offset: 45);
      async.flushMicrotasks();
      expect(fetcher.radarImages.last.$1, 'rain_icon_eu');
      expect(fetcher.radarImages.last.$3, DateTime.utc(2026, 10, 10, 16));
      expect(fetcher.radarJobs.last.$2, '-radar_dwd');
      expect(drawn(), <String>['radar_dwd', 'rain_icon_eu']);
      driver.dispose();
    });
  });

  test('a radar that does not answer is reported until it does again', () {
    fakeAsync((async) {
      fetcher.radarUp = false;
      configure(radar: true);
      driver.attach(map);
      async.flushMicrotasks();
      expect(driver.status.value.failed, <WeatherKind>{WeatherKind.radar});
      // Still drawn: the tiles may come back by themselves.
      expect(drawn(), <String>['radar_dwd']);
      fetcher.radarUp = true;
      now = now.add(radarRefreshInterval);
      async.elapse(radarRefreshInterval);
      expect(fetcher.probes, hasLength(2));
      expect(driver.status.value.failed, isEmpty);
      expect(
        map.weatherLayers.single.tiles,
        contains('time=2026-10-10T14:40:00.000Z'),
      );
      driver.dispose();
    });
  });

  test('no refresh while the app is in the background', () {
    fakeAsync((async) {
      configure(radar: true);
      driver.attach(map);
      async.flushMicrotasks();
      driver.setForeground(false);
      async.elapse(radarRefreshInterval * 3);
      expect(fetcher.probes, hasLength(1));
      driver.setForeground(true);
      async.flushMicrotasks();
      expect(fetcher.probes, hasLength(2));
      driver.dispose();
    });
  });

  test('clouds over Europe: one image of the region, under the rain', () {
    fakeAsync((async) {
      configure(radar: true, clouds: true);
      driver.attach(map);
      async.flushMicrotasks();
      expect(drawn(), <String>['clouds_eumetsat.0', 'radar_dwd']);
      final clouds = map.weatherLayers.first;
      expect(clouds.image, isNotNull);
      expect(clouds.imageBox, eumetsatClouds.coverage.single);
      expect(
        clouds.attribution,
        'Clouds: Contains modified EUMETSAT Meteosat data 2026',
      );
      expect(fetcher.images, <String>[
        'clouds_eumetsat.0@${DateTime.utc(2026, 10, 10, 14)}',
      ]);
      expect(driver.status.value.cloudsFrame, DateTime.utc(2026, 10, 10, 14));
      // The same hour is not asked again.
      now = now.add(cloudsRefreshInterval);
      async.elapse(cloudsRefreshInterval);
      expect(fetcher.images, hasLength(1));
      driver.dispose();
    });
  });

  test('clouds that do not come are reported; the next refresh recovers', () {
    fakeAsync((async) {
      fetcher.cloudsUp = false;
      configure(clouds: true);
      driver.attach(map);
      async.flushMicrotasks();
      expect(map.weatherLayers, isEmpty);
      expect(driver.status.value.failed, <WeatherKind>{WeatherKind.clouds});
      // Not asked again with every move of the map.
      map.emitCameraIdle();
      async.flushMicrotasks();
      expect(fetcher.images, hasLength(1));
      fetcher.cloudsUp = true;
      async.elapse(cloudsRefreshInterval);
      expect(fetcher.images, hasLength(2));
      expect(driver.status.value.failed, isEmpty);
      expect(drawn(), <String>['clouds_eumetsat.0']);
      driver.dispose();
    });
  });

  test('a failure elsewhere is not reported over the view', () {
    fakeAsync((async) {
      fetcher.radarUp = false;
      configure(radar: true);
      driver.attach(map);
      async.flushMicrotasks();
      expect(driver.status.value.failed, isNotEmpty);
      map.visibleBounds = _view(100, 10);
      map.emitCameraIdle();
      async.flushMicrotasks();
      expect(driver.status.value.failed, isEmpty);
      driver.dispose();
    });
  });

  test('a source the mirror switched off is not drawn; the satellite '
      'takes its place', () {
    fakeAsync((async) {
      configure(
        radar: true,
        sources: applyWeatherOverride(defaultWeatherMapSources, [
          {'id': 'radar_dwd', 'enabled': false},
        ]),
      );
      driver.attach(map);
      async.flushMicrotasks();
      expect(drawn(), <String>['rain_hsaf']);
      expect(fetcher.radarJobs.single.$2, isEmpty);
      driver.dispose();
    });
  });

  test('switched off, the layers go', () {
    fakeAsync((async) {
      configure(radar: true, clouds: true);
      driver.attach(map);
      async.flushMicrotasks();
      configure();
      async.flushMicrotasks();
      expect(map.weatherLayers, isEmpty);
      expect(driver.status.value.cloudsFrame, isNull);
      driver.dispose();
    });
  });

  group('cloud detail', () {
    /// The view moves to [box] at [zoom] and comes to rest.
    void rest(FakeAsync async, BoundingBox box, double zoom) {
      map
        ..visibleBounds = box
        ..zoom = zoom;
      map.emitCameraIdle();
      async.flushMicrotasks();
    }

    WeatherLayer? detailLayer() => map.weatherLayers
        .where((l) => l.id == 'clouds_eumetsat.detail')
        .firstOrNull;

    test('asked for once the camera rests at zoom 6, over the region', () {
      fakeAsync((async) {
        map.zoom = 8;
        configure(radar: true, clouds: true);
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.details, isEmpty);
        async.elapse(cloudDetailDebounce - const Duration(milliseconds: 1));
        expect(fetcher.details, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(fetcher.details, hasLength(1));
        expect(drawn(), <String>[
          'clouds_eumetsat.0',
          'clouds_eumetsat.detail',
          'radar_dwd',
        ]);
        final box = detailLayer()!.imageBox!;
        expect(box.west, lessThan(berlin.west));
        expect(box.north, greaterThan(berlin.north));
        expect(detailLayer()!.image, <int>[4, 5, 6]);
        expect(
          detailLayer()!.attribution,
          'Clouds: Contains modified EUMETSAT Meteosat data 2026',
        );
        // A small move inside the box, or a little zoom, asks nothing new.
        rest(async, _view(13.45, 52.52), 8.5);
        async.elapse(cloudDetailDebounce);
        expect(fetcher.details, hasLength(1));
        driver.dispose();
      });
    });

    test('not below zoom 6; zoomed out, the detail goes', () {
      fakeAsync((async) {
        map.zoom = 5;
        configure(clouds: true);
        driver.attach(map);
        async.elapse(cloudDetailDebounce * 2);
        expect(fetcher.details, isEmpty);
        rest(async, berlin, 7);
        async.elapse(cloudDetailDebounce);
        expect(detailLayer(), isNotNull);
        rest(async, berlin, 5.5);
        expect(detailLayer(), isNull);
        expect(drawn(), <String>['clouds_eumetsat.0']);
        driver.dispose();
      });
    });

    test('switched off, the detail goes and is not asked for', () {
      fakeAsync((async) {
        map.zoom = 8;
        configure(clouds: true);
        driver.attach(map);
        async.elapse(cloudDetailDebounce);
        expect(detailLayer(), isNotNull);
        configure();
        async.elapse(cloudDetailDebounce);
        expect(map.weatherLayers, isEmpty);
        rest(async, _view(2.35, 48.85), 8);
        async.elapse(cloudDetailDebounce);
        expect(fetcher.details, hasLength(1));
        driver.dispose();
      });
    });

    test('leaving the box or zooming on asks anew; the old one stays '
        'until the new one is in', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.holdDetails = true;
        configure(clouds: true);
        driver.attach(map);
        async.elapse(cloudDetailDebounce);
        fetcher.held.single.complete(Uint8List.fromList(<int>[1]));
        async.flushMicrotasks();
        final first = detailLayer()!;
        // Paris is far outside Berlin's box.
        rest(async, _view(2.35, 48.85), 8);
        async.elapse(cloudDetailDebounce);
        expect(fetcher.details, hasLength(2));
        expect(detailLayer(), first);
        fetcher.held.last.complete(Uint8List.fromList(<int>[2]));
        async.flushMicrotasks();
        expect(detailLayer()!.frameKey, isNot(first.frameKey));
        expect(detailLayer()!.image, <int>[2]);
        // Zoomed in by 1.5 over the same place: a finer one.
        rest(async, _view(2.35, 48.85), 9.5);
        async.elapse(cloudDetailDebounce);
        expect(fetcher.details, hasLength(3));
        driver.dispose();
      });
    });

    test('one request at a time; an answer for a view left is dropped', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.holdDetails = true;
        configure(clouds: true);
        driver.attach(map);
        async.elapse(cloudDetailDebounce);
        expect(fetcher.details, hasLength(1));
        rest(async, _view(2.35, 48.85), 8);
        async.elapse(cloudDetailDebounce);
        rest(async, _view(-3.7, 40.4), 8); // Madrid
        async.elapse(cloudDetailDebounce);
        expect(fetcher.details, hasLength(1));
        // Berlin's answer comes when the view is over Madrid: not drawn,
        // and Madrid is asked for next.
        fetcher.held.single.complete(Uint8List.fromList(<int>[1]));
        async.flushMicrotasks();
        expect(detailLayer(), isNull);
        expect(fetcher.details, hasLength(2));
        expect(fetcher.details.last.west, lessThan(-3.9));
        expect(fetcher.details.last.east, greaterThan(-3.5));
        fetcher.held.last.complete(Uint8List.fromList(<int>[3]));
        async.flushMicrotasks();
        expect(detailLayer()!.image, <int>[3]);
        driver.dispose();
      });
    });

    test('a detail that does not come is reported, not asked again '
        'until the refresh', () {
      fakeAsync((async) {
        map.zoom = 8;
        configure(clouds: true);
        driver.attach(map);
        async.flushMicrotasks();
        fetcher.cloudsUp = false;
        async.elapse(cloudDetailDebounce);
        expect(driver.status.value.failed, <WeatherKind>{WeatherKind.clouds});
        rest(async, berlin, 8);
        async.elapse(cloudDetailDebounce);
        expect(fetcher.details, hasLength(1));
        fetcher.cloudsUp = true;
        async.elapse(cloudsRefreshInterval);
        expect(fetcher.details, hasLength(2));
        expect(driver.status.value.failed, isEmpty);
        expect(detailLayer(), isNotNull);
        driver.dispose();
      });
    });

    test('the next hour brings a new detail', () {
      fakeAsync((async) {
        map.zoom = 8;
        configure(clouds: true);
        driver.attach(map);
        async.elapse(cloudDetailDebounce);
        final first = detailLayer()!;
        now = now.add(const Duration(hours: 1));
        async.elapse(cloudsRefreshInterval);
        expect(fetcher.details, hasLength(2));
        expect(detailLayer()!.frameKey, isNot(first.frameKey));
        driver.dispose();
      });
    });
  });

  group('soft radar', () {
    void soft({int offset = 0, bool clouds = false}) => configure(
      radar: true,
      clouds: clouds,
      offset: offset,
      radarStyle: RadarStyle.soft,
    );

    /// The view moves to [box] at [zoom] and comes to rest.
    void rest(FakeAsync async, BoundingBox box, double zoom) {
      map
        ..visibleBounds = box
        ..zoom = zoom;
      map.emitCameraIdle();
      async.flushMicrotasks();
    }

    group('cut by the DWD\'s frame', () {
      // Strasbourg to Nancy: the DWD's reach ends in the view.
      const edge = BoundingBox(south: 48.2, west: 6.0, north: 48.9, east: 7.8);
      bool cutAt(List<RainCoverage> coverages, double lon) => coverages.any(
        (c) => c.coversMercator(mercatorX(lon), mercatorY(48.5)),
      );

      test('the satellite waits for the frame of its step and is cut where '
          'it measures; ahead, the model by the nowcast\'s own, which '
          'reaches less', () {
        fakeAsync((async) {
          map
            ..visibleBounds = edge
            ..zoom = 8;
          fetcher.holdRadar = true;
          soft();
          driver.attach(map);
          async.flushMicrotasks();
          // The DWD's frame first; the satellite waits for it.
          expect(fetcher.radarImages.map((r) => r.$1), <String>['radar_dwd']);
          final nowBox = fetcher.radarImages.single.$2;
          fetcher.heldRadar.single.complete(
            _dwdFrame(nowBox, (lon) => lon > 7),
          );
          async.flushMicrotasks();
          expect(fetcher.radarImages.last.$1, 'rain_hsaf');
          final hsafCut = fetcher.radarCoverages.last;
          expect(cutAt(hsafCut, 7.4), isTrue);
          expect(cutAt(hsafCut, 6.6), isFalse);
          final hsafKey = fetcher.radarJobs.last.$2;
          expect(hsafKey, startsWith('-radar_dwd~'));
          fetcher.heldRadar.last.complete(Uint8List.fromList(<int>[5]));
          async.flushMicrotasks();
          expect(drawn(), <String>['radar_dwd', 'rain_hsaf']);

          // Half an hour on: the nowcast's frame first, ICON-EU waits.
          soft(offset: 30);
          async.flushMicrotasks();
          expect(fetcher.radarImages.last.$1, 'radar_dwd');
          expect(
            fetcher.radarImages.where((r) => r.$1 == 'rain_icon_eu'),
            isEmpty,
          );
          final aheadBox = fetcher.radarImages.last.$2;
          fetcher.heldRadar.last.complete(
            _dwdFrame(aheadBox, (lon) => lon > 7.5),
          );
          async.flushMicrotasks();
          expect(fetcher.radarImages.last.$1, 'rain_icon_eu');
          final iconCut = fetcher.radarCoverages.last;
          // Where the nowcast no longer reaches, the model fills in.
          expect(cutAt(iconCut, 7.2), isFalse);
          expect(cutAt(iconCut, 7.7), isTrue);
          expect(fetcher.radarJobs.last.$2, startsWith('-radar_dwd~'));
          expect(fetcher.radarJobs.last.$2, isNot(hsafKey));
          fetcher.heldRadar.last.complete(Uint8List.fromList(<int>[6]));
          async.flushMicrotasks();
          expect(drawn(), <String>['radar_dwd', 'rain_icon_eu']);

          // A new frame of the step (the refresh) cuts it anew.
          now = now.add(radarRefreshInterval);
          async.elapse(radarRefreshInterval);
          expect(fetcher.radarImages.last.$1, 'radar_dwd');
          fetcher.heldRadar.last.complete(
            _dwdFrame(fetcher.radarImages.last.$2, (lon) => lon > 7.3),
          );
          async.flushMicrotasks();
          expect(fetcher.radarImages.last.$1, 'rain_icon_eu');
          expect(cutAt(fetcher.radarCoverages.last, 7.4), isTrue);
          driver.dispose();
        });
      });

      test('where the frame measures all over the view, nothing after it is '
          'asked for or drawn', () {
        fakeAsync((async) {
          map.zoom = 8;
          fetcher.radarAnswer = (source, box) => source.id == 'radar_dwd'
              ? _dwdFrame(box, (_) => true)
              : Uint8List.fromList(<int>[5]);
          for (final offset in <int>[0, 30, 90]) {
            soft(offset: offset);
            driver.attach(map);
            async.flushMicrotasks();
          }
          expect(fetcher.radarImages.map((r) => r.$1).toSet(), <String>{
            'radar_dwd',
          });
          expect(drawn(), <String>['radar_dwd']);
          driver.dispose();
        });
      });

      test('a frame that does not come: its fixed reach stands in', () {
        fakeAsync((async) {
          map
            ..visibleBounds = edge
            ..zoom = 8;
          fetcher.radarAnswer = (source, box) =>
              source.id == 'radar_dwd' ? null : Uint8List.fromList(<int>[5]);
          soft();
          driver.attach(map);
          async.flushMicrotasks();
          expect(fetcher.radarImages.map((r) => r.$1), <String>[
            'radar_dwd',
            'rain_hsaf',
          ]);
          expect(fetcher.radarJobs.last.$2, '-radar_dwd');
          expect(fetcher.radarCoverages.last, isEmpty);
          // Inside the reach, nothing after it.
          rest(async, berlin, 8);
          async.elapse(radarImageDebounce);
          expect(
            fetcher.radarImages.where((r) => r.$1 == 'rain_hsaf'),
            hasLength(1),
          );
          driver.dispose();
        });
      });
    });

    test('one image of the view at once, drawn as an image, no probe', () {
      fakeAsync((async) {
        map.zoom = 8;
        soft();
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(1));
        final (id, box, time) = fetcher.radarImages.single;
        expect(id, 'radar_dwd');
        expect(time, DateTime.utc(2026, 10, 10, 14, 35));
        // The view and its margin.
        expect(box.west, lessThan(berlin.west));
        expect(box.east, greaterThan(berlin.east));
        expect(fetcher.probes, isEmpty);
        final layer = map.weatherLayers.single;
        expect(layer.id, 'radar_dwd');
        expect(layer.kind, WeatherKind.radar);
        expect(layer.image, <int>[7, 8, 9]);
        expect(layer.tiles, isNull);
        expect(layer.imageBox, box);
        expect(layer.attribution, 'Radar: Deutscher Wetterdienst (CC BY 4.0)');
        expect(driver.status.value.failed, isEmpty);
        driver.dispose();
      });
    });

    test('asked for once the camera rests, not for a move inside the box', () {
      fakeAsync((async) {
        map.zoom = 8;
        soft();
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(1));
        // A little move: inside the image's box.
        rest(async, _view(13.42, 52.5), 8.2);
        async.elapse(radarImageDebounce);
        expect(fetcher.radarImages, hasLength(1));
        // Off to Munich: once the camera has rested.
        rest(async, _view(11.6, 48.1), 8);
        async.elapse(radarImageDebounce - const Duration(milliseconds: 1));
        expect(fetcher.radarImages, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(fetcher.radarImages, hasLength(2));
        expect(
          fetcher.radarImages.last.$2.contains(LatLng(48.1, 11.6)),
          isTrue,
        );
        // The new image replaces the old under the same layer.
        expect(map.weatherLayers.single.imageBox, fetcher.radarImages.last.$2);
        driver.dispose();
      });
    });

    test('the time control asks at once for its moment; the image shown '
        'stays until the new one is in', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.holdRadar = true;
        soft();
        driver.attach(map);
        async.flushMicrotasks();
        fetcher.heldRadar.single.complete(Uint8List.fromList(<int>[1]));
        async.flushMicrotasks();
        expect(map.weatherLayers.single.image, <int>[1]);
        soft(offset: 30);
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(2));
        expect(fetcher.radarImages.last.$3, DateTime.utc(2026, 10, 10, 15, 5));
        // Still the last one while the new one is out.
        expect(map.weatherLayers.single.image, <int>[1]);
        fetcher.heldRadar.last.complete(Uint8List.fromList(<int>[2]));
        async.flushMicrotasks();
        expect(map.weatherLayers.single.image, <int>[2]);
        driver.dispose();
      });
    });

    test('the refresh asks for the newer frame', () {
      fakeAsync((async) {
        map.zoom = 8;
        soft();
        driver.attach(map);
        async.flushMicrotasks();
        now = now.add(radarRefreshInterval);
        async.elapse(radarRefreshInterval);
        expect(fetcher.radarImages, hasLength(2));
        expect(fetcher.radarImages.last.$3, DateTime.utc(2026, 10, 10, 14, 40));
        // Nothing newer five minutes on, when the clock has not moved.
        async.elapse(radarRefreshInterval);
        expect(fetcher.radarImages, hasLength(2));
        driver.dispose();
      });
    });

    test('one request per source at a time; an answer for a view left is '
        'dropped', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.holdRadar = true;
        soft();
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(1));
        rest(async, _view(11.6, 48.1), 8);
        async.elapse(radarImageDebounce);
        // Still one out: the next waits.
        expect(fetcher.radarImages, hasLength(1));
        fetcher.heldRadar.single.complete(Uint8List.fromList(<int>[1]));
        async.flushMicrotasks();
        // Berlin's is dropped, Munich's asked for.
        expect(map.weatherLayers, isEmpty);
        expect(fetcher.radarImages, hasLength(2));
        fetcher.heldRadar.last.complete(Uint8List.fromList(<int>[2]));
        async.flushMicrotasks();
        expect(map.weatherLayers.single.image, <int>[2]);
        driver.dispose();
      });
    });

    test('an image that does not come is reported; the refresh recovers', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.radarImagesUp = false;
        soft();
        driver.attach(map);
        async.flushMicrotasks();
        expect(driver.status.value.failed, {WeatherKind.radar});
        expect(map.weatherLayers, isEmpty);
        // Not asked again for the same view before the refresh.
        map.emitCameraIdle();
        async.elapse(radarImageDebounce);
        expect(fetcher.radarImages, hasLength(1));
        fetcher.radarImagesUp = true;
        async.elapse(radarRefreshInterval);
        expect(fetcher.radarImages, hasLength(2));
        expect(driver.status.value.failed, isEmpty);
        expect(map.weatherLayers.single.image, <int>[7, 8, 9]);
        driver.dispose();
      });
    });

    test('ahead over the US, the model\'s image instead of NOAA\'s', () {
      fakeAsync((async) {
        map
          ..visibleBounds = newYork
          ..zoom = 8;
        soft(offset: 30);
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.radarImages.single.$1, 'rain_icon');
        expect(fetcher.radarJobs.single, (RadarStyle.soft, ''));
        soft();
        async.flushMicrotasks();
        expect(fetcher.radarImages.last.$1, 'radar_noaa');
        expect(drawn(), <String>['radar_noaa']);
        driver.dispose();
      });
    });

    test('a forecast that does not come is reported as the forecast', () {
      fakeAsync((async) {
        map
          ..visibleBounds = newYork
          ..zoom = 8;
        fetcher.radarImagesUp = false;
        soft(offset: 60);
        driver.attach(map);
        async.flushMicrotasks();
        expect(driver.status.value.failedRain, <RainRole>{RainRole.model});
        expect(driver.status.value.failed, <WeatherKind>{WeatherKind.radar});
        driver.dispose();
      });
    });

    test('as measured, the satellite and the models are still images, as '
        'see-through as the tiles', () {
      fakeAsync((async) {
        map
          ..visibleBounds = newYork
          ..zoom = 8;
        configure(radar: true, offset: 60);
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.radarJobs.single, (RadarStyle.measured, ''));
        final layer = map.weatherLayers.single;
        expect(layer.image, isNotNull);
        expect(layer.opacity, 0.75);
        driver.dispose();
      });
    });

    test('above the clouds', () {
      fakeAsync((async) {
        map.zoom = 5;
        soft(clouds: true);
        driver.attach(map);
        async.flushMicrotasks();
        expect(drawn(), <String>['clouds_eumetsat.0', 'radar_dwd']);
        expect(map.weatherLayers.last.image, <int>[7, 8, 9]);
        driver.dispose();
      });
    });

    test('switching the look swaps tiles and image, the tiles staying until '
        'the image is in', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.holdRadar = true;
        configure(radar: true);
        driver.attach(map);
        async.flushMicrotasks();
        expect(map.weatherLayers.single.tiles, isNotNull);
        expect(fetcher.probes, hasLength(1));
        soft();
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(1));
        // The tiles until the image comes.
        expect(map.weatherLayers.single.tiles, isNotNull);
        fetcher.heldRadar.single.complete(Uint8List.fromList(<int>[3]));
        async.flushMicrotasks();
        expect(map.weatherLayers.single.image, <int>[3]);
        expect(map.weatherLayers.single.tiles, isNull);
        // And back: the tiles at once, probed afresh.
        configure(radar: true);
        async.flushMicrotasks();
        expect(map.weatherLayers.single.tiles, isNotNull);
        expect(fetcher.probes, hasLength(2));
        driver.dispose();
      });
    });

    test('a source without an image request stays on tiles', () {
      fakeAsync((async) {
        map.zoom = 8;
        final tilesOnly = WeatherMapSource(
          id: 'radar_x',
          kind: WeatherKind.radar,
          urlTemplate: 'https://radar.example/{z}/{x}/{y}.png',
          coverage: dwdRadar.coverage,
          attribution: 'Radar: X',
        );
        configure(
          radar: true,
          sources: <WeatherMapSource>[tilesOnly],
          radarStyle: RadarStyle.soft,
        );
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.radarImages, isEmpty);
        expect(map.weatherLayers.single.tiles, isNotNull);
        expect(fetcher.probes, hasLength(1));
        driver.dispose();
      });
    });
    test('Now, an hour on and back to Now draws Now\'s image again, also '
        'of a source the hour ahead does not use', () {
      fakeAsync((async) {
        // Over New York: NOAA's radar now, the global model ahead.
        map
          ..visibleBounds = newYork
          ..zoom = 8;
        soft();
        driver.attach(map);
        async.flushMicrotasks();
        final nowImage = fetcher.radarImages.single;
        expect(nowImage.$1, 'radar_noaa');
        soft(offset: 60);
        async.flushMicrotasks();
        expect(fetcher.radarImages.last.$1, 'rain_icon');
        expect(drawn(), <String>['rain_icon']);
        final asked = fetcher.radarImages.length;
        soft();
        async.flushMicrotasks();
        // Asked again (the fetcher's cache answers it) and drawn.
        expect(fetcher.radarImages, hasLength(asked + 1));
        expect(fetcher.radarImages.last, nowImage);
        expect(drawn(), <String>['radar_noaa']);
        expect(map.weatherLayers.single.imageBox, nowImage.$2);
        driver.dispose();
      });
    });

    test('an answer for Now that comes after the time control moved on is '
        'asked for again back at Now', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.holdRadar = true;
        soft();
        driver.attach(map);
        async.flushMicrotasks();
        soft(offset: 60);
        async.flushMicrotasks();
        // Now's comes while the hour ahead is shown: dropped.
        fetcher.heldRadar.single.complete(Uint8List.fromList(<int>[1]));
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(2));
        soft();
        async.flushMicrotasks();
        fetcher.heldRadar.last.complete(Uint8List.fromList(<int>[2]));
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(3));
        expect(fetcher.radarImages.last, fetcher.radarImages.first);
        fetcher.heldRadar.last.complete(Uint8List.fromList(<int>[3]));
        async.flushMicrotasks();
        expect(map.weatherLayers.single.image, <int>[3]);
        driver.dispose();
      });
    });

    test('a failed image is not asked again for the same view and step '
        'until the refresh, another step asks', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.radarImagesUp = false;
        soft();
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(1));
        map.emitCameraIdle();
        async.elapse(radarImageDebounce);
        expect(fetcher.radarImages, hasLength(1));
        // Another step is asked for, and back at Now so is Now again.
        soft(offset: 60);
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(2));
        soft();
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(3));
        map.emitCameraIdle();
        async.elapse(radarImageDebounce);
        expect(fetcher.radarImages, hasLength(3));
        driver.dispose();
      });
    });

    test('zoomed out below $weatherImageMinZoom no image of the view is '
        'asked for, and those shown go', () {
      fakeAsync((async) {
        map.zoom = 8;
        soft(clouds: true);
        driver.attach(map);
        async.elapse(cloudDetailDebounce);
        expect(fetcher.radarImages, hasLength(1));
        expect(fetcher.details, hasLength(1));
        expect(
          map.weatherLayers.where((l) => l.kind == WeatherKind.radar),
          isNotEmpty,
        );
        rest(
          async,
          const BoundingBox(south: 25, west: -10, north: 70, east: 50),
          2.5,
        );
        async.elapse(cloudDetailDebounce);
        expect(fetcher.radarImages, hasLength(1));
        expect(fetcher.details, hasLength(1));
        // The region's clouds stay; the rain's image and the detail go.
        expect(drawn(), <String>['clouds_eumetsat.0']);
        // The satellite and the model ahead neither.
        soft(offset: 180, clouds: true);
        async.elapse(radarImageDebounce);
        expect(fetcher.radarImages, hasLength(1));
        expect(drawn(), <String>['clouds_eumetsat.0']);
        driver.dispose();
      });
    });

    test('the whole world, wider than the map\'s 360°: no box MapLibre '
        'cannot draw is asked for or drawn', () {
      for (final zoom in <double?>[null, 0, 1, 2.9, 3, 4]) {
        for (final offset in <int>[0, 60, 600]) {
          fakeAsync((async) {
            final world = const BoundingBox(
              south: -85,
              west: -540,
              north: 85,
              east: 540,
            );
            map
              ..visibleBounds = world
              ..zoom = zoom;
            soft(offset: offset, clouds: true);
            driver.attach(map);
            async.elapse(cloudDetailDebounce);
            for (final (id, box, _) in fetcher.radarImages) {
              expect(safeImageBox(box), isTrue, reason: '$id $box');
            }
            for (final box in fetcher.details) {
              expect(safeImageBox(box), isTrue, reason: '$box');
            }
            for (final layer in map.weatherLayers) {
              final box = layer.imageBox;
              if (box == null) continue;
              expect(safeImageBox(box), isTrue, reason: '${layer.id} $box');
            }
            // A view of a wide screen at zoom 3, past the antimeridian.
            rest(
              async,
              const BoundingBox(south: -60, west: -260, north: 60, east: -60),
              3,
            );
            async.elapse(cloudDetailDebounce);
            for (final (id, box, _) in fetcher.radarImages) {
              expect(safeImageBox(box), isTrue, reason: '$id $box');
            }
            for (final layer in map.weatherLayers) {
              final box = layer.imageBox;
              if (box == null) continue;
              expect(safeImageBox(box), isTrue, reason: '${layer.id} $box');
            }
            driver.dispose();
          });
          fetcher = _Fetcher();
          driver = WeatherMapDriver(fetcher: fetcher, clock: () => now);
        }
      }
    });
  });

  group('wind', () {
    void rest(FakeAsync async, BoundingBox box, double zoom) {
      map
        ..visibleBounds = box
        ..zoom = zoom;
      map.emitCameraIdle();
      async.flushMicrotasks();
    }

    test('one grid of the view at the hour, its arrows over the view', () {
      fakeAsync((async) {
        map.zoom = 9;
        configure(wind: true);
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.winds, hasLength(1));
        final (request, time) = fetcher.winds.single;
        // Now is the hour now falls in.
        expect(time, DateTime.utc(2026, 10, 10, 14));
        expect(request.fits(berlin, 9), isTrue);
        final arrows = map.windArrows!;
        expect(arrows.arrows, isNotEmpty);
        // The test grid's west wind blows east.
        expect(arrows.arrows.every((a) => a.dir == 90 && a.ms == 5), isTrue);
        expect(arrows.attribution, 'Wind: Deutscher Wetterdienst (CC BY 4.0)');
        // No rain, no clouds, no probe.
        expect(map.weatherLayers, isEmpty);
        expect(fetcher.probes, isEmpty);
        expect(driver.status.value.failed, isEmpty);
        // A pan inside the box asks nothing; the arrows follow the view.
        rest(async, _view(13.45, 52.52), 9);
        async.elapse(windDebounce);
        expect(fetcher.winds, hasLength(1));
        expect(map.windArrows, isNot(arrows));
        driver.dispose();
      });
    });

    test('debounced on the camera, one in flight, an answer since left '
        'dropped', () {
      fakeAsync((async) {
        map.zoom = 9;
        fetcher.holdWind = true;
        configure(wind: true);
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.winds, hasLength(1));
        // Off to Paris while Berlin's is out: nothing more yet.
        rest(async, _view(2.35, 48.85), 9);
        async.elapse(windDebounce);
        expect(fetcher.winds, hasLength(1));
        // Berlin's comes, and is dropped; Paris's is asked for.
        fetcher.heldWind.first.complete(windGridOver(fetcher.winds[0].$1.box));
        async.flushMicrotasks();
        expect(map.windArrows, isNull);
        expect(fetcher.winds, hasLength(2));
        expect(fetcher.winds[1].$1.fits(_view(2.35, 48.85), 9), isTrue);
        fetcher.heldWind[1].complete(windGridOver(fetcher.winds[1].$1.box));
        async.flushMicrotasks();
        expect(map.windArrows!.arrows, isNotEmpty);
        // Several rests close together ask once, at the end.
        rest(async, berlin, 9);
        rest(async, _view(13.6, 52.6), 9);
        async.elapse(windDebounce ~/ 2);
        expect(fetcher.winds, hasLength(2));
        async.elapse(windDebounce);
        expect(fetcher.winds, hasLength(3));
        driver.dispose();
      });
    });

    test('not below zoom 3: no request, the arrows go', () {
      fakeAsync((async) {
        map.zoom = 2;
        configure(wind: true);
        driver.attach(map);
        async.elapse(windDebounce);
        expect(fetcher.winds, isEmpty);
        expect(map.windArrows, isNull);
        rest(async, berlin, 9);
        async.elapse(windDebounce);
        expect(map.windArrows, isNotNull);
        rest(async, berlin, 2.5);
        expect(map.windArrows, isNull);
        expect(fetcher.winds, hasLength(1));
        driver.dispose();
      });
    });

    test('the time control: another hour is another grid, the old arrows '
        'until it is in', () {
      fakeAsync((async) {
        map.zoom = 9;
        configure(wind: true);
        driver.attach(map);
        async.flushMicrotasks();
        final before = map.windArrows;
        fetcher.holdWind = true;
        // +15 min is still the same hour: nothing new.
        configure(wind: true, offset: 15);
        async.flushMicrotasks();
        expect(fetcher.winds, hasLength(1));
        configure(wind: true, offset: 180);
        async.flushMicrotasks();
        expect(fetcher.winds, hasLength(2));
        expect(fetcher.winds.last.$2, DateTime.utc(2026, 10, 10, 17));
        expect(map.windArrows, before);
        driver.dispose();
      });
    });

    test('from the cache of the fetcher when the step comes back', () {
      fakeAsync((async) {
        map.zoom = 9;
        configure(wind: true);
        driver.attach(map);
        async.flushMicrotasks();
        configure(wind: true, offset: 180);
        async.flushMicrotasks();
        configure(wind: true);
        async.flushMicrotasks();
        // The driver asks; the fetcher answers from its files.
        expect(fetcher.winds.map((w) => w.$2), <DateTime>[
          DateTime.utc(2026, 10, 10, 14),
          DateTime.utc(2026, 10, 10, 17),
          DateTime.utc(2026, 10, 10, 14),
        ]);
        driver.dispose();
      });
    });

    test('a service that does not answer says so, and is asked again with '
        'the refresh', () {
      fakeAsync((async) {
        map.zoom = 9;
        fetcher.windUp = false;
        configure(wind: true);
        driver.attach(map);
        async.flushMicrotasks();
        expect(driver.status.value.failed, <WeatherKind>{WeatherKind.wind});
        expect(map.windArrows, isNull);
        // Not asked again on every rest.
        rest(async, _view(13.45, 52.52), 9);
        async.elapse(windDebounce);
        expect(fetcher.winds, hasLength(1));
        // The refresh asks again, and it answers.
        fetcher.windUp = true;
        async.elapse(windRefreshInterval);
        expect(fetcher.winds, hasLength(2));
        expect(driver.status.value.failed, isEmpty);
        expect(map.windArrows!.arrows, isNotEmpty);
        driver.dispose();
      });
    });

    test('a new hour or an hour old: asked again with the refresh', () {
      fakeAsync((async) {
        map.zoom = 9;
        configure(wind: true);
        driver.attach(map);
        async.flushMicrotasks();
        now = now.add(const Duration(minutes: 20));
        async.elapse(windRefreshInterval);
        // 15:02: the next hour.
        expect(fetcher.winds.last.$2, DateTime.utc(2026, 10, 10, 15));
        expect(fetcher.winds, hasLength(2));
        driver.dispose();
      });
    });

    test('switched off, the arrows go and nothing is asked', () {
      fakeAsync((async) {
        map.zoom = 9;
        configure(wind: true, radar: true);
        driver.attach(map);
        async.flushMicrotasks();
        expect(map.windArrows, isNotNull);
        expect(drawn(), contains('radar_dwd'));
        configure(radar: true);
        async.flushMicrotasks();
        expect(map.windArrows, isNull);
        expect(drawn(), contains('radar_dwd'));
        rest(async, _view(2.35, 48.85), 9);
        async.elapse(windRefreshInterval);
        expect(fetcher.winds, hasLength(1));
        driver.dispose();
      });
    });

    test('a source the mirror turned off is not asked', () {
      fakeAsync((async) {
        map.zoom = 9;
        configure(
          wind: true,
          sources: <WeatherMapSource>[dwdWind.copyWith(enabled: false)],
        );
        driver.attach(map);
        async.elapse(windDebounce);
        expect(fetcher.winds, isEmpty);
        expect(map.windArrows, isNull);
        driver.dispose();
      });
    });

    test('detached, the arrows are taken off the map', () {
      fakeAsync((async) {
        map.zoom = 9;
        configure(wind: true);
        driver.attach(map);
        async.flushMicrotasks();
        driver.detach();
        async.flushMicrotasks();
        expect(map.windArrows, isNull);
        driver.dispose();
      });
    });
  });
}
