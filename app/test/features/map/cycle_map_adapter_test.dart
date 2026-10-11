import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/cycle_map_layers.dart';
import 'package:velorki/features/map/data/maplibre_map_controller.dart';
import 'package:velorki/features/map/domain/cycle_map.dart';

import 'support/maplibre_style_ops_fake.dart';

void main() {
  late RecordingStyleOps ops;
  late MaplibreMapControllerAdapter map;
  final layers = const CycleMapLayers(CycleMapColors.light).layers;

  setUp(() async {
    ops = RecordingStyleOps()
      ..styleLayerIds = <String>['road_minor', 'waterway_line_label', 'poi'];
    map = MaplibreMapControllerAdapter.withOps(
      ops,
      cycleMapSwapDelay: Duration.zero,
    );
    await map.attachToStyle();
    ops.clearCalls();
  });

  List<String> cycleLayers() => [
    for (final id in ops.layerIds)
      if (id.startsWith('velorki-cycle-')) id,
  ];

  test('loads the file as a source under the base map labels', () async {
    await map.setCycleMap('/data/out/cycle-map-1.geojson');
    final source = ops.addSourceOf(CycleMapLayers.sourceId(0))!;
    expect(source.properties!['data'], 'file:///data/out/cycle-map-1.geojson');
    expect(cycleLayers(), hasLength(layers.length));
    for (final layer in layers) {
      final added = ops.addLayerOf(CycleMapLayers.layerId(0, layer))!;
      expect(added.belowLayerId, 'waterway_line_label');
      expect(added.enableInteraction, isFalse);
      expect(added.filter, layer.filter);
    }
    expect(
      ops.images,
      containsAll(<String>[
        CycleMapLayers.arrowImage,
        CycleMapLayers.onewayStreetImage,
        CycleMapLayers.climbImage,
        CycleMapLayers.contraflowImage,
      ]),
    );
  });

  test('a style it does not know: under everything Velorki draws', () async {
    ops = RecordingStyleOps();
    map = MaplibreMapControllerAdapter.withOps(
      ops,
      cycleMapSwapDelay: Duration.zero,
    );
    await map.attachToStyle();
    await map.setCycleMap('/a.geojson');
    expect(
      ops.addLayerOf(CycleMapLayers.layerId(0, layers.first))!.belowLayerId,
      MapLayerIds.trackLayer,
    );
  });

  test('the parts not wanted are hidden', () async {
    await map.setCycleMapParts({CycleMapPart.infrastructure});
    await map.setCycleMap('/a.geojson');
    final hidden = {
      for (final c in ops.callsNamed('setLayerVisibility'))
        if (c.visible == false) c.id,
    };
    for (final layer in layers) {
      expect(
        hidden.contains(CycleMapLayers.layerId(0, layer)),
        layer.part != CycleMapPart.infrastructure,
        reason: layer.name,
      );
    }
  });

  test('a new file swaps the source and takes the old one away', () async {
    await map.setCycleMap('/a.geojson');
    await map.setCycleMap('/b.geojson');
    expect(ops.sourceIds, contains(CycleMapLayers.sourceId(1)));
    expect(ops.sourceIds, isNot(contains(CycleMapLayers.sourceId(0))));
    expect(cycleLayers(), hasLength(layers.length));
    expect(
      cycleLayers().every((id) => id.startsWith('velorki-cycle-1-')),
      isTrue,
    );
    // The old layers went before their source.
    final names = ops.names;
    expect(
      names.lastIndexOf('removeLayer'),
      lessThan(names.lastIndexOf('removeSource')),
    );
  });

  test('null takes the cycle map away', () async {
    await map.setCycleMap('/a.geojson');
    await map.setCycleMap(null);
    expect(cycleLayers(), isEmpty);
    expect(ops.sourceIds.where((s) => s.startsWith('velorki-cycle')), isEmpty);
  });

  test('parts switched later show and hide the drawn layers', () async {
    await map.setCycleMap('/a.geojson');
    ops.clearCalls();
    await map.setCycleMapParts({CycleMapPart.surface});
    final calls = ops.callsNamed('setLayerVisibility');
    expect(calls, hasLength(layers.length));
    for (final c in calls) {
      final layer = layers.firstWhere(
        (l) => CycleMapLayers.layerId(0, l) == c.id,
      );
      expect(c.visible, layer.part == CycleMapPart.surface);
    }
  });

  test('a style reload draws the last file again', () async {
    await map.setCycleMap('/a.geojson');
    ops.reloadStyle();
    await map.attachToStyle();
    final sources = ops.sourceIds.where((s) => s.startsWith('velorki-cycle'));
    expect(sources, hasLength(1));
    expect(ops.lastCall('addSource')!.properties!['data'], 'file:///a.geojson');
    expect(cycleLayers(), hasLength(layers.length));
  });

  test(
    'a new palette repaints the layers and keeps hidden ones hidden',
    () async {
      await map.setCycleMapParts({CycleMapPart.infrastructure});
      await map.setCycleMap('/a.geojson');
      ops.clearCalls();
      await map.setPalette(
        const MapPalette(
          routeMain: '#1565C0',
          routeMainCasing: '#0D3C6E',
          routeAlternative: '#78909C',
          routeAlternatives: <String>['#78909C'],
          routePreview: '#EF6C00',
          track: '#AD1457',
          trackSlow: '#1D6FD0',
          trackFast: '#AD1457',
          waypointStart: '#2E7D32',
          waypointVia: '#1565C0',
          waypointEnd: '#C62828',
          waypointStroke: '#FFFFFF',
          waypointLabel: '#FFFFFF',
          waypointLabelHalo: '#00000055',
          mapLabel: '#14171A',
          mapLabelHalo: '#FFFFFFCC',
          positionDot: '#1E88E5',
          positionAccuracy: '#1E88E5',
          cycle: CycleMapColors.dark,
        ),
      );
      final repainted = {
        for (final c in ops.callsNamed('setLayerProperties')) c.id,
      };
      for (final layer in layers) {
        expect(repainted, contains(CycleMapLayers.layerId(0, layer)));
      }
      final shownAfter = {
        for (final c in ops.callsNamed('setLayerVisibility')) c.id: c.visible,
      };
      final rough = layers.firstWhere((l) => l.name == 'rough');
      expect(shownAfter[CycleMapLayers.layerId(0, rough)], isFalse);
    },
  );

  test('every layer fades in over the zoom step before its own', () async {
    await map.setCycleMap('/a.geojson');
    for (final layer in layers) {
      final added = ops.addLayerOf(CycleMapLayers.layerId(0, layer))!;
      final props = added.properties!;
      final opacity =
          props['line-opacity'] ??
          props['icon-opacity'] ??
          props['circle-opacity'];
      expect(opacity, isA<List<Object?>>(), reason: layer.name);
      final fade = opacity as List<Object?>;
      expect(fade[0], 'interpolate');
      expect(fade[3], layer.minZoom, reason: layer.name);
      expect(fade[4], 0);
    }
  });

  test('no one-way street chevron where a lane shows its own way', () {
    final layer = layers.firstWhere((l) => l.name == 'oneway-streets');
    expect(
      layer.filter,
      containsAll(<Object>[
        <Object>[
          '!',
          <Object>['has', 'dl'],
        ],
        <Object>[
          '!',
          <Object>['has', 'dr'],
        ],
      ]),
    );
  });
}
