import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/map/data/cycle_map_layers.dart';
import 'package:velorki/features/map/data/maplibre_map_controller.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/data/weather_paint.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/map/domain/wind_field.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/maplibre_style_ops_fake.dart';

WeatherLayer _radar(String id, String frame) => WeatherLayer.tiles(
  id: id,
  kind: WeatherKind.radar,
  tiles: 'https://radar.example/$id?bbox={bbox-epsg-3857}&time=$frame',
  attribution: 'Radar: $id',
  bounds: const <double>[1.5, 45, 19, 56.5],
);

WeatherLayer _clouds(String id, String frame) => WeatherLayer.image(
  id: id,
  kind: WeatherKind.clouds,
  image: Uint8List.fromList(<int>[1, 2, 3]),
  imageBox: eumetsatClouds.coverage.first,
  frameKey: '$id@$frame',
  attribution: 'Clouds: $id',
);

void main() {
  late RecordingStyleOps ops;
  late MaplibreMapControllerAdapter map;

  setUp(() async {
    ops = RecordingStyleOps()
      ..styleLayerIds = <String>['road_minor', 'waterway_line_label', 'poi'];
    map = MaplibreMapControllerAdapter.withOps(
      ops,
      cycleMapSwapDelay: Duration.zero,
      weatherSwapDelay: Duration.zero,
    );
    await map.attachToStyle();
    ops.clearCalls();
  });

  test('radar is a raster source under the labels, credited', () async {
    await map.setWeatherLayers([_radar('radar_dwd', '1')]);
    final source = ops.addSourceOf(MapLayerIds.weatherSource('radar_dwd', 0))!;
    expect(source.properties!['tiles'], [
      'https://radar.example/radar_dwd?bbox={bbox-epsg-3857}&time=1',
    ]);
    expect(source.properties!['bounds'], [1.5, 45, 19, 56.5]);
    expect(source.properties!['attribution'], 'Radar: radar_dwd');
    final layer = ops.addLayerOf(MapLayerIds.weatherLayer('radar_dwd', 0))!;
    expect(layer.belowLayerId, 'waterway_line_label');
    expect(layer.enableInteraction, isFalse);
    expect(layer.properties!['raster-opacity'], radarTone.opacity);
    expect(map.weatherAttributions.value, ['Radar: radar_dwd']);
  });

  test('clouds are an image source under the rain', () async {
    await map.setWeatherLayers([_radar('radar_dwd', '1')]);
    await map.setWeatherLayers([
      _clouds('clouds_eumetsat.0', 'a'),
      _radar('radar_dwd', '1'),
    ]);
    final image = ops.lastCall('addImageSource')!;
    expect(image.id, MapLayerIds.weatherSource('clouds_eumetsat.0', 1));
    final corners = image.properties!['coordinates'] as List;
    expect(corners.first, [70.0, -30.0]); // top left, lat/lng
    expect(corners[2], [25.0, 45.0]); // bottom right
    final layer = ops.addLayerOf(
      MapLayerIds.weatherLayer('clouds_eumetsat.0', 1),
    )!;
    expect(layer.belowLayerId, MapLayerIds.weatherLayer('radar_dwd', 0));
    expect(
      layer.properties!['raster-brightness-max'],
      cloudsLightTone.brightnessMax,
    );
    expect(map.weatherAttributions.value, [
      'Clouds: clouds_eumetsat.0',
      'Radar: radar_dwd',
    ]);
  });

  test('both stay under the cycle map', () async {
    await map.setCycleMap('/cycle.geojson');
    await map.setWeatherLayers([_radar('radar_dwd', '1')]);
    final lowestCycle = CycleMapLayers.layerId(
      0,
      const CycleMapLayers(CycleMapColors.light).layers.first,
    );
    expect(
      ops.addLayerOf(MapLayerIds.weatherLayer('radar_dwd', 0))!.belowLayerId,
      lowestCycle,
    );
  });

  test('a new frame goes over the old one, which then goes', () async {
    await map.setWeatherLayers([_radar('radar_dwd', '1')]);
    ops.clearCalls();
    await map.setWeatherLayers([_radar('radar_dwd', '2')]);
    expect(ops.names, ['addSource', 'addLayer', 'removeLayer', 'removeSource']);
    expect(ops.calls[2].id, MapLayerIds.weatherLayer('radar_dwd', 0));
    expect(ops.layerIds, contains(MapLayerIds.weatherLayer('radar_dwd', 1)));
    // The same frame again changes nothing.
    ops.clearCalls();
    await map.setWeatherLayers([_radar('radar_dwd', '2')]);
    expect(ops.calls, isEmpty);
  });

  test('switched off or out of view, the layer and its credit go', () async {
    await map.setWeatherLayers([
      _clouds('clouds_eumetsat.0', 'a'),
      _radar('radar_dwd', '1'),
    ]);
    await map.setWeatherLayers(const <WeatherLayer>[]);
    expect(
      ops.layerIds.where((id) => id.startsWith('velorki-weather-')),
      isEmpty,
    );
    expect(
      ops.sourceIds.where((id) => id.startsWith('velorki-weather-')),
      isEmpty,
    );
    expect(map.weatherAttributions.value, isEmpty);
  });

  test('a style reload puts the layers back', () async {
    await map.setWeatherLayers([_radar('radar_dwd', '1')]);
    ops
      ..reloadStyle()
      ..clearCalls();
    await map.attachToStyle();
    await pumpEventQueue();
    expect(
      ops.callsNamed('addLayer').map((c) => c.layerId),
      contains(startsWith('velorki-weather-radar_dwd-')),
    );
  });

  test('a dark map paints the clouds softer', () async {
    await map.setWeatherLayers([_clouds('clouds_eumetsat.0', 'a')]);
    await map.setWeatherDark(true);
    expect(
      ops
          .lastPropertiesOf(MapLayerIds.weatherLayer('clouds_eumetsat.0', 0))!
          .properties!['raster-brightness-max'],
      cloudsDarkTone.brightnessMax,
    );
  });

  test('a cloud detail goes over its region, and stays over a new frame '
      'of the region', () async {
    WeatherLayer detail(String frame) => WeatherLayer.image(
      id: 'clouds_eumetsat.detail',
      kind: WeatherKind.clouds,
      image: Uint8List.fromList(<int>[4]),
      imageBox: const BoundingBox(south: 52, west: 13, north: 53, east: 14),
      frameKey: 'detail@$frame',
      attribution: 'Clouds: clouds_eumetsat.0',
    );
    await map.setWeatherLayers([
      _clouds('clouds_eumetsat.0', 'a'),
      _radar('radar_dwd', '1'),
    ]);
    await map.setWeatherLayers([
      _clouds('clouds_eumetsat.0', 'a'),
      detail('a'),
      _radar('radar_dwd', '1'),
    ]);
    final detailLayer = MapLayerIds.weatherLayer('clouds_eumetsat.detail', 2);
    expect(
      ops.addLayerOf(detailLayer)!.belowLayerId,
      MapLayerIds.weatherLayer('radar_dwd', 1),
    );
    // The region's next hour goes under the detail, not over it.
    await map.setWeatherLayers([
      _clouds('clouds_eumetsat.0', 'b'),
      detail('a'),
      _radar('radar_dwd', '1'),
    ]);
    expect(
      ops
          .addLayerOf(MapLayerIds.weatherLayer('clouds_eumetsat.0', 3))!
          .belowLayerId,
      detailLayer,
    );
    // A new detail goes over the old one, then the old one goes.
    await map.setWeatherLayers([
      _clouds('clouds_eumetsat.0', 'b'),
      detail('b'),
      _radar('radar_dwd', '1'),
    ]);
    expect(
      ops
          .addLayerOf(MapLayerIds.weatherLayer('clouds_eumetsat.detail', 4))!
          .belowLayerId,
      MapLayerIds.weatherLayer('radar_dwd', 1),
    );
    expect(ops.layerIds, isNot(contains(detailLayer)));
    expect(map.weatherAttributions.value, [
      'Clouds: clouds_eumetsat.0',
      'Radar: radar_dwd',
    ]);
  });

  test('cloud images are smoothed, linearly; the radar is left as it '
      'was', () async {
    await map.setWeatherLayers([
      _clouds('clouds_eumetsat.0', 'a'),
      _radar('radar_dwd', '1'),
    ]);
    expect(
      ops
          .addLayerOf(MapLayerIds.weatherLayer('clouds_eumetsat.0', 0))!
          .properties!['raster-resampling'],
      'linear',
    );
    expect(
      ops
          .addLayerOf(MapLayerIds.weatherLayer('radar_dwd', 1))!
          .properties!
          .containsKey('raster-resampling'),
      isFalse,
    );
    await map.setWeatherDark(true);
    expect(
      ops
          .lastPropertiesOf(MapLayerIds.weatherLayer('clouds_eumetsat.0', 0))!
          .properties!['raster-resampling'],
      'linear',
    );
  });

  test('the soft radar is an image over the clouds, opaque as a layer, '
      'smoothed linearly', () async {
    final soft = WeatherLayer.image(
      id: 'radar_dwd',
      kind: WeatherKind.radar,
      image: Uint8List.fromList(<int>[7]),
      imageBox: const BoundingBox(south: 52, west: 13, north: 53, east: 14),
      frameKey: 'radar_dwd@a',
      attribution: 'Radar: radar_dwd',
    );
    await map.setWeatherLayers([_clouds('clouds_eumetsat.0', 'a'), soft]);
    final image = ops.lastCall('addImageSource')!;
    expect(image.id, MapLayerIds.weatherSource('radar_dwd', 1));
    final layer = ops.addLayerOf(MapLayerIds.weatherLayer('radar_dwd', 1))!;
    expect(layer.properties!['raster-resampling'], 'linear');
    expect(layer.properties!['raster-opacity'], radarSoftTone.opacity);
    expect(radarSoftTone.opacity, 1.0);
    // Over the clouds, under the labels.
    expect(layer.belowLayerId, 'waterway_line_label');
    expect(
      ops
          .addLayerOf(MapLayerIds.weatherLayer('clouds_eumetsat.0', 0))!
          .belowLayerId,
      'waterway_line_label',
    );
    final ids = ops.layerIds.toList();
    expect(
      ids.indexOf(MapLayerIds.weatherLayer('clouds_eumetsat.0', 0)),
      lessThan(ids.indexOf(MapLayerIds.weatherLayer('radar_dwd', 1))),
    );
    // Switched to As measured: the tiles over the image, which then goes.
    await map.setWeatherLayers([
      _clouds('clouds_eumetsat.0', 'a'),
      _radar('radar_dwd', '1'),
    ]);
    expect(ops.sourceIds, contains(MapLayerIds.weatherSource('radar_dwd', 2)));
    expect(
      ops.sourceIds,
      isNot(contains(MapLayerIds.weatherSource('radar_dwd', 1))),
    );
    expect(
      ops
          .addLayerOf(MapLayerIds.weatherLayer('radar_dwd', 2))!
          .properties!['raster-opacity'],
      radarTone.opacity,
    );
  });
  test('an image MapLibre cannot draw adds no source, and the next update '
      'and removal still work', () async {
    WeatherLayer soft(String frame, BoundingBox box) => WeatherLayer.image(
      id: 'radar_dwd',
      kind: WeatherKind.radar,
      image: Uint8List.fromList(<int>[7]),
      imageBox: box,
      frameKey: 'radar_dwd@$frame',
      attribution: 'Radar: radar_dwd',
    );
    const good = BoundingBox(south: 52, west: 13, north: 53, east: 14);
    for (final bad in const <BoundingBox>[
      BoundingBox(south: 52, west: 13, north: 53, east: 13), // no width
      BoundingBox(south: 52, west: 14, north: 53, east: 13), // inverted
      BoundingBox(south: 86, west: 13, north: 88, east: 14), // past 85.05
      BoundingBox(south: -85, west: -540, north: 85, east: 540), // world
    ]) {
      await map.setWeatherLayers([soft('a', good)]);
      ops.clearCalls();
      // The unsafe box: the safe one shown goes, nothing is added.
      await map.setWeatherLayers([soft('b', bad), _radar('radar_noaa', '1')]);
      expect(ops.callsNamed('addImageSource'), isEmpty, reason: '$bad');
      expect(
        ops.sourceIds.where((id) => id.startsWith('velorki-weather-radar_dwd')),
        isEmpty,
      );
      expect(map.weatherAttributions.value, ['Radar: radar_noaa']);
      // The next safe image is drawn, and goes again when asked.
      await map.setWeatherLayers([soft('c', good)]);
      expect(ops.callsNamed('addImageSource'), hasLength(1));
      await map.setWeatherLayers(const <WeatherLayer>[]);
      expect(
        ops.sourceIds.where((id) => id.startsWith('velorki-weather-')),
        isEmpty,
      );
    }
  });

  group('frames kept unseen for the time control', () {
    const box = BoundingBox(south: 52, west: 13, north: 53, east: 14);
    WeatherImageFrame frame(String key) => WeatherImageFrame(
      frameKey: key,
      image: Uint8List.fromList(<int>[key.length]),
      box: box,
    );
    WeatherLayer rain(String shown, List<String> kept, {bool visible = true}) =>
        WeatherLayer.image(
          id: 'radar_dwd',
          kind: WeatherKind.radar,
          image: Uint8List.fromList(<int>[1]),
          imageBox: box,
          frameKey: shown,
          attribution: 'Radar: radar_dwd',
          visible: visible,
          preloaded: <WeatherImageFrame>[for (final k in kept) frame(k)],
        );
    double? opacityOf(int n) =>
        (ops.lastPropertiesOf(MapLayerIds.weatherLayer('radar_dwd', n)) ??
                    ops.addLayerOf(MapLayerIds.weatherLayer('radar_dwd', n)))!
                .properties!['raster-opacity']
            as double?;

    test(
      'each frame its own source, those kept unseen at no opacity',
      () async {
        await map.setWeatherLayers([
          rain('a', <String>['b', 'c']),
        ]);
        expect(ops.callsNamed('addImageSource'), hasLength(3));
        expect(opacityOf(0), radarSoftTone.opacity);
        expect(opacityOf(1), 0);
        expect(opacityOf(2), 0);
        expect(map.weatherAttributions.value, ['Radar: radar_dwd']);
      },
    );

    test('showing a frame kept unseen adds nothing: the new one up, then '
        'the old one down', () async {
      await map.setWeatherLayers([
        rain('a', <String>['b', 'c']),
      ]);
      ops.clearCalls();
      await map.setWeatherLayers([
        rain('b', <String>['a', 'c']),
      ]);
      expect(ops.names, ['setLayerProperties', 'setLayerProperties']);
      expect(ops.calls[0].id, MapLayerIds.weatherLayer('radar_dwd', 1));
      expect(opacityOf(1), radarSoftTone.opacity);
      expect(ops.calls[1].id, MapLayerIds.weatherLayer('radar_dwd', 0));
      expect(opacityOf(0), 0);
      // And on through the steps, still adding nothing.
      ops.clearCalls();
      await map.setWeatherLayers([
        rain('c', <String>['a', 'b']),
      ]);
      await map.setWeatherLayers([
        rain('a', <String>['b', 'c']),
      ]);
      expect(ops.callsNamed('addImageSource'), isEmpty);
      expect(ops.callsNamed('addLayer'), isEmpty);
      expect(ops.callsNamed('removeSource'), isEmpty);
    });

    test('a frame no longer kept goes at once; a new frame shown goes over '
        'the old, which then goes', () async {
      await map.setWeatherLayers([
        rain('a', <String>['b', 'c']),
      ]);
      await map.setWeatherLayers([
        rain('a', <String>['b']),
      ]);
      expect(
        ops.sourceIds,
        isNot(contains(MapLayerIds.weatherSource('radar_dwd', 2))),
      );
      ops.clearCalls();
      await map.setWeatherLayers([rain('d', const <String>[])]);
      expect(ops.callsNamed('addImageSource'), hasLength(1));
      expect(ops.names.first, 'addImageSource');
      expect(ops.sourceIds.where((id) => id.startsWith('velorki-weather-')), [
        MapLayerIds.weatherSource('radar_dwd', 3),
      ]);
    });

    test('a layer kept unseen altogether: no opacity, no credit', () async {
      await map.setWeatherLayers([
        rain('a', <String>['b'], visible: false),
      ]);
      expect(opacityOf(0), 0);
      expect(opacityOf(1), 0);
      expect(map.weatherAttributions.value, isEmpty);
      await map.setWeatherLayers([
        rain('b', <String>['a']),
      ]);
      expect(opacityOf(1), radarSoftTone.opacity);
      expect(opacityOf(0), 0);
      expect(map.weatherAttributions.value, ['Radar: radar_dwd']);
    });

    test(
      'a kept frame MapLibre cannot draw is left out, the rest drawn',
      () async {
        await map.setWeatherLayers([
          WeatherLayer.image(
            id: 'radar_dwd',
            kind: WeatherKind.radar,
            image: Uint8List.fromList(<int>[1]),
            imageBox: box,
            frameKey: 'a',
            attribution: 'Radar: radar_dwd',
            preloaded: <WeatherImageFrame>[
              frame('b'),
              WeatherImageFrame(
                frameKey: 'c',
                image: Uint8List.fromList(<int>[3]),
                box: const BoundingBox(
                  south: 86,
                  west: 13,
                  north: 88,
                  east: 14,
                ),
              ),
            ],
          ),
        ]);
        expect(ops.callsNamed('addImageSource'), hasLength(2));
      },
    );

    test('a dark map repaints each frame, the unseen ones unseen', () async {
      await map.setWeatherLayers([
        rain('a', <String>['b']),
      ]);
      await map.setWeatherDark(true);
      expect(opacityOf(0), radarSoftTone.opacity);
      expect(opacityOf(1), 0);
    });

    test('the rider\'s opacity scales what is seen, live, the unseen frames '
        'at none, nothing added', () async {
      double? cloudsOpacity() =>
          (ops.lastPropertiesOf(
                        MapLayerIds.weatherLayer('clouds_eumetsat.0', 0),
                      ) ??
                      ops.addLayerOf(
                        MapLayerIds.weatherLayer('clouds_eumetsat.0', 0),
                      ))!
                  .properties!['raster-opacity']
              as double?;
      await map.setWeatherLayers([
        _clouds('clouds_eumetsat.0', 'x'),
        rain('a', <String>['b']),
      ]);
      expect(cloudsOpacity(), cloudsLightTone.opacity);
      final before = ops.calls.length;
      await map.setWeatherOpacity(
        const WeatherOpacity(radar: 0.5, clouds: 0.6),
      );
      // The clouds are generation 0, the rain's frames 1 and 2.
      expect(opacityOf(1), closeTo(radarSoftTone.opacity * 0.5, 1e-9));
      expect(opacityOf(2), 0);
      expect(cloudsOpacity(), closeTo(cloudsLightTone.opacity * 0.6, 1e-9));
      // Only the frames seen were repainted; nothing fetched or added.
      final repainted = ops.calls.skip(before).toList();
      expect(repainted, hasLength(2));
      expect(repainted.map((c) => c.name), everyElement('setLayerProperties'));
      // Stepping on, the frame shown takes the scaled opacity, the one
      // before none.
      await map.setWeatherLayers([
        _clouds('clouds_eumetsat.0', 'x'),
        rain('b', <String>['a']),
      ]);
      expect(opacityOf(2), closeTo(radarSoftTone.opacity * 0.5, 1e-9));
      expect(opacityOf(1), 0);
      // A new frame over the old: added at the scaled opacity.
      await map.setWeatherLayers([
        _clouds('clouds_eumetsat.0', 'x'),
        rain('d', const <String>[]),
      ]);
      expect(opacityOf(3), closeTo(radarSoftTone.opacity * 0.5, 1e-9));
      // A dark map keeps the share.
      await map.setWeatherDark(true);
      expect(cloudsOpacity(), closeTo(cloudsDarkTone.opacity * 0.6, 1e-9));
      // A source's own opacity is scaled too.
      await map.setWeatherLayers([_radar('radar_noaa', '1')]);
      expect(
        ops
            .addLayerOf(MapLayerIds.weatherLayer('radar_noaa', 4))!
            .properties!['raster-opacity'],
        closeTo(radarTone.opacity * 0.5, 1e-9),
      );
    });

    test('a map made with the rider\'s opacity draws with it', () async {
      final scaled = MaplibreMapControllerAdapter.withOps(
        ops,
        weatherSwapDelay: Duration.zero,
        weatherOpacity: const WeatherOpacity(),
      );
      await scaled.attachToStyle();
      await scaled.setWeatherLayers([
        rain('a', <String>['b']),
      ]);
      expect(
        opacityOf(0),
        closeTo(radarSoftTone.opacity * weatherOpacityDefault, 1e-9),
      );
      expect(opacityOf(1), 0);
    });
  });

  group('wind', () {
    WindArrows arrows(double ms) => WindArrows(
      arrows: <WindArrow>[
        WindArrow(at: const LatLng(47.5, 8.5), dir: 180, ms: ms),
        WindArrow(at: const LatLng(47.6, 8.6), dir: 90, ms: ms),
      ],
      attribution: 'Wind: Deutscher Wetterdienst (CC BY 4.0)',
    );

    test('arrows are a symbol layer of one SDF arrow under the labels, '
        'credited', () async {
      await map.setWindArrows(arrows(6));
      final image = ops.lastCall('addImage')!;
      expect(image.id, MapLayerIds.windArrowImage);
      expect(image.sdf, isTrue);
      final data = ops.lastGeoJsonOf(MapLayerIds.windSource)!;
      final features = data['features'] as List;
      expect(features, hasLength(2));
      final first = features.first as Map<String, dynamic>;
      expect(first['properties'], <String, dynamic>{'dir': 180.0, 'ms': 6.0});
      expect((first['geometry'] as Map)['coordinates'], <double>[8.5, 47.5]);
      final layer = ops.addLayerOf(MapLayerIds.windLayer)!;
      expect(layer.belowLayerId, 'waterway_line_label');
      expect(layer.enableInteraction, isFalse);
      final props = layer.properties!;
      expect(props['icon-image'], MapLayerIds.windArrowImage);
      expect(props['icon-rotate'], <Object>['get', 'dir']);
      expect(props['icon-rotation-alignment'], 'map');
      expect(props['icon-allow-overlap'], isTrue);
      expect(props['icon-ignore-placement'], isTrue);
      const palette = MapPalette.classic();
      expect(props['icon-color'], <Object>[
        'step',
        <Object>['get', 'ms'],
        palette.windArrowCalm,
        2.0,
        palette.windArrowLight,
        5.0,
        palette.windArrowModerate,
        8.0,
        palette.windArrowFresh,
        11.0,
        palette.windArrowStrong,
      ]);
      expect(props['icon-halo-color'], palette.windArrowHalo);
      expect(props['icon-halo-width'], windArrowHaloWidth);
      expect(map.weatherAttributions.value, [
        'Wind: Deutscher Wetterdienst (CC BY 4.0)',
      ]);
    });

    test('over the rain and the clouds, whichever comes first', () async {
      // The rain first: the arrows go over it.
      await map.setWeatherLayers([_radar('radar_dwd', '1')]);
      await map.setWindArrows(arrows(3));
      expect(
        ops.addLayerOf(MapLayerIds.windLayer)!.belowLayerId,
        'waterway_line_label',
      );
      // The clouds after: under the rain, so under the arrows.
      await map.setWeatherLayers([
        _clouds('clouds_eumetsat.0', 'a'),
        _radar('radar_dwd', '1'),
      ]);
      expect(
        ops
            .addLayerOf(MapLayerIds.weatherLayer('clouds_eumetsat.0', 1))!
            .belowLayerId,
        MapLayerIds.weatherLayer('radar_dwd', 0),
      );
      // A new rain frame: under the arrows.
      await map.setWeatherLayers([
        _clouds('clouds_eumetsat.0', 'a'),
        _radar('radar_dwd', '2'),
      ]);
      expect(
        ops.addLayerOf(MapLayerIds.weatherLayer('radar_dwd', 2))!.belowLayerId,
        MapLayerIds.windLayer,
      );
      expect(map.weatherAttributions.value, [
        'Clouds: clouds_eumetsat.0',
        'Radar: radar_dwd',
        'Wind: Deutscher Wetterdienst (CC BY 4.0)',
      ]);
    });

    test('over the cycle map, whichever comes first', () async {
      // The cycle map first: the arrows go over it, under the labels.
      await map.setCycleMap('/cycle.geojson');
      await map.setWindArrows(arrows(3));
      expect(
        ops.addLayerOf(MapLayerIds.windLayer)!.belowLayerId,
        'waterway_line_label',
      );
      // A new cycle map after: under the arrows.
      await map.setCycleMap('/cycle2.geojson');
      expect(
        ops
            .addLayerOf(
              CycleMapLayers.layerId(
                1,
                const CycleMapLayers(CycleMapColors.light).layers.first,
              ),
            )!
            .belowLayerId,
        MapLayerIds.windLayer,
      );
      // The rain under the cycle map, and so under the arrows.
      await map.setWeatherLayers([_radar('radar_dwd', '1')]);
      expect(
        ops.addLayerOf(MapLayerIds.weatherLayer('radar_dwd', 0))!.belowLayerId,
        startsWith('velorki-cycle'),
      );
    });

    test('new arrows replace the data; none empties it, uncredited', () async {
      await map.setWindArrows(arrows(3));
      ops.clearCalls();
      await map.setWindArrows(arrows(12));
      expect(ops.names, ['setGeoJsonSource']);
      await map.setWindArrows(null);
      expect(ops.lastGeoJsonOf(MapLayerIds.windSource)!['features'], isEmpty);
      expect(map.weatherAttributions.value, isEmpty);
    });

    test('back after a style reload, image and all', () async {
      await map.setWindArrows(arrows(3));
      ops.clearCalls();
      await map.attachToStyle();
      await pumpEventQueue();
      expect(
        ops.callsNamed('addImage').map((c) => c.id),
        contains(MapLayerIds.windArrowImage),
      );
      expect(ops.addLayerOf(MapLayerIds.windLayer), isNotNull);
    });

    test('a new palette recolours the arrows', () async {
      await map.setWindArrows(arrows(3));
      final night = MapPalette.fromTheme(buildDarkTheme(AccentPreset.ember));
      await map.setPalette(night);
      final props = ops.lastPropertiesOf(MapLayerIds.windLayer)!.properties!;
      expect((props['icon-color'] as List)[6], night.windArrowModerate);
      expect(props['icon-halo-color'], night.windArrowHalo);
      // A little lighter on a dark map.
      expect(
        night.windArrowModerate,
        isNot(MapPalette.classic().windArrowModerate),
      );
    });

    test('a cool ramp by strength, outlined in white on every look, apart '
        'from the roads\' arrows and the rain', () {
      for (final palette in <MapPalette>[
        const MapPalette.classic(),
        MapPalette.fromTheme(buildLightTheme(AccentPreset.ember)),
        MapPalette.fromTheme(buildDarkTheme(AccentPreset.ember)),
      ]) {
        // White, at most a little see-through.
        expect(palette.windArrowHalo, startsWith('#FFFFFF'));
        final ramp = <String>[
          palette.windArrowLight,
          palette.windArrowModerate,
          palette.windArrowFresh,
          palette.windArrowStrong,
        ].map(colorFromMapHex).map(HSVColor.fromColor).toList();
        for (final c in ramp) {
          // Coloured, not a grey or white like a road's arrow.
          expect(c.saturation, greaterThan(0.5), reason: '$c');
          // Blue to magenta: none of the rain's greens, yellows, oranges
          // or reds.
          expect(c.hue, inInclusiveRange(190, 330), reason: '$c');
        }
        // Each step on along the ramp, sky blue to magenta.
        for (var i = 1; i < ramp.length; i++) {
          expect(ramp[i].hue, greaterThan(ramp[i - 1].hue));
        }
        // Calm a neutral grey.
        expect(
          HSVColor.fromColor(colorFromMapHex(palette.windArrowCalm)).saturation,
          lessThan(0.2),
        );
      }
    });
  });
}
