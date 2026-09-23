import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart' show Brightness, Color, ThemeData;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/theme.dart';
import '../domain/map_controller.dart';
import 'cyclosm_tone.dart';
import 'geojson.dart';
import 'heading_cone.dart';
import 'heading_smoother.dart';
import 'tile_template.dart';

/// Source and layer ids. Everything Velorki adds to the style is prefixed so
/// it can never collide with a layer of the base style.
abstract final class MapLayerIds {
  static const String cyclosmSource = 'velorki-cyclosm';
  static const String cyclosmLayer = 'velorki-cyclosm-raster';
  static const String trackSource = 'velorki-track';
  static const String trackLayer = 'velorki-track-line';
  static const String searchPinSource = 'velorki-search-pin';
  static const String searchPinLayer = 'velorki-search-pin-dot';
  static const String searchPinLabelLayer = 'velorki-search-pin-label';
  static const String positionSource = 'velorki-position';
  static const String positionAccuracyLayer = 'velorki-position-accuracy';
  static const String positionHeadingLayer = 'velorki-position-heading';
  static const String positionHaloLayer = 'velorki-position-halo';
  static const String positionDotLayer = 'velorki-position-dot';
  static const String waypointsSource = 'velorki-waypoints';
  static const String waypointsHitLayer = 'velorki-waypoints-hit';
  static const String waypointsCircleLayer = 'velorki-waypoints-circle';
  static const String waypointsLabelLayer = 'velorki-waypoints-label';
  static const String poisSource = 'velorki-pois';
  static const String poisCircleLayer = 'velorki-pois-circle';
  static const String poisLabelLayer = 'velorki-pois-label';
  static const String turnsSource = 'velorki-turns';
  static const String turnsLayer = 'velorki-turns-dot';

  static String routeSource(String id) => 'velorki-route-${_slug(id)}';
  static String routeLayer(String id) => 'velorki-route-${_slug(id)}-line';
  static String routeCasingLayer(String id) =>
      'velorki-route-${_slug(id)}-casing';

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
    required this.routeAlternatives,
    required this.routePreview,
    required this.track,
    required this.trackSlow,
    required this.trackFast,
    required this.waypointStart,
    required this.waypointVia,
    required this.waypointEnd,
    required this.waypointStroke,
    required this.waypointLabel,
    required this.waypointLabelHalo,
    required this.positionDot,
    required this.positionAccuracy,
    this.poiDanger = '#EF6C00',
    this.poiWater = '#1E88E5',
    this.poiFood = '#8E24AA',
    this.poiGeneric = '#78909C',
  });

  /// The points of interest by kind: a hazard, water, food, anything else.
  final String poiDanger;
  final String poiWater;
  final String poiFood;
  final String poiGeneric;

  /// The fixed palette of the first release.
  const MapPalette.classic()
    : routeMain = '#1565C0',
      routeMainCasing = '#0D3C6E',
      routeAlternative = '#78909C',
      routeAlternatives = const <String>['#78909C', '#5C6BC0', '#26A69A'],
      routePreview = '#EF6C00',
      track = '#AD1457',
      trackSlow = '#1D6FD0',
      trackFast = '#AD1457',
      waypointStart = '#2E7D32',
      waypointVia = '#1565C0',
      waypointEnd = '#C62828',
      waypointStroke = '#FFFFFF',
      waypointLabel = '#FFFFFF',
      waypointLabelHalo = '#00000055',
      positionDot = '#1E88E5',
      positionAccuracy = '#1E88E5',
      poiDanger = '#EF6C00',
      poiWater = '#1E88E5',
      poiFood = '#8E24AA',
      poiGeneric = '#78909C';

  /// The palette of [theme]'s [VelorkiColors].
  factory MapPalette.fromTheme(ThemeData theme) {
    final colors = theme.velorki;
    final dark = theme.brightness == Brightness.dark;
    return MapPalette(
      routeMain: VelorkiColors.hex(colors.routeMain),
      routeMainCasing: VelorkiColors.hex(colors.routeMainCasing),
      routeAlternative: VelorkiColors.hex(colors.routeAlternative),
      routeAlternatives: <String>[
        for (final c in colors.routeAlternatives) VelorkiColors.hex(c),
      ],
      routePreview: VelorkiColors.hex(colors.routePreview),
      track: VelorkiColors.hex(colors.track),
      trackSlow: VelorkiColors.hex(colors.trackSlow),
      trackFast: VelorkiColors.hex(colors.trackFast),
      waypointStart: VelorkiColors.hex(colors.waypointStart),
      waypointVia: VelorkiColors.hex(colors.waypointVia),
      waypointEnd: VelorkiColors.hex(colors.waypointEnd),
      waypointStroke: VelorkiColors.hex(colors.waypointStroke),
      // Labels sit on the via markers, which are white in both modes.
      waypointLabel: dark ? '#0B0D10' : '#14171A',
      waypointLabelHalo: '#FFFFFF66',
      positionDot: VelorkiColors.hex(colors.position),
      positionAccuracy: VelorkiColors.hex(colors.position),
      poiDanger: VelorkiColors.hex(colors.warning),
      poiWater: VelorkiColors.hex(colors.position),
      poiFood: VelorkiColors.hex(theme.colorScheme.tertiary),
      poiGeneric: VelorkiColors.hex(colors.routeAlternative),
    );
  }

  final String routeMain;
  final String routeMainCasing;
  final String routeAlternative;

  /// One colour per alternative index; wraps around when there are more.
  final List<String> routeAlternatives;
  final String routePreview;
  final String track;

  /// The slow end of the ride page's speed ramp.
  final String trackSlow;

  /// The fast end of it.
  final String trackFast;
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
      listEquals(other.routeAlternatives, routeAlternatives) &&
      other.routePreview == routePreview &&
      other.track == track &&
      other.trackSlow == trackSlow &&
      other.trackFast == trackFast &&
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
    Object.hashAll(routeAlternatives),
    routePreview,
    track,
    trackSlow,
    trackFast,
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

/// Font stack for the waypoint number labels.
///
/// A symbol layer without an explicit `text-font` falls back to the style
/// spec's default, `Open Sans Regular, Arial Unicode MS Regular`, which the
/// OpenFreeMap glyph endpoint does not serve: the request 404s, the glyph
/// dependency of the waypoint source's tiles is never satisfied, and MapLibre
/// then withholds the *whole* layout result for that source — so the circle
/// layer sharing it stays invisible as well. Every OpenFreeMap style ships
/// `Noto Sans Regular`, so name it explicitly.
const List<String> waypointLabelFont = <String>['Noto Sans Regular'];

/// `#RRGGBB` or `#RRGGBBAA` as a [Color], the inverse of [VelorkiColors.hex].
///
/// The palette travels as maplibre style strings, but the heading cone is
/// painted by us and needs a real colour back.
Color colorFromMapHex(String hex) {
  final digits = hex.startsWith('#') ? hex.substring(1) : hex;
  final value = int.tryParse(digits, radix: 16);
  if (value == null) return const Color(0xFF000000);
  return switch (digits.length) {
    6 => Color(0xFF000000 | value),
    8 => Color((value >>> 8) | ((value & 0xFF) << 24)),
    _ => const Color(0xFF000000),
  };
}

/// Attribution string handed to the raster source, so the native SDK's own
/// attribution sheet lists CyclOSM even though our chip draws it separately.
const String _cyclosmAttribution =
    '© OpenStreetMap contributors, tiles by CyclOSM';

/// How long the puck takes to walk from one fix to the next.
///
/// A recording fix arrives about once a second; drawing the puck straight at
/// each one makes it hop. Walking it there over most of that second is what
/// makes the dot look like it is riding rather than teleporting.
const Duration puckInterpolationDuration = Duration(milliseconds: 800);

/// How many steps that walk is drawn in. Twelve is smooth enough to read as
/// motion and cheap enough to write twelve times a second.
const int puckInterpolationSteps = 12;

/// A jump longer than this is not riding.
///
/// The first fix after a tunnel, a cold start or an OS cache comes from far
/// away; walking the puck across half a city would look like a bug, so it is
/// simply put where it belongs.
const double puckTeleportMeters = 100;

/// The slice of maplibre_gl's [ml.MapLibreMapController] the adapter drives.
///
/// The plugin controller only exists behind a platform view, so in
/// `flutter test` there is nothing to talk to and every member below is a
/// method channel call. Naming the handful the adapter actually uses lets the
/// layer choreography — the z-order, the caching, the self-healing after the
/// native side dropped a source — be driven by a recording fake instead.
abstract class MapLibreStyleOps {
  /// Creates a GeoJSON source called [sourceId] holding [geojson].
  Future<void> addGeoJsonSource(String sourceId, Map<String, dynamic> geojson);

  /// Replaces the data of an existing GeoJSON source. This is the cheap call
  /// routes and waypoints are built on: one message however long the line.
  Future<void> setGeoJsonSource(String sourceId, Map<String, dynamic> geojson);

  /// Creates a non-GeoJSON source; for Velorki that is only the CyclOSM
  /// raster tiles.
  Future<void> addSource(String sourceId, ml.SourceProperties properties);

  /// Adds the style layer [layerId] drawing [sourceId].
  ///
  /// [belowLayerId] is what keeps the route lines under the puck, and
  /// [enableInteraction] decides whether a layer's features can be dragged —
  /// only the waypoint circles want that.
  Future<void> addLayer(
    String sourceId,
    String layerId,
    ml.LayerProperties properties, {
    String? belowLayerId,
    bool enableInteraction = true,
  });

  /// Removes the layer [layerId]; a source can only go once nothing draws it.
  Future<void> removeLayer(String layerId);

  /// Removes the source [sourceId].
  Future<void> removeSource(String sourceId);

  /// Rewrites the paint and layout properties of [layerId], which is how a
  /// palette change and a new accuracy ring reach the map without a reload.
  Future<void> setLayerProperties(
    String layerId,
    ml.LayerProperties properties,
  );

  /// Shows or hides [layerId] — cheaper than adding and removing the overlay.
  Future<void> setLayerVisibility(String layerId, bool visible);

  /// Every source id the native style currently holds. MapLibre drops a
  /// source silently, so asking is the only way to notice.
  Future<List<String>> getSourceIds();

  /// Registers [bytes] as the style image [name], replacing any image already
  /// under that name. The heading cone is a bitmap we paint ourselves.
  Future<void> addImage(String name, Uint8List bytes);

  /// Flies the camera to [update], over [duration] when one is given.
  Future<void> animateCamera(ml.CameraUpdate update, {Duration? duration});

  /// Jumps the camera to [update], for moves that should not be watched.
  Future<void> moveCamera(ml.CameraUpdate update);

  /// Where the camera last reported itself, `null` before the first frame.
  ml.CameraPosition? get cameraPosition;

  /// The area currently on screen. Throws once the platform view is gone.
  Future<ml.LatLngBounds> getVisibleRegion();

  /// The plugin's own list of feature drag listeners. It is a plain list, so
  /// the adapter registers and unregisters by adding to and removing from it
  /// rather than by holding a subscription.
  List<ml.OnFeatureDragCallback> get onFeatureDrag;

  /// The plugin's feature tap listeners, same shape as [onFeatureDrag].
  List<ml.OnFeatureInteractionCallback> get onFeatureTapped;
}

/// Completes [op] as if it had succeeded when the platform says there was
/// nothing to do.
///
/// Four answers mean exactly that: `MAP_NOT_READY` (Android) and
/// `styleNotFound` (iOS), when the view or its style is gone under the map
/// (a recreated activity, a page popped mid-write) and a fresh map with a
/// fresh adapter is on its way; a missing plugin implementation, when the
/// view's method channel has already been torn down; and "already exists",
/// when a style reload kept a source or layer the adapter had written off.
/// All used to surface as unhandled exceptions from fire-and-forget calls
/// and take an integration test down; none is worth reporting.
Future<void> tolerateMapGone(Future<void> Function() op) async {
  try {
    await op();
  } on MissingPluginException {
    return;
  } on PlatformException catch (e) {
    if (e.code == 'MAP_NOT_READY' || e.code == 'styleNotFound') return;
    if ((e.message ?? '').contains('already exists')) return;
    // A source or layer the style no longer has: the style is on its way
    // out under us, and the style-loaded callback that follows replays
    // everything onto the new one. (The adapter's own not-found handling
    // still matters for the fakes that stand in for the plugin.)
    if (isStyleGoneError(e)) return;
    rethrow;
  }
}

/// Whether [e] says the style no longer has what the call addressed: iOS
/// answers with `sourceNotFound`, `LAYER_NOT_FOUND_ERROR` and the like while
/// a look change tears the old style down under the adapter.
bool isStyleGoneError(PlatformException e) {
  final code = e.code.toLowerCase();
  return code.contains('notfound') || code.contains('not_found');
}

/// [MapLibreStyleOps] forwarding one for one to a real plugin controller.
///
/// Nothing but the forwarding lives here: every decision the adapter makes
/// stays in the adapter, where a test can reach it. The one thing added is
/// [tolerateMapGone] around every write, because those two platform answers
/// are facts about the platform view, not about the adapter's state.
class PluginMapLibreStyleOps implements MapLibreStyleOps {
  /// Wraps [map], the controller `MapLibreMap.onMapCreated` handed over.
  const PluginMapLibreStyleOps(this.map);

  /// The wrapped plugin controller.
  final ml.MapLibreMapController map;

  @override
  Future<void> addGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson,
  ) => tolerateMapGone(() => map.addGeoJsonSource(sourceId, geojson));

  @override
  Future<void> setGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson,
  ) => tolerateMapGone(() => map.setGeoJsonSource(sourceId, geojson));

  @override
  Future<void> addSource(String sourceId, ml.SourceProperties properties) =>
      tolerateMapGone(() => map.addSource(sourceId, properties));

  @override
  Future<void> addLayer(
    String sourceId,
    String layerId,
    ml.LayerProperties properties, {
    String? belowLayerId,
    bool enableInteraction = true,
  }) => tolerateMapGone(
    () => map.addLayer(
      sourceId,
      layerId,
      properties,
      belowLayerId: belowLayerId,
      enableInteraction: enableInteraction,
    ),
  );

  @override
  Future<void> removeLayer(String layerId) =>
      tolerateMapGone(() => map.removeLayer(layerId));

  @override
  Future<void> removeSource(String sourceId) =>
      tolerateMapGone(() => map.removeSource(sourceId));

  @override
  Future<void> setLayerProperties(
    String layerId,
    ml.LayerProperties properties,
  ) => tolerateMapGone(() => map.setLayerProperties(layerId, properties));

  @override
  Future<void> setLayerVisibility(String layerId, bool visible) =>
      tolerateMapGone(() => map.setLayerVisibility(layerId, visible));

  @override
  Future<List<String>> getSourceIds() => map.getSourceIds();

  @override
  Future<void> addImage(String name, Uint8List bytes) =>
      tolerateMapGone(() => map.addImage(name, bytes));

  @override
  Future<void> animateCamera(ml.CameraUpdate update, {Duration? duration}) =>
      tolerateMapGone(() => map.animateCamera(update, duration: duration));

  @override
  Future<void> moveCamera(ml.CameraUpdate update) =>
      tolerateMapGone(() => map.moveCamera(update));

  @override
  ml.CameraPosition? get cameraPosition => map.cameraPosition;

  @override
  Future<ml.LatLngBounds> getVisibleRegion() => map.getVisibleRegion();

  @override
  List<ml.OnFeatureDragCallback> get onFeatureDrag => map.onFeatureDrag;

  @override
  List<ml.OnFeatureInteractionCallback> get onFeatureTapped =>
      map.onFeatureTapped;
}

/// [MapController] over maplibre_gl's [ml.MapLibreMapController].
///
/// Routes, waypoints, the track and the puck are GeoJSON sources with style
/// layers rather than annotations: annotations go through a per-feature method
/// channel round trip, while a source swap is one call however long the line.
class MaplibreMapControllerAdapter implements MapController {
  /// Wraps the controller `MapLibreMap.onMapCreated` handed over.
  MaplibreMapControllerAdapter(
    ml.MapLibreMapController map, {
    String cyclosmTileUrl = '',
    double devicePixelRatio = 1.0,
    MapPalette palette = const MapPalette.classic(),
    RasterTone cyclosmTone = lightCyclosmTone,
  }) : this.withOps(
         PluginMapLibreStyleOps(map),
         cyclosmTileUrl: cyclosmTileUrl,
         devicePixelRatio: devicePixelRatio,
         palette: palette,
         cyclosmTone: cyclosmTone,
       );

  /// Drives [ops] instead of a plugin controller, so the layer work can be
  /// exercised without a platform view.
  MaplibreMapControllerAdapter.withOps(
    this._ops, {
    this.cyclosmTileUrl = '',
    this.devicePixelRatio = 1.0,
    MapPalette palette = const MapPalette.classic(),
    RasterTone cyclosmTone = lightCyclosmTone,
  }) : _palette = palette, // ignore: prefer_initializing_formals
       _cyclosmTone = cyclosmTone; // ignore: prefer_initializing_formals

  final MapLibreStyleOps _ops;
  MapPalette _palette;
  RasterTone _cyclosmTone;

  /// Screen density the heading cone bitmap is rasterised at.
  final double devicePixelRatio;

  /// The colours the layers are drawn with.
  MapPalette get palette => _palette;

  /// The raster paint the CyclOSM overlay is drawn with: the tone of the map
  /// look on screen, chosen by the owner (see [cyclosmToneFor]).
  RasterTone get cyclosmTone => _cyclosmTone;

  /// CyclOSM XYZ template, `{s}` included; empty disables the overlay.
  final String cyclosmTileUrl;

  final Map<String, RouteLineStyle> _routeLines = <String, RouteLineStyle>{};
  // What the map should show, replayed after a style (re)load and used to
  // re-create a source the native side has dropped.
  final Map<String, List<LatLng>> _routePoints = <String, List<LatLng>>{};
  // The style of every remembered route, so a replay after a style reload
  // draws a preview as a preview; `_routeLines` only knows what exists.
  final Map<String, RouteLineStyle> _routeStyles = <String, RouteLineStyle>{};
  List<MapWaypoint> _waypoints = const <MapWaypoint>[];
  List<MapPoi> _pois = const <MapPoi>[];
  List<MapTurnMarker> _turns = const <MapTurnMarker>[];

  @override
  void Function(int index)? onPoiTapped;

  @override
  void Function(int index)? onTurnTapped;
  LatLng? _searchPin;
  String? _searchPinLabel;
  List<LatLng> _track = const <LatLng>[];
  // The two ways of drawing the track share one source and one layer, so only
  // one of them is ever set; `_trackColoured` is what the layer currently
  // paints with, so a recording does not rewrite the paint on every fix.
  List<TrackSegment> _trackSegments = const <TrackSegment>[];
  bool _trackColoured = false;
  // Hysteresis and circular averaging for the heading cone, so it neither
  // blinks nor spins while the rider rolls along at walking pace.
  final HeadingSmoother _headingSmoother = HeadingSmoother();
  // Where the puck is drawn right now, and the ticker walking it towards the
  // newest fix; see [setPosition].
  LatLng? _puckPosition;
  Timer? _puckWalk;
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
  void Function(int index)? onWaypointTapped;

  // A drag ends with a release the platform also reports as a tap, and a
  // tap on a marker arrives as a map click too; both would add a waypoint.
  DateTime? _lastDragEnd;
  DateTime? _lastFeatureTap;
  bool _dragging = false;
  static const Duration _clickShadow = Duration(milliseconds: 600);

  @override
  VoidCallback? onCameraIdle;

  /// Whether [attachToStyle] has run and the layers exist.
  bool get isAttached => _attached;

  @override
  bool get isReady => _attached;

  /// Creates the sources and layers. Call once per loaded style, from
  /// `onStyleLoadedCallback`: a style change drops every layer we added.
  Future<void> attachToStyle() async {
    _attached = false;
    _routeLines.clear();
    // A fresh style draws the track in the plain colour until something asks
    // for the speed ramp again.
    _trackColoured = false;
    // A fresh style has no puck, so the next fix is drawn where it is rather
    // than walked there from wherever the old one stood.
    _puckWalk?.cancel();
    _puckWalk = null;
    _puckPosition = null;
    _ops.onFeatureDrag.remove(_handleFeatureDrag);
    _ops.onFeatureDrag.add(_handleFeatureDrag);
    _ops.onFeatureTapped.remove(_handleFeatureTapped);
    _ops.onFeatureTapped.add(_handleFeatureTapped);

    await _addCyclosmLayer();

    await _ops.addGeoJsonSource(
      MapLayerIds.trackSource,
      emptyFeatureCollection(),
    );
    await _ops.addLayer(
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

    await _ops.addGeoJsonSource(
      MapLayerIds.positionSource,
      emptyFeatureCollection(),
    );
    await _ops.addLayer(
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
    // The cone is a symbol, so its bitmap has to exist before the layer that
    // names it; re-registering under the same name replaces it.
    await _addHeadingConeImage();
    await _ops.addLayer(
      MapLayerIds.positionSource,
      MapLayerIds.positionHeadingLayer,
      ml.SymbolLayerProperties(
        iconImage: headingConeImageName,
        iconAnchor: 'bottom',
        iconRotate: <Object>['get', 'heading'],
        // The cone points along a compass course, so it turns with the map
        // rather than staying upright on the screen.
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        // No course worth drawing means no cone; the property is simply
        // absent from the feature then.
        iconOpacity: <Object>[
          'case',
          <Object>['has', 'heading'],
          1,
          0,
        ],
      ),
      enableInteraction: false,
    );
    await _ops.addLayer(
      MapLayerIds.positionSource,
      MapLayerIds.positionHaloLayer,
      ml.CircleLayerProperties(
        circleRadius: 14.0,
        circleColor: palette.positionDot,
        circleOpacity: 0.18,
      ),
      enableInteraction: false,
    );
    await _ops.addLayer(
      MapLayerIds.positionSource,
      MapLayerIds.positionDotLayer,
      ml.CircleLayerProperties(
        circleRadius: 8.0,
        circleColor: palette.positionDot,
        circleStrokeWidth: 3.0,
        circleStrokeColor: '#FFFFFF',
      ),
      enableInteraction: false,
    );

    await _ops.addGeoJsonSource(
      MapLayerIds.waypointsSource,
      emptyFeatureCollection(),
    );
    // The touch target: an invisible disc twice the marker's size. It is the
    // only interactive waypoint layer, so a tap or a drag is reported once,
    // and a finger on a dense screen still hits it.
    await _ops.addLayer(
      MapLayerIds.waypointsSource,
      MapLayerIds.waypointsHitLayer,
      ml.CircleLayerProperties(circleRadius: 22.0, circleOpacity: 0.0),
    );
    await _ops.addLayer(
      MapLayerIds.waypointsSource,
      MapLayerIds.waypointsCircleLayer,
      ml.CircleLayerProperties(
        circleRadius: 10.0,
        circleColor: _waypointColorExpression(),
        circleStrokeWidth: 2.5,
        circleStrokeColor: palette.waypointStroke,
      ),
      enableInteraction: false,
    );
    await _ops.addLayer(
      MapLayerIds.waypointsSource,
      MapLayerIds.waypointsLabelLayer,
      ml.SymbolLayerProperties(
        textField: <Object>['get', 'label'],
        textFont: waypointLabelFont,
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

    // The route's points of interest: small discs in the colour of their
    // kind, the name above each. Under the waypoints, so a start marker on a
    // water fountain still reads as the start.
    await _ops.addGeoJsonSource(
      MapLayerIds.poisSource,
      emptyFeatureCollection(),
    );
    // Turn markers, for a screen that reads the route: small dots in the
    // route's own colour, under the points of interest.
    await _ops.addGeoJsonSource(
      MapLayerIds.turnsSource,
      emptyFeatureCollection(),
    );
    await _ops.addLayer(
      MapLayerIds.turnsSource,
      MapLayerIds.turnsLayer,
      ml.CircleLayerProperties(
        circleRadius: 5.0,
        circleColor: palette.routeMain,
        circleStrokeWidth: 2.0,
        circleStrokeColor: palette.waypointStroke,
      ),
    );
    await _ops.addLayer(
      MapLayerIds.poisSource,
      MapLayerIds.poisCircleLayer,
      ml.CircleLayerProperties(
        circleRadius: 6.0,
        circleColor: _poiColorExpression(),
        circleStrokeWidth: 2.0,
        circleStrokeColor: palette.waypointStroke,
      ),
    );
    await _ops.addLayer(
      MapLayerIds.poisSource,
      MapLayerIds.poisLabelLayer,
      ml.SymbolLayerProperties(
        textField: <Object>['get', 'name'],
        textFont: waypointLabelFont,
        textSize: 11.0,
        textColor: _poiColorExpression(),
        textHaloColor: palette.waypointStroke,
        textHaloWidth: 1.2,
        textAnchor: 'bottom',
        textOffset: <Object>[0, -0.9],
        textOptional: true,
      ),
      enableInteraction: false,
    );

    // The searched place: a pin in the preview colour with the place name,
    // shown until the rider makes it a start, a destination, or drops it.
    await _ops.addGeoJsonSource(
      MapLayerIds.searchPinSource,
      emptyFeatureCollection(),
    );
    await _ops.addLayer(
      MapLayerIds.searchPinSource,
      MapLayerIds.searchPinLayer,
      ml.CircleLayerProperties(
        circleRadius: 9.0,
        circleColor: palette.routePreview,
        circleStrokeWidth: 2.5,
        circleStrokeColor: palette.waypointStroke,
      ),
      enableInteraction: false,
    );
    await _ops.addLayer(
      MapLayerIds.searchPinSource,
      MapLayerIds.searchPinLabelLayer,
      ml.SymbolLayerProperties(
        textField: <Object>['get', 'label'],
        textFont: waypointLabelFont,
        textSize: 13.0,
        textOffset: <Object>[0, -1.6],
        textAnchor: 'bottom',
        textColor: palette.waypointLabel,
        textHaloColor: palette.waypointLabelHalo,
        textHaloWidth: 1.2,
        textAllowOverlap: true,
        textIgnorePlacement: true,
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
    if (_pois.isNotEmpty) await setPois(_pois);
    if (_turns.isNotEmpty) await setTurnMarkers(_turns);
    if (_searchPin != null) {
      await setSearchPin(_searchPin, label: _searchPinLabel);
    }
    if (_track.isNotEmpty) await setTrackLine(_track);
    if (_trackSegments.isNotEmpty) await setTrackSegments(_trackSegments);
    final lines = Map<String, List<LatLng>>.of(_routePoints);
    for (final entry in lines.entries) {
      await setRouteLine(
        entry.key,
        entry.value,
        style: _routeStyles[entry.key] ?? RouteLineStyle.main,
      );
    }
  }

  /// Whether the native style still has [sourceId]. MapLibre only logs when
  /// a source vanished, so the adapter asks before updating.
  /// Whether the style has [sourceId]; `null` when the platform would not
  /// say (a style mid-swap, a view already gone).
  Future<bool?> _hasSource(String sourceId) async {
    try {
      final ids = await _ops.getSourceIds();
      return ids.contains(sourceId);
    } catch (_) {
      return null;
    }
  }

  /// Rasterises the heading cone in the palette's position colour and hands
  /// it to the style. Called on attach and again whenever the palette
  /// changes: `addImage` under an existing name replaces the bitmap.
  Future<void> _addHeadingConeImage() async {
    try {
      final bytes = await buildHeadingConeImage(
        color: colorFromMapHex(palette.positionDot),
        devicePixelRatio: devicePixelRatio,
      );
      if (_disposed) return;
      await _ops.addImage(headingConeImageName, bytes);
    } on Object catch (error) {
      // A missing cone is a cosmetic loss; the dot and ring still draw.
      debugPrint('velorki: heading cone image failed: $error');
    }
  }

  Future<void> _addCyclosmLayer() async {
    final tiles = expandTileTemplate(cyclosmTileUrl);
    if (tiles.isEmpty) return;
    await _ops.addSource(
      MapLayerIds.cyclosmSource,
      ml.RasterSourceProperties(
        tiles: tiles,
        tileSize: 256,
        minzoom: 0,
        maxzoom: 20,
        attribution: _cyclosmAttribution,
      ),
    );
    await _ops.addLayer(
      MapLayerIds.cyclosmSource,
      MapLayerIds.cyclosmLayer,
      _cyclosmTone.layerProperties(
        visibility: _cyclosmVisible ? 'visible' : 'none',
      ),
      enableInteraction: false,
    );
  }

  /// Re-paints the CyclOSM overlay in [tone], e.g. after the rider switched
  /// to the night map or changed how the overlay is treated there.
  ///
  /// A look change normally swaps the base style, and the style-loaded
  /// callback builds a fresh adapter that adds the overlay in the new tone.
  /// This is the other path — the overlay setting changing on its own, and
  /// the moment before a style reload lands — where the layer is still there
  /// and only its paint has to change.
  Future<void> setCyclosmTone(RasterTone tone) async {
    if (tone == _cyclosmTone) return;
    _cyclosmTone = tone;
    if (!_attached || expandTileTemplate(cyclosmTileUrl).isEmpty) return;
    try {
      await _ops.setLayerProperties(
        MapLayerIds.cyclosmLayer,
        tone.layerProperties(),
      );
    } on PlatformException {
      // The old style is on its way out; the next `attachToStyle` adds the
      // overlay in the tone set above.
    }
  }

  // ---------------------------------------------------------------- camera

  @override
  Future<void> moveTo(
    LatLng center, {
    double? zoom,
    double? bearing,
    bool animate = true,
    Duration? duration,
  }) async {
    // Only a full camera position carries a bearing, and it carries the zoom
    // and the tilt with it, so those have to be filled in from the live
    // camera or the move would flatten them to the defaults.
    final update = bearing != null
        ? ml.CameraUpdate.newCameraPosition(
            ml.CameraPosition(
              target: _toMl(center),
              zoom: zoom ?? _ops.cameraPosition?.zoom ?? 0,
              bearing: bearing,
              tilt: _ops.cameraPosition?.tilt ?? 0,
            ),
          )
        : zoom == null
        ? ml.CameraUpdate.newLatLng(_toMl(center))
        : ml.CameraUpdate.newLatLngZoom(_toMl(center), zoom);
    if (animate) {
      await _ops.animateCamera(update, duration: duration);
    } else {
      await _ops.moveCamera(update);
    }
  }

  @override
  Future<void> fitBounds(
    BoundingBox bounds, {
    EdgeInsets padding = const EdgeInsets.all(48),
  }) async {
    await _ops.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        _toMlBounds(bounds),
        left: padding.left,
        top: padding.top,
        right: padding.right,
        bottom: padding.bottom,
      ),
    );
  }

  @override
  LatLng? get center {
    final target = _ops.cameraPosition?.target;
    return target == null ? null : LatLng(target.latitude, target.longitude);
  }

  @override
  double? get zoom => _ops.cameraPosition?.zoom;

  @override
  double? get bearing => _ops.cameraPosition?.bearing;

  @override
  BoundingBox? get visibleBounds => _visibleBounds;

  // ------------------------------------------------------------ route lines

  /// One route line's writes and removals, in the order they were asked
  /// for. A removal still taking its source down while the next write for
  /// the same id looked for that source found it, refreshed it, and lost
  /// it a moment later to the removal: the line was gone and its owner
  /// none the wiser. Every id has its own queue; different lines do not
  /// wait for each other.
  final Map<String, Future<void>> _routeLineQueue = <String, Future<void>>{};

  Future<void> _queuedRouteLine(String id, Future<void> Function() op) {
    final next = (_routeLineQueue[id] ?? Future<void>.value()).then(
      (_) => op(),
    );
    _routeLineQueue[id] = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<void> setRouteLine(
    String id,
    List<LatLng> points, {
    RouteLineStyle style = RouteLineStyle.main,
  }) {
    // Remembered even before the style is ready: the replay after
    // `attachToStyle` draws it, so owners need not push it twice.
    _routePoints[id] = List<LatLng>.unmodifiable(points);
    _routeStyles[id] = style;
    return _queuedRouteLine(id, () => _setRouteLineNow(id, points, style));
  }

  Future<void> _setRouteLineNow(
    String id,
    List<LatLng> points,
    RouteLineStyle style,
  ) async {
    // Taken away again while this waited its turn, or no style to draw on:
    // nothing to do now; the replay after the next attach draws what is
    // remembered.
    if (!_attached || !_routePoints.containsKey(id)) return;
    final sourceId = MapLayerIds.routeSource(id);
    final layerId = MapLayerIds.routeLayer(id);
    final data = lineFeatureCollection(
      points,
      properties: <String, dynamic>{'id': id, 'style': style.name},
    );
    var previous = _routeLines[id];
    final present = await _hasSource(sourceId);
    if (previous != null && present == false) {
      _routeLines.remove(id);
      previous = null;
    }
    try {
      if (previous == null && present == true) {
        // The style kept the line through a reload the adapter treated as
        // a fresh start (`attachToStyle` forgets every line). Adding it
        // again would clash with what is there; refreshing it is what was
        // meant.
        await _ops.setGeoJsonSource(sourceId, data);
        await _ops.setLayerProperties(
          MapLayerIds.routeCasingLayer(id),
          _casingProperties(style),
        );
        await _ops.setLayerProperties(layerId, _lineProperties(style, id));
      } else if (previous == null) {
        await _addRouteLine(id, sourceId, layerId, data, style);
      } else {
        await _ops.setGeoJsonSource(sourceId, data);
        if (previous != style) {
          await _ops.setLayerProperties(
            MapLayerIds.routeCasingLayer(id),
            _casingProperties(style),
          );
          await _ops.setLayerProperties(layerId, _lineProperties(style, id));
        }
      }
      _routeLines[id] = style;
    } on PlatformException catch (e) {
      // iOS refuses a write to a source or layer the style has dropped
      // (Android keeps quiet), and a look change tears the old style down
      // piece by piece while the adapter is still writing. The line is
      // drawn afresh once; if the style is really going, the replay after
      // the next style load draws it anyway.
      if (!isStyleGoneError(e)) rethrow;
      _routeLines.remove(id);
      try {
        await _addRouteLine(id, sourceId, layerId, data, style);
        _routeLines[id] = style;
      } on PlatformException catch (e) {
        if (!isStyleGoneError(e)) rethrow;
      }
    }
  }

  /// Adds the source and the two layers of a route line.
  Future<void> _addRouteLine(
    String id,
    String sourceId,
    String layerId,
    Map<String, dynamic> data,
    RouteLineStyle style,
  ) async {
    await _ops.addGeoJsonSource(sourceId, data);
    // Under the puck and the markers; an alternative also under the track
    // and, since every chosen route sits above the track, under the chosen
    // route, whatever order they arrive in. A ride page draws the route it
    // followed that way, so the ridden track stays the subject.
    final below = style == RouteLineStyle.alternative
        ? MapLayerIds.trackLayer
        : MapLayerIds.positionAccuracyLayer;
    // A dark casing under the line keeps any accent readable on any map
    // style: lime on a green park, orange on a yellow road.
    await _ops.addLayer(
      sourceId,
      MapLayerIds.routeCasingLayer(id),
      _casingProperties(style),
      belowLayerId: below,
      enableInteraction: false,
    );
    await _ops.addLayer(
      sourceId,
      layerId,
      _lineProperties(style, id),
      belowLayerId: below,
      enableInteraction: false,
    );
  }

  @override
  Future<void> removeRouteLine(String id) {
    _routePoints.remove(id);
    _routeStyles.remove(id);
    return _queuedRouteLine(id, () => _removeRouteLineNow(id));
  }

  Future<void> _removeRouteLineNow(String id) async {
    // Set again while this waited its turn: the write after it draws.
    if (_routePoints.containsKey(id)) return;
    if (!_attached || _routeLines.remove(id) == null) return;
    await _ops.removeLayer(MapLayerIds.routeLayer(id));
    await _ops.removeLayer(MapLayerIds.routeCasingLayer(id));
    await _ops.removeSource(MapLayerIds.routeSource(id));
  }

  @override
  Future<void> clearRouteLines() async {
    for (final id in _routeLines.keys.toList()) {
      await removeRouteLine(id);
    }
  }

  ml.LineLayerProperties _lineProperties(RouteLineStyle style, [String? id]) =>
      switch (style) {
        RouteLineStyle.main => ml.LineLayerProperties(
          // A chosen alternative (`main-2`) keeps its own colour on top.
          lineColor: id == null || !_isVariantId(id)
              ? palette.routeMain
              : _alternativeColour(id),
          lineWidth: 5.0,
          lineOpacity: 1.0,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        RouteLineStyle.alternative => ml.LineLayerProperties(
          lineColor: id == null
              ? palette.routeAlternative
              : _alternativeColour(id),
          lineWidth: 4.0,
          lineOpacity: 0.85,
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

  /// Whether [id] names a numbered variant (`alt-2`, `main-2`).
  static bool _isVariantId(String id) => RegExp(r'-\d+$').hasMatch(id);

  /// `alt-2` → the third alternative colour; anything else → the fallback.
  String _alternativeColour(String id) {
    final match = RegExp(r'(\d+)$').firstMatch(id);
    final colours = palette.routeAlternatives;
    if (match == null || colours.isEmpty) return palette.routeAlternative;
    return colours[int.parse(match.group(1)!) % colours.length];
  }

  /// The casing drawn under a route line: wider, dark, translucent.
  ml.LineLayerProperties _casingProperties(RouteLineStyle style) =>
      switch (style) {
        RouteLineStyle.main => ml.LineLayerProperties(
          lineColor: palette.routeMainCasing,
          lineWidth: 9.0,
          lineOpacity: 0.55,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        RouteLineStyle.alternative => ml.LineLayerProperties(
          lineColor: palette.routeMainCasing,
          lineWidth: 7.0,
          lineOpacity: 0.3,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        RouteLineStyle.preview => ml.LineLayerProperties(
          lineColor: palette.routeMainCasing,
          lineWidth: 7.0,
          lineOpacity: 0.45,
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
    try {
      await _recolour(palette);
    } on PlatformException {
      // The style is on its way out (a theme switch swaps the map style in
      // the same frame it changes the palette): the next `attachToStyle`
      // draws every layer with the palette set above.
    }
  }

  Future<void> _recolour(MapPalette palette) async {
    await _ops.setLayerProperties(
      MapLayerIds.trackLayer,
      ml.LineLayerProperties(lineColor: _trackLineColor()),
    );
    await _ops.setLayerProperties(
      MapLayerIds.positionDotLayer,
      ml.CircleLayerProperties(circleColor: palette.positionDot),
    );
    await _ops.setLayerProperties(
      MapLayerIds.positionHaloLayer,
      ml.CircleLayerProperties(circleColor: palette.positionDot),
    );
    // The cone is a bitmap, not a style colour, so it has to be redrawn.
    await _addHeadingConeImage();
    await _ops.setLayerProperties(
      MapLayerIds.positionAccuracyLayer,
      ml.CircleLayerProperties(
        circleColor: palette.positionAccuracy,
        circleStrokeColor: palette.positionAccuracy,
      ),
    );
    await _ops.setLayerProperties(
      MapLayerIds.waypointsCircleLayer,
      ml.CircleLayerProperties(
        circleColor: _waypointColorExpression(),
        circleStrokeColor: palette.waypointStroke,
      ),
    );
    await _ops.setLayerProperties(
      MapLayerIds.poisCircleLayer,
      ml.CircleLayerProperties(
        circleColor: _poiColorExpression(),
        circleStrokeColor: palette.waypointStroke,
      ),
    );
    await _ops.setLayerProperties(
      MapLayerIds.turnsLayer,
      ml.CircleLayerProperties(
        circleColor: palette.routeMain,
        circleStrokeColor: palette.waypointStroke,
      ),
    );
    await _ops.setLayerProperties(
      MapLayerIds.poisLabelLayer,
      ml.SymbolLayerProperties(
        textColor: _poiColorExpression(),
        textHaloColor: palette.waypointStroke,
      ),
    );
    await _ops.setLayerProperties(
      MapLayerIds.waypointsLabelLayer,
      ml.SymbolLayerProperties(
        textColor: palette.waypointLabel,
        textHaloColor: palette.waypointLabelHalo,
      ),
    );
    await _ops.setLayerProperties(
      MapLayerIds.searchPinLayer,
      ml.CircleLayerProperties(
        circleColor: palette.routePreview,
        circleStrokeColor: palette.waypointStroke,
      ),
    );
    await _ops.setLayerProperties(
      MapLayerIds.searchPinLabelLayer,
      ml.SymbolLayerProperties(
        textColor: palette.waypointLabel,
        textHaloColor: palette.waypointLabelHalo,
      ),
    );
    for (final entry in _routeLines.entries) {
      await _ops.setLayerProperties(
        MapLayerIds.routeCasingLayer(entry.key),
        _casingProperties(entry.value),
      );
      await _ops.setLayerProperties(
        MapLayerIds.routeLayer(entry.key),
        _lineProperties(entry.value, entry.key),
      );
    }
  }

  List<Object> _poiColorExpression() => <Object>[
    'match',
    <Object>['get', 'kind'],
    'danger',
    palette.poiDanger,
    'water',
    palette.poiWater,
    'food',
    palette.poiFood,
    palette.poiGeneric,
  ];

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
    if (await _hasSource(MapLayerIds.waypointsSource) == false) {
      // The style dropped our sources without a style-loaded callback;
      // rebuild everything and let the replay draw the waypoints.
      await attachToStyle();
      return;
    }
    await _writeBaseSource(
      MapLayerIds.waypointsSource,
      waypointsFeatureCollection(waypoints),
    );
  }

  @override
  Future<void> setTurnMarkers(List<MapTurnMarker> turns) async {
    _turns = List<MapTurnMarker>.unmodifiable(turns);
    if (!_attached) return;
    if (await _hasSource(MapLayerIds.turnsSource) == false) {
      await attachToStyle();
      return;
    }
    await _writeBaseSource(
      MapLayerIds.turnsSource,
      turnsFeatureCollection(turns),
    );
  }

  @override
  Future<void> setPois(List<MapPoi> pois) async {
    _pois = List<MapPoi>.unmodifiable(pois);
    if (!_attached) return;
    if (await _hasSource(MapLayerIds.poisSource) == false) {
      await attachToStyle();
      return;
    }
    await _writeBaseSource(MapLayerIds.poisSource, poisFeatureCollection(pois));
  }

  /// Whether [attachToStyle] is running because a write found the style
  /// gone; stops a write during that rebuild from asking for another.
  bool _reattaching = false;

  /// Writes [data] into one of the sources [attachToStyle] creates.
  ///
  /// iOS refuses a write to a source the style has dropped with
  /// `sourceNotFound` (a look change tears the old style down before the
  /// style-loaded callback arrives). That is the same situation as the
  /// missing-source check above, so it is answered the same way: rebuild
  /// and let the replay draw everything.
  Future<void> _writeBaseSource(
    String sourceId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _ops.setGeoJsonSource(sourceId, data);
    } on PlatformException catch (e) {
      if (!isStyleGoneError(e)) rethrow;
      if (_reattaching) return;
      _reattaching = true;
      try {
        await attachToStyle();
      } finally {
        _reattaching = false;
      }
    }
  }

  @override
  Future<void> setTrackLine(List<LatLng> points) async {
    _track = List<LatLng>.unmodifiable(points);
    _trackSegments = const <TrackSegment>[];
    if (!_attached) return;
    if (await _hasSource(MapLayerIds.trackSource) == false) {
      await attachToStyle();
      return;
    }
    await _setTrackColoured(false);
    await _writeBaseSource(
      MapLayerIds.trackSource,
      lineFeatureCollection(points),
    );
  }

  @override
  Future<void> setTrackSegments(List<TrackSegment> segments) async {
    _trackSegments = List<TrackSegment>.unmodifiable(segments);
    _track = const <LatLng>[];
    if (!_attached) return;
    if (await _hasSource(MapLayerIds.trackSource) == false) {
      await attachToStyle();
      return;
    }
    await _setTrackColoured(true);
    await _writeBaseSource(
      MapLayerIds.trackSource,
      trackSegmentsFeatureCollection(segments),
    );
  }

  /// Switches the track layer between the flat colour and the speed ramp,
  /// writing the paint only when it actually changes.
  Future<void> _setTrackColoured(bool coloured) async {
    if (_trackColoured == coloured) return;
    _trackColoured = coloured;
    await _ops.setLayerProperties(
      MapLayerIds.trackLayer,
      ml.LineLayerProperties(lineColor: _trackLineColor()),
    );
  }

  /// What the track layer paints with: one colour for a recording, the
  /// slow-to-fast ramp for a finished ride.
  Object _trackLineColor() => _trackColoured
      ? trackSpeedColorExpression(palette.trackSlow, palette.trackFast)
      : palette.track;

  @override
  Future<void> setPosition(
    LatLng? position, {
    double? accuracyM,
    double? headingDeg,
    double? speedMps,
    bool headingFromCompass = false,
    bool minimal = false,
  }) async {
    // Whatever the last fix started is over; this one decides where the puck
    // goes now.
    _puckWalk?.cancel();
    _puckWalk = null;
    if (!_attached) return;
    // The cone is driven by the smoother, not by this one fix: it appears
    // only once the rider is clearly moving, keeps the last heading through a
    // fix without a course, and turns the long way around 0° like a compass.
    if (position == null) {
      _headingSmoother.reset();
    }
    final smoothed = position == null
        ? null
        : _headingSmoother.update(
            headingDeg: headingDeg,
            speedMps: speedMps,
            fromCompass: headingFromCompass,
          );
    // The smoother is kept fed either way, so switching the saver off
    // mid-ride does not start the cone from nothing.
    final heading = minimal ? null : smoothed;
    final from = _puckPosition;
    _puckPosition = position;
    // A fix per second drawn as a fix per second is a hopping dot. Walk the
    // puck from where it stands to where the rider now is, and only the last
    // step of that walk is the fix itself. A first fix and a jump that is no
    // ride at all go straight there.
    if (position != null &&
        from != null &&
        from != position &&
        haversineMeters(from, position) <= puckTeleportMeters) {
      _walkPuck(from, position, accuracyM: accuracyM, headingDeg: heading);
    } else {
      await _writeBaseSource(
        MapLayerIds.positionSource,
        positionFeatureCollection(
          position,
          accuracyM: accuracyM,
          resolvedHeadingDeg: heading,
        ),
      );
    }
    if (!_attached) return;
    // circle-radius is in pixels, so a metre-accurate ring needs a fresh
    // zoom expression whenever the accuracy or the latitude changes.
    final radius = position == null || accuracyM == null || accuracyM <= 0
        ? 0.0
        : accuracyRingRadiusExpression(accuracyM, position.lat);
    await _ops.setLayerProperties(
      MapLayerIds.positionAccuracyLayer,
      ml.CircleLayerProperties(
        circleRadius: radius,
        circleColor: palette.positionAccuracy,
        circleOpacity: minimal ? 0.0 : 0.15,
        circleStrokeWidth: 1.0,
        circleStrokeColor: palette.positionAccuracy,
        circleStrokeOpacity: minimal ? 0.0 : 0.4,
      ),
    );
  }

  /// Draws the puck on its way from [from] to [to] over
  /// [puckInterpolationDuration], ending exactly on [to].
  ///
  /// Every step carries the same heading and accuracy the fix came with, so
  /// only the dot moves; nothing blinks while it walks.
  void _walkPuck(
    LatLng from,
    LatLng to, {
    double? accuracyM,
    double? headingDeg,
  }) {
    final period = puckInterpolationDuration ~/ puckInterpolationSteps;
    var step = 0;
    _puckWalk = Timer.periodic(period, (timer) {
      step++;
      final done = step >= puckInterpolationSteps;
      if (done) {
        timer.cancel();
        if (identical(_puckWalk, timer)) _puckWalk = null;
      }
      if (!_attached) return;
      final t = step / puckInterpolationSteps;
      final at = done
          ? to
          : LatLng(
              from.lat + (to.lat - from.lat) * t,
              from.lon + (to.lon - from.lon) * t,
            );
      unawaited(
        _writeBaseSource(
          MapLayerIds.positionSource,
          positionFeatureCollection(
            at,
            accuracyM: accuracyM,
            resolvedHeadingDeg: headingDeg,
          ),
        ),
      );
    });
  }

  @override
  Future<void> setCyclosmOverlay(bool visible) async {
    _cyclosmVisible = visible;
    if (expandTileTemplate(cyclosmTileUrl).isEmpty || !_attached) return;
    await _ops.setLayerVisibility(MapLayerIds.cyclosmLayer, visible);
  }

  @override
  Future<void> setSearchPin(LatLng? position, {String? label}) async {
    _searchPin = position;
    _searchPinLabel = position == null ? null : label;
    if (!_attached) return;
    await _writeBaseSource(
      MapLayerIds.searchPinSource,
      position == null
          ? emptyFeatureCollection()
          : <String, dynamic>{
              'type': 'FeatureCollection',
              'features': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'Feature',
                  'properties': <String, dynamic>{'label': label ?? ''},
                  'geometry': <String, dynamic>{
                    'type': 'Point',
                    'coordinates': lngLat(position),
                  },
                },
              ],
            },
    );
  }

  /// Whether the CyclOSM overlay is currently switched on.
  bool get isCyclosmVisible => _cyclosmVisible;

  // ---------------------------------------------------------------- events

  /// Forwarded from `MapLibreMap.onMapClick`.
  void handleMapClick(ml.LatLng coordinates) {
    if (_inClickShadow()) return;
    onTap?.call(_fromMl(coordinates));
  }

  bool _inClickShadow() {
    final now = DateTime.now();
    for (final stamp in <DateTime?>[_lastDragEnd, _lastFeatureTap]) {
      if (stamp != null && now.difference(stamp) < _clickShadow) return true;
    }
    return false;
  }

  /// Forwarded from `MapLibreMap.onMapLongClick`.
  void handleMapLongClick(ml.LatLng coordinates) {
    // Holding a marker to drag it is not a long press on the map: that would
    // insert a point under the finger while the marker is being moved.
    if (_dragging || _inClickShadow()) return;
    onLongPress?.call(_fromMl(coordinates));
  }

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
    // The platform moves the marker under the finger by itself. Only the
    // release is reported: committing every intermediate position rewrote
    // the marker source under the native drag, flooded the undo stack and
    // re-routed on the way, which made the drag shaky.
    final index = waypointIndexFromFeatureId(id);
    if (index == null) return;
    if (eventType == ml.DragEventType.start) {
      _dragging = true;
      return;
    }
    // The platform does not move the feature itself: the marker follows
    // the finger through the source, and the planner hears about it once,
    // on release.
    if (index < _waypoints.length) {
      final moved = List<MapWaypoint>.of(_waypoints);
      final old = moved[index];
      moved[index] = MapWaypoint(
        position: _fromMl(current),
        kind: old.kind,
        label: old.label,
      );
      _waypoints = List<MapWaypoint>.unmodifiable(moved);
      if (_attached) {
        unawaited(
          _ops.setGeoJsonSource(
            MapLayerIds.waypointsSource,
            waypointsFeatureCollection(_waypoints),
          ),
        );
      }
    }
    if (eventType != ml.DragEventType.end) return;
    _dragging = false;
    _lastDragEnd = DateTime.now();
    if (_isTapSizedDrag(origin, current)) {
      // A finger that wobbled a few pixels meant to tap: the marker goes
      // back where it was and the tap is reported instead of a move.
      if (index < _waypoints.length) {
        final restored = List<MapWaypoint>.of(_waypoints);
        final old = restored[index];
        restored[index] = MapWaypoint(
          position: _fromMl(origin),
          kind: old.kind,
          label: old.label,
        );
        _waypoints = List<MapWaypoint>.unmodifiable(restored);
        if (_attached) {
          unawaited(
            _ops.setGeoJsonSource(
              MapLayerIds.waypointsSource,
              waypointsFeatureCollection(_waypoints),
            ),
          );
        }
      }
      _reportWaypointTap(index);
      return;
    }
    onWaypointDragged?.call(index, _fromMl(current));
  }

  /// Reports a marker tap once: the platform delivers a wobbly tap both as
  /// a drag (start/end) and as a feature tap, so the second one within the
  /// click shadow is dropped.
  void _reportWaypointTap(int index) {
    final now = DateTime.now();
    final last = _lastFeatureTap;
    if (last != null && now.difference(last) < _clickShadow) return;
    _lastFeatureTap = now;
    onWaypointTapped?.call(index);
  }

  /// Whether a drag from [origin] to [current] stayed within a tap's worth
  /// of screen pixels at the current zoom.
  bool _isTapSizedDrag(ml.LatLng origin, ml.LatLng current) {
    const tapPixels = 14.0;
    final zoom = _ops.cameraPosition?.zoom ?? 14.0;
    final metresPerPixel =
        156543.03 *
        math.cos(origin.latitude * math.pi / 180) /
        math.pow(2, zoom);
    return haversineMeters(_fromMl(origin), _fromMl(current)) <
        tapPixels * metresPerPixel;
  }

  void _handleFeatureTapped(
    Object? point,
    ml.LatLng coordinates,
    String id,
    String layerId,
    ml.Annotation? annotation,
  ) {
    final waypoint = waypointIndexFromFeatureId(id);
    if (waypoint != null) {
      _reportWaypointTap(waypoint);
      return;
    }
    final poi = poiIndexFromFeatureId(id);
    if (poi != null) {
      onPoiTapped?.call(poi);
      return;
    }
    final turn = turnIndexFromFeatureId(id);
    if (turn != null) onTurnTapped?.call(turn);
  }

  Future<void> _refreshVisibleBounds() async {
    try {
      final region = await _ops.getVisibleRegion();
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
    _puckWalk?.cancel();
    _puckWalk = null;
    _ops.onFeatureDrag.remove(_handleFeatureDrag);
    _ops.onFeatureTapped.remove(_handleFeatureTapped);
    onTap = null;
    onLongPress = null;
    onWaypointDragged = null;
    onWaypointTapped = null;
    onCameraIdle = null;
  }

  static ml.LatLng _toMl(LatLng p) => ml.LatLng(p.lat, p.lon);

  static LatLng _fromMl(ml.LatLng p) => LatLng(p.latitude, p.longitude);

  static ml.LatLngBounds _toMlBounds(BoundingBox b) => ml.LatLngBounds(
    southwest: ml.LatLng(b.south, b.west),
    northeast: ml.LatLng(b.north, b.east),
  );
}
