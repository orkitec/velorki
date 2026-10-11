import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/cycle_map_layers.dart';
import 'package:velorki/features/map/data/maplibre_map_controller.dart';
import 'package:velorki/features/map/data/weather_paint.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
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
  imageBox: eumetsatClouds.coverage.single,
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
    expect(corners.first, [75.0, -30.0]); // top left, lat/lng
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
}
