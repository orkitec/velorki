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
  }) => driver.configure(
    settings: WeatherMapSettings(radar: radar, clouds: clouds),
    sources: sources ?? defaultWeatherMapSources,
    offsetMinutes: offset,
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
}
