import 'dart:math' show Point;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:velorki/features/map/data/cyclosm_tone.dart';
import 'package:velorki/features/map/data/geojson.dart';
import 'package:velorki/features/map/data/heading_cone.dart';
import 'package:velorki/features/map/data/maplibre_map_controller.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/maplibre_style_ops_fake.dart';

/// A CyclOSM style template with the subdomain placeholder the real one has.
const String _cyclosmTemplate = 'https://{s}.tile.cyclosm.org/{z}/{x}/{y}.png';

const List<LatLng> _points = <LatLng>[LatLng(47.0, 8.0), LatLng(47.1, 8.1)];

/// A palette sharing no colour with [MapPalette.classic], so a repaint is
/// visible in every property the adapter writes.
const MapPalette _repainted = MapPalette(
  routeMain: '#111111',
  routeMainCasing: '#222222',
  routeAlternative: '#333333',
  routeAlternatives: <String>['#333333', '#343434', '#353535'],
  routePreview: '#444444',
  track: '#555555',
  trackSlow: '#505050',
  trackFast: '#5F5F5F',
  waypointStart: '#666666',
  waypointVia: '#777777',
  waypointEnd: '#888888',
  waypointStroke: '#999999',
  waypointLabel: '#AAAAAA',
  waypointLabelHalo: '#BBBBBB',
  positionDot: '#CCCCCC',
  positionAccuracy: '#DDDDDD',
);

final List<TrackSegment> _segments = <TrackSegment>[
  TrackSegment(points: _points, t: 0),
  TrackSegment(
    points: const <LatLng>[LatLng(47.1, 8.1), LatLng(47.2, 8.2)],
    t: 1,
  ),
];

const List<MapWaypoint> _waypoints = <MapWaypoint>[
  MapWaypoint(position: LatLng(47.0, 8.0), kind: MapWaypointKind.start),
  MapWaypoint(position: LatLng(47.2, 8.2), kind: MapWaypointKind.end),
];

MaplibreMapControllerAdapter _adapter(
  RecordingStyleOps ops, {
  String cyclosmTileUrl = '',
  MapPalette palette = const MapPalette.classic(),
  RasterTone cyclosmTone = lightCyclosmTone,
}) => MaplibreMapControllerAdapter.withOps(
  ops,
  cyclosmTileUrl: cyclosmTileUrl,
  palette: palette,
  cyclosmTone: cyclosmTone,
);

/// The features of the collection last written to [sourceId].
List<dynamic> _featuresOf(RecordingStyleOps ops, String sourceId) =>
    ops.lastGeoJsonOf(sourceId)!['features'] as List<dynamic>;

/// The properties of the first feature last written to [sourceId].
Map<String, dynamic> _firstProperties(RecordingStyleOps ops, String source) =>
    (_featuresOf(ops, source).first as Map<String, dynamic>)['properties']
        as Map<String, dynamic>;

void main() {
  // The heading cone is rasterised with dart:ui before it is registered.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('colorFromMapHex', () {
    test('reads the maplibre hex the palette travels as', () {
      expect(colorFromMapHex('#1E88E5'), const Color(0xFF1E88E5));
      // Without the `#` as well, since a style string may arrive either way.
      expect(colorFromMapHex('1E88E5'), const Color(0xFF1E88E5));
    });

    test('moves the trailing alpha of an 8 digit hex to the front', () {
      // maplibre writes `#RRGGBBAA`, dart:ui reads `0xAARRGGBB`.
      expect(colorFromMapHex('#00000055'), const Color(0x55000000));
      expect(colorFromMapHex('#FFFFFF66'), const Color(0x66FFFFFF));
    });

    test('falls back to opaque black on anything it cannot read', () {
      for (final hex in <String>['', '#12345', 'not-a-colour', '#12345678X']) {
        expect(colorFromMapHex(hex), const Color(0xFF000000), reason: hex);
      }
    });
  });

  group('attachToStyle', () {
    test('creates every source and layer in drawing order', () async {
      final ops = RecordingStyleOps();

      await _adapter(ops).attachToStyle();

      expect(
        ops.calls
            .where((c) => c.name == 'addGeoJsonSource' || c.name == 'addLayer')
            .map((c) => c.layerId ?? c.id)
            .toList(),
        <String>[
          MapLayerIds.trackSource,
          MapLayerIds.trackLayer,
          MapLayerIds.positionSource,
          // The ring is the bottom of the puck, the dot the top, so a route
          // line inserted below the ring stays under the whole puck.
          MapLayerIds.positionAccuracyLayer,
          MapLayerIds.positionHeadingLayer,
          MapLayerIds.positionHaloLayer,
          MapLayerIds.positionDotLayer,
          MapLayerIds.waypointsSource,
          MapLayerIds.waypointsHitLayer,
          MapLayerIds.waypointsCircleLayer,
          MapLayerIds.waypointsLabelLayer,
          MapLayerIds.poisSource,
          MapLayerIds.turnsSource,
          MapLayerIds.turnsLayer,
          MapLayerIds.poisCircleLayer,
          MapLayerIds.poisLabelLayer,
          MapLayerIds.searchPinSource,
          MapLayerIds.searchPinLayer,
          MapLayerIds.searchPinLabelLayer,
        ],
      );
    });

    test(
      'a tap on a point of interest or a turn marker reports its index',
      () async {
        final ops = RecordingStyleOps();
        final adapter = _adapter(ops);
        await adapter.attachToStyle();
        await adapter.setTurnMarkers(const <MapTurnMarker>[
          MapTurnMarker(position: LatLng(48, 11)),
          MapTurnMarker(position: LatLng(48.1, 11)),
        ]);
        expect(_featuresOf(ops, MapLayerIds.turnsSource), hasLength(2));
        final pois = <int>[];
        final turns = <int>[];
        adapter.onPoiTapped = pois.add;
        adapter.onTurnTapped = turns.add;

        for (final callback in List.of(ops.onFeatureTapped)) {
          callback(
            const Point<double>(0, 0),
            ml.LatLng(48, 11),
            poiFeatureId(2),
            MapLayerIds.poisCircleLayer,
            null,
          );
          callback(
            const Point<double>(0, 0),
            ml.LatLng(48.1, 11),
            turnFeatureId(1),
            MapLayerIds.turnsLayer,
            null,
          );
        }

        expect(pois, <int>[2]);
        expect(turns, <int>[1]);
      },
    );

    test('points of interest are written with their name and kind, and '
        'replayed after a style reload', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();

      await adapter.setPois(const <MapPoi>[
        MapPoi(
          position: LatLng(48, 11),
          name: 'Water Fountain',
          kind: MapPoiKind.water,
        ),
      ]);
      final features = _featuresOf(ops, MapLayerIds.poisSource);
      expect(features, hasLength(1));
      expect(features.single['properties'], {
        'name': 'Water Fountain',
        'kind': 'water',
      });

      await adapter.attachToStyle();
      expect(_featuresOf(ops, MapLayerIds.poisSource), hasLength(1));
    });

    test('starts every source off as an empty feature collection', () async {
      final ops = RecordingStyleOps();

      await _adapter(ops).attachToStyle();

      for (final source in <String>[
        MapLayerIds.trackSource,
        MapLayerIds.positionSource,
        MapLayerIds.waypointsSource,
        MapLayerIds.poisSource,
        MapLayerIds.turnsSource,
        MapLayerIds.searchPinSource,
      ]) {
        expect(
          ops.callsNamed('addGeoJsonSource').firstWhere((c) => c.id == source),
          isNotNull,
        );
        expect(_featuresOf(ops, source), isEmpty);
      }
    });

    test('registers the cone bitmap before the layer that names it', () async {
      final ops = RecordingStyleOps();

      await _adapter(ops).attachToStyle();

      final image = ops.calls.indexWhere(
        (c) => c.name == 'addImage' && c.id == headingConeImageName,
      );
      final layer = ops.calls.indexWhere(
        (c) => c.layerId == MapLayerIds.positionHeadingLayer,
      );
      expect(image, isNonNegative);
      expect(image, lessThan(layer));
      expect(
        ops
            .addLayerOf(MapLayerIds.positionHeadingLayer)!
            .properties!['icon-image'],
        headingConeImageName,
      );
      expect(ops.lastCall('addImage')!.imageBytes, isNotEmpty);
    });

    test('hides the cone unless the feature carries a heading', () async {
      final ops = RecordingStyleOps();

      await _adapter(ops).attachToStyle();

      final properties = ops
          .addLayerOf(MapLayerIds.positionHeadingLayer)!
          .properties!;
      expect(properties['icon-opacity'], <Object>[
        'case',
        <Object>['has', 'heading'],
        1,
        0,
      ]);
      // The cone points along a compass course, so it turns with the map.
      expect(properties['icon-rotation-alignment'], 'map');
      expect(properties['icon-rotate'], <Object>['get', 'heading']);
    });

    test('the waypoint hit discs, the turn markers and the points of '
        'interest are the layers that answer a touch', () async {
      final ops = RecordingStyleOps();

      await _adapter(ops).attachToStyle();

      // Only the hit discs are draggable (their features say so); the other
      // two report taps.
      final interactive = ops
          .callsNamed('addLayer')
          .where((c) => c.enableInteraction!)
          .map((c) => c.layerId)
          .toList();
      expect(interactive, <String>[
        MapLayerIds.waypointsHitLayer,
        MapLayerIds.turnsLayer,
        MapLayerIds.poisCircleLayer,
      ]);
    });

    test('names the glyph font the tile server actually serves', () async {
      final ops = RecordingStyleOps();

      await _adapter(ops).attachToStyle();

      expect(
        ops
            .addLayerOf(MapLayerIds.waypointsLabelLayer)!
            .properties!['text-font'],
        waypointLabelFont,
      );
    });

    test('reports itself attached only once the layers exist', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);

      expect(adapter.isAttached, isFalse);
      await adapter.attachToStyle();

      expect(adapter.isAttached, isTrue);
    });

    test('registers the drag callback exactly once per style load', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);

      await adapter.attachToStyle();
      await adapter.attachToStyle();

      expect(ops.onFeatureDrag, hasLength(1));
    });

    test('reads the visible region while attaching', () async {
      final ops = RecordingStyleOps()
        ..visibleRegion = ml.LatLngBounds(
          southwest: const ml.LatLng(46.5, 7.5),
          northeast: const ml.LatLng(47.5, 8.5),
        );
      final adapter = _adapter(ops);

      await adapter.attachToStyle();

      expect(
        adapter.visibleBounds,
        const BoundingBox(south: 46.5, west: 7.5, north: 47.5, east: 8.5),
      );
    });
  });

  group('the CyclOSM overlay', () {
    test('adds the raster source under everything Velorki draws', () async {
      final ops = RecordingStyleOps();

      await _adapter(ops, cyclosmTileUrl: _cyclosmTemplate).attachToStyle();

      final source = ops.lastCall('addSource')!;
      expect(source.id, MapLayerIds.cyclosmSource);
      // MapLibre does not understand `{s}`, so the template is expanded.
      expect(source.properties!['tiles'], <String>[
        'https://a.tile.cyclosm.org/{z}/{x}/{y}.png',
        'https://b.tile.cyclosm.org/{z}/{x}/{y}.png',
        'https://c.tile.cyclosm.org/{z}/{x}/{y}.png',
      ]);
      expect(source.properties!['attribution'], contains('CyclOSM'));
      expect(ops.calls.first.id, MapLayerIds.cyclosmSource);
      expect(ops.layerIds.first, MapLayerIds.cyclosmLayer);
    });

    test('adds nothing when no tile template is configured', () async {
      final ops = RecordingStyleOps();

      await _adapter(ops).attachToStyle();

      expect(ops.callsNamed('addSource'), isEmpty);
      expect(ops.layerIds, isNot(contains(MapLayerIds.cyclosmLayer)));
    });

    test('starts hidden while the overlay is switched off', () async {
      final ops = RecordingStyleOps();

      await _adapter(ops, cyclosmTileUrl: _cyclosmTemplate).attachToStyle();

      expect(
        ops.addLayerOf(MapLayerIds.cyclosmLayer)!.properties!['visibility'],
        'none',
      );
    });

    test('comes back visible after a style reload', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops, cyclosmTileUrl: _cyclosmTemplate);

      await adapter.setCyclosmOverlay(true);
      await adapter.attachToStyle();

      expect(adapter.isCyclosmVisible, isTrue);
      expect(
        ops.addLayerOf(MapLayerIds.cyclosmLayer)!.properties!['visibility'],
        'visible',
      );
    });

    test('toggles the layer visibility rather than re-adding it', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops, cyclosmTileUrl: _cyclosmTemplate);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setCyclosmOverlay(true);
      await adapter.setCyclosmOverlay(false);

      expect(
        ops.callsNamed('setLayerVisibility').map((c) => c.visible).toList(),
        <bool>[true, false],
      );
      expect(ops.callsNamed('addLayer'), isEmpty);
    });

    test('is added in the tone of the look on screen', () async {
      final ops = RecordingStyleOps();

      await _adapter(
        ops,
        cyclosmTileUrl: _cyclosmTemplate,
        cyclosmTone: nightInvertedTone,
      ).attachToStyle();

      final added = ops.addLayerOf(MapLayerIds.cyclosmLayer)!.properties!;
      expect(added, containsPair('raster-brightness-min', 1.0));
      expect(added, containsPair('raster-brightness-max', 0.0));
      expect(added, containsPair('raster-hue-rotate', 180.0));
      expect(added, containsPair('raster-saturation', -0.2));
      expect(added, containsPair('raster-opacity', 0.9));
    });

    test('is re-painted, not re-added, when the look changes', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops, cyclosmTileUrl: _cyclosmTemplate);
      await adapter.attachToStyle();
      await adapter.setCyclosmOverlay(true);
      ops.clearCalls();

      await adapter.setCyclosmTone(blackInvertedTone);

      final painted = ops.lastPropertiesOf(MapLayerIds.cyclosmLayer)!;
      expect(painted.properties, containsPair('raster-brightness-min', 0.85));
      expect(painted.properties, containsPair('raster-saturation', -0.4));
      // The overlay is on, and a repaint must not switch it off: the
      // visibility is left out of the write entirely.
      expect(painted.properties!.keys, isNot(contains('visibility')));
      expect(ops.callsNamed('addLayer'), isEmpty);
      expect(adapter.cyclosmTone, blackInvertedTone);
    });

    test('follows the dark-map setting without a style change', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(
        ops,
        cyclosmTileUrl: _cyclosmTemplate,
        cyclosmTone: nightInvertedTone,
      );
      await adapter.attachToStyle();
      ops.clearCalls();

      // The rider switched the treatment from inverted to dimmed; the map
      // look, and so the style, stayed where it was.
      await adapter.setCyclosmTone(nightDimmedTone);

      expect(
        ops.lastPropertiesOf(MapLayerIds.cyclosmLayer)!.properties,
        containsPair('raster-brightness-max', 0.55),
      );
      expect(ops.callsNamed('addLayer'), isEmpty);
    });

    test('writes nothing when the tone is already the one on screen', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(
        ops,
        cyclosmTileUrl: _cyclosmTemplate,
        cyclosmTone: nightInvertedTone,
      );
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setCyclosmTone(nightInvertedTone);

      expect(ops.calls, isEmpty);
    });

    test('is added in the new tone after the style reload', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops, cyclosmTileUrl: _cyclosmTemplate);

      // What a look change does: the tone is set, the style reloads, and the
      // overlay comes back painted for the new map.
      await adapter.setCyclosmTone(blackInvertedTone);
      await adapter.attachToStyle();

      expect(
        ops.addLayerOf(MapLayerIds.cyclosmLayer)!.properties,
        containsPair('raster-brightness-min', 0.85),
      );
    });

    test('a repaint of a style already gone is not an error', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops, cyclosmTileUrl: _cyclosmTemplate);
      await adapter.attachToStyle();
      ops.layerPropertiesError = PlatformException(
        code: 'LAYER_NOT_FOUND_ERROR',
        message: 'Layer not found',
      );

      await adapter.setCyclosmTone(nightInvertedTone);

      // The next attach draws the overlay in the tone set here.
      await adapter.attachToStyle();
      expect(
        ops.addLayerOf(MapLayerIds.cyclosmLayer)!.properties,
        containsPair('raster-hue-rotate', 180.0),
      );
    });

    test('re-toning does nothing without a tile template', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setCyclosmTone(nightInvertedTone);

      expect(ops.calls, isEmpty);
    });

    test('toggling does nothing without a tile template', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setCyclosmOverlay(true);

      expect(ops.calls, isEmpty);
      // The flag is still remembered, so the button can reflect it.
      expect(adapter.isCyclosmVisible, isTrue);
    });
  });

  group('setRouteLine', () {
    test(
      'a line the style kept through a reload is refreshed, not re-added',
      () async {
        // The plugin fires onStyleLoaded again without dropping the style's
        // sources on some Android builds; the adapter has forgotten the line
        // by then and adding it twice threw "already exists" in CI.
        final ops = RecordingStyleOps();
        final adapter = _adapter(ops);
        await adapter.attachToStyle();
        await adapter.setRouteLine('main', _points);
        ops.clearCalls();

        await adapter.attachToStyle();

        final source = MapLayerIds.routeSource('main');
        expect(
          ops.callsNamed('addGeoJsonSource').where((c) => c.id == source),
          isEmpty,
        );
        expect(ops.addLayerOf(MapLayerIds.routeLayer('main')), isNull);
        expect(ops.lastCall('setGeoJsonSource')!.id, source);
        expect(
          ops.lastCall('setLayerProperties')!.id,
          MapLayerIds.routeLayer('main'),
        );
      },
    );

    test('a source the style lost is drawn afresh when iOS says so', () async {
      // A style swap on iOS can drop a source between two writes; the
      // platform then refuses the update with sourceNotFound.
      final ops = RecordingStyleOps()..strictSources = true;
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setRouteLine('main', _points);
      ops.sourceIds.remove(MapLayerIds.routeSource('main'));
      ops.scriptedSourceIds.add(<String>[MapLayerIds.routeSource('main')]);
      ops.clearCalls();

      await adapter.setRouteLine('main', _points.reversed.toList());

      expect(
        ops.lastCall('addGeoJsonSource')!.id,
        MapLayerIds.routeSource('main'),
      );
      expect(ops.addLayerOf(MapLayerIds.routeLayer('main')), isNotNull);
    });

    test(
      'a line the style lists but refuses to update is drawn afresh',
      () async {
        // Mid-swap the style can still list a source it will not write to.
        final ops = RecordingStyleOps()..strictSources = true;
        final adapter = _adapter(ops);
        await adapter.attachToStyle();
        await adapter.setRouteLine('main', _points);
        await adapter.attachToStyle();
        ops.sourceIds.remove(MapLayerIds.routeSource('main'));
        ops.scriptedSourceIds.add(<String>[MapLayerIds.routeSource('main')]);
        ops.clearCalls();

        await adapter.setRouteLine('main', _points.reversed.toList());

        expect(
          ops.lastCall('addGeoJsonSource')!.id,
          MapLayerIds.routeSource('main'),
        );
        expect(ops.addLayerOf(MapLayerIds.routeLayer('main')), isNotNull);
      },
    );

    test('a waypoint write iOS refuses rebuilds the style once', () async {
      final ops = RecordingStyleOps()..strictSources = true;
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.sourceIds.remove(MapLayerIds.waypointsSource);
      // The style still lists the source when asked, but refuses the write.
      ops.scriptedSourceIds.add(<String>[MapLayerIds.waypointsSource]);
      ops.clearCalls();

      await adapter.setWaypoints(_waypoints);

      // Rebuilt: the base sources are added again and the waypoints replayed.
      expect(
        ops.callsNamed('addGeoJsonSource').map((c) => c.id),
        contains(MapLayerIds.waypointsSource),
      );
      expect(_featuresOf(ops, MapLayerIds.waypointsSource), hasLength(2));
    });

    test('a layer iOS reports missing mid-update is drawn afresh', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setRouteLine('main', _points);
      ops.clearCalls();
      ops.layerPropertiesError = PlatformException(
        code: 'LAYER_NOT_FOUND_ERROR',
        message: 'Layer velorki-route-main-linenot found',
      );

      await adapter.setRouteLine(
        'main',
        _points,
        style: RouteLineStyle.alternative,
      );

      expect(
        ops.lastCall('addGeoJsonSource')!.id,
        MapLayerIds.routeSource('main'),
      );
      expect(ops.addLayerOf(MapLayerIds.routeLayer('main')), isNotNull);
    });

    test('adds the source and the layer below the puck', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setRouteLine('main', _points);

      final source = ops.lastCall('addGeoJsonSource')!;
      expect(source.id, MapLayerIds.routeSource('main'));
      final geometry =
          (_featuresOf(ops, MapLayerIds.routeSource('main')).first
                  as Map<String, dynamic>)['geometry']
              as Map<String, dynamic>;
      expect(geometry['coordinates'], <List<double>>[
        <double>[8.0, 47.0],
        <double>[8.1, 47.1],
      ]);
      final layer = ops.lastCall('addLayer')!;
      expect(layer.layerId, MapLayerIds.routeLayer('main'));
      expect(layer.belowLayerId, MapLayerIds.positionAccuracyLayer);
      expect(layer.enableInteraction, isFalse);
      expect(
        layer.properties!['line-color'],
        const MapPalette.classic().routeMain,
      );
    });

    test('updates the existing source on the second call', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setRouteLine('main', _points);
      ops.clearCalls();

      await adapter.setRouteLine('main', const <LatLng>[
        LatLng(46.0, 7.0),
        LatLng(46.5, 7.5),
      ]);

      expect(ops.names, <String>['setGeoJsonSource']);
      expect(ops.calls.single.id, MapLayerIds.routeSource('main'));
    });

    test('rewrites the layer properties only when the style changed', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setRouteLine('main', _points);
      ops.clearCalls();

      await adapter.setRouteLine('main', _points);
      expect(ops.callsNamed('setLayerProperties'), isEmpty);

      await adapter.setRouteLine(
        'main',
        _points,
        style: RouteLineStyle.preview,
      );
      final restyled = ops.lastPropertiesOf(MapLayerIds.routeLayer('main'))!;
      expect(
        restyled.properties!['line-color'],
        const MapPalette.classic().routePreview,
      );
      expect(restyled.properties!['line-dasharray'], <double>[2, 1.5]);
    });

    test('re-adds the line when the native side dropped the source', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setRouteLine('main', _points);
      ops.clearCalls();
      // The style forgot our source without telling anyone.
      ops.scriptedSourceIds.add(const <String>[]);

      await adapter.setRouteLine('main', _points);

      // The casing goes in first, the line on top of it.
      expect(ops.names, <String>['addGeoJsonSource', 'addLayer', 'addLayer']);
      expect(ops.callsNamed('addLayer').map((c) => c.layerId), <String>[
        MapLayerIds.routeCasingLayer('main'),
        MapLayerIds.routeLayer('main'),
      ]);
    });

    test(
      'a chosen alternative keeps its colour but is drawn as main',
      () async {
        final ops = RecordingStyleOps();
        final adapter = _adapter(ops);
        await adapter.attachToStyle();

        await adapter.setRouteLine('main-2', _points);
        await adapter.setRouteLine('main', _points);

        expect(
          ops
              .addLayerOf('velorki-route-main-2-line')!
              .properties!['line-color'],
          const MapPalette.classic().routeAlternatives[2],
        );
        expect(
          ops.addLayerOf('velorki-route-main-line')!.properties!['line-color'],
          const MapPalette.classic().routeMain,
        );
        // Both are main-styled: the usual width, not an alternative's.
        expect(
          ops
              .addLayerOf('velorki-route-main-2-line')!
              .properties!['line-width'],
          5.0,
        );
      },
    );

    test('keeps two ids apart and slugs them into source names', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();

      await adapter.setRouteLine('main', _points);
      await adapter.setRouteLine(
        'alt/1',
        _points,
        style: RouteLineStyle.alternative,
      );

      expect(
        ops.sourceIds,
        containsAll(<String>['velorki-route-main', 'velorki-route-alt_1']),
      );
      // Alternative 1 wears the second alternative colour, and sits under
      // the chosen route's casing.
      expect(
        ops.addLayerOf('velorki-route-alt_1-line')!.properties!['line-color'],
        const MapPalette.classic().routeAlternatives[1],
      );
      expect(
        ops.addLayerOf('velorki-route-alt_1-line')!.belowLayerId,
        MapLayerIds.routeCasingLayer('main'),
      );
    });
  });

  group('removeRouteLine and clearRouteLines', () {
    test('removes the layer before its source', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setRouteLine('main', _points);
      ops.clearCalls();

      await adapter.removeRouteLine('main');

      // Both layers go before the source they read from.
      expect(ops.names, <String>['removeLayer', 'removeLayer', 'removeSource']);
      expect(ops.calls.first.id, MapLayerIds.routeLayer('main'));
      expect(ops.calls[1].id, MapLayerIds.routeCasingLayer('main'));
      expect(ops.calls.last.id, MapLayerIds.routeSource('main'));
    });

    test(
      'forgets the points, so a reload does not bring the line back',
      () async {
        final ops = RecordingStyleOps();
        final adapter = _adapter(ops);
        await adapter.attachToStyle();
        await adapter.setRouteLine('main', _points);
        await adapter.removeRouteLine('main');
        ops.clearCalls();

        await adapter.attachToStyle();

        expect(
          ops.callsNamed('addLayer').map((c) => c.layerId),
          isNot(contains(MapLayerIds.routeLayer('main'))),
        );
      },
    );

    test('removing an id that was never drawn does nothing', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.removeRouteLine('never-drawn');

      expect(ops.calls, isEmpty);
    });

    test('clearRouteLines takes every line away', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setRouteLine('main', _points);
      await adapter.setRouteLine('alt', _points);
      ops.clearCalls();

      await adapter.clearRouteLines();

      expect(ops.callsNamed('removeSource').map((c) => c.id).toList(), <String>[
        MapLayerIds.routeSource('main'),
        MapLayerIds.routeSource('alt'),
      ]);
      // And nothing is left to replay.
      ops.clearCalls();
      await adapter.attachToStyle();
      expect(
        ops.callsNamed('addLayer').map((c) => c.layerId),
        isNot(contains(MapLayerIds.routeLayer('main'))),
      );
    });
  });

  group('setWaypoints', () {
    test('writes one draggable point feature per waypoint', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setWaypoints(_waypoints);

      expect(ops.names, <String>['setGeoJsonSource']);
      final features = _featuresOf(ops, MapLayerIds.waypointsSource);
      expect(features, hasLength(2));
      expect((features.first as Map<String, dynamic>)['id'], 'velorki-wp-0');
      final properties = _firstProperties(ops, MapLayerIds.waypointsSource);
      expect(properties['kind'], 'start');
      expect(properties['label'], '1');
      expect(properties['draggable'], isTrue);
    });

    test('rebuilds the style when its source has vanished', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();
      ops.scriptedSourceIds.add(const <String>[]);

      await adapter.setWaypoints(_waypoints);

      // Everything is re-created, and the replay still draws the waypoints.
      expect(
        ops.callsNamed('addGeoJsonSource').map((c) => c.id),
        contains(MapLayerIds.waypointsSource),
      );
      expect(_featuresOf(ops, MapLayerIds.waypointsSource), hasLength(2));
    });

    test('a style whose sources cannot be listed is left alone', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();
      ops.sourceIdsError = StateError('channel closed');

      await adapter.setWaypoints(_waypoints);

      // Assuming the source is still there beats rebuilding the whole style.
      expect(ops.names, <String>['setGeoJsonSource']);
    });
  });

  group('setTrackLine', () {
    test('writes the track as a single line string', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setTrackLine(_points);

      expect(ops.names, <String>['setGeoJsonSource']);
      expect(_featuresOf(ops, MapLayerIds.trackSource), hasLength(1));
    });

    test('rebuilds the style when its source has vanished', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();
      ops.scriptedSourceIds.add(const <String>[]);

      await adapter.setTrackLine(_points);

      expect(
        ops.callsNamed('addGeoJsonSource').map((c) => c.id),
        contains(MapLayerIds.trackSource),
      );
      expect(_featuresOf(ops, MapLayerIds.trackSource), hasLength(1));
    });
  });

  group('setTrackSegments', () {
    test('writes one line per segment, each carrying its t', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setTrackSegments(_segments);

      final features = _featuresOf(ops, MapLayerIds.trackSource);
      expect(features, hasLength(2));
      expect(
        features.map((f) => (f as Map<String, dynamic>)['properties']['t']),
        <double>[0, 1],
      );
      expect(
        (features.first as Map<String, dynamic>)['geometry']['coordinates'],
        // GeoJSON is lon, lat.
        <List<double>>[
          <double>[8.0, 47.0],
          <double>[8.1, 47.1],
        ],
      );
    });

    test('the layer colours the line by t, slow to fast', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops, palette: _repainted);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setTrackSegments(_segments);

      final paint = ops.lastPropertiesOf(MapLayerIds.trackLayer)!;
      expect(paint.properties!['line-color'], <Object>[
        'interpolate',
        <Object>['linear'],
        <Object>['get', 't'],
        0,
        '#505050',
        1,
        '#5F5F5F',
      ]);
    });

    test('the paint is written once, not on every update', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setTrackSegments(_segments);
      await adapter.setTrackSegments(_segments);

      expect(ops.callsNamed('setLayerProperties'), hasLength(1));
    });

    test('a plain track line puts the flat colour back', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setTrackSegments(_segments);
      ops.clearCalls();

      await adapter.setTrackLine(_points);

      expect(
        ops.lastPropertiesOf(MapLayerIds.trackLayer)!.properties!['line-color'],
        const MapPalette.classic().track,
      );
      expect(_featuresOf(ops, MapLayerIds.trackSource), hasLength(1));
    });

    test('a segment of one point is not drawn at all', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setTrackSegments(<TrackSegment>[
        TrackSegment(points: const <LatLng>[LatLng(47, 8)], t: 0),
      ]);

      expect(_featuresOf(ops, MapLayerIds.trackSource), isEmpty);
    });

    test('a style reload replays the coloured track', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setTrackSegments(_segments);
      ops.clearCalls();

      ops.reloadStyle();
      await adapter.attachToStyle();

      expect(_featuresOf(ops, MapLayerIds.trackSource), hasLength(2));
      expect(
        ops.lastPropertiesOf(MapLayerIds.trackLayer)!.properties!['line-color'],
        isA<List<Object?>>(),
      );
    });

    test('rebuilds the style when its source has vanished', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();
      ops.scriptedSourceIds.add(const <String>[]);

      await adapter.setTrackSegments(_segments);

      expect(_featuresOf(ops, MapLayerIds.trackSource), hasLength(2));
    });
  });

  group('before the style is attached', () {
    test('nothing at all is sent to the map', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);

      await adapter.setWaypoints(_waypoints);
      await adapter.setTrackLine(_points);
      await adapter.setRouteLine('main', _points);
      await adapter.setPosition(const LatLng(47.0, 8.0), accuracyM: 10);
      await adapter.setPalette(_repainted);

      expect(ops.calls, isEmpty);
    });

    test('the waypoints and the track are replayed once it is', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.setWaypoints(_waypoints);
      await adapter.setTrackLine(_points);

      await adapter.attachToStyle();

      expect(_featuresOf(ops, MapLayerIds.waypointsSource), hasLength(2));
      expect(_featuresOf(ops, MapLayerIds.trackSource), hasLength(1));
    });

    test('a route line set early is drawn by the first attach', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.setRouteLine('main', _points);

      await adapter.attachToStyle();

      expect(
        ops.callsNamed('addLayer').map((c) => c.layerId),
        contains(MapLayerIds.routeLayer('main')),
      );
    });
  });

  group('a style reload', () {
    test('replays the waypoints, the track and the route lines', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setWaypoints(_waypoints);
      await adapter.setTrackLine(_points);
      await adapter.setRouteLine('main', _points);
      ops.clearCalls();

      ops.reloadStyle();
      await adapter.attachToStyle();

      expect(_featuresOf(ops, MapLayerIds.waypointsSource), hasLength(2));
      expect(_featuresOf(ops, MapLayerIds.trackSource), hasLength(1));
      final line = ops.addLayerOf(MapLayerIds.routeLayer('main'))!;
      expect(_featuresOf(ops, MapLayerIds.routeSource('main')), hasLength(1));
      // Still under the puck, as on the first attach.
      expect(line.belowLayerId, MapLayerIds.positionAccuracyLayer);
    });

    test('replays a preview route as a preview', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setRouteLine(
        'preview',
        _points,
        style: RouteLineStyle.preview,
      );
      ops.clearCalls();

      ops.reloadStyle();
      await adapter.attachToStyle();

      expect(
        ops
            .addLayerOf(MapLayerIds.routeLayer('preview'))!
            .properties!['line-color'],
        const MapPalette.classic().routePreview,
      );
    });
  });

  group('setSearchPin', () {
    test('writes the place with its label and clears it again', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();

      await adapter.setSearchPin(const LatLng(47.5, 8.5), label: 'Zoo');
      final features = _featuresOf(ops, MapLayerIds.searchPinSource);
      expect(features, hasLength(1));
      expect(
        (features.single['properties'] as Map<String, dynamic>)['label'],
        'Zoo',
      );

      await adapter.setSearchPin(null);
      expect(_featuresOf(ops, MapLayerIds.searchPinSource), isEmpty);
    });

    test('comes back after a style reload', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setSearchPin(const LatLng(47.5, 8.5), label: 'Zoo');
      ops.clearCalls();

      await adapter.attachToStyle();

      expect(_featuresOf(ops, MapLayerIds.searchPinSource), hasLength(1));
    });
  });

  group('setPalette', () {
    test('rewrites every colour it owns', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setPalette(_repainted);

      expect(adapter.palette, _repainted);
      expect(
        ops.lastPropertiesOf(MapLayerIds.trackLayer)!.properties!['line-color'],
        '#555555',
      );
      for (final layer in <String>[
        MapLayerIds.positionDotLayer,
        MapLayerIds.positionHaloLayer,
      ]) {
        expect(
          ops.lastPropertiesOf(layer)!.properties!['circle-color'],
          '#CCCCCC',
        );
      }
      final ring = ops.lastPropertiesOf(MapLayerIds.positionAccuracyLayer)!;
      expect(ring.properties!['circle-color'], '#DDDDDD');
      expect(ring.properties!['circle-stroke-color'], '#DDDDDD');
      final circle = ops.lastPropertiesOf(MapLayerIds.waypointsCircleLayer)!;
      expect(circle.properties!['circle-color'], <Object>[
        'match',
        <Object>['get', 'kind'],
        'start',
        '#666666',
        'end',
        '#888888',
        '#777777',
      ]);
      expect(circle.properties!['circle-stroke-color'], '#999999');
      final label = ops.lastPropertiesOf(MapLayerIds.waypointsLabelLayer)!;
      expect(label.properties!['text-color'], '#AAAAAA');
      expect(label.properties!['text-halo-color'], '#BBBBBB');
    });

    test('redraws the heading cone, which is a bitmap not a colour', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      final before = ops.lastCall('addImage')!.imageBytes!;
      ops.clearCalls();

      await adapter.setPalette(_repainted);

      final after = ops.lastCall('addImage')!;
      expect(after.id, headingConeImageName);
      expect(after.imageBytes, isNot(before));
    });

    test('recolours every route line that is on the map', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setRouteLine('main', _points);
      await adapter.setRouteLine(
        'alt',
        _points,
        style: RouteLineStyle.alternative,
      );
      ops.clearCalls();

      await adapter.setPalette(_repainted);

      expect(
        ops
            .lastPropertiesOf(MapLayerIds.routeLayer('main'))!
            .properties!['line-color'],
        '#111111',
      );
      expect(
        ops
            .lastPropertiesOf(MapLayerIds.routeLayer('alt'))!
            .properties!['line-color'],
        '#333333',
      );
    });

    test('says nothing when the palette did not change', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setPalette(const MapPalette.classic());

      expect(ops.calls, isEmpty);
    });
  });

  group('setPosition', () {
    test(
      'writes the fix and a ring that holds its size on the ground',
      () async {
        final ops = RecordingStyleOps();
        final adapter = _adapter(ops);
        await adapter.attachToStyle();
        ops.clearCalls();

        await adapter.setPosition(const LatLng(47.0, 8.0), accuracyM: 20);

        final feature =
            _featuresOf(ops, MapLayerIds.positionSource).single
                as Map<String, dynamic>;
        expect(
          (feature['geometry'] as Map<String, dynamic>)['coordinates'],
          <double>[8.0, 47.0],
        );
        expect((feature['properties'] as Map<String, dynamic>)['accuracy'], 20);
        expect(
          ops
              .lastPropertiesOf(MapLayerIds.positionAccuracyLayer)!
              .properties!['circle-radius'],
          accuracyRingRadiusExpression(20, 47.0),
        );
      },
    );

    test('a minimal fix is a bare dot: no ring, no cone', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      // What a battery-saver ride asks for: fewer pixels lit, less to redraw.
      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        accuracyM: 20,
        headingDeg: 90,
        speedMps: 5,
        minimal: true,
      );

      expect(
        _firstProperties(ops, MapLayerIds.positionSource),
        isNot(contains('heading')),
      );
      final ring = ops
          .lastPropertiesOf(MapLayerIds.positionAccuracyLayer)!
          .properties!;
      expect(ring['circle-opacity'], 0.0);
      expect(ring['circle-stroke-opacity'], 0.0);
    });

    test('the cone is back on the next ordinary fix', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 90,
        speedMps: 5,
        minimal: true,
      );
      ops.clearCalls();

      // The smoother was kept fed while the cone was hidden, so switching the
      // saver off mid-ride does not start it from nothing.
      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 90,
        speedMps: 5,
      );

      expect(
        _firstProperties(ops, MapLayerIds.positionSource),
        contains('heading'),
      );
      expect(
        ops
            .lastPropertiesOf(MapLayerIds.positionAccuracyLayer)!
            .properties!['circle-opacity'],
        0.15,
      );
    });

    test('writes no heading while the rider is standing still', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      // A GNSS course jitters through the full circle at a standstill, so the
      // property is simply absent and the cone layer hides itself.
      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 90,
        speedMps: 0.1,
      );

      expect(
        _firstProperties(ops, MapLayerIds.positionSource),
        isNot(contains('heading')),
      );
    });

    test('writes the heading once the rider is moving', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.clearCalls();

      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 450,
        speedMps: 5,
      );

      // And it arrives normalised into 0–360.
      expect(_firstProperties(ops, MapLayerIds.positionSource)['heading'], 90);
    });

    test('keeps the cone through a dip in speed, then drops it', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();

      // Rolling out at a traffic light: one threshold would blink the cone
      // on and off with every fix, two keep it steady.
      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 90,
        speedMps: 3,
      );
      expect(
        _firstProperties(ops, MapLayerIds.positionSource),
        contains('heading'),
      );

      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 90,
        speedMps: 1.0,
      );
      expect(
        _firstProperties(ops, MapLayerIds.positionSource),
        contains('heading'),
      );

      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 90,
        speedMps: 0.4,
      );
      expect(
        _firstProperties(ops, MapLayerIds.positionSource),
        isNot(contains('heading')),
      );
    });

    test('waits for a real pace before the cone appears at all', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();

      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 90,
        speedMps: 1.0,
      );

      expect(
        _firstProperties(ops, MapLayerIds.positionSource),
        isNot(contains('heading')),
        reason: 'walking pace is not riding',
      );
    });

    test('smooths the course instead of following every jitter', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();

      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 0,
        speedMps: 5,
      );
      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 100,
        speedMps: 5,
      );

      expect(
        _firstProperties(ops, MapLayerIds.positionSource)['heading'] as double,
        closeTo(50, 1e-9),
      );
    });

    /// The fixes written to the position source since [ops] was last cleared.
    List<LatLng> puckWrites(RecordingStyleOps ops) => ops
        .callsNamed('setGeoJsonSource')
        .where((c) => c.id == MapLayerIds.positionSource)
        .map((c) {
          final feature =
              (c.geojson!['features'] as List<dynamic>).single
                  as Map<String, dynamic>;
          final at =
              (feature['geometry'] as Map<String, dynamic>)['coordinates']
                  as List<dynamic>;
          return LatLng(at[1] as double, at[0] as double);
        })
        .toList();

    test('walks the puck from the last fix to the new one', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setPosition(const LatLng(47.0, 8.0), accuracyM: 5);
      ops.clearCalls();

      fakeAsync((async) {
        // Fifty metres north: a second of riding, drawn as a walk rather than
        // a hop.
        adapter.setPosition(const LatLng(47.00045, 8.0), accuracyM: 5);
        async.flushMicrotasks();
        async.elapse(puckInterpolationDuration);
        async.flushMicrotasks();

        final writes = puckWrites(ops);
        expect(
          writes.length,
          greaterThan(2),
          reason: 'the puck is drawn on its way there',
        );
        expect(writes.last, const LatLng(47.00045, 8.0));
        expect(writes.first.lat, greaterThan(47.0));
        expect(writes.first.lat, lessThan(47.00045));
      });
    });

    test('a fix from far away is simply put there', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setPosition(const LatLng(47.0, 8.0));
      ops.clearCalls();

      fakeAsync((async) {
        // Half a kilometre in one fix is not riding, it is the OS handing
        // over a fix from somewhere else.
        adapter.setPosition(const LatLng(47.0045, 8.0));
        async.flushMicrotasks();
        expect(puckWrites(ops), <LatLng>[const LatLng(47.0045, 8.0)]);

        async.elapse(puckInterpolationDuration);
        expect(puckWrites(ops), hasLength(1));
      });
    });

    test('a new fix ends the walk the last one started', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setPosition(const LatLng(47.0, 8.0));

      fakeAsync((async) {
        adapter.setPosition(const LatLng(47.00045, 8.0));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));
        ops.clearCalls();

        adapter.setPosition(const LatLng(47.0009, 8.0));
        async.flushMicrotasks();
        async.elapse(puckInterpolationDuration);

        // Everything drawn from here on belongs to the second walk, and it
        // ends on the second fix.
        expect(puckWrites(ops).last, const LatLng(47.0009, 8.0));
        expect(
          puckWrites(ops).length,
          lessThanOrEqualTo(puckInterpolationSteps),
        );
      });
    });

    test('keeps the last heading when a fix brings no course', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();

      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 90,
        speedMps: 5,
      );
      await adapter.setPosition(const LatLng(47.0, 8.0), speedMps: 5);

      expect(_firstProperties(ops, MapLayerIds.positionSource)['heading'], 90);
    });

    test('starts the average over after the cone was hidden', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();

      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 0,
        speedMps: 5,
      );
      // Stopped: the cone goes, and with it the average.
      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 0,
        speedMps: 0,
      );
      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 100,
        speedMps: 5,
      );

      expect(
        _firstProperties(ops, MapLayerIds.positionSource)['heading'],
        100,
        reason: 'no drift from a heading two stops ago',
      );
    });

    test('a lost fix forgets the heading as well', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();

      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 0,
        speedMps: 5,
      );
      await adapter.setPosition(null);
      await adapter.setPosition(
        const LatLng(47.0, 8.0),
        headingDeg: 100,
        speedMps: 5,
      );

      expect(_firstProperties(ops, MapLayerIds.positionSource)['heading'], 100);
    });

    test('collapses the ring when there is no usable accuracy', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();

      for (final accuracy in <double?>[null, 0, -1]) {
        ops.clearCalls();
        await adapter.setPosition(const LatLng(47.0, 8.0), accuracyM: accuracy);
        expect(
          ops
              .lastPropertiesOf(MapLayerIds.positionAccuracyLayer)!
              .properties!['circle-radius'],
          0.0,
          reason: 'accuracy $accuracy',
        );
      }
    });

    test('empties the source and the ring when the fix is gone', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setPosition(const LatLng(47.0, 8.0), accuracyM: 20);
      ops.clearCalls();

      await adapter.setPosition(null, accuracyM: 20);

      expect(_featuresOf(ops, MapLayerIds.positionSource), isEmpty);
      expect(
        ops
            .lastPropertiesOf(MapLayerIds.positionAccuracyLayer)!
            .properties!['circle-radius'],
        0.0,
      );
    });
  });

  group('the feature drag callback', () {
    test('intermediate drag positions are not reported', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      final moves = <String>[];
      adapter.onWaypointDragged = (index, position) =>
          moves.add('$index@${position.lat},${position.lon}');

      // Committing every step rewrote the plan and re-routed on the way;
      // the marker itself still follows the finger through the source.
      ops.emitFeatureDrag(waypointFeatureId(2), const ml.LatLng(47.5, 8.5));
      expect(moves, isEmpty);

      ops.emitFeatureDrag(
        waypointFeatureId(2),
        const ml.LatLng(47.6, 8.6),
        eventType: ml.DragEventType.end,
      );
      expect(moves, hasLength(1));
      expect(moves.single, startsWith('2@47.6,8.'));
    });

    test('a long press while dragging a marker inserts nothing', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      final inserted = <LatLng>[];
      adapter.onLongPress = inserted.add;

      ops.emitFeatureDrag(
        waypointFeatureId(1),
        const ml.LatLng(47.5, 8.5),
        eventType: ml.DragEventType.start,
      );
      adapter.handleMapLongClick(const ml.LatLng(47.5, 8.5));
      ops.emitFeatureDrag(
        waypointFeatureId(1),
        const ml.LatLng(47.6, 8.6),
        eventType: ml.DragEventType.end,
      );
      adapter.handleMapLongClick(const ml.LatLng(47.6, 8.6));

      expect(inserted, isEmpty);
    });

    test('the marker follows the finger while it is dragged', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      await adapter.setWaypoints(_waypoints);
      ops.clearCalls();

      ops.emitFeatureDrag(waypointFeatureId(1), const ml.LatLng(47.9, 8.9));

      final features = _featuresOf(ops, MapLayerIds.waypointsSource);
      final moved = features[1]['geometry'] as Map<String, dynamic>;
      final coordinates = (moved['coordinates'] as List).cast<double>();
      expect(coordinates[0], closeTo(8.9, 1e-6));
      expect(coordinates[1], closeTo(47.9, 1e-6));
    });

    test(
      'a wobble of a few pixels is a tap, and the marker snaps back',
      () async {
        final ops = RecordingStyleOps();
        final adapter = _adapter(ops);
        await adapter.attachToStyle();
        await adapter.setWaypoints(_waypoints);
        final moves = <int>[];
        final tapped = <int>[];
        adapter.onWaypointDragged = (index, _) => moves.add(index);
        adapter.onWaypointTapped = tapped.add;
        final origin = _waypoints[1].position;

        // ~1 m away: far below 14 px at any zoom the map is used at.
        ops.emitFeatureDrag(
          waypointFeatureId(1),
          ml.LatLng(origin.lat + 0.00001, origin.lon),
          origin: ml.LatLng(origin.lat, origin.lon),
          eventType: ml.DragEventType.end,
        );

        expect(moves, isEmpty);
        expect(tapped, <int>[1]);

        // The platform also reports the wobble as a feature tap right
        // after the drag; that must not open a second sheet.
        for (final callback in List.of(ops.onFeatureTapped)) {
          callback(
            const Point<double>(0, 0),
            ml.LatLng(origin.lat, origin.lon),
            waypointFeatureId(1),
            MapLayerIds.waypointsHitLayer,
            null,
          );
        }
        expect(tapped, <int>[1]);
        final features = _featuresOf(ops, MapLayerIds.waypointsSource);
        final back =
            (features[1]['geometry'] as Map<String, dynamic>)['coordinates']
                as List;
        expect(back[1], closeTo(origin.lat, 1e-9));
      },
    );

    test('the release after a drag is not also a map tap', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      final taps = <LatLng>[];
      adapter.onTap = taps.add;

      ops.emitFeatureDrag(
        waypointFeatureId(0),
        const ml.LatLng(47.5, 8.5),
        eventType: ml.DragEventType.end,
      );
      adapter.handleMapClick(const ml.LatLng(47.5, 8.5));

      expect(taps, isEmpty, reason: 'the release would add a waypoint');
    });

    test('a tap on a marker reports its index, not a map tap', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      final taps = <LatLng>[];
      final tapped = <int>[];
      adapter.onTap = taps.add;
      adapter.onWaypointTapped = tapped.add;

      for (final callback in List.of(ops.onFeatureTapped)) {
        callback(
          const Point<double>(0, 0),
          const ml.LatLng(47.5, 8.5),
          waypointFeatureId(1),
          MapLayerIds.waypointsCircleLayer,
          null,
        );
      }
      adapter.handleMapClick(const ml.LatLng(47.5, 8.5));

      expect(tapped, <int>[1]);
      expect(taps, isEmpty);
    });

    test('reports the end of a drag as the final word', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      final moves = <int>[];
      adapter.onWaypointDragged = (index, _) => moves.add(index);

      ops.emitFeatureDrag(
        waypointFeatureId(0),
        const ml.LatLng(47.5, 8.5),
        eventType: ml.DragEventType.end,
      );

      expect(moves, <int>[0]);
    });

    test('ignores the start, which carries the untouched position', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      var calls = 0;
      adapter.onWaypointDragged = (_, _) => calls++;

      ops.emitFeatureDrag(
        waypointFeatureId(1),
        const ml.LatLng(47.5, 8.5),
        eventType: ml.DragEventType.start,
      );

      expect(calls, 0);
    });

    test('ignores a feature that is not one of our waypoints', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      var calls = 0;
      adapter.onWaypointDragged = (_, _) => calls++;

      ops.emitFeatureDrag('some-other-feature', const ml.LatLng(47.5, 8.5));

      expect(calls, 0);
    });
  });

  group('the camera', () {
    test('moveTo animates to a plain centre by default', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);

      await adapter.moveTo(const LatLng(47.0, 8.0));

      expect(ops.names, <String>['animateCamera']);
      expect(ops.calls.single.cameraUpdate, <Object>[
        'newLatLng',
        <double>[47.0, 8.0],
      ]);
    });

    test('moveTo takes a zoom along when it is given one', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);

      await adapter.moveTo(const LatLng(47.0, 8.0), zoom: 14);

      expect(ops.calls.single.cameraUpdate, <Object>[
        'newLatLngZoom',
        <double>[47.0, 8.0],
        14.0,
      ]);
    });

    test('moveTo carries a bearing as a whole camera position', () async {
      final ops = RecordingStyleOps()
        ..cameraPosition = const ml.CameraPosition(
          target: ml.LatLng(47.0, 8.0),
          zoom: 12.5,
          tilt: 20,
        );
      final adapter = _adapter(ops);

      await adapter.moveTo(const LatLng(47.0, 8.0), bearing: 90);

      expect(ops.names, <String>['animateCamera']);
      final update = ops.calls.single.cameraUpdate! as List<Object?>;
      expect(update.first, 'newCameraPosition');
      final position = update[1]! as Map<Object?, Object?>;
      expect(position['bearing'], 90.0);
      // The zoom and the tilt come from the live camera, so asking for a
      // bearing alone does not flatten them.
      expect(position['zoom'], 12.5);
      expect(position['tilt'], 20.0);
    });

    test('moveTo takes the zoom it is given along with the bearing', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);

      await adapter.moveTo(const LatLng(47.0, 8.0), zoom: 16, bearing: 0);

      final update = ops.calls.single.cameraUpdate! as List<Object?>;
      final position = update[1]! as Map<Object?, Object?>;
      expect(position['zoom'], 16.0);
      expect(position['bearing'], 0.0);
    });

    test('the bearing reads the live camera position', () async {
      final ops = RecordingStyleOps()
        ..cameraPosition = const ml.CameraPosition(
          target: ml.LatLng(47.0, 8.0),
          bearing: 42,
        );

      expect(_adapter(ops).bearing, 42);
      expect(_adapter(RecordingStyleOps()).bearing, isNull);
    });

    test('moveTo jumps when the caller asks for no animation', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);

      await adapter.moveTo(const LatLng(47.0, 8.0), animate: false);

      expect(ops.names, <String>['moveCamera']);
    });

    test('fitBounds animates to the padded bounds', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);

      await adapter.fitBounds(
        const BoundingBox(south: 46.0, west: 7.0, north: 48.0, east: 9.0),
        paddingPx: 24,
      );

      expect(ops.names, <String>['animateCamera']);
      expect(ops.calls.single.cameraUpdate, <Object>[
        'newLatLngBounds',
        <List<double>>[
          <double>[46.0, 7.0],
          <double>[48.0, 9.0],
        ],
        24.0,
        24.0,
        24.0,
        24.0,
      ]);
    });

    test('centre and zoom read the live camera position', () async {
      final ops = RecordingStyleOps()
        ..cameraPosition = const ml.CameraPosition(
          target: ml.LatLng(47.0, 8.0),
          zoom: 12.5,
        );
      final adapter = _adapter(ops);

      expect(adapter.center, const LatLng(47.0, 8.0));
      expect(adapter.zoom, 12.5);
    });

    test('centre and zoom are unknown before the first frame', () {
      final adapter = _adapter(RecordingStyleOps());

      expect(adapter.center, isNull);
      expect(adapter.zoom, isNull);
    });

    test('the visible bounds are refreshed when the camera rests', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      ops.visibleRegion = ml.LatLngBounds(
        southwest: const ml.LatLng(40.0, 1.0),
        northeast: const ml.LatLng(41.0, 2.0),
      );

      adapter.handleCameraIdle();
      await Future<void>.delayed(Duration.zero);

      expect(
        adapter.visibleBounds,
        const BoundingBox(south: 40.0, west: 1.0, north: 41.0, east: 2.0),
      );
    });

    test(
      'a platform view that is already gone keeps the last bounds',
      () async {
        final ops = RecordingStyleOps();
        final adapter = _adapter(ops);
        await adapter.attachToStyle();
        final attached = adapter.visibleBounds;
        ops.visibleRegionError = StateError('platform view disposed');

        adapter.handleCameraIdle();
        await Future<void>.delayed(Duration.zero);

        expect(adapter.visibleBounds, attached);
        expect(attached, isNotNull);
      },
    );
  });

  group('the map events', () {
    test('a tap is forwarded as a plain LatLng', () {
      final adapter = _adapter(RecordingStyleOps());
      final taps = <LatLng>[];
      adapter.onTap = taps.add;

      adapter.handleMapClick(const ml.LatLng(47.0, 8.0));

      expect(taps, <LatLng>[const LatLng(47.0, 8.0)]);
    });

    test('a long press is forwarded as a plain LatLng', () {
      final adapter = _adapter(RecordingStyleOps());
      final presses = <LatLng>[];
      adapter.onLongPress = presses.add;

      adapter.handleMapLongClick(const ml.LatLng(47.0, 8.0));

      expect(presses, <LatLng>[const LatLng(47.0, 8.0)]);
    });

    test('the camera coming to rest is announced', () async {
      final adapter = _adapter(RecordingStyleOps());
      var idles = 0;
      adapter.onCameraIdle = () => idles++;

      adapter.handleCameraIdle();
      await Future<void>.delayed(Duration.zero);

      expect(idles, 1);
    });

    test('an event with no handler is simply dropped', () {
      final adapter = _adapter(RecordingStyleOps());

      expect(
        () => adapter.handleMapClick(const ml.LatLng(47.0, 8.0)),
        returnsNormally,
      );
    });
  });

  group('dispose', () {
    test('unregisters the drag callback and forgets the handlers', () async {
      final ops = RecordingStyleOps();
      final adapter = _adapter(ops);
      await adapter.attachToStyle();
      var drags = 0;
      adapter
        ..onWaypointDragged = ((_, _) {
          drags++;
        })
        ..onTap = (_) {}
        ..onLongPress = (_) {}
        ..onCameraIdle = () {};

      adapter.dispose();

      expect(ops.onFeatureDrag, isEmpty);
      ops.emitFeatureDrag(waypointFeatureId(0), const ml.LatLng(47.0, 8.0));
      expect(drags, 0);
      expect(adapter.onTap, isNull);
      expect(adapter.onLongPress, isNull);
      expect(adapter.onWaypointDragged, isNull);
      expect(adapter.onCameraIdle, isNull);
    });
  });
}
