import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../map/data/map_preferences.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/map_chrome.dart';
import '../../map/presentation/puck_ownership.dart';

part 'planner_map_host.g.dart';

/// Builds the widget that renders the map and hands its [MapController] to
/// [onReady] as soon as the map is usable.
typedef MapViewBuilder = Widget Function(
  void Function(MapController controller) onReady,
);

/// The map widget the planner and the route detail screen embed.
///
/// The default is an empty placeholder so that screens compose and widget
/// tests run without maplibre. `bootstrap()` overrides it with the real
/// `MapView`, and tests override it with a builder that hands out a fake
/// controller.
@Riverpod(keepAlive: true)
MapViewBuilder mapViewBuilder(Ref ref) =>
    (onReady) => const ColoredBox(color: Color(0xFFE8E6E1));

/// Places the map and forwards its controller, so no screen imports maplibre.
///
/// It is also where the app-wide map settings reach a map: the CyclOSM
/// overlay is one setting for the whole app ([cyclosmOverlayProvider]), and
/// several maps are alive at once — the tabs of the shell keep their screens
/// in an `IndexedStack`. Every host applies the setting to its own map when
/// the map becomes usable (which is again after a style reload, when every
/// layer we added is gone) and whenever the setting changes, so a toggle on
/// one tab is on the map of every other tab as well.
class PlannerMapHost extends ConsumerStatefulWidget {
  /// Creates the host.
  const PlannerMapHost({
    required this.onMapReady,
    super.key,
    this.embedded = false,
    this.ownsPosition = false,
  });

  /// Called once the map can be driven.
  final void Function(MapController controller) onMapReady;

  /// Whether the map sits above other content rather than reaching the
  /// bottom of the screen. An embedded map drops the bottom safe-area inset
  /// (the floating navigation bar), which would otherwise push its
  /// attribution chip into the middle of the map.
  final bool embedded;

  /// Whether the screen draws the position puck itself and the map's own
  /// fixes must stay off it; see [PuckOwnership].
  final bool ownsPosition;

  @override
  ConsumerState<PlannerMapHost> createState() => _PlannerMapHostState();
}

class _PlannerMapHostState extends ConsumerState<PlannerMapHost> {
  MapController? _map;

  /// Takes the map the builder just handed over, puts the app-wide map
  /// settings on it and passes it to the screen.
  void _handleMapReady(MapController controller) {
    _map = controller;
    unawaited(controller.setCyclosmOverlay(ref.read(cyclosmOverlayProvider)));
    widget.onMapReady(controller);
  }

  @override
  Widget build(BuildContext context) {
    // Not only the map of the screen the rider is looking at: every map that
    // is alive follows the setting, so switching tabs never shows a map that
    // disagrees with the overlay button.
    ref.listen<bool>(cyclosmOverlayProvider, (_, next) {
      unawaited(_map?.setCyclosmOverlay(next));
    });
    final map = PuckOwnership(
      owned: widget.ownsPosition,
      child: ref.watch(mapViewBuilderProvider)(_handleMapReady),
    );
    if (!widget.embedded) return map;
    // An embedded map keeps the chrome its owner declared, minus the
    // routing-tile download that only the planner needs.
    final inherited = MapChromeInsets.maybeOf(context);
    return MapChromeInsets(
      controlsTop: inherited?.controlsTop,
      attributionBottom: inherited?.attributionBottom,
      showRoutingTiles: false,
      following: inherited?.following ?? false,
      headingUp: inherited?.headingUp ?? false,
      bearingDeg: inherited?.bearingDeg ?? 0,
      onLocate: inherited?.onLocate,
      onCompass: inherited?.onCompass,
      routeShown: inherited?.routeShown ?? false,
      onToggleRoute: inherited?.onToggleRoute,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: map,
      ),
    );
  }
}
