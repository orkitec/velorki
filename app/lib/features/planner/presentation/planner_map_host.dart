import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../map/domain/map_controller.dart';
import '../../map/presentation/map_chrome.dart';

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
class PlannerMapHost extends ConsumerWidget {
  /// Creates the host.
  const PlannerMapHost({
    required this.onMapReady,
    super.key,
    this.embedded = false,
  });

  /// Called once the map can be driven.
  final void Function(MapController controller) onMapReady;

  /// Whether the map sits above other content rather than reaching the
  /// bottom of the screen. An embedded map drops the bottom safe-area inset
  /// (the floating navigation bar), which would otherwise push its
  /// attribution chip into the middle of the map.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = ref.watch(mapViewBuilderProvider)(onMapReady);
    if (!embedded) return map;
    // An embedded map keeps the chrome its owner declared, minus the
    // routing-tile download that only the planner needs.
    final inherited = MapChromeInsets.maybeOf(context);
    return MapChromeInsets(
      controlsTop: inherited?.controlsTop,
      attributionBottom: inherited?.attributionBottom,
      showRoutingTiles: false,
      following: inherited?.following ?? false,
      onLocate: inherited?.onLocate,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: map,
      ),
    );
  }
}
