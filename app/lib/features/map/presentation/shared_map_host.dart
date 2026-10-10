import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/shell_layout.dart';
import '../../planner/presentation/planner_map_host.dart';
import '../../shared/application/active_tab.dart';
import '../../shared/application/nav_bar_docking.dart';
import '../../shared/presentation/adaptive_docking_sheet.dart';
import '../application/cycle_map_binding.dart';
import '../application/locate_on_open.dart';
import '../application/weather_map_binding.dart';
import '../data/map_preferences.dart';
import '../domain/map_controller.dart';
import 'map_attribution.dart' show shellAttributionFloor;
import 'map_chrome.dart';
import 'puck_ownership.dart';

part 'shared_map_host.g.dart';

/// The map the Plan and Record tabs share, once it can be driven; `null`
/// before the style has loaded and between a style reload and the next
/// load, when every layer a screen drew is gone.
///
/// The shell paints one map under both tabs, so switching between them
/// neither moves nor flashes it. Each tab draws its own layers on this
/// controller while it is the tab on screen and takes them off when it
/// leaves; the shell's control column drives the camera through it.
@Riverpod(keepAlive: true)
class SharedMapController extends _$SharedMapController {
  @override
  MapController? build() => null;

  /// Records the map, or that there is none right now.
  void set(MapController? controller) {
    if (!ref.mounted || identical(state, controller)) return;
    state = controller;
  }
}

/// The shell's one map under the Plan and Record tabs.
///
/// Built once and kept in place: a map widget that is moved, hidden with
/// `Offstage` or rebuilt makes the platform view start over, and that shows
/// as black frames. What changes around it — which screen owns the puck,
/// where the control column sits — reaches the map through inherited
/// widgets, so the map widget itself is the same element frame after frame.
/// The app-wide overlay setting is applied here, as [PlannerMapHost] does
/// for the other maps, and so is [LocateOnOpen]: this host is there from the
/// app's start to its end, sees the app come and go, and is the one place a
/// hand on the map can be noticed.
class SharedMapHost extends ConsumerStatefulWidget {
  /// Creates the host.
  const SharedMapHost({super.key});

  @override
  ConsumerState<SharedMapHost> createState() => _SharedMapHostState();
}

class _SharedMapHostState extends ConsumerState<SharedMapHost>
    with WidgetsBindingObserver {
  MapController? _map;

  /// The map widget, built once per builder rather than once per build.
  Widget? _view;
  MapViewBuilder? _builder;

  late final SharedMapController _shared;

  /// The offline cycle map on this map; its hint is the shell's.
  late final CycleMapBinding _cycleMap;

  /// The weather layers on this map; their status is the shell's.
  late final WeatherMapBinding _weather;

  @override
  void initState() {
    super.initState();
    _shared = ref.read(sharedMapControllerProvider.notifier);
    _cycleMap = CycleMapBinding(ref);
    final hint = ref.read(sharedCycleMapNeedsDownloadProvider.notifier);
    _cycleMap.driver.needsDownload.addListener(
      () => hint.set(_cycleMap.driver.needsDownload.value),
    );
    _weather = WeatherMapBinding(ref);
    final weatherStatus = ref.read(sharedWeatherMapStatusProvider.notifier);
    // Out of the build that may have handed the map over: a status may
    // not be written to a provider there.
    _weather.driver.status.addListener(
      () => scheduleMicrotask(() {
        if (mounted) weatherStatus.set(_weather.driver.status.value);
      }),
    );
    _locate = ref.read(locateOnOpenProvider);
    WidgetsBinding.instance.addObserver(this);
    // A cold start: the remembered view is on screen from the first frame,
    // and the rider's position follows once there is a fix.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_locate.opened());
    });
  }

  late final LocateOnOpen _locate;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _locate.paused(DateTime.now());
      case AppLifecycleState.resumed:
        unawaited(_locate.resumed(DateTime.now()));
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Takes the map the builder just handed over (a fresh one, or the same
  /// one after a style reload), puts the app-wide overlay on it and
  /// publishes it. After the frame: the builder hands it over from a build,
  /// which may not write a provider.
  void _handleMapReady(MapController controller) {
    _map = controller;
    unawaited(controller.setCyclosmOverlay(ref.read(cyclosmOverlayProvider)));
    _cycleMap.attach(controller);
    _weather.attach(controller);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_map, controller)) _shared.set(controller);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cycleMap.dispose();
    _weather.dispose();
    // Deferred: the tree is locked while a widget goes.
    final shared = _shared;
    scheduleMicrotask(() => shared.set(null));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(cyclosmOverlayProvider, (_, next) {
      unawaited(_map?.setCyclosmOverlay(next));
    });
    _cycleMap.listen();
    _weather.listen();
    final builder = ref.watch(mapViewBuilderProvider);
    if (!identical(builder, _builder)) {
      _builder = builder;
      _view = builder(_handleMapReady);
    }
    // The shell draws the one control column over this map, so the map
    // draws none of its own.
    // Sideways the chip and the (i) sit on the map beside the rail and the
    // sheet; where the sheet comes to rest, docked or not, not every frame
    // of its travel, so the native view is not updated sixty times a second.
    final layout = ShellLayout.of(context);
    final docked = ref.watch(
      navBarDockingProvider.select(
        (docking) => docking.contains(ref.watch(activeTabProvider)),
      ),
    );
    final cover = sidewaysSheetCover(
      MediaQueryData.fromView(View.of(context)),
      layout,
      docked: docked,
    );
    // Read for the dependency: this map's own media has the bottom inset
    // taken off, so the zone is measured on the screen's.
    MediaQuery.systemGestureInsetsOf(context);
    final attributionFloor = shellAttributionFloor(
      MediaQueryData.fromView(View.of(context)),
      layout,
      defaultTargetPlatform,
    );
    final attributionInsets = !layout.sideRail
        ? EdgeInsets.zero
        : layout.side == RailSide.left
        ? EdgeInsets.only(left: cover)
        : EdgeInsets.only(right: cover);
    return MapChromeInsets(
      hoistedControls: true,
      attributionInsets: attributionInsets,
      attributionFloor: attributionFloor,
      child: PuckOwnership(
        owned: ref.watch(recorderOwnsPuckProvider),
        // Any touch on the map itself — a pan, a pinch, a tap — is the
        // rider's own say over the camera, which a late move to their
        // position must not overrule.
        child: Listener(onPointerDown: (_) => _locate.touched(), child: _view!),
      ),
    );
  }
}
