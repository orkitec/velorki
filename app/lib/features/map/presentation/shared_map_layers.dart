import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/application/active_tab.dart';
import '../domain/map_controller.dart';
import 'shared_map_host.dart';

/// What a page over the shared map does with its layers: draws them while
/// its tab is on screen and the map is usable, takes them all off the moment
/// either stops being true, and draws them again from scratch when both are
/// true again, since another page may have drawn on the same layers in
/// between.
///
/// The order matters, because the tabs share layers: a tab that leaves
/// clears at once, from the change of tab itself, and a tab that arrives
/// draws a moment later, once every leaving tab has cleared. So [clearLayers]
/// runs synchronously and [drawLayers] from a microtask.
///
/// The state names its tab through [layersTab], calls [initLayers] once its
/// dependencies are there, [listenLayers] from every build and
/// [disposeLayers] from `dispose`.
mixin SharedMapLayers<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  MapController? _layersMap;
  bool _layersDrawing = false;
  bool _layersShown = false;
  bool _drawPending = false;

  /// The route of the tab the page belongs to.
  String get layersTab;

  /// The map this page draws on right now, or `null` while it may not.
  MapController? get layersMap => _layersDrawing ? _layersMap : null;

  /// Puts every layer of the page on [map], from scratch.
  void drawLayers(MapController map);

  /// Takes every layer of the page off [map].
  void clearLayers(MapController map);

  /// Reads the map and the tab, and draws if the page is on screen.
  void initLayers() {
    _layersMap = ref.read(sharedMapControllerProvider);
    _layersShown = ref.read(activeTabProvider) == layersTab;
    _syncLayers();
  }

  /// Follows the tab as it comes and goes, and the map as it comes, goes or
  /// is replaced after a style reload, when every layer on it is gone.
  void listenLayers() {
    ref.listen<String>(activeTabProvider, (_, next) {
      final shown = next == layersTab;
      if (shown == _layersShown) return;
      _layersShown = shown;
      _syncLayers();
    });
    ref.listen<MapController?>(sharedMapControllerProvider, (_, next) {
      if (identical(next, _layersMap)) return;
      _layersDrawing = false;
      _layersMap = next;
      _syncLayers();
    });
  }

  void _syncLayers() {
    final map = _layersMap;
    final wanted = _layersShown && map != null;
    if (!wanted) {
      if (!_layersDrawing) return;
      _layersDrawing = false;
      clearLayers(map!);
      return;
    }
    if (_layersDrawing || _drawPending) return;
    _drawPending = true;
    scheduleMicrotask(() {
      _drawPending = false;
      final map = _layersMap;
      if (!mounted || !_layersShown || map == null || _layersDrawing) return;
      _layersDrawing = true;
      drawLayers(map);
    });
  }

  /// Takes the layers off the map the page goes with.
  void disposeLayers() {
    final map = _layersMap;
    if (_layersDrawing && map != null) clearLayers(map);
    _layersDrawing = false;
  }
}
