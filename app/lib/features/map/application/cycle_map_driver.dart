import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:velorki_cycle_map/velorki_cycle_map.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../domain/cycle_map.dart';
import '../domain/map_controller.dart';

/// How far beyond the map on screen the cycle map is made, as a share of
/// the screen's width and height on each side: panning within that needs
/// no new map.
const double cycleMapMargin = 0.5;

/// Keeps one map drawing the offline cycle map: on every rest of the
/// camera it asks the [renderer] for the area around what is on screen,
/// unless the map it drew last still covers it, and hands the file to the
/// map.
///
/// A new map is made when the view leaves the area of the last one, when
/// the zoom changes how finely lines are drawn, when other parts are
/// wanted, and when the downloaded tiles change. Parts switched on or off
/// show at once, before the new map arrives, by showing and hiding the
/// map's layers.
///
/// [needsDownload] says when the middle of the view has no downloaded
/// tile, for the screen's hint.
class CycleMapDriver {
  /// A driver asking [renderer] for maps, which [covers] says whether a
  /// point lies in a downloaded tile.
  CycleMapDriver({required this._renderer, required this._covers});

  final CycleMapRenderer _renderer;
  bool Function(LatLng point) _covers;
  MapController? _map;
  CycleMapSettings _settings = const CycleMapSettings();

  /// The area, zoom step and content of the map on the map, when there is
  /// one.
  ({BoundingBox box, int step, int content})? _drawn;
  int _serial = 0;
  bool _disposed = false;

  final ValueNotifier<bool> _needsDownload = ValueNotifier<bool>(false);

  /// Whether the cycle map is on and the middle of the view has no
  /// downloaded tile.
  ValueListenable<bool> get needsDownload => _needsDownload;

  /// The step of [zoom] at which lines are drawn differently.
  static int zoomStep(double zoom) => math.min(16, zoom.floor());

  /// Draws on [map] from now on. A map is attached again after a style
  /// reload; the map itself keeps the last file and puts it back.
  void attach(MapController map) {
    if (identical(map, _map)) return;
    detach();
    _map = map;
    _drawn = null;
    map.addCameraIdleListener(_update);
    unawaited(map.setCycleMapParts(_settings.parts));
    _update();
  }

  /// Lets the map go, taking the cycle map off it when [clear] is true.
  void detach({bool clear = true}) {
    final map = _map;
    if (map == null) return;
    map.removeCameraIdleListener(_update);
    _renderer.release(this);
    _serial++;
    if (clear && _drawn != null) unawaited(map.setCycleMap(null));
    _drawn = null;
    _map = null;
  }

  /// Follows new settings.
  void configure(CycleMapSettings settings) {
    if (settings == _settings) return;
    final partsChanged = !setEquals(settings.parts, _settings.parts);
    _settings = settings;
    final map = _map;
    if (map == null) return;
    if (partsChanged) unawaited(map.setCycleMapParts(settings.parts));
    _update();
  }

  /// The downloaded tiles changed: [covers] answers for the new ones.
  void tilesChanged(bool Function(LatLng point) covers) {
    _covers = covers;
    _renderer.tilesChanged();
    _drawn = null;
    _update();
  }

  void _update() {
    final map = _map;
    if (map == null || _disposed) return;
    if (!_settings.shown) {
      _needsDownload.value = false;
      _renderer.release(this);
      _serial++;
      if (_drawn != null) {
        _drawn = null;
        unawaited(map.setCycleMap(null));
      }
      return;
    }
    final zoom = map.zoom;
    final bounds = map.visibleBounds;
    if (zoom == null || bounds == null) return;
    // Zoomed out the map keeps what it has; its layers stop drawing at
    // [cycleMapMinZoom] by themselves.
    if (zoom < cycleMapMinZoom - 0.01) return;
    _needsDownload.value = !_covers(bounds.center);
    final step = zoomStep(zoom);
    final content = cycleContentOf(_settings.parts);
    final drawn = _drawn;
    if (drawn != null &&
        drawn.step == step &&
        drawn.content == content &&
        _within(bounds, drawn.box)) {
      return;
    }
    final box = _grown(bounds, cycleMapMargin);
    final serial = ++_serial;
    unawaited(_render(map, box, zoom, step, content, serial));
  }

  Future<void> _render(
    MapController map,
    BoundingBox box,
    double zoom,
    int step,
    int content,
    int serial,
  ) async {
    final CycleMapFile? file;
    try {
      file = await _renderer.render(
        CycleMapRequest(
          south: box.south,
          west: box.west,
          north: box.north,
          east: box.east,
          zoom: zoom,
          wanted: content,
        ),
        client: this,
      );
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'cycle map',
          context: ErrorDescription('while making the cycle map'),
        ),
      );
      return;
    }
    if (file == null || serial != _serial || !identical(map, _map)) return;
    _drawn = (box: box, step: step, content: content);
    await map.setCycleMap(file.path);
  }

  /// Stops for good.
  void dispose() {
    detach(clear: false);
    _disposed = true;
    _needsDownload.dispose();
  }

  static bool _within(BoundingBox inner, BoundingBox outer) =>
      inner.south >= outer.south &&
      inner.north <= outer.north &&
      inner.west >= outer.west &&
      inner.east <= outer.east;

  static BoundingBox _grown(BoundingBox box, double share) {
    final dLat = (box.north - box.south) * share;
    final dLon = (box.east - box.west) * share;
    return BoundingBox(
      south: math.max(-85.0, box.south - dLat),
      west: math.max(-180.0, box.west - dLon),
      north: math.min(85.0, box.north + dLat),
      east: math.min(180.0, box.east + dLon),
    );
  }
}
