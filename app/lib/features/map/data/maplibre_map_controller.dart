import 'dart:async';

import 'package:flutter/material.dart' show Brightness, ThemeData;
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/theme.dart';
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
/// The colours of the layers Velorki adds, as maplibre hex strings.
///
/// Built from the theme so the route follows the chosen accent and the
/// markers hold up on both map styles; [MapPalette.classic] is the fixed set
/// used where no theme is around.
@immutable
class MapPalette {
  /// Creates the palette.
  const MapPalette({
    required this.routeMain,
    required this.routeMainCasing,
    required this.routeAlternative,
    required this.routePreview,
    required this.track,
    required this.waypointStart,
    required this.waypointVia,
    required this.waypointEnd,
    required this.waypointStroke,
    required this.waypointLabel,
    required this.waypointLabelHalo,
    required this.positionDot,
    required this.positionAccuracy,
  });

  /// The fixed palette of the first release.
  const MapPalette.classic()
    : routeMain = '#1565C0',
      routeMainCasing = '#0D3C6E',
      routeAlternative = '#78909C',
      routePreview = '#EF6C00',
      track = '#AD1457',
      waypointStart = '#2E7D32',
      waypointVia = '#1565C0',
      waypointEnd = '#C62828',
      waypointStroke = '#FFFFFF',
      waypointLabel = '#FFFFFF',
      waypointLabelHalo = '#00000055',
      positionDot = '#1E88E5',
      positionAccuracy = '#1E88E5';

  /// The palette of [theme]'s [VelorkiColors].
  factory MapPalette.fromTheme(ThemeData theme) {
    final colors = theme.velorki;
    final dark = theme.brightness == Brightness.dark;
    return MapPalette(
      routeMain: VelorkiColors.hex(colors.routeMain),
      routeMainCasing: VelorkiColors.hex(colors.routeMainCasing),
      routeAlternative: VelorkiColors.hex(colors.routeAlternative),
      routePreview: VelorkiColors.hex(colors.routePreview),
      track: VelorkiColors.hex(colors.track),
      waypointStart: VelorkiColors.hex(colors.waypointStart),
      waypointVia: VelorkiColors.hex(colors.waypointVia),
      waypointEnd: VelorkiColors.hex(colors.waypointEnd),
      waypointStroke: VelorkiColors.hex(colors.waypointStroke),
      // Labels sit on the via markers, which are white in both modes.
      waypointLabel: dark ? '#0B0D10' : '#14171A',
      waypointLabelHalo: '#FFFFFF66',
      positionDot: VelorkiColors.hex(colors.position),
      positionAccuracy: VelorkiColors.hex(colors.position),
    );
  }

  final String routeMain;
  final String routeMainCasing;
  final String routeAlternative;
  final String routePreview;
  final String track;
  final String waypointStart;
  final String waypointVia;
  final String waypointEnd;
  final String waypointStroke;
  final String waypointLabel;
  final String waypointLabelHalo;
  final String positionDot;
  final String positionAccuracy;

  @override
  bool operator ==(Object other) =>
      other is MapPalette &&
      other.routeMain == routeMain &&
      other.routeMainCasing == routeMainCasing &&
      other.routeAlternative == routeAlternative &&
      other.routePreview == routePreview &&
      other.track == track &&
      other.waypointStart == waypointStart &&
      other.waypointVia == waypointVia &&
      other.waypointEnd == waypointEnd &&
      other.waypointStroke == waypointStroke &&
      other.waypointLabel == waypointLabel &&
      other.waypointLabelHalo == waypointLabelHalo &&
      other.positionDot == positionDot &&
      other.positionAccuracy == positionAccuracy;

  @override
  int get hashCode => Object.hash(
    routeMain,
    routeMainCasing,
    routeAlternative,
    routePreview,
    track,
    waypointStart,
    waypointVia,
    waypointEnd,
    waypointStroke,
    waypointLabel,
    waypointLabelHalo,
    positionDot,
    positionAccuracy,
  );
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
  MaplibreMapControllerAdapter(
    this._map, {
    this.cyclosmTileUrl = '',
    MapPalette palette = const MapPalette.classic(),
  }) : _palette = palette; // ignore: prefer_initializing_formals

  final ml.MapLibreMapController _map;
  MapPalette _palette;

  /// The colours the layers are drawn with.
  MapPalette get palette => _palette;

  /// CyclOSM XYZ template, `{s}` included; empty disables the overlay.
  final String cyclosmTileUrl;

  final Map<String, RouteLineStyle> _routeLines = <String, RouteLineStyle>{};
  // What the map should show, replayed after a style (re)load and used to
  // re-create a source the native side has dropped.
  final Map<String, List<LatLng>> _routePoints = <String, List<LatLng>>{};
  List<MapWaypoint> _waypoints = const <MapWaypoint>[];
  List<LatLng> _track = const <LatLng>[];
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
      ml.LineLayerProperties(
        lineColor: palette.track,
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
      ml.CircleLayerProperties(
        circleRadius: 0.0,
        circleColor: palette.positionAccuracy,
        circleOpacity: 0.15,
        circleStrokeWidth: 1.0,
        circleStrokeColor: palette.positionAccuracy,
        circleStrokeOpacity: 0.4,
      ),
      enableInteraction: false,
    );
    await _map.addLayer(
      MapLayerIds.positionSource,
      MapLayerIds.positionDotLayer,
      ml.CircleLayerProperties(
        circleRadius: 6.0,
        circleColor: palette.positionDot,
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
      ml.CircleLayerProperties(
        circleRadius: 10.0,
        circleColor: _waypointColorExpression(),
        circleStrokeWidth: 2.5,
        circleStrokeColor: palette.waypointStroke,
      ),
      // Drag gestures only reach layers that take part in feature interaction.
    );
    await _map.addLayer(
      MapLayerIds.waypointsSource,
      MapLayerIds.waypointsLabelLayer,
      ml.SymbolLayerProperties(
        textField: <Object>['get', 'label'],
        textSize: 12.0,
        textColor: palette.waypointLabel,
        textHaloColor: palette.waypointLabelHalo,
        textHaloWidth: 0.6,
        textAllowOverlap: true,
        textIgnorePlacement: true,
        textAnchor: 'center',
      ),
      enableInteraction: false,
    );

    _attached = true;
    await _refreshVisibleBounds();
    await _replay();
  }

  /// Re-applies the cached waypoints, track and route lines after a style
  /// load dropped every source.
  Future<void> _replay() async {
    if (_waypoints.isNotEmpty) await setWaypoints(_waypoints);
    if (_track.isNotEmpty) await setTrackLine(_track);
    final lines = Map<String, List<LatLng>>.of(_routePoints);
    final styles = Map<String, RouteLineStyle>.of(_routeLines);
    _routeLines.clear();
    for (final entry in lines.entries) {
      await setRouteLine(
        entry.key,
        entry.value,
        style: styles[entry.key] ?? RouteLineStyle.main,
      );
    }
  }

  /// Whether the native style still has [sourceId]. MapLibre only logs when
  /// a source vanished, so the adapter asks before updating.
  Future<bool> _hasSource(String sourceId) async {
    try {
      final ids = await _map.getSourceIds();
      return ids.contains(sourceId);
    } catch (_) {
      return true;
    }
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
    _routePoints[id] = List<LatLng>.unmodifiable(points);
    var previous = _routeLines[id];
    if (previous != null && !await _hasSource(sourceId)) {
      _routeLines.remove(id);
      previous = null;
    }
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
    _routePoints.remove(id);
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

  ml.LineLayerProperties _lineProperties(RouteLineStyle style) =>
      switch (style) {
        RouteLineStyle.main => ml.LineLayerProperties(
          lineColor: palette.routeMain,
          lineWidth: 5.0,
          lineOpacity: 1.0,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        RouteLineStyle.alternative => ml.LineLayerProperties(
          lineColor: palette.routeAlternative,
          lineWidth: 4.0,
          lineOpacity: 0.75,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        RouteLineStyle.preview => ml.LineLayerProperties(
          lineColor: palette.routePreview,
          lineWidth: 4.0,
          lineOpacity: 0.9,
          lineCap: 'round',
          lineJoin: 'round',
          lineDasharray: <double>[2, 1.5],
        ),
      };

  /// Recolours every layer for [palette], e.g. after the accent changed
  /// without a style reload.
  Future<void> setPalette(MapPalette palette) async {
    if (palette == _palette) return;
    _palette = palette;
    if (!_attached) return;
    await _map.setLayerProperties(
      MapLayerIds.trackLayer,
      ml.LineLayerProperties(lineColor: palette.track),
    );
    await _map.setLayerProperties(
      MapLayerIds.positionDotLayer,
      ml.CircleLayerProperties(circleColor: palette.positionDot),
    );
    await _map.setLayerProperties(
      MapLayerIds.positionAccuracyLayer,
      ml.CircleLayerProperties(
        circleColor: palette.positionAccuracy,
        circleStrokeColor: palette.positionAccuracy,
      ),
    );
    await _map.setLayerProperties(
      MapLayerIds.waypointsCircleLayer,
      ml.CircleLayerProperties(
        circleColor: _waypointColorExpression(),
        circleStrokeColor: palette.waypointStroke,
      ),
    );
    await _map.setLayerProperties(
      MapLayerIds.waypointsLabelLayer,
      ml.SymbolLayerProperties(
        textColor: palette.waypointLabel,
        textHaloColor: palette.waypointLabelHalo,
      ),
    );
    for (final entry in _routeLines.entries) {
      await _map.setLayerProperties(
        MapLayerIds.routeLayer(entry.key),
        _lineProperties(entry.value),
      );
    }
  }

  List<Object> _waypointColorExpression() => <Object>[
    'match',
    <Object>['get', 'kind'],
    'start',
    palette.waypointStart,
    'end',
    palette.waypointEnd,
    palette.waypointVia,
  ];

  // -------------------------------------------------------------- features

  @override
  Future<void> setWaypoints(List<MapWaypoint> waypoints) async {
    _waypoints = List<MapWaypoint>.unmodifiable(waypoints);
    if (!_attached) return;
    if (!await _hasSource(MapLayerIds.waypointsSource)) {
      // The style dropped our sources without a style-loaded callback;
      // rebuild everything and let the replay draw the waypoints.
      await attachToStyle();
      return;
    }
    await _map.setGeoJsonSource(
      MapLayerIds.waypointsSource,
      waypointsFeatureCollection(waypoints),
    );
  }

  @override
  Future<void> setTrackLine(List<LatLng> points) async {
    _track = List<LatLng>.unmodifiable(points);
    if (!_attached) return;
    if (!await _hasSource(MapLayerIds.trackSource)) {
      await attachToStyle();
      return;
    }
    await _map.setGeoJsonSource(
      MapLayerIds.trackSource,
      lineFeatureCollection(points),
    );
  }

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
        circleColor: palette.positionAccuracy,
        circleOpacity: 0.15,
        circleStrokeWidth: 1.0,
        circleStrokeColor: palette.positionAccuracy,
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
