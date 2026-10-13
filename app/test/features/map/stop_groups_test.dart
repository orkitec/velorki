import 'dart:math' show Point;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/map/application/map_stops_controller.dart'
    show stopGroupOrder, stopMarker;
import 'package:velorki/features/map/data/geojson.dart';
import 'package:velorki/features/map/data/maplibre_map_controller.dart';
import 'package:velorki/features/map/data/marker_layers.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/maplibre_style_ops_fake.dart';

MaplibreMapControllerAdapter _adapter(RecordingStyleOps ops) =>
    MaplibreMapControllerAdapter.withOps(
      ops,
      cyclosmTileUrl: '',
      palette: const MapPalette.classic(),
    );

MapPoi _cafe(double lat, {bool selected = false}) => MapPoi(
  position: LatLng(lat, 11),
  name: 'c$lat',
  kind: MapPoiKind.food,
  icon: Icons.local_cafe_outlined,
  selected: selected,
  group: 'cafe',
);

MapPoi _water(double lat) => MapPoi(
  position: LatLng(lat, 11),
  name: 'w$lat',
  kind: MapPoiKind.water,
  icon: Icons.water_drop_outlined,
  group: 'drinking_water',
);

const List<String> _three = <String>['drinking_water', 'cafe', 'toilets'];

List<dynamic> _featuresOf(RecordingStyleOps ops, String sourceId) =>
    ops.lastGeoJsonOf(sourceId)!['features'] as List<dynamic>;

/// The sources written since the calls were last cleared.
List<String> _written(RecordingStyleOps ops) => <String>[
  for (final call in ops.calls)
    if (call.name == 'setGeoJsonSource') call.id!,
];

List<String> _registered(RecordingStyleOps ops) =>
    ops.callsNamed('addImage').map((c) => c.id!).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stopGroupLayout', () {
    MapPoi of(String group) => MapPoi(
      position: const LatLng(0, 0),
      name: '',
      kind: MapPoiKind.generic,
      group: group,
    );

    test('keeps the wanted order, then groups not wanted by name', () {
      expect(
        stopGroupLayout(
          <String>['cafe', 'toilets'],
          <MapPoi>[of('zoo'), of('bakery'), of('cafe')],
        ),
        <String>['cafe', 'toilets', 'bakery', 'zoo'],
      );
    });

    test('gathers the groups past the most into one', () {
      final wanted = <String>[for (var i = 0; i < 20; i++) 'k$i'];
      final layout = stopGroupLayout(wanted, const <MapPoi>[]);
      expect(layout, hasLength(stopGroupsMax));
      expect(layout.take(stopGroupsMax - 1), wanted.take(stopGroupsMax - 1));
      expect(layout.last, stopGroupMore);
    });
  });

  group('stopGroupOrder', () {
    test('is the order the app knows the kinds in, whatever the set', () {
      expect(
        stopGroupOrder(<String>{'bakery', 'cafe', 'toilets', 'drinking_water'}),
        <String>['drinking_water', 'toilets', 'cafe', 'bakery'],
      );
      expect(stopGroupOrder(<String>{'zz_unknown', 'cafe'}), <String>[
        'cafe',
        'zz_unknown',
      ]);
    });

    test('a stop marker carries its kind as its group', () {
      const stop = SearchResult(
        kind: SearchKind.poi,
        name: '',
        position: LatLng(0, 0),
        detail: 'cafe',
      );
      expect(stopMarker(stop).group, 'cafe');
    });
  });

  group('the fan of the groups', () {
    test('a lone group stands where its stops are', () {
      expect(MarkerLayers.groupFanOffset(0, 1), Offset.zero);
    });

    test('groups stand off evenly round a circle, the first straight up', () {
      const r = MarkerLayers.groupFanRadiusPx;
      expect(MarkerLayers.groupFanOffset(0, 4), const Offset(0, -r));
      expect(MarkerLayers.groupFanOffset(1, 4), const Offset(r, 0));
      expect(MarkerLayers.groupFanOffset(2, 4), const Offset(0, r));
      for (var i = 0; i < 13; i++) {
        final o = MarkerLayers.groupFanOffset(i, 13);
        expect(o.distance, closeTo(r, 0.1));
      }
    });
  });

  group('stops gathered by group', () {
    test('each group gets a clustered source and three layers, in order, '
        'and its stops alone', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setStops(<MapPoi>[
        _cafe(48),
        _water(48.1),
        _cafe(48.2),
      ], groups: _three);

      for (final group in _three) {
        final source = ops
            .callsNamed('addSource')
            .singleWhere((c) => c.id == MapLayerIds.stopGroupSource(group));
        expect(source.properties!['cluster'], isTrue, reason: group);
        expect(source.properties!['clusterMaxZoom'], stopsClusterMaxZoom);
        expect(
          ops.addLayerOf(MapLayerIds.stopGroupLayer(group))!.filter,
          MarkerLayers.isNotCluster,
        );
        expect(
          ops.addLayerOf(MapLayerIds.stopGroupClusterLayer(group))!.filter,
          MarkerLayers.isCluster,
        );
        // Every group goes under the stops of no group, the first lowest.
        expect(
          ops.addLayerOf(MapLayerIds.stopGroupLayer(group))!.belowLayerId,
          MapLayerIds.stopsLayer,
        );
      }
      final added = <String>[
        for (final c in ops.callsNamed('addLayer')) c.layerId!,
      ];
      expect(
        added.indexOf(MapLayerIds.stopGroupClusterLayer('drinking_water')),
        lessThan(added.indexOf(MapLayerIds.stopGroupLayer('cafe'))),
      );

      final cafes = _featuresOf(ops, MapLayerIds.stopGroupSource('cafe'));
      expect(cafes.map((f) => f['properties']['name']), <String>[
        'c48.0',
        'c48.2',
      ]);
      expect(cafes.map((f) => f['id']), <String>[
        stopFeatureId(0),
        stopFeatureId(1),
      ]);
      expect(
        _featuresOf(ops, MapLayerIds.stopGroupSource('drinking_water')),
        hasLength(1),
      );
      // No stop of its own, nothing written to it.
      expect(
        _written(ops),
        isNot(contains(MapLayerIds.stopGroupSource('toilets'))),
      );

      // Each group's bubbles stand off in their own direction.
      for (var i = 0; i < _three.length; i++) {
        final fan = MarkerLayers.groupFanOffset(i, _three.length);
        final bubble = ops
            .addLayerOf(MapLayerIds.stopGroupClusterLayer(_three[i]))!
            .properties!;
        expect(bubble['icon-offset'], <double>[fan.dx, fan.dy]);
        expect(bubble['icon-allow-overlap'], isTrue);
        expect(bubble['icon-ignore-placement'], isTrue);
        expect(bubble['text-allow-overlap'], isTrue);
        expect(bubble['icon-image'], MarkerLayers.groupImage(_three[i]));
      }
    });

    test('a write rewrites only the groups whose stops changed, and the '
        'same stops again write nothing', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setStops(<MapPoi>[_cafe(48), _water(48.1)], groups: _three);

      ops.clearCalls();
      await adapter.setStops(<MapPoi>[_cafe(48), _water(48.1)], groups: _three);
      expect(_written(ops), isEmpty);
      expect(ops.callsNamed('addLayer'), isEmpty);
      expect(ops.callsNamed('addImage'), isEmpty);

      ops.clearCalls();
      await adapter.setStops(<MapPoi>[
        _cafe(48),
        _water(48.1),
        _water(48.3),
      ], groups: _three);
      expect(_written(ops), <String>[
        MapLayerIds.stopGroupSource('drinking_water'),
      ]);

      // The chosen stop changes its group's source alone.
      ops.clearCalls();
      await adapter.setStops(<MapPoi>[
        _cafe(48, selected: true),
        _water(48.1),
        _water(48.3),
      ], groups: _three);
      expect(_written(ops), <String>[MapLayerIds.stopGroupSource('cafe')]);
    });

    test('groups no longer wanted lose their source and layers, a new one '
        'goes in its place in the order, and the fan follows', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setStops(<MapPoi>[_cafe(48)], groups: _three);

      ops.clearCalls();
      await adapter.setStops(<MapPoi>[_cafe(48)], groups: <String>['cafe']);
      for (final group in <String>['drinking_water', 'toilets']) {
        expect(
          ops.callsNamed('removeSource').map((c) => c.id),
          contains(MapLayerIds.stopGroupSource(group)),
        );
        expect(
          ops.callsNamed('removeLayer').map((c) => c.id),
          containsAll(<String>[
            MapLayerIds.stopGroupLayer(group),
            MapLayerIds.stopGroupLabelLayer(group),
            MapLayerIds.stopGroupClusterLayer(group),
          ]),
        );
      }
      expect(
        ops.sourceIds,
        isNot(contains(MapLayerIds.stopGroupSource('toilets'))),
      );
      expect(ops.callsNamed('removeSource'), hasLength(2));
      // Alone now, the cafes' bubbles stand where their stops are.
      expect(
        ops
            .lastPropertiesOf(MapLayerIds.stopGroupClusterLayer('cafe'))!
            .properties!['icon-offset'],
        <double>[0, 0],
      );
      expect(_written(ops), isEmpty);

      ops.clearCalls();
      await adapter.setStops(
        <MapPoi>[_cafe(48), _water(48.1)],
        groups: <String>['drinking_water', 'cafe'],
      );
      expect(
        ops
            .addLayerOf(MapLayerIds.stopGroupLayer('drinking_water'))!
            .belowLayerId,
        MapLayerIds.stopGroupLayer('cafe'),
      );

      // Stops off: every group goes.
      ops.clearCalls();
      await adapter.setStops(const <MapPoi>[]);
      expect(ops.callsNamed('removeSource'), hasLength(2));
    });

    test('a group\'s bubbles are drawn once, a picture per width of count, '
        'and again in a new palette', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setStops(<MapPoi>[_cafe(48), _cafe(48.2)], groups: _three);
      final bubbles = <String>[
        for (var n = 1; n <= 3; n++) MarkerLayers.groupImageName('cafe', n),
      ];
      expect(_registered(ops), containsAll(bubbles));
      // No stops of their own: no pictures for them.
      expect(
        _registered(ops).where((n) => n.contains('drinking_water')),
        isEmpty,
      );

      ops.clearCalls();
      await adapter.setStops(<MapPoi>[_cafe(48), _cafe(48.3)], groups: _three);
      expect(_registered(ops), isEmpty);

      ops.clearCalls();
      await adapter.setPalette(MapPalette.fromTheme(buildDarkTheme()));
      expect(_registered(ops), containsAll(bubbles));
    });

    test('a tap on a group\'s bubble zooms to where that group\'s bubble '
        'splits', () async {
      final ops = RecordingStyleOps()
        ..cameraPosition = const ml.CameraPosition(
          target: ml.LatLng(48, 11),
          zoom: 12,
        )
        ..clusterExpansionZooms[4] = 14
        ..renderedFeatures = <Map<String, dynamic>>[
          <String, dynamic>{
            'layer': MapLayerIds.stopGroupClusterLayer('cafe'),
            'type': 'Feature',
            'properties': <String, dynamic>{'cluster_id': 4, 'point_count': 5},
            'geometry': <String, dynamic>{
              'type': 'Point',
              'coordinates': <double>[11.001, 48.001],
            },
          },
        ];
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setStops(<MapPoi>[_cafe(48), _water(48.1)], groups: _three);
      final stops = <int>[];
      adapter.onStopTapped = stops.add;
      ops.clearCalls();

      for (final callback in List.of(ops.onFeatureTapped)) {
        callback(
          const Point<double>(0, 0),
          const ml.LatLng(48.0011, 11.0011),
          '4',
          MapLayerIds.stopGroupClusterLayer('cafe'),
          null,
        );
      }
      await pumpEventQueue();

      expect(stops, isEmpty);
      expect(ops.clusterExpansionSources, <String>[
        MapLayerIds.stopGroupSource('cafe'),
      ]);
      final update = ops.lastCall('animateCamera')!.cameraUpdate! as List;
      expect(update[0], 'newLatLngZoom');
      expect((update[1] as List)[0] as double, closeTo(48.001, 1e-9));
      expect(update[2], 14.0);
    });

    test('a tap on a single stop of a group reports its index among all the '
        'stops', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setStops(<MapPoi>[
        _cafe(48),
        _water(48.1),
        _cafe(48.2),
      ], groups: _three);
      final stops = <int>[];
      adapter.onStopTapped = stops.add;

      for (final callback in List.of(ops.onFeatureTapped)) {
        callback(
          const Point<double>(0, 0),
          const ml.LatLng(48.2, 11),
          stopFeatureId(1),
          MapLayerIds.stopGroupLayer('cafe'),
          null,
        );
        callback(
          const Point<double>(0, 0),
          const ml.LatLng(48.1, 11),
          stopFeatureId(0),
          MapLayerIds.stopGroupLayer('drinking_water'),
          null,
        );
      }
      await pumpEventQueue();

      expect(stops, <int>[2, 1]);
    });

    test('after a style reload the groups are drawn again', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setStops(<MapPoi>[_cafe(48)], groups: _three);

      ops
        ..reloadStyle()
        ..clearCalls();
      await adapter.attachToStyle();
      expect(
        _featuresOf(ops, MapLayerIds.stopGroupSource('cafe')),
        hasLength(1),
      );
      expect(
        _registered(ops),
        contains(MarkerLayers.groupImageName('cafe', 1)),
      );
    });
  });
}
