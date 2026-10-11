import 'dart:async';
import 'dart:math' as math;
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

  /// The fades each cloud source's last region image was asked with.
  final Map<String, List<CloudFade>> cloudFades = <String, List<CloudFade>>{};

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

  /// The newest frame each source's service says it has, by id; the
  /// sources asked, in order; and the sources whose images were refused
  /// (an XML error) and not yet taken.
  final Map<String, DateTime> newest = <String, DateTime>{};
  final List<String> newestAsked = <String>[];
  final Set<String> refused = <String>{};

  @override
  Future<DateTime?> newestFrame(WeatherMapSource source) {
    newestAsked.add(source.id);
    return Future<DateTime?>.value(newest[source.id]);
  }

  @override
  bool takeRefusal(String sourceId) => refused.remove(sourceId);

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
    // A little stronger each hour on from 14 UTC, so hours tell apart.
    final hours = frame.time == null ? 0 : frame.time!.hour - 14;
    return Future<WindGrid?>.value(
      windUp ? windGridOver(request.box, u: 5 + 0.5 * hours) : null,
    );
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
    DateTime now, {
    List<CloudFade> fades = const <CloudFade>[],
  }) async {
    images.add('${source.id}.$region@${frame.time}');
    cloudFades[source.id] = fades;
    return cloudsUp ? Uint8List.fromList(<int>[1, 2, 3]) : null;
  }

  @override
  Future<Uint8List?> cloudDetailImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now, {
    List<CloudFade> fades = const <CloudFade>[],
  }) {
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

/// A steady west wind of [u] m/s (blowing east) over [box], on the model's
/// grid.
WindGrid windGridOver(BoundingBox box, {double u = 5}) {
  final columns = ((box.east - box.west) / windGridStep).round() + 1;
  final rows = ((box.north - box.south) / windGridStep).round() + 1;
  return WindGrid(
    lon0: box.west,
    lat0: box.north,
    lonStep: windGridStep,
    latStep: -windGridStep,
    columns: columns,
    rows: rows,
    u: Float32List(columns * rows)..fillRange(0, columns * rows, u),
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
      covered[y * width + x] = 255;
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
    driver = WeatherMapDriver(
      fetcher: fetcher,
      clock: () => now,
      prefetch: false,
    );
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

  /// The layers seen on the map: those kept unseen for the time control
  /// left out.
  List<WeatherLayer> shown() => <WeatherLayer>[
    for (final layer in map.weatherLayers)
      if (layer.visible) layer,
  ];

  List<String> drawn() => <String>[for (final layer in shown()) layer.id];

  test('off, nothing is drawn or asked', () {
    fakeAsync((async) {
      configure();
      driver.attach(map);
      async.flushMicrotasks();
      expect(shown(), isEmpty);
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
      expect(shown().single.tiles, contains('time=2026-10-10T14:35:00.000Z'));
      expect(
        shown().single.attribution,
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
      expect(shown(), isEmpty);
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
        shown().single.attribution,
        'Forecast: Deutscher Wetterdienst (CC BY 4.0)',
      );
      // Over Germany the nowcast, inside its reach alone.
      map.visibleBounds = berlin;
      map.emitCameraIdle();
      async.flushMicrotasks();
      expect(drawn(), <String>['radar_dwd']);
      expect(shown().single.tiles, contains('time=2026-10-10T15:05:00.000Z'));
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
      expect(shown().single.tiles, contains('time=2026-10-10T14:40:00.000Z'));
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
      final clouds = shown().first;
      expect(clouds.image, isNotNull);
      expect(clouds.imageBox, eumetsatClouds.coverage.first);
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
      expect(shown(), isEmpty);
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
      expect(shown(), isEmpty);
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

    WeatherLayer? detailLayer() =>
        shown().where((l) => l.id == 'clouds_eumetsat.detail').firstOrNull;

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
        expect(shown(), isEmpty);
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

  group('the newest frame a service has', () {
    final paris = _view(2.35, 48.85);
    DateTime at(int h, int m) => DateTime.utc(2026, 10, 11, h, m);
    List<DateTime?> satelliteTimes() => <DateTime?>[
      for (final (id, _, time) in fetcher.radarImages)
        if (id == 'rain_hsaf') time,
    ];

    setUp(() {
      map.visibleBounds = paris;
      now = at(15, 12);
    });

    test('once it is in, "now" keeps to it without a pan, and the label '
        'too', () {
      fakeAsync((async) {
        fetcher.newest['rain_hsaf'] = at(14, 20);
        configure(radar: true);
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.newestAsked, <String>['rain_hsaf']);
        // The clock's frame went out before the answer; then the newest.
        expect(satelliteTimes(), <DateTime>[at(14, 40), at(14, 20)]);
        expect(drawn(), contains('rain_hsaf'));
        expect(driver.status.value.newest, <String, DateTime>{
          'rain_hsaf': at(14, 20),
        });
        // Rests of the camera ask for neither again.
        map.emitCameraIdle();
        async.flushMicrotasks();
        expect(fetcher.newestAsked, hasLength(1));
        expect(satelliteTimes(), hasLength(2));
        driver.dispose();
      });
    });

    test('asked at most every five minutes; a failure or an older answer '
        'keeps the last', () {
      fakeAsync((async) {
        fetcher.newest['rain_hsaf'] = at(14, 20);
        configure(radar: true);
        driver.attach(map);
        async.flushMicrotasks();
        now = now.add(const Duration(minutes: 2));
        map.emitCameraIdle();
        async.flushMicrotasks();
        expect(fetcher.newestAsked, hasLength(1));
        // The refresh asks; no answer leaves 14:20.
        fetcher.newest.remove('rain_hsaf');
        now = now.add(radarRefreshInterval);
        async.elapse(radarRefreshInterval);
        expect(fetcher.newestAsked, hasLength(2));
        expect(driver.status.value.newest['rain_hsaf'], at(14, 20));
        // An older one, from a server behind, neither.
        fetcher.newest['rain_hsaf'] = at(14, 10);
        now = now.add(radarRefreshInterval);
        async.elapse(radarRefreshInterval);
        expect(fetcher.newestAsked, hasLength(3));
        expect(driver.status.value.newest['rain_hsaf'], at(14, 20));
        expect(satelliteTimes().toSet(), <DateTime>{at(14, 40), at(14, 20)});
        // A newer one moves the frame on.
        fetcher.newest['rain_hsaf'] = at(14, 50);
        now = now.add(radarRefreshInterval);
        async.elapse(radarRefreshInterval);
        expect(satelliteTimes().last, at(14, 50));
        driver.dispose();
      });
    });

    test('a refused frame asks again at once and shows the newest', () {
      fakeAsync((async) {
        var answers = 0;
        fetcher.radarAnswer = (source, box) {
          if (source.id != 'rain_hsaf' || answers++ > 0) {
            return Uint8List.fromList(<int>[5]);
          }
          // The service's XML error for a moment past its newest frame.
          fetcher.refused.add(source.id);
          return null;
        };
        configure(radar: true);
        driver.attach(map);
        // The first answer has none; by the refusal the service has 14:20.
        fetcher.newest['rain_hsaf'] = at(14, 20);
        async.flushMicrotasks();
        expect(fetcher.newestAsked, <String>['rain_hsaf', 'rain_hsaf']);
        expect(satelliteTimes(), <DateTime>[at(14, 40), at(14, 20)]);
        expect(drawn(), contains('rain_hsaf'));
        expect(driver.status.value.failedRain, isEmpty);
        driver.dispose();
      });
    });

    group('the model in the satellite\'s place at "Now"', () {
      /// Whether the satellite answers, and whether with the service's XML
      /// error.
      var hsafUp = true;
      var hsafRefuses = false;
      setUp(() {
        hsafUp = true;
        hsafRefuses = false;
        fetcher.radarAnswer = (source, box) {
          if (source.id != 'rain_hsaf' || hsafUp) {
            return Uint8List.fromList(<int>[source.id.length]);
          }
          if (hsafRefuses) fetcher.refused.add(source.id);
          return null;
        };
      });

      List<DateTime?> modelTimes() => <DateTime?>[
        for (final (id, _, time) in fetcher.radarImages)
          if (id == 'rain_icon_eu') time,
      ];

      void expectModel() {
        expect(drawn(), contains('rain_icon_eu'));
        expect(drawn(), isNot(contains('rain_hsaf')));
        // The hour "Now" falls in, as at +15 min.
        expect(modelTimes().last, at(16, 0));
        expect(driver.status.value.missing, <String>{'rain_hsaf'});
        // The rain shows: nothing to report.
        expect(driver.status.value.failed, isEmpty);
      }

      void expectSatellite() {
        expect(drawn(), contains('rain_hsaf'));
        expect(drawn(), isNot(contains('rain_icon_eu')));
        expect(driver.status.value.missing, isEmpty);
      }

      test('its image failed, its newest not known: the model, until an '
          'image comes again', () {
        fakeAsync((async) {
          hsafUp = false;
          configure(radar: true);
          driver.attach(map);
          async.flushMicrotasks();
          expectModel();
          // Asked again in the background with the refresh; in, it is back.
          hsafUp = true;
          now = now.add(radarRefreshInterval);
          async.elapse(radarRefreshInterval);
          expect(satelliteTimes(), <DateTime>[at(14, 40), at(14, 50)]);
          expectSatellite();
          driver.dispose();
        });
      });

      test(
        'refused with an XML error, its newest not to be had: the model',
        () {
          fakeAsync((async) {
            hsafUp = false;
            hsafRefuses = true;
            configure(radar: true);
            driver.attach(map);
            async.flushMicrotasks();
            // Its newest asked for again at once, in vain.
            expect(fetcher.newestAsked, <String>['rain_hsaf', 'rain_hsaf']);
            expectModel();
            // Not asked again before the refresh.
            map.emitCameraIdle();
            async.elapse(radarImageDebounce);
            expect(satelliteTimes(), hasLength(1));
            driver.dispose();
          });
        },
      );

      test('its newest frame over 90 minutes old: the model, never the old '
          'frame; a newer one takes its place back', () {
        fakeAsync((async) {
          fetcher.newest['rain_hsaf'] = at(13, 30);
          configure(radar: true);
          driver.attach(map);
          async.flushMicrotasks();
          expectModel();
          expect(satelliteTimes(), isNot(contains(at(13, 30))));
          fetcher.newest['rain_hsaf'] = at(14, 50);
          now = now.add(radarRefreshInterval);
          async.elapse(radarRefreshInterval);
          expect(satelliteTimes().last, at(14, 50));
          expectSatellite();
          driver.dispose();
        });
      });

      test('ahead, nothing changes', () {
        fakeAsync((async) {
          hsafUp = false;
          configure(radar: true);
          driver.attach(map);
          async.flushMicrotasks();
          configure(radar: true, offset: 15);
          async.flushMicrotasks();
          expect(drawn(), contains('rain_icon_eu'));
          expect(modelTimes().toSet(), <DateTime>{at(16, 0)});
          driver.dispose();
        });
      });
    });

    test('a source without one, or without a frame for the step, is not '
        'asked; a model named by its run is, over its coverage', () {
      fakeAsync((async) {
        map.visibleBounds = newYork;
        configure(radar: true, offset: 45);
        driver.attach(map);
        async.flushMicrotasks();
        // Over New York the HRRR's run, which it has no frame without.
        expect(fetcher.newestAsked, <String>['rain_hrrr']);
        // Over Paris ahead, the satellite has no frame: not asked either.
        map.visibleBounds = paris;
        map.emitCameraIdle();
        async.flushMicrotasks();
        expect(fetcher.newestAsked, <String>['rain_hrrr']);
        expect(driver.status.value.newest, isEmpty);
        driver.dispose();
      });
    });

    test('the Meteosat clouds keep to it on the full hour', () {
      fakeAsync((async) {
        now = at(15, 30);
        fetcher.newest['clouds_eumetsat'] = at(14, 50);
        configure(clouds: true);
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.newestAsked, <String>['clouds_eumetsat']);
        expect(fetcher.images, <String>[
          'clouds_eumetsat.0@${at(15, 0)}',
          'clouds_eumetsat.0@${at(14, 0)}',
        ]);
        expect(driver.status.value.cloudsFrame, at(14, 0));
        map.emitCameraIdle();
        async.flushMicrotasks();
        expect(fetcher.images, hasLength(2));
        driver.dispose();
      });
    });
  });

  group('the HRRR over the contiguous US', () {
    final run = DateTime.utc(2026, 10, 10, 12);

    test('ahead over New York, its frame of the newest run nearest the '
        'moment, the global model left out', () {
      fakeAsync((async) {
        fetcher.newest['rain_hrrr'] = run;
        map.visibleBounds = newYork;
        configure(radar: true);
        driver.attach(map);
        async.flushMicrotasks();
        // "Now" is the radar's, never the model's.
        expect(drawn(), <String>['radar_noaa']);
        expect(fetcher.radarImages, isEmpty);
        configure(radar: true, offset: 30);
        async.flushMicrotasks();
        // 15:12 is 192 minutes from the run: its frame of 195, 15:15.
        expect(fetcher.radarImages.map((i) => (i.$1, i.$3)), <Object>[
          ('rain_hrrr', DateTime.utc(2026, 10, 10, 15, 15)),
        ]);
        expect(drawn(), <String>['rain_hrrr']);
        expect(
          shown().single.attribution,
          'Forecast: NOAA HRRR via Iowa Environmental Mesonet',
        );
        expect(driver.status.value.newest, <String, DateTime>{
          'rain_hrrr': run,
        });
        driver.dispose();
      });
    });

    test('past the run\'s end, and while its run is not known, the global '
        'model', () {
      fakeAsync((async) {
        fetcher.newest['rain_hrrr'] = run;
        map.visibleBounds = newYork;
        // 14:42 and 18 hours is past the run's 18 hours from 12 UTC.
        configure(radar: true, offset: 1080);
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.radarImages.map((i) => i.$1), <String>['rain_icon']);
        expect(drawn(), <String>['rain_icon']);
        driver.dispose();
      });
      fakeAsync((async) {
        final unknown = WeatherMapDriver(
          fetcher: fetcher..radarImages.clear(),
          clock: () => now,
          prefetch: false,
        );
        fetcher.newest.remove('rain_hrrr');
        map.visibleBounds = newYork;
        unknown
          ..configure(
            settings: const WeatherMapSettings(radar: true),
            sources: defaultWeatherMapSources,
            offsetMinutes: 30,
          )
          ..attach(map);
        async.flushMicrotasks();
        expect(fetcher.newestAsked, contains('rain_hrrr'));
        expect(fetcher.radarImages.map((i) => i.$1), <String>['rain_icon']);
        unknown.dispose();
      });
    });

    test('its image failed: the global model in its place', () {
      fakeAsync((async) {
        fetcher
          ..newest['rain_hrrr'] = run
          ..radarAnswer = (source, _) => source.id == 'rain_hrrr'
              ? null
              : Uint8List.fromList(<int>[7, 8, 9]);
        map.visibleBounds = newYork;
        configure(radar: true, offset: 30, radarStyle: RadarStyle.soft);
        driver.attach(map);
        async.flushMicrotasks();
        // Before the run is known the global model alone; then the HRRR,
        // which fails, and the global model again, not left to it.
        expect(fetcher.radarImages.map((i) => i.$1), <String>[
          'rain_icon',
          'rain_hrrr',
          'rain_icon',
        ]);
        expect(drawn(), <String>['rain_icon']);
        expect(fetcher.radarJobs.last.$2, '-rain_hrrr!');
        driver.dispose();
      });
    });

    test('over Europe ahead, ICON-EU as before', () {
      fakeAsync((async) {
        fetcher.newest['rain_hrrr'] = run;
        map.visibleBounds = _view(2.35, 48.85);
        configure(radar: true, offset: 180);
        driver.attach(map);
        async.flushMicrotasks();
        expect(drawn(), <String>['rain_icon_eu']);
        expect(fetcher.newestAsked, isNot(contains('rain_hrrr')));
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
        final layer = shown().single;
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
        expect(shown().single.imageBox, fetcher.radarImages.last.$2);
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
        expect(shown().single.image, <int>[1]);
        soft(offset: 30);
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(2));
        expect(fetcher.radarImages.last.$3, DateTime.utc(2026, 10, 10, 15, 5));
        // Still the last one while the new one is out.
        expect(shown().single.image, <int>[1]);
        fetcher.heldRadar.last.complete(Uint8List.fromList(<int>[2]));
        async.flushMicrotasks();
        expect(shown().single.image, <int>[2]);
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
        expect(shown(), isEmpty);
        expect(fetcher.radarImages, hasLength(2));
        fetcher.heldRadar.last.complete(Uint8List.fromList(<int>[2]));
        async.flushMicrotasks();
        expect(shown().single.image, <int>[2]);
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
        expect(shown(), isEmpty);
        // Not asked again for the same view before the refresh.
        map.emitCameraIdle();
        async.elapse(radarImageDebounce);
        expect(fetcher.radarImages, hasLength(1));
        fetcher.radarImagesUp = true;
        async.elapse(radarRefreshInterval);
        expect(fetcher.radarImages, hasLength(2));
        expect(driver.status.value.failed, isEmpty);
        expect(shown().single.image, <int>[7, 8, 9]);
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
        final layer = shown().single;
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
        expect(shown().last.image, <int>[7, 8, 9]);
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
        expect(shown().single.tiles, isNotNull);
        expect(fetcher.probes, hasLength(1));
        soft();
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(1));
        // The tiles until the image comes.
        expect(shown().single.tiles, isNotNull);
        fetcher.heldRadar.single.complete(Uint8List.fromList(<int>[3]));
        async.flushMicrotasks();
        expect(shown().single.image, <int>[3]);
        expect(shown().single.tiles, isNull);
        // And back: the tiles at once, probed afresh.
        configure(radar: true);
        async.flushMicrotasks();
        expect(shown().single.tiles, isNotNull);
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
        expect(shown().single.tiles, isNotNull);
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
        // Now's image is kept on the map unseen.
        expect(
          map.weatherLayers.where((l) => !l.visible).map((l) => l.id),
          contains('radar_noaa'),
        );
        soft();
        async.flushMicrotasks();
        // Not asked again: still loaded, drawn at once.
        expect(fetcher.radarImages, hasLength(asked));
        expect(drawn(), <String>['radar_noaa']);
        expect(shown().single.imageBox, nowImage.$2);
        driver.dispose();
      });
    });

    test('an answer for Now that comes after the time control moved on is '
        'kept, and drawn at once back at Now', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.holdRadar = true;
        soft();
        driver.attach(map);
        async.flushMicrotasks();
        soft(offset: 60);
        async.flushMicrotasks();
        // Now's comes while the hour ahead is shown: kept, not seen.
        fetcher.heldRadar.single.complete(Uint8List.fromList(<int>[1]));
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(2));
        expect(shown(), isEmpty);
        soft();
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(2));
        expect(shown().single.image, <int>[1]);
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

    test('zoomed far out the rain is still images of the view, coarser; '
        'the clouds\' detail goes', () {
      fakeAsync((async) {
        map.zoom = 8;
        soft(clouds: true);
        driver.attach(map);
        async.elapse(cloudDetailDebounce);
        expect(fetcher.radarImages, hasLength(1));
        expect(fetcher.details, hasLength(1));
        rest(
          async,
          const BoundingBox(south: 25, west: -10, north: 70, east: 50),
          2.5,
        );
        async.elapse(cloudDetailDebounce);
        // Europe at zoom 2.5: the DWD's radar and the satellite around it,
        // one image each, at most the longest side a soft image has.
        final asked = fetcher.radarImages.skip(1).map((r) => r.$1).toSet();
        expect(asked, containsAll(<String>['radar_dwd', 'rain_hsaf']));
        for (final (id, box, _) in fetcher.radarImages) {
          expect(safeImageBox(box), isTrue, reason: '$id $box');
          final source = defaultWeatherMapSources.firstWhere((s) => s.id == id);
          final (w, h) = radarSoftImageSize(source, box);
          expect(math.max(w, h), lessThanOrEqualTo(radarSoftMaxSide));
        }
        expect(fetcher.details, hasLength(1));
        expect(drawn(), containsAll(<String>['radar_dwd', 'rain_hsaf']));
        // No detail of the clouds this far out.
        expect(drawn(), isNot(contains('clouds_eumetsat.detail')));
        // The models ahead too.
        soft(offset: 180, clouds: true);
        async.elapse(radarImageDebounce);
        expect(fetcher.radarImages.map((r) => r.$1), contains('rain_icon_eu'));
        expect(drawn(), contains('rain_icon_eu'));
        driver.dispose();
      });
    });

    test('the whole world: two images of a half each, side by side, drawn '
        'at every zoom from 0 to 3', () {
      const world = BoundingBox(south: -85, west: -540, north: 85, east: 540);
      for (final zoom in <double>[0, 1, 2, 3]) {
        fakeAsync((async) {
          map
            ..visibleBounds = world
            ..zoom = zoom;
          soft(offset: 600);
          driver.attach(map);
          async.flushMicrotasks();
          // Ten hours ahead the global model everywhere: one image of each
          // half of the world.
          final boxes = <BoundingBox>[
            for (final (id, box, _) in fetcher.radarImages)
              if (id == 'rain_icon') box,
          ];
          expect(boxes, hasLength(2), reason: 'zoom $zoom');
          boxes.sort((a, b) => a.west.compareTo(b.west));
          expect(boxes.first.west, -180);
          expect(boxes.first.east, 0);
          expect(boxes.last.west, 0);
          expect(boxes.last.east, 180);
          for (final box in boxes) {
            expect(safeImageBox(box), isTrue, reason: '$box');
          }
          expect(drawn(), containsAll(<String>['rain_icon', 'rain_icon#1']));
          for (final layer in map.weatherLayers) {
            expect(safeImageBox(layer.imageBox!), isTrue, reason: '$layer');
          }
          driver.dispose();
        });
        fetcher = _Fetcher();
        driver = WeatherMapDriver(
          fetcher: fetcher,
          clock: () => now,
          prefetch: false,
        );
      }
    });

    test('a view across the antimeridian: an image each side of it', () {
      fakeAsync((async) {
        map
          ..visibleBounds = const BoundingBox(
            south: 50,
            west: 170,
            north: 60,
            east: -170,
          )
          ..zoom = 4;
        soft(offset: 600);
        driver.attach(map);
        async.flushMicrotasks();
        final boxes = <BoundingBox>[
          for (final (_, box, _) in fetcher.radarImages) box,
        ]..sort((a, b) => a.west.compareTo(b.west));
        expect(boxes, hasLength(2));
        expect(boxes.first.west, -180);
        expect(boxes.first.east, greaterThan(-170));
        expect(boxes.last.east, 180);
        expect(boxes.last.west, lessThan(170));
        expect(drawn(), <String>['rain_icon', 'rain_icon#1']);
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
          driver = WeatherMapDriver(
            fetcher: fetcher,
            clock: () => now,
            prefetch: false,
          );
        }
      }
    });
  });

  group('the other steps, in the background, and the slider', () {
    late WeatherMapDriver live;

    setUp(() {
      live = WeatherMapDriver(fetcher: fetcher, clock: () => now);
    });

    void soft({int offset = 0, bool radar = true, bool wind = false}) =>
        live.configure(
          settings: WeatherMapSettings(radar: radar, wind: wind),
          sources: defaultWeatherMapSources,
          offsetMinutes: offset,
          radarStyle: RadarStyle.soft,
        );

    /// Answers the held rain requests oldest first, the DWD's with a frame
    /// measuring all over the view, each answer let in before the next;
    /// checks no more than [weatherPrefetchConcurrency] are ever out
    /// besides the step's own, and returns the moments asked for in order.
    List<(String, DateTime?)> answerAll(FakeAsync async) {
      var answered = 0;
      while (answered < fetcher.heldRadar.length) {
        final out = fetcher.heldRadar.length - answered;
        expect(out, lessThanOrEqualTo(weatherPrefetchConcurrency + 1));
        final (id, box, _) = fetcher.radarImages[answered];
        fetcher.heldRadar[answered].complete(
          id == 'radar_dwd'
              ? _dwdFrame(box, (_) => true)
              : Uint8List.fromList(<int>[answered]),
        );
        answered++;
        async.flushMicrotasks();
      }
      return <(String, DateTime?)>[
        for (final (id, _, time) in fetcher.radarImages) (id, time),
      ];
    }

    test('once the step\'s own are in: the nowcast\'s steps first, then the '
        'hours ahead, two at a time, each once', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.holdRadar = true;
        soft();
        live.attach(map);
        async.flushMicrotasks();
        // The step's own first, alone.
        expect(fetcher.radarImages, hasLength(1));
        final asked = answerAll(async);
        // Now, then the nowcast's eight quarter hours, nearest first.
        expect(asked.first, ('radar_dwd', DateTime.utc(2026, 10, 10, 14, 35)));
        final nowcast = asked.skip(1).take(8).toList();
        expect(nowcast.every((a) => a.$1 == 'radar_dwd'), isTrue);
        expect(nowcast.map((a) => a.$2), <DateTime>[
          for (var m = 15; m <= 120; m += 15)
            DateTime.utc(2026, 10, 10, 14, 35).add(Duration(minutes: m)),
        ]);
        // Then ICON-EU for the hours ahead, the nowcast's reach covering
        // the view before.
        final ahead = asked.skip(9).toList();
        expect(ahead, isNotEmpty);
        expect(ahead.every((a) => a.$1 == 'rain_icon_eu'), isTrue);
        // Each image once.
        expect(asked.toSet(), hasLength(asked.length));
        // All kept on the map, one layer with its frames unseen but Now's.
        final dwd = map.weatherLayers.firstWhere((l) => l.id == 'radar_dwd');
        expect(dwd.visible, isTrue);
        expect(dwd.preloaded, hasLength(8));
        expect(dwd.preloaded.length, lessThan(weatherPreloadMaxFrames));
        final icon = map.weatherLayers.firstWhere(
          (l) => l.id == 'rain_icon_eu',
        );
        expect(icon.visible, isFalse);
        expect(drawn(), <String>['radar_dwd']);
        live.dispose();
      });
    });

    test('from a step mid-slider: outwards, alternately later and '
        'earlier', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.holdRadar = true;
        soft(offset: 120);
        live.attach(map);
        async.flushMicrotasks();
        final asked = answerAll(async);
        final base = DateTime.utc(2026, 10, 10, 14, 35);
        DateTime dwd(int m) => base.add(Duration(minutes: m));
        // The step's own, then from it outwards: three hours on and an hour
        // and three quarters, four hours and an hour and a half, ...
        expect(asked.take(9).toList(), <(String, DateTime)>[
          ('radar_dwd', dwd(120)),
          ('rain_icon_eu', DateTime.utc(2026, 10, 10, 18)),
          ('radar_dwd', dwd(105)),
          ('rain_icon_eu', DateTime.utc(2026, 10, 10, 19)),
          ('radar_dwd', dwd(90)),
          ('rain_icon_eu', DateTime.utc(2026, 10, 10, 20)),
          ('radar_dwd', dwd(75)),
          ('rain_icon_eu', DateTime.utc(2026, 10, 10, 21)),
          ('radar_dwd', dwd(60)),
        ]);
        // Now last of the earlier side, then the rest of the day ahead.
        final now = asked.indexOf(('radar_dwd', base));
        expect(
          asked.skip(now + 1).every((a) => a.$1 == 'rain_icon_eu'),
          isTrue,
        );
        expect(asked.toSet(), hasLength(asked.length));
        live.dispose();
      });
    });

    test('dragged, the step under the finger at once from what is loaded, '
        'nothing asked; let go, the step set', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.holdRadar = true;
        soft();
        live.attach(map);
        async.flushMicrotasks();
        answerAll(async);
        final asked = fetcher.radarImages.length;
        final calls = map.weatherLayerCalls.length;
        live.preview(45);
        expect(live.status.value.shownOffset, 45);
        final dwd = shown().single;
        expect(dwd.id, 'radar_dwd');
        // The frame 45 minutes on, which was kept unseen.
        expect(
          dwd.frameKey,
          contains(
            '${DateTime.utc(2026, 10, 10, 15, 20).millisecondsSinceEpoch}',
          ),
        );
        expect(map.weatherLayerCalls, hasLength(calls + 1));
        // The frame shown before kept unseen in its turn: the map adds no
        // source, it only switches which frame is seen.
        expect(dwd.preloaded, hasLength(8));
        live.preview(300);
        expect(live.status.value.shownOffset, 300);
        expect(drawn(), <String>['rain_icon_eu']);
        expect(fetcher.radarImages, hasLength(asked));
        // Let go: the step set, still nothing asked.
        soft(offset: 300);
        live.preview(null);
        async.flushMicrotasks();
        expect(live.status.value.shownOffset, 300);
        expect(drawn(), <String>['rain_icon_eu']);
        expect(fetcher.radarImages, hasLength(asked));
        live.dispose();
      });
    });

    test('dragged to a step not loaded yet: the nearest that is, on the '
        'side of the step set', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.holdRadar = true;
        soft();
        live.attach(map);
        async.flushMicrotasks();
        // Now's, then 15 minutes on; 30 is still out.
        for (var i = 0; i < 2; i++) {
          final (_, box, _) = fetcher.radarImages[i];
          fetcher.heldRadar[i].complete(_dwdFrame(box, (_) => true));
          async.flushMicrotasks();
        }
        live.preview(45);
        expect(live.status.value.shownOffset, 15);
        live.preview(15);
        expect(live.status.value.shownOffset, 15);
        // Nothing loaded near three hours: back to the step set.
        live.preview(180);
        expect(live.status.value.shownOffset, 15);
        live.preview(null);
        expect(live.status.value.shownOffset, 0);
        live.dispose();
      });
    });

    test('the view moves on: what was loaded for it goes, answers for it '
        'are dropped, the new view asked for', () {
      fakeAsync((async) {
        map.zoom = 8;
        fetcher.holdRadar = true;
        soft();
        live.attach(map);
        async.flushMicrotasks();
        // Now's and the first two in the background.
        final (_, nowBox, _) = fetcher.radarImages.single;
        fetcher.heldRadar.single.complete(_dwdFrame(nowBox, (_) => true));
        async.flushMicrotasks();
        expect(fetcher.heldRadar, hasLength(3));
        // Off to Munich while two are out.
        map
          ..visibleBounds = _view(11.6, 48.1)
          ..zoom = 8;
        map.emitCameraIdle();
        async.elapse(radarImageDebounce);
        expect(fetcher.radarImages, hasLength(4));
        final munich = fetcher.radarImages.last.$2;
        expect(munich.contains(const LatLng(48.1, 11.6)), isTrue);
        // Berlin's answers come: dropped, nothing of Berlin kept but the
        // frame seen until Munich's is in.
        for (var i = 1; i < 3; i++) {
          fetcher.heldRadar[i].complete(
            _dwdFrame(fetcher.radarImages[i].$2, (_) => true),
          );
        }
        async.flushMicrotasks();
        bool overBerlin(BoundingBox box) =>
            box.contains(const LatLng(52.5, 13.4));
        expect(map.weatherLayers.single.preloaded, isEmpty);
        // Munich's in, then its other steps.
        fetcher.heldRadar[3].complete(_dwdFrame(munich, (_) => true));
        async.flushMicrotasks();
        for (final layer in map.weatherLayers) {
          expect(overBerlin(layer.imageBox!), isFalse, reason: '$layer');
          for (final frame in layer.preloaded) {
            expect(overBerlin(frame.box), isFalse, reason: '$frame');
          }
        }
        final after = fetcher.radarImages.skip(4).toList();
        expect(after, hasLength(weatherPrefetchConcurrency));
        for (final (_, box, _) in after) {
          expect(box.contains(const LatLng(48.1, 11.6)), isTrue);
        }
        live.dispose();
      });
    });

    test('the wind\'s hours too, and dragged with the rain off, the arrows '
        'of the hour at once', () {
      fakeAsync((async) {
        map.zoom = 9;
        soft(radar: false, wind: true);
        live.attach(map);
        async.flushMicrotasks();
        // Every hour of the next 24 once, two at a time, the step's own
        // first.
        final hours = fetcher.winds.map((w) => w.$2).toList();
        expect(hours.first, DateTime.utc(2026, 10, 10, 14));
        expect(hours.toSet(), hasLength(hours.length));
        expect(hours, hasLength(25));
        final asked = fetcher.winds.length;
        final before = map.windArrows;
        live.preview(180);
        expect(live.status.value.shownOffset, 180);
        expect(map.windArrows, isNot(before));
        // 17 UTC's wind.
        expect(map.windArrows!.arrows.first.ms, 6.5);
        expect(fetcher.winds, hasLength(asked));
        live.dispose();
      });
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
        expect(shown(), isEmpty);
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

    test('zoomed out to the whole world too, on a thinned grid', () {
      fakeAsync((async) {
        const world = BoundingBox(south: -85, west: -540, north: 85, east: 540);
        for (final zoom in <double>[0, 1, 2, 2.9]) {
          rest(async, world, zoom);
          configure(wind: true);
          driver.attach(map);
          async.elapse(windDebounce);
          final (request, _) = fetcher.winds.last;
          expect(request.thinning, greaterThan(1), reason: 'zoom $zoom');
          expect(request.box.east - request.box.west, lessThanOrEqualTo(360));
          expect(map.windArrows?.arrows, isNotEmpty, reason: 'zoom $zoom');
        }
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

    test('from memory when the step comes back', () {
      fakeAsync((async) {
        map.zoom = 9;
        configure(wind: true);
        driver.attach(map);
        async.flushMicrotasks();
        configure(wind: true, offset: 180);
        async.flushMicrotasks();
        configure(wind: true);
        async.flushMicrotasks();
        // Back at Now the grid is still in memory: nothing asked, and its
        // arrows drawn.
        expect(fetcher.winds.map((w) => w.$2), <DateTime>[
          DateTime.utc(2026, 10, 10, 14),
          DateTime.utc(2026, 10, 10, 17),
        ]);
        expect(map.windArrows!.arrows, isNotEmpty);
        expect(driver.status.value.shownOffset, 0);
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
