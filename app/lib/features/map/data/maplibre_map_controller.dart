import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:velorki_geo/velorki_geo.dart';

import '../domain/map_controller.dart';
import 'geojson.dart';
import 'tile_template.dart';

/// Source and layer ids. Everything Velorki adds to the style is prefixed so
/// it can never collide with a layer of the base style.
abstract final class MapLayerIds {
  static const String cyclosmSource = 'velorki-cyclosm';
  static const String cyclosmLayer = 'velorki-cyclosm-raster';
  static const String trackSource = 'velorki-track';
  static const String trackLayer = 'velorki-track-line';
  static const String positionSource = 'velorki-position';
  static const String positionAccuracyLayer = 'velorki-position-accuracy';
  static const String positionDotLayer = 'velorki-position-dot';
  static const String waypointsSource = 'velorki-waypoints';
  static const String waypointsCircleLayer = 'velorki-waypoints-circle';
  static const String waypointsLabelLayer = 'velorki-waypoints-label';

  static String routeSource(String id) => 'velorki-route-${_slug(id)}';
  static String routeLayer(String id) => 'velorki-route-${_slug(id)}-line';

  static String _slug(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}

/// Line, circle and text colours, kept in one place so the planner's legend
/// and the map agree.
abstract final class MapColors {
  static const String routeMain = '#1565C0';
  static const String routeMainCasing = '#0D3C6E';
  static const String routeAlternative = '#78909C';
  static const String routePreview = '#EF6C00';
  static const String track = '#AD1457';
  static const String waypointStart = '#2E7D32';
  static const String waypointVia = '#1565C0';
  static const String waypointEnd = '#C62828';
  static const String waypointStroke = '#FFFFFF';
  static const String waypointLabel = '#FFFFFF';
  static const String waypointLabelHalo = '#00000055';
  static const String positionDot = '#1E88E5';
  static const String positionAccuracy = '#1E88E5';
}

/// Attribution string handed to the raster source, so the native SDK's own
/// attribution sheet lists CyclOSM even though our chip draws it separately.
const String _cyclosmAttribution =
    '© OpenStreetMap contributors, tiles by CyclOSM';

/// [MapController] over maplibre_gl's [ml.MapLibreMapController].
///
/// Routes, waypoints, the track and the puck are GeoJSON sources with style
/// layers rather than annotations: annotations go through a per-feature method
/// channel round trip, while a source swap is one call however long the line.
class MaplibreMapControllerAdapter implements MapController {
  MaplibreMapControllerAdapter(this._map, {this.cyclosmTileUrl = ''});

  final ml.MapLibreMapController _map;

  /// CyclOSM XYZ template, `{s}` included; empty disables the overlay.
  final String cyclosmTileUrl;

  final Map<String, RouteLineStyle> _routeLines = <String, RouteLineStyle>{};
  BoundingBox? _visibleBounds;
  bool _cyclosmVisible = false;
  bool _attached = false;
  bool _disposed = false;

  @override
  ValueChanged<LatLng>? onTap;

  @override
  ValueChanged<LatLng>? onLongPress;

  @override
  void Function(int index, LatLng position)? onWaypointDragged;

  @override
  VoidCallback? onCameraIdle;

  /// Whether [attachToStyle] has run and the layers exist.
  bool get isAttached => _attached;

  /// Creates the sources and layers. Call once per loaded style, from
  /// `onStyleLoadedCallback`: a style change drops every layer we added.
  Future<void> attachToStyle() async {
    _attached = false;
    _routeLines.clear();
    _map.onFeatureDrag.remove(_handleFeatureDrag);
    _map.onFeatureDrag.add(_handleFeatureDrag);

    await _addCyclosmLayer();

    await _map.addGeoJsonSource(
      MapLayerIds.trackSource,
      emptyFeatureCollection(),
    );
    await _map.addLayer(
      MapLayerIds.trackSource,
      MapLayerIds.trackLayer,
      const ml.LineLayerProperties(
        lineColor: MapColors.track,
        lineWidth: 4.0,
        lineOpacity: 0.9,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    await _map.addGeoJsonSource(
      MapLayerIds.positionSource,
      emptyFeatureCollection(),
    );
    await _map.addLayer(
      MapLayerIds.positionSource,
      MapLayerIds.positionAccuracyLayer,
      const ml.CircleLayerProperties(
        circleRadius: 0.0,
        circleColor: MapColors.positionAccuracy,
        circleOpacity: 0.15,
        circleStrokeWidth: 1.0,
        circleStrokeColor: MapColors.positionAccuracy,
        circleStrokeOpacity: 0.4,
      ),
      enableInteraction: false,
    );
    await _map.addLayer(
      MapLayerIds.positionSource,
      MapLayerIds.positionDotLayer,
      const ml.CircleLayerProperties(
        circleRadius: 6.0,
        circleColor: MapColors.positionDot,
        circleStrokeWidth: 2.0,
        circleStrokeColor: '#FFFFFF',
      ),
      enableInteraction: false,
    );

    await _map.addGeoJsonSource(
      MapLayerIds.waypointsSource,
      emptyFeatureCollection(),
    );
    await _map.addLayer(
      MapLayerIds.waypointsSource,
      MapLayerIds.waypointsCircleLayer,
      const ml.CircleLayerProperties(
        circleRadius: 10.0,
        circleColor: <Object>[
          'match',
          <Object>['get', 'kind'],
          'start',
          MapColors.waypointStart,
          'end',
          MapColors.waypointEnd,
          MapColors.waypointVia,
        ],
        circleStrokeWidth: 2.0,
        circleStrokeColor: MapColors.waypointStroke,
      ),
      // Drag gestures only reach layers that take part in feature interaction.
    );
    await _map.addLayer(
      MapLayerIds.waypointsSource,
      MapLayerIds.waypointsLabelLayer,
      const ml.SymbolLayerProperties(
        textField: <Object>['get', 'label'],
        textSize: 12.0,
        textColor: MapColors.waypointLabel,
        textHaloColor: MapColors.waypointLabelHalo,
        textHaloWidth: 0.6,
        textAllowOverlap: true,
        textIgnorePlacement: true,
        textAnchor: 'center',
      ),
      enableInteraction: false,
    );

    _attached = true;
    await _refreshVisibleBounds();
  }

  Future<void> _addCyclosmLayer() async {
    final tiles = expandTileTemplate(cyclosmTileUrl);
    if (tiles.isEmpty) return;
    await _map.addSource(
      MapLayerIds.cyclosmSource,
      ml.RasterSourceProperties(
        tiles: tiles,
        tileSize: 256,
        minzoom: 0,
        maxzoom: 20,
        attribution: _cyclosmAttribution,
      ),
    );
    await _map.addLayer(
      MapLayerIds.cyclosmSource,
      MapLayerIds.cyclosmLayer,
      ml.RasterLayerProperties(
        rasterOpacity: 0.85,
        visibility: _cyclosmVisible ? 'visible' : 'none',
      ),
      enableInteraction: false,
    );
  }

  // ---------------------------------------------------------------- camera

  @override
  Future<void> moveTo(
    LatLng center, {
    double? zoom,
    bool animate = true,
  }) async {
    final update = zoom == null
        ? ml.CameraUpdate.newLatLng(_toMl(center))
        : ml.CameraUpdate.newLatLngZoom(_toMl(center), zoom);
    if (animate) {
      await _map.animateCamera(update);
    } else {
      await _map.moveCamera(update);
    }
  }

  @override
  Future<void> fitBounds(BoundingBox bounds, {double paddingPx = 48}) async {
    await _map.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        _toMlBounds(bounds),
        left: paddingPx,
        top: paddingPx,
        right: paddingPx,
        bottom: paddingPx,
      ),
    );
  }

  @override
  LatLng? get center {
    final target = _map.cameraPosition?.target;
    return target == null ? null : LatLng(target.latitude, target.longitude);
  }

  @override
  double? get zoom => _map.cameraPosition?.zoom;

  @override
  BoundingBox? get visibleBounds => _visibleBounds;

  // ------------------------------------------------------------ route lines

  @override
  Future<void> setRouteLine(
    String id,
    List<LatLng> points, {
    RouteLineStyle style = RouteLineStyle.main,
  }) async {
    if (!_attached) return;
    final sourceId = MapLayerIds.routeSource(id);
    final layerId = MapLayerIds.routeLayer(id);
    final data = lineFeatureCollection(
      points,
      properties: <String, dynamic>{'id': id, 'style': style.name},
    );
    final previous = _routeLines[id];
    if (previous == null) {
      await _map.addGeoJsonSource(sourceId, data);
      await _map.addLayer(
        sourceId,
        layerId,
        _lineProperties(style),
        // Keep route lines under the puck and the waypoint markers.
        belowLayerId: MapLayerIds.positionAccuracyLayer,
        enableInteraction: false,
      );
    } else {
      await _map.setGeoJsonSource(sourceId, data);
      if (previous != style) {
        await _map.setLayerProperties(layerId, _lineProperties(style));
      }
    }
    _routeLines[id] = style;
  }

  @override
  Future<void> removeRouteLine(String id) async {
    if (!_attached || _routeLines.remove(id) == null) return;
    await _map.removeLayer(MapLayerIds.routeLayer(id));
    await _map.removeSource(MapLayerIds.routeSource(id));
  }

  @override
  Future<void> clearRouteLines() async {
    for (final id in _routeLines.keys.toList()) {
      await removeRouteLine(id);
    }
  }

  static ml.LineLayerProperties _lineProperties(RouteLineStyle style) =>
      switch (style) {
        RouteLineStyle.main => const ml.LineLayerProperties(
          lineColor: MapColors.routeMain,
          lineWidth: 6.0,
          lineOpacity: 1.0,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        RouteLineStyle.alternative => const ml.LineLayerProperties(
          lineColor: MapColors.routeAlternative,
          lineWidth: 4.0,
          lineOpacity: 0.75,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        RouteLineStyle.preview => const ml.LineLayerProperties(
          lineColor: MapColors.routePreview,
          lineWidth: 4.0,
          lineOpacity: 0.9,
          lineCap: 'round',
          lineJoin: 'round',
          lineDasharray: <double>[2, 1.5],
        ),
      };

  // -------------------------------------------------------------- features

  @override
  Future<void> setWaypoints(List<MapWaypoint> waypoints) =>
      _map.setGeoJsonSource(
        MapLayerIds.waypointsSource,
        waypointsFeatureCollection(waypoints),
      );

  @override
  Future<void> setTrackLine(List<LatLng> points) => _map.setGeoJsonSource(
    MapLayerIds.trackSource,
    lineFeatureCollection(points),
  );

  @override
  Future<void> setPosition(
    LatLng? position, {
    double? accuracyM,
    double? headingDeg,
  }) async {
    if (!_attached) return;
    await _map.setGeoJsonSource(
      MapLayerIds.positionSource,
      positionFeatureCollection(
        position,
        accuracyM: accuracyM,
        headingDeg: headingDeg,
      ),
    );
    // circle-radius is in pixels, so a metre-accurate ring needs a fresh
    // zoom expression whenever the accuracy or the latitude changes.
    final radius = position == null || accuracyM == null || accuracyM <= 0
        ? 0.0
        : accuracyRingRadiusExpression(accuracyM, position.lat);
    await _map.setLayerProperties(
      MapLayerIds.positionAccuracyLayer,
      ml.CircleLayerProperties(
        circleRadius: radius,
        circleColor: MapColors.positionAccuracy,
        circleOpacity: 0.15,
        circleStrokeWidth: 1.0,
        circleStrokeColor: MapColors.positionAccuracy,
        circleStrokeOpacity: 0.4,
      ),
    );
  }

  @override
  Future<void> setCyclosmOverlay(bool visible) async {
    _cyclosmVisible = visible;
    if (expandTileTemplate(cyclosmTileUrl).isEmpty || !_attached) return;
    await _map.setLayerVisibility(MapLayerIds.cyclosmLayer, visible);
  }

  /// Whether the CyclOSM overlay is currently switched on.
  bool get isCyclosmVisible => _cyclosmVisible;

  // ---------------------------------------------------------------- events

  /// Forwarded from `MapLibreMap.onMapClick`.
  void handleMapClick(ml.LatLng coordinates) =>
      onTap?.call(_fromMl(coordinates));

  /// Forwarded from `MapLibreMap.onMapLongClick`.
  void handleMapLongClick(ml.LatLng coordinates) =>
      onLongPress?.call(_fromMl(coordinates));

  /// Forwarded from `MapLibreMap.onCameraIdle`.
  void handleCameraIdle() {
    unawaited(_refreshVisibleBounds());
    onCameraIdle?.call();
  }

  void _handleFeatureDrag(
    Object? point,
    ml.LatLng origin,
    ml.LatLng current,
    ml.LatLng delta,
    String id,
    ml.Annotation? annotation,
    ml.DragEventType eventType,
  ) {
    // `start` carries the untouched position, so it would report a move that
    // did not happen; `drag` keeps the route in step with the finger and
    // `end` is the final word.
    if (eventType == ml.DragEventType.start) return;
    final index = waypointIndexFromFeatureId(id);
    if (index == null) return;
    onWaypointDragged?.call(index, _fromMl(current));
  }

  Future<void> _refreshVisibleBounds() async {
    try {
      final region = await _map.getVisibleRegion();
      if (_disposed) return;
      _visibleBounds = BoundingBox(
        south: region.southwest.latitude,
        west: region.southwest.longitude,
        north: region.northeast.latitude,
        east: region.northeast.longitude,
      );
    } on Object {
      // The platform view can be gone between an idle event and this call.
    }
  }

  /// Stops listening to the underlying controller. The map itself is disposed
  /// by the widget that owns it.
  void dispose() {
    _disposed = true;
    _map.onFeatureDrag.remove(_handleFeatureDrag);
    onTap = null;
    onLongPress = null;
    onWaypointDragged = null;
    onCameraIdle = null;
  }

  static ml.LatLng _toMl(LatLng p) => ml.LatLng(p.lat, p.lon);

  static LatLng _fromMl(ml.LatLng p) => LatLng(p.latitude, p.longitude);

  static ml.LatLngBounds _toMlBounds(BoundingBox b) => ml.LatLngBounds(
    southwest: ml.LatLng(b.south, b.west),
    northeast: ml.LatLng(b.north, b.east),
  );
}
