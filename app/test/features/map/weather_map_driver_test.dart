import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/application/weather_map_driver.dart';
import 'package:velorki/features/map/data/weather_fetcher.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
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

  @override
  Future<Uint8List?> radarImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now,
  ) {
    radarImages.add((source.id, box, frame.time));
    if (holdRadar) {
      final answer = Completer<Uint8List?>();
      heldRadar.add(answer);
      return answer.future;
    }
    return Future<Uint8List?>.value(
      radarImagesUp ? Uint8List.fromList(<int>[7, 8, 9]) : null,
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

BoundingBox _view(double lon, double lat) => BoundingBox(
  south: lat - 0.2,
  west: lon - 0.2,
  north: lat + 0.2,
  east: lon + 0.2,
);

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
    int offset = 0,
    List<WeatherMapSource>? sources,
    RadarStyle radarStyle = RadarStyle.measured,
  }) => driver.configure(
    settings: WeatherMapSettings(radar: radar, clouds: clouds),
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
      expect(
        driver.status.value.radarFrame,
        DateTime.utc(2026, 10, 10, 14, 35),
      );
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

  test('a moment ahead: NOAA has none, and says forecast is Germany only', () {
    fakeAsync((async) {
      map.visibleBounds = newYork;
      configure(radar: true);
      driver.attach(map);
      async.flushMicrotasks();
      expect(drawn(), <String>['radar_noaa']);
      expect(driver.status.value.forecastElsewhere, isFalse);
      configure(radar: true, offset: 30);
      async.flushMicrotasks();
      expect(map.weatherLayers, isEmpty);
      expect(driver.status.value.forecastElsewhere, isTrue);
      expect(driver.status.value.radarFrame, DateTime.utc(2026, 10, 10, 15, 5));
      // Over Germany the forecast is there.
      map.visibleBounds = berlin;
      map.emitCameraIdle();
      async.flushMicrotasks();
      expect(drawn(), <String>['radar_dwd']);
      expect(
        map.weatherLayers.single.tiles,
        contains('time=2026-10-10T15:05:00.000Z'),
      );
      expect(driver.status.value.forecastElsewhere, isFalse);
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

  test('a source the mirror switched off is not drawn', () {
    fakeAsync((async) {
      configure(
        radar: true,
        sources: applyWeatherOverride(defaultWeatherMapSources, [
          {'id': 'radar_dwd', 'enabled': false},
        ]),
      );
      driver.attach(map);
      async.flushMicrotasks();
      expect(map.weatherLayers, isEmpty);
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
      expect(driver.status.value.radarFrame, isNull);
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
        soft(offset: -30);
        async.flushMicrotasks();
        expect(fetcher.radarImages, hasLength(2));
        expect(fetcher.radarImages.last.$3, DateTime.utc(2026, 10, 10, 14, 5));
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

    test('NOAA has no moment ahead; the forecast hint is as on tiles', () {
      fakeAsync((async) {
        map
          ..visibleBounds = newYork
          ..zoom = 8;
        soft(offset: 30);
        driver.attach(map);
        async.flushMicrotasks();
        expect(fetcher.radarImages, isEmpty);
        expect(map.weatherLayers, isEmpty);
        expect(driver.status.value.forecastElsewhere, isTrue);
        soft();
        async.flushMicrotasks();
        expect(fetcher.radarImages.single.$1, 'radar_noaa');
        expect(driver.status.value.forecastElsewhere, isFalse);
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
  });
}
