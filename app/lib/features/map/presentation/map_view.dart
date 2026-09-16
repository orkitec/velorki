import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/app_config.dart';
import '../../recording/data/battery_saver.dart';
import '../../settings/data/appearance_controller.dart';
import '../data/map_preferences.dart';
import '../data/maplibre_map_controller.dart';
import '../data/position_provider.dart';
import '../domain/map_controller.dart';
import 'map_attribution.dart';
import 'map_chrome.dart';
import 'map_controls.dart';

/// Sets up the native map before the first map is built.
///
/// Android draws platform views through a virtual display unless told
/// otherwise, and on some devices (a Pixel 3 XL on Android 12) that path never
/// composes a frame: the map shows once and then neither moves nor reacts to
/// touch. Hybrid composition puts the native view into the Flutter tree
/// instead, which is also what the plugin recommends.
void configureMapRendering() {
  ml.MapLibreMap.useHybridComposition = true;
}

/// Used when the build passes no `VELORKI_MAP_STYLE_URL`, so a bare
/// `flutter run` still shows a map.
const String fallbackMapStyleUrl =
    'https://tiles.openfreemap.org/styles/liberty';

/// The dark-mode counterpart, used when `VELORKI_MAP_STYLE_URL_DARK` is empty.
const String fallbackMapStyleUrlDark =
    'https://tiles.openfreemap.org/styles/fiord';

/// OpenFreeMap's black style, the "Black" map look.
const String blackMapStyleUrl = 'https://tiles.openfreemap.org/styles/dark';

/// The style for [look] under [brightness]: the configured URLs, else
/// OpenFreeMap's.
String mapStyleUrlFor(
  AppConfig config,
  Brightness brightness, [
  MapLook look = MapLook.auto,
]) {
  final light = config.mapStyleUrl.isEmpty
      ? fallbackMapStyleUrl
      : config.mapStyleUrl;
  final night = config.mapStyleUrlDark.isEmpty
      ? fallbackMapStyleUrlDark
      : config.mapStyleUrlDark;
  return switch (look) {
    MapLook.light => light,
    MapLook.night => night,
    MapLook.black => blackMapStyleUrl,
    MapLook.auto => brightness == Brightness.dark ? night : light,
  };
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

  /// Pushes a fix into the puck layers.
  ///
  /// Never moves the camera: the map only follows the rider when the locate
  /// button says so. Screens that own their own position source (the
  /// recorder) push on top of this; the last write wins and both agree.
  ///
  /// The GPS course is the only heading here. The phone's compass belongs to
  /// the screen that navigates: the planner and the library maps would be
  /// running the magnetometer for a cone nobody is riding behind.
  void _pushPosition(MapPosition? fix) {
    final adapter = _adapter;
    if (adapter == null || !mounted) return;
    unawaited(
      adapter.setPosition(
        fix?.position,
        accuracyM: fix?.accuracyM,
        headingDeg: fix?.headingDeg,
        speedMps: fix?.speedMps,
      ),
    );
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
    final MaplibreMapControllerAdapter adapter;
    try {
      adapter = MaplibreMapControllerAdapter(
        map,
        cyclosmTileUrl: ref.read(effectiveConfigProvider).cyclosmTileUrl,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        palette: MapPalette.fromTheme(Theme.of(context)),
      );
    } on StateError {
      // The style finished loading while the world around the map is being
      // torn down (a test's container disposed before its widgets); there
      // is nobody left to draw for.
      return;
    }
    _adapter = adapter;
    await adapter.attachToStyle();
    if (!mounted) return;
    await adapter.setCyclosmOverlay(ref.read(cyclosmOverlayProvider));
    if (!mounted) return;
    setState(() {});
    widget.onControllerReady(adapter);
    // A fix that arrived before the style finished loading would otherwise
    // wait for the next one, which is up to five metres of riding away.
    final known = ref.read(devicePositionProvider).value;
    if (known != null) _pushPosition(known);
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
    // Listening from build keeps the auto-dispose position stream alive for
    // as long as a map is on screen, and starts it again by itself once the
    // locate button has turned the permission into `granted` — the stream
    // provider watches the permission controller. It never prompts: the
    // controller only *checks* until something asks it to request.
    ref.listen<AsyncValue<MapPosition?>>(devicePositionProvider, (_, next) {
      // A loading or errored stream leaves the last fix on the map; only a
      // real `null` (permission gone) takes the puck away.
      if (next.hasValue) _pushPosition(next.value);
    });
    final config = ref.watch(effectiveConfigProvider);
    // The black style of a battery-saver ride wins over the rider's own look
    // for as long as that ride lasts.
    final look =
        ref.watch(appearanceOverrideProvider)?.mapLook ??
        ref.watch(appearanceSettingProvider).mapLook;
    final styleUrl = mapStyleUrlFor(config, Theme.of(context).brightness, look);
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
      // The map claims every touch that lands on it. Inside a scroll view
      // (the ride page) the list would otherwise win every vertical drag
      // and the map could neither pan nor zoom.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
      // The puck is drawn by our own layers from `devicePositionProvider`;
      // the native location component would ask for permission by itself.
      myLocationEnabled: false,
      // Everything on the map is a GeoJSON source with style layers; the
      // plugin's annotation managers would only add four layers nobody uses,
      // and their asynchronous set-up is what throws when the activity is
      // recreated under a map (MAP_NOT_READY from inside the plugin).
      annotationOrder: const <ml.AnnotationType>[],
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
