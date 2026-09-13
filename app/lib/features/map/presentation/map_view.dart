import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/app_config.dart';
import '../data/map_preferences.dart';
import '../data/maplibre_map_controller.dart';
import '../domain/map_controller.dart';
import 'map_attribution.dart';
import 'map_chrome.dart';
import 'map_controls.dart';

/// Used when the build passes no `VELORKI_MAP_STYLE_URL`, so a bare
/// `flutter run` still shows a map.
const String fallbackMapStyleUrl =
    'https://tiles.openfreemap.org/styles/liberty';

/// The dark-mode counterpart, used when `VELORKI_MAP_STYLE_URL_DARK` is empty.
const String fallbackMapStyleUrlDark =
    'https://tiles.openfreemap.org/styles/dark';

/// The style for [brightness]: the configured URLs, else OpenFreeMap's.
String mapStyleUrlFor(AppConfig config, Brightness brightness) {
  if (brightness == Brightness.dark) {
    return config.mapStyleUrlDark.isEmpty
        ? fallbackMapStyleUrlDark
        : config.mapStyleUrlDark;
  }
  return config.mapStyleUrl.isEmpty ? fallbackMapStyleUrl : config.mapStyleUrl;
}

/// The map itself: a `MapLibreMap` platform view plus the adapter that turns
/// it into a [MapController].
///
/// The widget owns nothing about routes or waypoints. It hands the controller
/// to [onControllerReady] and the owning screen (the planner, the recorder)
/// drives it from there. [onControllerReady] fires again after a style
/// reload, because every layer we added is gone at that point and has to be
/// re-applied by the owner.
class MapView extends ConsumerStatefulWidget {
  const MapView({
    required this.onControllerReady,
    this.onControllerDisposed,
    this.rememberCamera = true,
    this.showAttribution = true,
    this.showControls = true,
    this.controlsPadding = const EdgeInsets.only(top: 12, right: 12),
    this.attributionPadding = const EdgeInsets.only(left: 8, bottom: 8),
    super.key,
  });

  /// Called once the style is loaded and the Velorki layers exist.
  final void Function(MapController controller) onControllerReady;

  /// Called when the map goes away, so owners can drop their reference.
  final VoidCallback? onControllerDisposed;

  /// Whether the camera is persisted and restored across app starts.
  final bool rememberCamera;

  /// Whether the OpenStreetMap attribution chip is drawn over the map.
  ///
  /// Both stores and the ODbL require the attribution to be visible on the
  /// map, so screens should leave this on unless they draw their own.
  final bool showAttribution;

  /// Whether the locate/overlay/zoom column is drawn over the map.
  final bool showControls;

  /// Inset of the control column from the top right corner.
  final EdgeInsets controlsPadding;

  /// Inset of the attribution chip from the bottom left corner.
  final EdgeInsets attributionPadding;

  @override
  ConsumerState<MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<MapView> {
  ml.MapLibreMapController? _map;
  MaplibreMapControllerAdapter? _adapter;

  @override
  void dispose() {
    _adapter?.dispose();
    _adapter = null;
    _map = null;
    widget.onControllerDisposed?.call();
    super.dispose();
  }

  void _onMapCreated(ml.MapLibreMapController controller) {
    _map = controller;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // An accent change without a brightness change keeps the style, so the
    // layers are recoloured in place; a brightness change swaps the style
    // and rebuilds the adapter from `_onStyleLoaded`.
    final adapter = _adapter;
    if (adapter == null) return;
    unawaited(adapter.setPalette(MapPalette.fromTheme(Theme.of(context))));
  }

  Future<void> _onStyleLoaded() async {
    final map = _map;
    if (map == null) return;
    _adapter?.dispose();
    final adapter = MaplibreMapControllerAdapter(
      map,
      cyclosmTileUrl: ref.read(effectiveConfigProvider).cyclosmTileUrl,
      palette: MapPalette.fromTheme(Theme.of(context)),
    );
    _adapter = adapter;
    await adapter.attachToStyle();
    if (!mounted) return;
    await adapter.setCyclosmOverlay(ref.read(cyclosmOverlayProvider));
    if (!mounted) return;
    setState(() {});
    widget.onControllerReady(adapter);
  }

  void _onCameraIdle() {
    _adapter?.handleCameraIdle();
    if (!widget.rememberCamera) return;
    final position = _map?.cameraPosition;
    if (position == null) return;
    unawaited(
      ref
          .read(lastMapCameraProvider.notifier)
          .save(
            MapCamera(
              center: LatLng(
                position.target.latitude,
                position.target.longitude,
              ),
              zoom: position.zoom,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(effectiveConfigProvider);
    final styleUrl = mapStyleUrlFor(config, Theme.of(context).brightness);
    // Read, not watch: the initial camera must not rebuild the platform view
    // every time the camera is saved.
    final camera = widget.rememberCamera
        ? ref.read(lastMapCameraProvider)
        : defaultMapCamera;

    final map = ml.MapLibreMap(
      styleString: styleUrl,
      initialCameraPosition: ml.CameraPosition(
        target: ml.LatLng(camera.center.lat, camera.center.lon),
        zoom: camera.zoom,
      ),
      // The adapter reads `cameraPosition` for `center`/`zoom`.
      trackCameraPosition: true,
      compassEnabled: false,
      logoEnabled: false,
      // maplibre_gl 0.27 cannot hide the native attribution (i) button, so it
      // is parked bottom right, opposite our own MapAttributionChip.
      attributionButtonPosition: ml.AttributionButtonPosition.bottomRight,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: false,
      // The puck is drawn by our own layers from `devicePositionProvider`;
      // the native location component would ask for permission by itself.
      myLocationEnabled: false,
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: () => unawaited(_onStyleLoaded()),
      onMapClick: (_, coordinates) => _adapter?.handleMapClick(coordinates),
      onMapLongClick: (_, coordinates) =>
          _adapter?.handleMapLongClick(coordinates),
      onCameraIdle: _onCameraIdle,
    );

    if (!widget.showAttribution && !widget.showControls) return map;
    final chrome = MapChromeInsets.maybeOf(context);
    final chromeTop = chrome?.controlsTop;
    final chromeBottom = chrome?.attributionBottom;
    final controlsPadding = chromeTop == null
        ? widget.controlsPadding
        : widget.controlsPadding.copyWith(top: chromeTop);
    final attributionPadding = chromeBottom == null
        ? widget.attributionPadding
        : widget.attributionPadding.copyWith(bottom: chromeBottom);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        map,
        if (widget.showControls)
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: controlsPadding,
                child: Align(
                  alignment: Alignment.topRight,
                  child: MapControls(controller: _adapter),
                ),
              ),
            ),
          ),
        if (widget.showAttribution)
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: attributionPadding,
                child: const Align(
                  alignment: Alignment.bottomLeft,
                  child: MapAttributionChip(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
